// import MetalKit
// import SwiftUI
//
// // Better implementation for pencil input
// import UIKit
//
// struct StrokeSample {
//     let location: CGPoint
//     let coalescedSample: Bool
//     init(point: CGPoint, coalesced: Bool = false) {
//         self.location = point
//         self.coalescedSample = coalesced
//     }
// }
//
// /// A single drawn line.
// class Stroke {
//     var samples: [StrokeSample] = []
//     var predictedSamples: [StrokeSample] = [] // 🔹
//     var drawQueue: [StrokeSample] = []
//     // Persistent, non‑cleared predicted samples for debugging
//     var pred_debug: [StrokeSample] = []
//     // What the samples would be without prediction
//     var samples_debug: [StrokeSample] = []
//
//     // MARK: mutation
//
//     func add(sample: StrokeSample) { self.samples.append(sample) }
//     func addQueue(sample: StrokeSample) { self.drawQueue.append(sample) }
//     func setPredicted(samples: [StrokeSample]) { self.predictedSamples = samples } // 🔹
//     func clearPredictions() { self.predictedSamples.removeAll() } // 🔹
// }
//
// final class StrokeCollection {
//     var strokes: [Stroke] = []
//     var activeStroke: Stroke?
//
//     /// Move the live stroke into the archive (predictions are discarded).
//     func acceptActiveStroke() {
//         if let stroke = activeStroke {
//             stroke.clearPredictions()
//             self.strokes.append(stroke)
//             self.activeStroke = nil
//         }
//     }
// }
//
// class PencilInputView: UIView {
//     weak var delegate: PencilInputDelegate?
//
//     private let slowDown: TimeInterval = 0.0 // set >0 if you want to slow input
//     private var lastSampleTime: TimeInterval = 0
//
//     // Injected from SwiftUI wrapper
//     var strokeCollection: StrokeCollection? {
//         didSet { if oldValue !== self.strokeCollection { } }
//     }
//
//     override init(frame: CGRect) {
//         super.init(frame: frame)
//         isMultipleTouchEnabled = true
//     }
//
//     required init?(coder: NSCoder) {
//         super.init(coder: coder)
//         isMultipleTouchEnabled = true
//     }
//
//     override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//         guard let touch: UITouch = touches.first else { return }
//
//         if #available(iOS 12.1, *) {
//             if touch.type != .pencil {
//                 return
//             }
//         }
//         if let coalesced = event?.coalescedTouches(for: touch) {
//             logger.ilog("count coaosce start ", coalesced.count)
//             self.processCoalescedTouches(for: coalesced, state: .began)
//             self.totalV += coalesced.count
//
//         } else {
//             self.processTouches(touches, state: .began)
//         }
//     }
//
//     var totalV = 0
//
//     override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
//         guard let touch: UITouch = touches.first else { return }
//         if #available(iOS 12.1, *) {
//             if touch.type != .pencil {
//                 return
//             }
//         }
// //        if counter % 5 != 0 {return }
//
//         if let coalesced = event?.coalescedTouches(for: touch) {
//             self.processCoalescedTouches(for: coalesced, state: .changed)
//
// //            self.processCoalescedTouches(for: [touch], state: .changed)
// //            logger.ilog("touchesCount: ", touches.count)
// //            logger.ilog("AdditionalTouchCount: ", coalesced.count)
//
//             self.totalV += coalesced.count
//         } else {
//             self.processTouches(touches, state: .began)
//         }
//     }
//
//     override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
//         guard let touch: UITouch = touches.first else { return }
//         if #available(iOS 12.1, *) {
//             if touch.type != .pencil {
//                 return
//             }
//         }
//
//         if let coalesced = event?.coalescedTouches(for: touch) {
//             self.processCoalescedTouches(for: coalesced, state: .ended)
//             self.totalV += coalesced.count
//
//         } else {
//             self.processTouches(touches, state: .ended)
//         }
//         logger.ilog( "Total vertices sent to the screen: ",
//         self.totalV)
//     }
//
//     override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
//         super.touchesCancelled(touches, with: event)
//     }
//
//     private func processCoalescedTouches(for touches: [UITouch], state: UIGestureRecognizer.State = .changed) {
//         let locations = touches.map { touch in
//             self.normalisedPoint(from: touch.preciseLocation(in: self))
//         }
//
//         self.delegate?.pencilInput(locations: locations, state: state)
//     }
//
//     private func processTouches(_ touches: Set<UITouch>, state: UIGestureRecognizer.State) {
//         let locations = touches.map { touch in
//             self.normalisedPoint(from: touch.preciseLocation(in: self))
//         }
//
//         self.delegate?.pencilInput(locations: locations, state: state)
//     }
//
//     func normalisedPoint(from location: CGPoint) -> SIMD2<Float> {
//         let width = self.bounds.width
//         let height = self.bounds.height
//
//         let x = Float((location.x / width) * 2 - 1)
//         let y = Float(1 - (location.y / height) * 2)
//         let result = SIMD2<Float>(x, y)
//
//         let end = CACurrentMediaTime()
//         return result
//     }
// }
//
// // 2. Protocol for handling pencil input
// protocol PencilInputDelegate: AnyObject {
//     func pencilInput(locations: [SIMD2<Float>],
//                      state: UIGestureRecognizer.State)
// }
//
// // 3. Implement in your view controller
// extension CanvasHistoryRenderer: PencilInputDelegate, UIPencilInteractionDelegate {
//     private enum AssociatedKeys {
//         static let boundsKey = UnsafeRawPointer(bitPattern: "bounds".hashValue)!
//         static let currentStrokeWidthKey = UnsafeRawPointer(bitPattern: "currentStrokeWidth".hashValue)!
//     }
//
//     private var bounds: CGRect {
//         get { return (objc_getAssociatedObject(self, AssociatedKeys.boundsKey) as?
//                 CGRect) ?? CGRect() }
//         set {
//             objc_setAssociatedObject(
//                 self,
//                 AssociatedKeys.boundsKey,
//                 newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
//             )
//         }
//     }
//
//     private var currentStrokeWidth: CGFloat {
//         get { return (objc_getAssociatedObject(self, AssociatedKeys.currentStrokeWidthKey) as?
//                 CGFloat) ?? 1.0 }
//         set {
//             objc_setAssociatedObject(
//                 self,
//                 AssociatedKeys.currentStrokeWidthKey,
//                 newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
//             )
//         }
//     }
//
//     func setupPencilInput(view: MTKView) {
//         logger.ilog("pencil view initiated")
//         // Remove any existing PencilInputView first to avoid duplicates
//         for subview in view.subviews {
//             if subview is PencilInputView {
//                 subview.removeFromSuperview()
//             }
//         }
//         self.bounds = view.bounds
//
//         // Create a new PencilInputView with the correct frame
//         let pencilView = PencilInputView(frame: view.bounds)
//         pencilView.delegate = self
//         pencilView.backgroundColor = .clear
//         pencilView.autoresizingMask = [.flexibleWidth, .flexibleHeight] // Ensure it resizes with parent
//         pencilView.isUserInteractionEnabled = true // Make sure interaction is enabled
//
//         // Add it to the view
//         view.addSubview(pencilView)
//
//         // Enable pencil interaction if available
//         if #available(iOS 12.1, *) {
//             let pencilInteraction = UIPencilInteraction()
//             pencilInteraction.delegate = self
//             pencilView.addInteraction(pencilInteraction)
//         }
//     }
//
//     func pencilInput(locations: [SIMD2<Float>],
//                      state: UIGestureRecognizer.State)
//
//     {
//         switch state {
//         case .began:
//             self.beginPencilStroke(at: locations)
//         case .changed:
//             self.continuePencilStroke(at: locations)
//         case .ended, .cancelled:
//             self.endPencilStroke(at: locations)
//         default:
//             break
//         }
//     }
//
//     private func beginPencilStroke(at locations: [SIMD2<Float>]) {
//         self.unPauseDisplayLink()
//         self.enqueue(points: locations)
//     }
//
//     private func continuePencilStroke(at locations: [SIMD2<Float>]) {
//         self.enqueue(points: locations)
//     }
//
//     private func endPencilStroke(at locations: [SIMD2<Float>]) {
//         self.enqueue(points: locations)
//         self.pauseDisplayLink()
//     }
// }
//
// // MARK: - - Testing the polling rate
//
// class TouchRateMonitor {
//     private var touchTimestamps: [TimeInterval] = []
//     private var isMonitoring = false
//
//     func startMonitoring() {
//         self.touchTimestamps.removeAll()
//         self.isMonitoring = true
//     }
//
//     func recordTouch() {
//         if self.isMonitoring {
//             self.touchTimestamps.append(ProcessInfo.processInfo.systemUptime)
//         }
//     }
//
//     func stopMonitoring() -> (count: Int, avgRate: Double, intervals: [TimeInterval]) {
//         self.isMonitoring = false
//         guard self.touchTimestamps.count > 1 else { return (0, 0, []) }
//
//         let duration = self.touchTimestamps.last! - self.touchTimestamps.first!
//         let count = self.touchTimestamps.count - 1
//         let rate = Double(count) / duration
//
//         var intervals: [TimeInterval] = []
//         for i in 1 ..< self.touchTimestamps.count {
//             intervals.append(self.touchTimestamps[i] - self.touchTimestamps[i - 1])
//         }
//
//         return (count, rate, intervals)
//     }
// }
