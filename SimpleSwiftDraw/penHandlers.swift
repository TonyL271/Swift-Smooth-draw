import SwiftUI
import MetalKit

// Better implementation for pencil input
import UIKit

// 1. Create a custom view that can detect pencil input
class PencilInputView: UIView {
    weak var delegate: PencilInputDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.processTouches(touches, state: .began)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.processTouches(touches, state: .changed)
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.processTouches(touches, state: .ended)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.processTouches(touches, state: .cancelled)
        super.touchesCancelled(touches, with: event)
    }

    private func processTouches(_ touches: Set<UITouch>, state: UIGestureRecognizer.State) {
        for touch in touches {
            // Process all touches for testing, not just pencil
            let location = touch.location(in: self)
            let force = touch.type == .pencil ? touch.force / touch.maximumPossibleForce : 0.5
            let altitudeAngle = touch.type == .pencil ? touch.altitudeAngle : .pi/4
            let azimuthAngle = touch.type == .pencil ? touch.azimuthAngle(in: self) : 0
            
            print("Processing touch at \(location), state: \(state)")
            self.delegate?.pencilInput(touch: touch, at: location, force: force,
                                       altitude: altitudeAngle, azimuth: azimuthAngle,
                                       state: state)
        }
    }
}

// 2. Protocol for handling pencil input
protocol PencilInputDelegate: AnyObject {
    func pencilInput(touch: UITouch, at location: CGPoint, force: CGFloat,
                     altitude: CGFloat, azimuth: CGFloat,
                     state: UIGestureRecognizer.State)
}



// 3. Implement in your view controller
extension CanvasHistoryRenderer: PencilInputDelegate, UIPencilInteractionDelegate {
    
    private enum AssociatedKeys {
        static let boundsKey = UnsafeRawPointer(bitPattern: "bounds".hashValue)!
        static let currentStrokeWidthKey = UnsafeRawPointer(bitPattern: "currentStrokeWidth".hashValue)!

    }

    private var bounds: CGRect {
        get { return (objc_getAssociatedObject(self, AssociatedKeys.boundsKey) as?
                      CGRect) ?? CGRect() }
        set {
            objc_setAssociatedObject(
                self,
                AssociatedKeys.boundsKey,
                newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    private var currentStrokeWidth: CGFloat {
        get { return (objc_getAssociatedObject(self, AssociatedKeys.currentStrokeWidthKey) as?
                CGFloat) ?? 1.0 }
        set {
            objc_setAssociatedObject(
                self,
                AssociatedKeys.currentStrokeWidthKey,
                newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    


    
    
    func setupPencilInput(view: MTKView) {
        // Remove any existing PencilInputView first to avoid duplicates
        for subview in view.subviews {
            if subview is PencilInputView {
                subview.removeFromSuperview()
            }
        }
        self.bounds = view.bounds
        
        // Create a new PencilInputView with the correct frame
        let pencilView = PencilInputView(frame: view.bounds)
        pencilView.delegate = self
        pencilView.backgroundColor = .clear
        pencilView.autoresizingMask = [.flexibleWidth, .flexibleHeight] // Ensure it resizes with parent
        pencilView.isUserInteractionEnabled = true // Make sure interaction is enabled
        
        // Add it to the view
        view.addSubview(pencilView)
        print("Added PencilInputView with frame: \(pencilView.frame)")
        
        // Enable pencil interaction if available
        if #available(iOS 12.1, *) {
            let pencilInteraction = UIPencilInteraction()
            pencilInteraction.delegate = self
            pencilView.addInteraction(pencilInteraction)
        }
    }
    
    
         private func normalisedPoint(from location: CGPoint) -> SIMD2<Float> {
             let midX = self.bounds.midX
             let midY = self.bounds.midY
             let halfW = self.bounds.width * 0.5
             let halfH = self.bounds.height * 0.5
    
             // UIKit’s Y‑axis is downwards; we flip it so +Y is up.
             let nx = Float((location.x - midX) / halfW) // –1 … 1
             let ny = -Float((location.y - midY) / halfH) // –1 … 1 (flipped)
    
             return SIMD2<Float>(nx, ny)
         }

    func pencilInput(touch : UITouch, at location: CGPoint, force: CGFloat,
                     altitude: CGFloat, azimuth: CGFloat,
                     state: UIGestureRecognizer.State)
    {
        switch state {
        case .began:
            self.beginPencilStroke(at: location, force: force, altitude: altitude, azimuth: azimuth)
        case .changed:
            self.continuePencilStroke(at: location, force: force, altitude: altitude, azimuth: azimuth)
        case .ended, .cancelled:
            self.endPencilStroke(at: location)
        default:
            break
        }
    }

    private func beginPencilStroke(at location: CGPoint, force: CGFloat, altitude: CGFloat, azimuth: CGFloat) {
        self.enqueue(points: [normalisedPoint(from: location)])
        // Store stroke properties
        self.currentStrokeWidth = self.calculateStrokeWidth(force: force, altitude: altitude)
    }

    private func continuePencilStroke(at location: CGPoint, force: CGFloat, altitude: CGFloat, azimuth _: CGFloat) {
        self.enqueue(points: [normalisedPoint(from: location)])
        self.currentStrokeWidth = self.calculateStrokeWidth(force: force, altitude: altitude)
    }

    private func endPencilStroke(at location: CGPoint) {
        self.enqueue(points: [normalisedPoint(from: location)])
    }

    private func calculateStrokeWidth(force: CGFloat, altitude: CGFloat) -> CGFloat {
        // Base width
        let baseWidth: CGFloat = 2.0

        // Pressure effect (more pressure = thicker line)
        let pressureEffect = force * 5.0

        // Tilt effect (more tilt = wider stroke, like a real pen)
        let tiltFactor = 1.0 - altitude / (CGFloat.pi / 2)
        let tiltEffect = tiltFactor * 3.0

        return baseWidth + pressureEffect + tiltEffect
    }
}
