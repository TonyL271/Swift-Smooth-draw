//
//  SmoothPencilView.swift
//
//  Drawing demo that combines coalesced *and* predicted Apple‑Pencil
//  samples, then runs them through a Catmull–Rom spline for a silky stroke.
//

import SwiftUI
import UIKit                    // ObjectiveC not needed

// MARK: –– Model types -------------------------------------------------------

struct StrokeSample {
    let location: CGPoint
    let coalescedSample: Bool
    init(point: CGPoint, coalesced: Bool = false) {
        location  = point
        coalescedSample = coalesced
    }
}

/// A single drawn line.
class Stroke {
    var samples:          [StrokeSample] = []
    var predictedSamples: [StrokeSample] = []          // 🔹
    // Persistent, non‑cleared predicted samples for debugging
    var pred_debug:   [StrokeSample] = []
    // What the samples would be without prediction
    var samples_debug:[StrokeSample] = []

    // MARK: mutation
    func add(sample: StrokeSample)               { samples.append(sample) }
    func setPredicted(samples: [StrokeSample])   { predictedSamples = samples } // 🔹
    func clearPredictions()                      { predictedSamples.removeAll() } // 🔹
}

final class StrokeCollection {
    var strokes: [Stroke] = []
    var activeStroke: Stroke?

    /// Move the live stroke into the archive (predictions are discarded).
    func acceptActiveStroke() {
        if let stroke = activeStroke {
            stroke.clearPredictions()   // 🔹 predictions are no longer relevant
            strokes.append(stroke)
            activeStroke = nil
        }
    }
}

// MARK: –– Core Graphics helper ---------------------------------------------

extension CGContext {

    /// Uniform Catmull–Rom spline that *clamps* the ends so the curve
    /// passes through the first and last sample.
    func addCatmullRomPath(points: [CGPoint]) {
        guard points.count >= 2 else { return }

        // 2–3 points → plain segments
        guard points.count >= 4 else {
            move(to: points[0])
            points.dropFirst().forEach { addLine(to: $0) }
            return
        }

        // Duplicate first & last samples
        var pts = points
        pts.insert(points.first!, at: 0)
        pts.append(points.last!)

        move(to: pts[1])                        // original first

        // ⚠️  Stop one segment early → no cubic that ends at the last sample
        for i in 0 ..< pts.count - 4 {          //  … -4  instead of  … -3
            let p0 = pts[i],   p1 = pts[i+1],
                p2 = pts[i+2], p3 = pts[i+3]

            let c1 = CGPoint(x: p1.x + (p2.x - p0.x)/6,
                             y: p1.y + (p2.y - p0.y)/6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x)/6,
                             y: p2.y - (p3.y - p1.y)/6)
            addCurve(to: p2, control1: c1, control2: c2)
        }

        // Straight finish
        addLine(to: points.last!)
    }
    
    func addCentripetalCatmullRom(points: [CGPoint]) {
        guard points.count >= 2 else { return }

        move(to: points[0])

        // Helper to compute parameter t values
        func tj(_ ti: CGFloat, _ pi: CGPoint, _ pj: CGPoint) -> CGFloat {
            return ti + pow(dist(from:pj,to:pi), 0.5)   // α = 0.5
        }

        for i in 0 ..< points.count - 1 {
            let p0 = i > 0 ? points[i-1] : points[i]
            let p1 = points[i]
            let p2 = points[i+1]
            let p3 = i+2 < points.count ? points[i+2] : points[i+1]

            let t0: CGFloat = 0
            let t1 = tj(t0, p0, p1)
            let t2 = tj(t1, p1, p2)
            let t3 = tj(t2, p2, p3)

            // Calculate the control points for the cubic between p1 and p2
            let m1 = (p2 - p0)*( (t2 - t1)/(t2 - t0) )
            let m2 = (p3 - p1)*( (t2 - t1)/(t3 - t1) )

            let c1 = p1 + m1/3
            let c2 = p2 - m2/3

            addCurve(to: p2, control1: c1, control2: c2)
        }
    }
    func dist(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let xDistance = point2.x - point1.x
        let yDistance = point2.y - point1.y
        return sqrt(xDistance * xDistance + yDistance * yDistance)
    }
}

fileprivate func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}
fileprivate func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}
fileprivate func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
    CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}
fileprivate func /(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
    CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
}
// MARK: –– SwiftUI bridge ----------------------------------------------------

struct DemoViewRepresentable: UIViewRepresentable {
    @Binding var strokeCollection: StrokeCollection

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DemoView {
        let v = DemoView()
        v.strokeCollection = context.coordinator.strokeCollection
        return v
    }

