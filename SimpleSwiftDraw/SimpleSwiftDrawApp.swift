import MetalKit
import SwiftUI
import UIKit

@main
struct MetalDemoApp: App {
    init() {
        logger.log("")
        logger.log("")
        logger.log("")
        logger.log("")
        logger.log("----------- MetalDraw has launched ---------------")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            CanvasHistoryView()
                .padding()
                .background(Color.white.opacity(0.8))
                .cornerRadius(8)
                .padding()
        }
    }
}

struct CanvasHistoryView: UIViewRepresentable {
    // explicit init so Swift knows how to bind
    init() {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MTKView {
        let mtk = MTKView()
        mtk.device = MTLCreateSystemDefaultDevice()
        mtk.framebufferOnly = false
        mtk.autoResizeDrawable = true
        mtk.colorPixelFormat = .bgra8Unorm
        // mtk.isPaused = true
        mtk.enableSetNeedsDisplay = true // (was already true via default)
        mtk.delegate = context.coordinator.renderer
        context.coordinator.renderer.setup(view: mtk)
        return mtk
    }

    func updateUIView(_: MTKView, context _: Context) {}

    class Coordinator {
        var parent: CanvasHistoryView
        let renderer: CanvasHistoryRenderer

        init(_ parent: CanvasHistoryView) {
            self.parent = parent
            self.renderer = CanvasHistoryRenderer()
        }
    }
}

class CanvasHistoryRenderer: NSObject, MTKViewDelegate {
    // Types and constants
    private enum Constants {
        static let maxPointsPerFrame = 8192
    }

    // Metal objects
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    weak var metalView: MTKView!

    private var quadPipeline: MTLRenderPipelineState!
    private var strokePipeline: MTLRenderPipelineState!
    // used every frame
    private var quadVB: MTLBuffer!
    private var strokeVB: MTLBuffer!

    // Canvas state
    private var history: [MTLTexture] = []
    private var currentIdx = 0
    var pendingPoints: [SIMD2<Float>] = []

    // Display link
    private var displayLink: CADisplayLink?

    // MARK: - - Public API

    func enqueue(points: [SIMD2<Float>]) {
        self.pendingPoints.append(contentsOf: points)
        //        self.metalView.setNeedsDisplay(
        //            CanvasHistoryRenderer.dirtyRect(from: points))
    }

    // MARK: - - Setup

    func setup(view: MTKView) {
        self.metalView = view
        guard let dev = view.device else { fatalError("Metal not supported") }
        self.device = dev
        self.queue = self.device.makeCommandQueue()

        let library = self.device.makeDefaultLibrary()!

        // 1) Full‑screen quad pipeline
        let quadDesc = MTLRenderPipelineDescriptor()
        quadDesc.vertexFunction = library.makeFunction(
            name: "vertex_passthrough")
        quadDesc.fragmentFunction = library.makeFunction(
            name: "fragment_texture")
        quadDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        self.quadPipeline = try! self.device.makeRenderPipelineState(
            descriptor: quadDesc)

        // 2) Stroke pipeline with alpha blending
        let strokeDesc = MTLRenderPipelineDescriptor()
        strokeDesc.vertexFunction = library.makeFunction(name: "vertex_stroke")
        strokeDesc.fragmentFunction = library.makeFunction(
            name: "fragment_stroke")

        strokeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        strokeDesc.colorAttachments[0]!.isBlendingEnabled = false
        self.strokePipeline = try! self.device.makeRenderPipelineState(
            descriptor: strokeDesc)

        // 3) Quad vertex buffer
        let quadVerts: [Float] = [
            -1, -1, 0, 1,
            1, -1, 1, 1,
            -1, 1, 0, 0,
            1, 1, 1, 0,
        ]
        self.quadVB = self.device.makeBuffer(
            bytes: quadVerts,
            length: quadVerts.count * MemoryLayout<Float>.stride,
            options: []
        )

        self.strokeVB = self.device.makeBuffer(
            length: Constants.maxPointsPerFrame
                * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )

        // 4) Allocate history textures
        self.resizeHistoryTextures(size: view.drawableSize)
        self.setupPencilInput(view: view)

        self.createDisplayLink()
    }

    func createDisplayLink() {
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(self.step)
        )

        displayLink.add(
            to: RunLoop.main,
            forMode: .common
        )
        displayLink.isPaused = true
        self.displayLink = displayLink
    }

    func pauseDisplayLink() {
        self.displayLink?.isPaused = true
    }

    func unPauseDisplayLink() {
        self.displayLink?.isPaused = false
    }

