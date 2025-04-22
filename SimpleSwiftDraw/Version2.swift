import UIKit
import Metal
import MetalKit
import QuartzCore

class MetalAnimationViewController: UIViewController {
    // Core components
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    
    // Animation timing
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMetal()
        setupView()
        setupRenderPipeline()
        createGeometry()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAnimation()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAnimation()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update metal layer size when view changes
        metalLayer.frame = view.layer.bounds
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * UIScreen.main.scale,
            height: view.bounds.height * UIScreen.main.scale
        )
    }
}

extension MetalAnimationViewController {
    private func setupMetal() {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
    }
    
    private func setupView() {
        // Set up the CAMetalLayer for rendering
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = view.layer.bounds
        
        // Set drawable size to match view with correct scale
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * UIScreen.main.scale,
            height: view.bounds.height * UIScreen.main.scale
        )
        
        // Add metal layer to the view's layer hierarchy
        view.layer.addSublayer(metalLayer)
    }
}

extension MetalAnimationViewController {
    private func setupRenderPipeline() {
        // Load default library containing our shaders
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default library")
        }
        
        // Get shader functions
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Failed to create shader functions")
        }
        
        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        
        // Create render pipeline state
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    private func createGeometry() {
        // Define vertex data structure (must match shader)
        struct Vertex {
            var position: SIMD3<Float>
            var color: SIMD3<Float>
        }
        
        // Create triangle vertices
        let vertices = [
            Vertex(position: SIMD3<Float>(0.0, 0.5, 0.0), color: SIMD3<Float>(1.0, 0.0, 0.0)),  // Top - Red
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0.0), color: SIMD3<Float>(0.0, 1.0, 0.0)),  // Bottom left - Green
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0.0), color: SIMD3<Float>(0.0, 0.0, 1.0))   // Bottom right - Blue
        ]
        
        // Create vertex buffer
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Vertex>.stride,
                                         options: .storageModeShared)
    }
}


extension MetalAnimationViewController {
    private func startAnimation() {
        // Set up display link for rendering
        displayLink = CADisplayLink(target: self, selector: #selector(draw))
        displayLink?.add(to: .main, forMode: .common)
        startTime = CACurrentMediaTime()
        
        // Add Core Animation to the metal layer (rotation)
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 2 * Double.pi
        rotation.duration = 2.0
        rotation.repeatCount = .infinity
        metalLayer.add(rotation, forKey: "rotationAnimation")
        
        // Add Core Animation for scale
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.5
        scale.duration = 1.0
        scale.autoreverses = true
        scale.repeatCount = .infinity
        metalLayer.add(scale, forKey: "scaleAnimation")
    }
    
    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        metalLayer.removeAllAnimations()
    }
    
    @objc private func draw(_ displayLink: CADisplayLink) {
        autoreleasepool {
            guard let drawable = metalLayer.nextDrawable() else { return }
            
            let currentTime = CACurrentMediaTime()
            let elapsedTime = startTime != nil ? Float(currentTime - startTime!) : 0
            
            render(drawable: drawable, elapsedTime: elapsedTime)
        }
    }
    
    private func render(drawable: CAMetalDrawable, elapsedTime: Float) {
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        // Set render pipeline state
        renderEncoder.setRenderPipelineState(renderPipelineState)
        
        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set rotation value for internal animation
        var rotation = elapsedTime
        renderEncoder.setVertexBytes(&rotation, length: MemoryLayout<Float>.size, index: 1)
        
        // Draw triangle
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        // End encoding
        renderEncoder.endEncoding()
        
        // Present drawable and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}




// AppDelegate.swift
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Nothing to do here for now
    }
}


// SceneDelegate.swift
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MetalAnimationViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
