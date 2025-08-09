import Foundation
import UIKit
import CoreML

// Temporal lifter scaffold: tries to load a CoreML model named 'VideoPose3D.mlmodelc'.
// If absent, applies a windowed moving-average smoothing across all joints as an offline pass.
final class PoseLifter {
    private var model: MLModel?
    private var prepared = false

    func prepareIfNeeded() { prepared = true }

    func lift(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard !frames.isEmpty else { return frames }
        // Model disabled per request; return simple smoother
        return smoothAllJoints(frames: frames, window: 5)
        // Unreachable due to early return above
    }

    // Windowed moving-average smoothing across the clip (offline, low-lag not required)
    private func smoothAllJoints(frames: [(image: UIImage, joints: [Int: CGPoint])], window: Int) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard window > 1, frames.count > window else { return frames }
        var result = frames
        let jointCount = 33
        // Build sequences per joint
        var xs = Array(repeating: [CGFloat](), count: jointCount)
        var ys = Array(repeating: [CGFloat](), count: jointCount)
        var present = Array(repeating: [Bool](), count: jointCount)
        xs = xs.map { _ in Array(repeating: 0, count: frames.count) }
        ys = ys.map { _ in Array(repeating: 0, count: frames.count) }
        present = present.map { _ in Array(repeating: false, count: frames.count) }
        for (i, f) in frames.enumerated() {
            for j in 0..<jointCount {
                if let p = f.joints[j] { xs[j][i] = p.x; ys[j][i] = p.y; present[j][i] = true }
            }
        }
        func movAvg(_ v: [CGFloat], mask: [Bool], w: Int) -> [CGFloat] {
            let n = v.count
            guard n > w else { return v }
            var out = v
            var sum: CGFloat = 0
            var cnt: Int = 0
            let half = w/2
            // init window
            for i in 0..<w { if mask[i] { sum += v[i]; cnt += 1 } }
            if cnt > 0 { out[half] = sum / CGFloat(cnt) }
            for i in w..<n {
                if mask[i] { sum += v[i]; cnt += 1 }
                if mask[i - w] { sum -= v[i - w]; cnt -= 1 }
                let c = i - half
                if c < n, cnt > 0 { out[c] = sum / CGFloat(cnt) }
            }
            return out
        }
        for j in 0..<jointCount {
            let sx = movAvg(xs[j], mask: present[j], w: window)
            let sy = movAvg(ys[j], mask: present[j], w: window)
            for i in 0..<frames.count where present[j][i] {
                var joints = result[i].joints
                joints[j] = CGPoint(x: sx[i], y: sy[i])
                result[i] = (image: result[i].image, joints: joints)
            }
        }
        return result
    }

    // MARK: - Helpers
    private func cocoToBlazeMap() -> [(coco: Int, blaze: Int)] {
        // COCO17 -> BlazePose indices
        return [
            (0, 0),    // nose
            (1, 2),    // left eye
            (2, 5),    // right eye
            (3, 7),    // left ear
            (4, 8),    // right ear
            (5, 11),   // left shoulder
            (6, 12),   // right shoulder
            (7, 13),   // left elbow
            (8, 14),   // right elbow
            (9, 15),   // left wrist
            (10, 16),  // right wrist
            (11, 23),  // left hip
            (12, 24),  // right hip
            (13, 25),  // left knee
            (14, 26),  // right knee
            (15, 27),  // left ankle
            (16, 28)   // right ankle
        ]
    }

    private func mapBlazePoseToCOCO17(frames: [(image: UIImage, joints: [Int: CGPoint])]) -> [[CGPoint]] {
        let map = cocoToBlazeMap()
        var result: [[CGPoint]] = Array(repeating: Array(repeating: .zero, count: 17), count: frames.count)
        for (i, f) in frames.enumerated() {
            var row = Array(repeating: CGPoint.zero, count: 17)
            for (c, b) in map {
                if let p = f.joints[b] { row[c] = p } else { row[c] = .zero }
            }
            result[i] = row
        }
        return result
    }

    private func fitWeakPerspective(source: [CGPoint], target: [CGPoint]) -> (s: CGFloat, tx: CGFloat, ty: CGFloat) {
        // Solve s, tx, ty minimizing sum |s*src + t - tgt|^2
        var sx: CGFloat = 0, sy: CGFloat = 0, txSum: CGFloat = 0, tySum: CGFloat = 0, ss: CGFloat = 0
        let n = min(source.count, target.count)
        guard n > 0 else { return (1, 0, 0) }
        for i in 0..<n { sx += source[i].x; sy += source[i].y; txSum += target[i].x; tySum += target[i].y; ss += source[i].x*source[i].x + source[i].y*source[i].y }
        let mx = sx / CGFloat(n), my = sy / CGFloat(n)
        let ux = txSum / CGFloat(n), uy = tySum / CGFloat(n)
        var num: CGFloat = 0
        for i in 0..<n {
            let xs = source[i].x - mx, ys = source[i].y - my
            let xt = target[i].x - ux, yt = target[i].y - uy
            num += xs*xt + ys*yt
        }
        let den = ss - CGFloat(n) * (mx*mx + my*my)
        let s = den != 0 ? num / den : 1
        let tx = ux - s * mx
        let ty = uy - s * my
        return (s, tx, ty)
    }
}