    @objc
    func step(displayLink: CADisplayLink) {
        self.metalView.draw()
        let timeOverSpent = CACurrentMediaTime() - displayLink.targetTimestamp
        if timeOverSpent >= 0 {
            let actualFramesPerSecond =
                1 / (displayLink.targetTimestamp - displayLink.timestamp)
            logger.ilog("too long, spent: ", timeOverSpent)
            logger.ilog("rendered fps: ", actualFramesPerSecond)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.resizeHistoryTextures(size: size)
        self.setupPencilInput(view: view)
    }

    // MARK: ‑‑ MTKViewDelegate

    func draw(in view: MTKView) {
        autoreleasepool {
            let cpuStart = CACurrentMediaTime()

            guard let drawable = view.currentDrawable else { return }
            guard self.history.count == 2 else { return }

            let c1 = CACurrentMediaTime()
            let cmd = self.queue.makeCommandBuffer()!

            let c2 = CACurrentMediaTime()
            if self.pendingPoints.isEmpty {
                self.present(
                    texture: self.history[self.currentIdx],
                    on: drawable, with: view,
                    commandBuffer: cmd
                )
                cmd.commit()

                return
            }

            let c3 = CACurrentMediaTime()

            // Unsure about this
            let nextIdx = (currentIdx + 1) & 1

            let dirty = CanvasHistoryRenderer.dirtyRect(from: self.pendingPoints)
            let origin = MTLOrigin(x: Int(dirty.minX), y: Int(dirty.minY), z: 0)
            let size = MTLSize(
                width: Int(dirty.width), height: Int(dirty.height), depth: 1
            )

            // Copy only the dirty region
            let blit = cmd.makeBlitCommandEncoder()!
            blit.copy(
                from: self.history[self.currentIdx],
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: origin, sourceSize: size,
                to: self.history[nextIdx],
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: origin
            )
            blit.endEncoding()

            // —— Phase 1b: Draw new strokes into history[nextIdx] ——

            self.pendingPoints.withUnsafeBufferPointer { buf in
                guard let src = buf.baseAddress else { return }
                let bytes = buf.count * MemoryLayout<SIMD2<Float>>.stride
                memcpy(self.strokeVB.contents(), src, bytes)
            }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = self.history[nextIdx]
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
            enc.setRenderPipelineState(self.strokePipeline)
            enc.setVertexBuffer(self.strokeVB, offset: 0, index: 0)
            enc.drawPrimitives(
                type: .point,
                vertexStart: 0,
                vertexCount: self.pendingPoints.count
            )
            enc.endEncoding()
            self.pendingPoints.removeAll()

            self.present(
                texture: self.history[nextIdx], on: drawable, with: view,
                commandBuffer: cmd
            )
            let cpuEnd = CACurrentMediaTime()
            var gpuStart: Double = CACurrentMediaTime()
            cmd.addScheduledHandler { _ in
                gpuStart = CACurrentMediaTime()
            }

            cmd.addCompletedHandler { _ in

                let gpuEnd = CACurrentMediaTime()
                logger.ilog("total render Time: ", gpuEnd - cpuStart)
                logger.ilog("CPU Time: ", cpuEnd - cpuStart)
                logger.ilog(" --> C1 Time: ", c1 - cpuStart)
                logger.ilog(" --> C2 Time: ", c2 - c1)
                logger.ilog(" --> C3 Time: ", c3 - c2)
                logger.ilog(" --> END Time: ", cpuEnd - c3)
                logger.ilog("GPU Time: ", gpuEnd - gpuStart)
                logger.ilog(" -> GPU wait for CPU: ", gpuStart - cpuEnd)
                logger.ilog("Budget: ", 1 / 120)
            }

            cmd.commit()
            self.currentIdx = nextIdx
        }
    }

    // MARK: ‑‑ Helpers

    private func present(
        texture: MTLTexture, on drawable: CAMetalDrawable, with view: MTKView,
        commandBuffer cmd: MTLCommandBuffer
    ) {
        guard let passDesc = view.currentRenderPassDescriptor else { return }

        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        passDesc.colorAttachments[0].storeAction = .store

        let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc)!
        enc.setRenderPipelineState(self.quadPipeline)
        enc.setVertexBuffer(self.quadVB, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
    }

    private func resizeHistoryTextures(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))

        self.history.removeAll()

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .private

        self.history = (0 ..< 2).compactMap { _ in
            self.device.makeTexture(descriptor: desc)
        }
        self.currentIdx = 0

        // clear the first texture so canvas starts empty
        let cmd = self.queue.makeCommandBuffer()!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = self.history[0]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Setup and finish encoding
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        enc.endEncoding()
        cmd.commit()

        self.currentIdx = 0
    }

    private static func dirtyRect(from vertices: [SIMD2<Float>]) -> CGRect {
        guard let first = vertices.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for v in vertices.dropFirst() {
            minX = min(minX, v.x)
            minY = min(minY, v.y)
            maxX = max(maxX, v.x)
            maxY = max(maxY, v.y)
        }
        let normalize = PencilInputView.normalisedPoint

        let left = CGFloat(floor(minX))
        let top = CGFloat(floor(minY))
        let right = CGFloat(ceil(maxX))
        let bottom = CGFloat(ceil(maxY))
        return CGRect(
            x: left, y: top, width: right - left, height: bottom - top
        )
    }
}
