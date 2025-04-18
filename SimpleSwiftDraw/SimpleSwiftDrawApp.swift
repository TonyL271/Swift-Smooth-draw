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

//struct ContentView: View {
//    var body: some View {
//        ZStack(alignment: .top) {
//            CanvasHistoryView()
//                .padding()
//                .background(Color.white.opacity(0.8))
//                .cornerRadius(8)
//                .padding()
//        }
//    }
//}

struct ContentView: View {
    @State private var strokes = StrokeCollection()

    var body: some View {
        VStack {
            DemoViewRepresentable(strokeCollection: $strokes)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            Button("Clear") {
                strokes.strokes.removeAll()
            }
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
        mtk.delegate = context.coordinator.renderer
        mtk.isUserInteractionEnabled = true // Make sure this is set to true
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
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    private var history: [MTLTexture] = []
    private var currentIdx = 0

    private var quadPipeline: MTLRenderPipelineState!
    private var strokePipeline: MTLRenderPipelineState!

    private var quadVB: MTLBuffer!
    private var strokeVB: MTLBuffer!
    private var pendingPoints: [SIMD2<Float>] = []

    func setup(view: MTKView) {
        guard let dev = view.device else { fatalError("Metal not supported") }
        self.device = dev
        self.queue = self.device.makeCommandQueue()

        let library = self.device.makeDefaultLibrary()!

        // 1) Full‑screen quad pipeline
        let quadDesc = MTLRenderPipelineDescriptor()
        quadDesc.vertexFunction = library.makeFunction(name: "vertex_passthrough")
        quadDesc.fragmentFunction = library.makeFunction(name: "fragment_texture")
        quadDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        self.quadPipeline = try! self.device.makeRenderPipelineState(descriptor: quadDesc)

        // 2) Stroke pipeline with alpha blending
        let strokeDesc = MTLRenderPipelineDescriptor()
        strokeDesc.vertexFunction = library.makeFunction(name: "vertex_stroke")
        strokeDesc.fragmentFunction = library.makeFunction(name: "fragment_stroke")
        strokeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let blend = strokeDesc.colorAttachments[0]!
        blend.isBlendingEnabled = true
        blend.sourceRGBBlendFactor = .sourceAlpha
        blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blend.sourceAlphaBlendFactor = .one
        blend.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.strokePipeline = try! self.device.makeRenderPipelineState(descriptor: strokeDesc)

        // 3) Quad vertex buffer
        let quadVerts: [Float] = [
            -1, -1, 0, 1,
            1, -1, 1, 1,
            -1, 1, 0, 0,
            1, 1, 1, 0,
        ]
        self.quadVB = self.device.makeBuffer(bytes: quadVerts,
                                             length: quadVerts.count * MemoryLayout<Float>.stride,
                                             options: [])

        // 4) Allocate history textures
        self.resizeHistoryTextures(size: view.drawableSize)
        self.setupPencilInput(view: view)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.resizeHistoryTextures(size: size)
        self.setupPencilInput(view: view)
    }

    private func resizeHistoryTextures(size: CGSize) {
        let width = Int(size.width), height = Int(size.height)
        self.history.removeAll()
        guard width > 0 && height > 0 else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .private

        self.history.append(self.device.makeTexture(descriptor: desc)!)
        self.history.append(self.device.makeTexture(descriptor: desc)!)

        // clear the first texture so canvas starts empty
        let cmd = self.queue.makeCommandBuffer()!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = self.history[0]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        enc.endEncoding()
        cmd.commit()

        self.currentIdx = 0
    }

    func enqueue(points: [SIMD2<Float>]) {
        self.pendingPoints.append(contentsOf: points)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard self.history.count == 2 else { return }
        let cmd = self.queue.makeCommandBuffer()!

        // —— Phase 1a: Bit‑exact copy (ping–pong) ——
        let nextIdx = (currentIdx + 1) & 1
        let blit = cmd.makeBlitCommandEncoder()!

        blit.copy(from: self.history[self.currentIdx],
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: self.history[0].width,
                                      height: self.history[0].height,
                                      depth: 1),
                  to: self.history[nextIdx],
                  destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin())

        blit.endEncoding()

        // —— Phase 1b: Draw new strokes into history[nextIdx] ——
        if !self.pendingPoints.isEmpty {
            self.strokeVB = self.device.makeBuffer(bytes: self.pendingPoints,
                                                   length: self.pendingPoints.count
                                                       * MemoryLayout<SIMD2<Float>>.stride,
                                                   options: [])
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = self.history[nextIdx]
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
            enc.setRenderPipelineState(self.strokePipeline)
            enc.setVertexBuffer(self.strokeVB, offset: 0, index: 0)
            enc.drawPrimitives(type: .point,
                               vertexStart: 0,
                               vertexCount: self.pendingPoints.count)
            enc.endEncoding()
            self.pendingPoints.removeAll()
        }

        // —— Phase 2: Present history[nextIdx] ——
        if let passDesc = view.currentRenderPassDescriptor {
            passDesc.colorAttachments[0].loadAction = .clear
            passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            passDesc.colorAttachments[0].storeAction = .store
            let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc)!
            enc.setRenderPipelineState(self.quadPipeline)
            enc.setVertexBuffer(self.quadVB, offset: 0, index: 0)
            enc.setFragmentTexture(self.history[nextIdx], index: 0)
            enc.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4)
            enc.endEncoding()
        }

        cmd.present(drawable)
        self.currentIdx = nextIdx
        cmd.commit()
    }
}
