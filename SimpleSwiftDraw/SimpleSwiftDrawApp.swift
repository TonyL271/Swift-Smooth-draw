import MetalKit
import QuartzCore  // for CAMetalDisplayLink
import SwiftUI
import UIKit
import simd  // for SIMD types

@main
struct MyMetalApp: App {
    var body: some Scene {
        WindowGroup {
            MetalCanvasView()
                .edgesIgnoringSafeArea(.all)  // full‑screen
        }
    }
}

struct MetalCanvasView: UIViewRepresentable {
    class Coordinator {
        var renderer: CanvasHistoryRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero)
        // keep the renderer alive in the coordinator
        context.coordinator.renderer = CanvasHistoryRenderer(metalView: mtkView)
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // no dynamic updates for now
    }
}

class CanvasHistoryRenderer: NSObject {
    private weak var mtkView: MTKView?
    private var commandQueue: MTLCommandQueue!

    // Render pipeline
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!

    // Display‑link variants
    @available(iOS 17.0, *)
    private var displayLink: CAMetalDisplayLink?
    private var fallbackDisplayLink: CADisplayLink?

    // Per‑frame uniform layout must match the Metal shader
    private struct Uniforms {
        var color: SIMD4<Float>
    }

    init(metalView view: MTKView) {
        super.init()
        self.mtkView = view

        // 1) Create the Metal device & command queue
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device")
        }
        view.device = device

        // Cap at 120fps if available
        view.preferredFramesPerSecond = 120

        self.commandQueue = device.makeCommandQueue()

        // 2) Build our render pipeline & buffers
        self.setupPipeline(
            with: device, colorPixelFormat: view.colorPixelFormat)

        // 3) Hook up the appropriate display link
        self.setupDisplayLink(for: view)
        logger.ilog("viisted init")
    }

    private func setupPipeline(
        with device: MTLDevice, colorPixelFormat: MTLPixelFormat
    ) {
        // Load the .metal file from the app bundle
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library")
        }
        guard
            let vFunc = library.makeFunction(name: "vertex_main"),
            let fFunc = library.makeFunction(name: "fragment_main")
        else {
            fatalError("Could not find shader functions in library")
        }

        let pDesc = MTLRenderPipelineDescriptor()
        pDesc.vertexFunction = vFunc
        pDesc.fragmentFunction = fFunc
        pDesc.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            self.pipelineState = try device.makeRenderPipelineState(
                descriptor: pDesc)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }

        // Fullscreen triangle (in clip space)
        let verts: [SIMD2<Float>] = [
            [-1, -1],
            [3, -1],
            [-1, 3],
        ]
        self.vertexBuffer = device.makeBuffer(
            bytes: verts,
            length: MemoryLayout<SIMD2<Float>>.stride * verts.count,
            options: []
        )

        // Uniform buffer for a single float4
        self.uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.size,
            options: []
        )
    }

    private func setupDisplayLink(for view: MTKView) {
        if #available(iOS 17.0, *) {
            // iOS17+ Metal display link
            guard let layer = view.layer as? CAMetalLayer else {
                fatalError("MTKView.layer is not a CAMetalLayer")
            }
            let link = CAMetalDisplayLink(metalLayer: layer)
            link.delegate = self

            link.add(to: .main, forMode: .common)

            link.isPaused = false  // start immediately
            self.displayLink = link
        } else {
            // Fallback CADisplayLink → solid green clear
            let link = CADisplayLink(
                target: self,
                selector: #selector(self.fallbackRender(_:))
            )
            link.preferredFramesPerSecond = view.preferredFramesPerSecond
            link.add(to: .main, forMode: .common)
            link.isPaused = false
            self.fallbackDisplayLink = link
        }
    }

    // MARK: – Dynamic render

    private func render(
        drawable: CAMetalDrawable,
        at timestamp: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        let renderStartTime = CACurrentMediaTime()
        guard let cb = commandQueue.makeCommandBuffer() else { return }

        // Manually build a render‑pass descriptor
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear

        // Compute a smooth, looping color
        let t = Float(timestamp)
        let r = abs(sin(t))
        let g = abs(sin(t + 2.0))
        let b = abs(sin(t + 4.0))
        var uni = Uniforms(color: SIMD4<Float>(r, g, b, 1))

        // Update our uniform buffer
        memcpy(self.uniformBuffer.contents(), &uni, MemoryLayout<Uniforms>.size)

        // Encode a clear‑and‑draw pass
        rpd.colorAttachments[0].loadAction = .clear
        // (the clear color is ignored once you draw a fullscreen triangle)

        let encoder = cb.makeRenderCommandEncoder(descriptor: rpd)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        // present *this* drawable
        cb.present(drawable)
        cb.addCompletedHandler { buffer in
            let renderDoneTime = CACurrentMediaTime()
            logger.ilog(
                "time it took to render the frame: ",
                renderDoneTime - renderStartTime)
        }
        cb.commit()
    }

    // MARK: – Fallback render (green only)

    @objc private func fallbackRender(_: CADisplayLink) {

        guard
            let view = mtkView,
            let drawable = view.currentDrawable,
            let rpd = view.currentRenderPassDescriptor,
            let cb = commandQueue.makeCommandBuffer()
        else { return }

        // Just clear to green
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 0, 1)

        let encoder = cb.makeRenderCommandEncoder(descriptor: rpd)!
        encoder.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

// MARK: – CAMetalDisplayLinkDelegate

@available(iOS 17.0, *)
extension CanvasHistoryRenderer: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(
        _ link: CAMetalDisplayLink,
        needsUpdate update: CAMetalDisplayLink.Update
    ) {
        let drawable = update.drawable
        let timestamp = update.targetTimestamp
        let duration = update.targetPresentationTimestamp - timestamp
        self.render(drawable: drawable, at: timestamp, duration: duration)
    }
}
