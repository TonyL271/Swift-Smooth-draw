// Better implementation for pencil input

// import SwiftUI
// import UIKit
//
// extension CanvasHistoryRenderer: UIGestureRecognizerDelegate {
//     private enum AssociatedKeys {
//         static let scaleKey = UnsafeRawPointer(bitPattern: "scale".hashValue)!
//         static let rotationKey = UnsafeRawPointer(bitPattern: "rotation".hashValue)!
//         static let positionKey = UnsafeRawPointer(bitPattern: "position".hashValue)!
//     }
//
//     private var scale: CGFloat {
//         get { return (objc_getAssociatedObject(self, AssociatedKeys.scaleKey) as?
//                 CGFloat) ?? 1.0 }
//         set {
//             objc_setAssociatedObject(
//                 self,
//                 AssociatedKeys.scaleKey,
//                 newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
//             )
//         }
//     }
//
//     private var rotation: CGFloat {
//         get { return objc_getAssociatedObject(self, AssociatedKeys.rotationKey) as?
//             CGFloat ?? 0.0
//         }
//         set { objc_setAssociatedObject(self, AssociatedKeys.rotationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
//     }
//
//     private var position: CGPoint {
//         get { return objc_getAssociatedObject(self, AssociatedKeys.positionKey) as?
//             CGPoint ?? CGPoint(x: 0.0, y: 0.0)
//         }
//         set { objc_setAssociatedObject(self, AssociatedKeys.positionKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
//     }
//
//     func setupGestureRecognizers(for view: UIView) {
//         // Tap gesture
//         let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
//         view.addGestureRecognizer(tapGesture)
//
//         // Pan gesture
//         let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
//         view.addGestureRecognizer(panGesture)
//
//         // Pinch gesture for zooming
//         let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(self.handlePinch(_:)))
//         view.addGestureRecognizer(pinchGesture)
//
//         // Rotation gesture
//         let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(self.handleRotation(_:)))
//         view.addGestureRecognizer(rotationGesture)
//
//         let drawGesture = UILongPressGestureRecognizer()
//
//         // Enable multiple gesture recognition
//         panGesture.maximumNumberOfTouches = 2
//         pinchGesture.delegate = self
//         rotationGesture.delegate = self
//     }
//
//     // MARK: - Gesture Handlers
//
//     private func normalisedPoint(from location: CGPoint, in view: UIView) -> SIMD2<Float> {
//         let midX = view.bounds.midX
//         let midY = view.bounds.midY
//         let halfW = view.bounds.width * 0.5
//         let halfH = view.bounds.height * 0.5
//
//         // UIKit’s Y‑axis is downwards; we flip it so +Y is up.
//         let nx = Float((location.x - midX) / halfW) // –1 … 1
//         let ny = -Float((location.y - midY) / halfH) // –1 … 1 (flipped)
//
//         return SIMD2<Float>(nx, ny)
//     }
//
//     @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
//         logger.ilog("handleTap entered")
//         let newPts = (0 ..< 6).map { _ in
//             SIMD2<Float>(Float.random(in: -1 ... 1),
//                          Float.random(in: -1 ... 1))
//         }
//         self.enqueue(points: newPts)
//
//         // Example: Reset transformations on double tap
//         if gesture.numberOfTapsRequired == 2 {
//             self.scale = 1.0
//             self.rotation = 0.0
//             self.position = CGPoint(x: 0, y: 0)
//         }
//     }
//
//     @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
//         let translation = gesture.translation(in: gesture.view)
//
//         // Update position based on pan
//         if gesture.state == .changed {
//             self.position.x += translation.x
//             self.position.y += translation.y
//             gesture.setTranslation(.zero, in: gesture.view)
//         }
//     }
//
//     @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
//         // Update scale based on pinch
//         if gesture.state == .changed {
//             self.scale *= CGFloat(gesture.scale)
//             gesture.scale = 1.0
//         }
//     }
//
//     @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
//         // Update rotation based on rotation gesture
//         if gesture.state == .changed {
//             self.rotation += CGFloat(gesture.rotation)
//             gesture.rotation = 0
//         }
//     }
//
//     @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
//         // Update rotation based on rotation gesture
//         gesture.touchesBegan(Set<UITouch>, with: UIEvent)
//
//     }
//
//     @MainActor
//     func touchesBegan(
//         _ touches: Set<UITouch>,
//         with _: UIEvent
//     ) {
//         logger.ilog("touch began entered")
//
//         let touchesArray: [UITouch] = touches.shuffled()
//
//         for touch in touchesArray {
//             let location = touch.location(in: touch.view)
//
//             logger.ilog("[", location.x, ", ", location.y, "]")
//         }
//     }
// }