    func updateUIView(_ uiView: DemoView, context: Context) {
        uiView.strokeCollection = context.coordinator.strokeCollection
    }

    final class Coordinator: NSObject {
        var parent: DemoViewRepresentable
        var strokeCollection: StrokeCollection
        init(_ parent: DemoViewRepresentable) {
            self.parent = parent
            self.strokeCollection = parent.strokeCollection
        }
    }
}

// MARK: –– The drawing surface ----------------------------------------------

final class DemoView: UIView {

    // Optional debug throttle
    private let slowDown: TimeInterval = 0.0

    // Injected from SwiftUI wrapper
    var strokeCollection: StrokeCollection? {
        didSet { if oldValue !== strokeCollection { setNeedsDisplay() } }
    }

    // MARK: init
    override init(frame: CGRect) { super.init(frame: frame); commonInit() }
    required init?(coder: NSCoder) { super.init(coder: coder); commonInit() }

    private func commonInit() {
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
        isMultipleTouchEnabled = false
    }

    // MARK: drawing
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext(),
              let col = strokeCollection else { return }

        col.strokes.forEach { draw(stroke: $0, in: c, isActive: false) }
        if let live = col.activeStroke {
            draw(stroke: live, in: c, isActive: true)
        }
    }

    private func draw(stroke: Stroke, in ctx: CGContext, isActive: Bool = true) {
        guard stroke.samples.count > 1 else { return }

        // Actual (red) stroke
        ctx.beginPath()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(5)
        UIColor.red.setStroke()

        let actualPoints = stroke.samples.map(\.location)
//        ctx.addCatmullRomPath(points: actualPoints)
        ctx.addCentripetalCatmullRom(points: actualPoints)
        ctx.strokePath()

        // Predicted (blue) – straight lines feel snappier and never overshoot
        if isActive && !stroke.predictedSamples.isEmpty {
            ctx.beginPath()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(4)
            UIColor.blue.withAlphaComponent(0.6).setStroke()

            var predictedPath = [actualPoints.last!]
            predictedPath.append(contentsOf: stroke.predictedSamples.map(\.location))
            ctx.addLines(between: predictedPath)
            ctx.strokePath()
        }

        // Debug (green) – unchanged
        if stroke.samples_debug.count > 1 {
            ctx.beginPath()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(5)
            UIColor.green.setStroke()

            let sampleDebug = stroke.samples_debug.map(\.location)
            ctx.addCatmullRomPath(points: sampleDebug)
            ctx.strokePath()
        }
    }

    // MARK: touch handling ----------------------------------------------------

    private var lastSampleTime: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let collection = strokeCollection else { return }

        let stroke = Stroke()
        collection.activeStroke = stroke

        // Actual samples
        if let coalesced = event?.coalescedTouches(for: touch) {
            addSamples(coalesced, to: stroke, coalesced: true)
        } else {
            stroke.add(sample: .init(point: touch.preciseLocation(in: self)))
        }

        // Predictions
        updatePredictions(from: touch, event: event, for: stroke)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let stroke = strokeCollection?.activeStroke else { return }

        if slowDown > 0 {
            let now = touch.timestamp
            guard now - lastSampleTime >= slowDown else { return }
            lastSampleTime = now
        }

        stroke.add(sample: .init(point: touch.preciseLocation(in: self)))
        updatePredictions(from: touch, event: event, for: stroke)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let collection = strokeCollection else { return }

        if let touch = touches.first,
           let coalesced = event?.coalescedTouches(for: touch),
           let stroke = collection.activeStroke {
            addSamples(coalesced, to: stroke, coalesced: true)
            updatePredictions(from: touch, event: event, for: stroke)
        }

        collection.acceptActiveStroke()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        strokeCollection?.activeStroke = nil
        setNeedsDisplay()
    }

    // MARK: helpers -----------------------------------------------------------

    private func addSamples(_ touches: [UITouch],
                            to stroke: Stroke,
                            coalesced: Bool) {
        touches.forEach {
            stroke.add(sample: .init(point: $0.preciseLocation(in: self),
                                     coalesced: coalesced))
        }
    }

    private func updatePredictions(from touch: UITouch,
                                   event: UIEvent?,
                                   for stroke: Stroke) {
        guard let preds = event?.predictedTouches(for: touch),
              !preds.isEmpty else {
            stroke.clearPredictions()
            return
        }

        let predicted = preds.map { StrokeSample(point: $0.preciseLocation(in: self)) }
        stroke.setPredicted(samples: predicted)
    }
}
