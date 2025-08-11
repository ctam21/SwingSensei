import Foundation
import UIKit
import CoreImage

// Detects dominant line orientation inside an ROI using CoreImage line overlay + PCA
final class ClubCueDetector {
    private let ciContext = CIContext(options: nil)

    struct Result {
        let angleRadians: CGFloat // angle of dominant line in image coords
        let confidence: CGFloat   // 0..1
    }

    func detectDominantLine(in image: UIImage, roi: CGRect, priorAngleRadians: CGFloat? = nil) -> Result? {
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let pixelRect = CGRect(x: roi.origin.x * scale,
                               y: roi.origin.y * scale,
                               width: roi.size.width * scale,
                               height: roi.size.height * scale).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        let ci = CIImage(cgImage: cropped)
        guard let lineOverlay = CIFilter(name: "CILineOverlay") else { return nil }
        lineOverlay.setValue(ci, forKey: kCIInputImageKey)
        // Defaults of CILineOverlay are reasonable; could tune if needed
        guard let out = lineOverlay.outputImage,
              let outCG = ciContext.createCGImage(out, from: out.extent) else { return nil }

        // Sample grayscale intensities and collect strong edge points
        guard let data = outCG.dataProvider?.data as Data?,
              let provider = outCG.dataProvider else { return nil }
        let bytes = CFDataGetBytePtr(provider.data)
        let width = outCG.width
        let height = outCG.height
        let bytesPerRow = outCG.bytesPerRow
        let bpp = outCG.bitsPerPixel / 8
        var points: [CGPoint] = []
        points.reserveCapacity(1024)
        let step = max(1, min(width, height) / 80) // subsample
        for y in stride(from: 0, to: height, by: step) {
            let row = bytes! + y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                let px = row + x * bpp
                // Assuming BGRA/RGBA; take luminance approx
                let r = CGFloat(px[0])
                let g = CGFloat(px[1])
                let b = CGFloat(px[2])
                let lum = (0.299*r + 0.587*g + 0.114*b) / 255.0
                if lum > 0.75 { // strong line pixel
                    points.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    if points.count >= 3000 { break }
                }
            }
            if points.count >= 3000 { break }
        }
        guard points.count >= 50 else { return nil }

        // PCA principal axis via covariance
        var meanX: CGFloat = 0, meanY: CGFloat = 0
        for p in points { meanX += p.x; meanY += p.y }
        let n = CGFloat(points.count)
        meanX /= n; meanY /= n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            let dx = p.x - meanX
            let dy = p.y - meanY
            sxx += dx*dx; syy += dy*dy; sxy += dx*dy
        }
        sxx /= n; syy /= n; sxy /= n
        // principal angle = 0.5 * atan2(2*sxy, sxx - syy)
        var angle = 0.5 * atan2(2*sxy, sxx - syy)
        // Confidence from anisotropy: (lambda1 - lambda2) / (lambda1 + lambda2)
        // For 2x2 covariance, trace = sxx + syy, det = sxx*syy - sxy^2
        let trace = sxx + syy
        let temp = sqrt(max(0, (sxx - syy)*(sxx - syy) + 4*sxy*sxy))
        let lambda1 = 0.5 * (trace + temp)
        let lambda2 = 0.5 * (trace - temp)
        let ani = (lambda1 + lambda2) > 0 ? (lambda1 - lambda2) / (lambda1 + lambda2) : 0
        var conf = min(1, max(0, ani))

        // If a prior angle is provided (from forearm direction), bias toward it
        if let prior = priorAngleRadians {
            // Normalize angles to [-pi, pi]
            func wrap(_ a: CGFloat) -> CGFloat { var x = a; while x > .pi { x -= 2 * .pi }; while x <= -.pi { x += 2 * .pi }; return x }
            let a = wrap(angle)
            let p = wrap(prior)
            var d = a - p
            d = wrap(d)
            let deg = abs(d) * 180 / .pi
            // If PCA is weak or far from prior, snap/blend to prior
            if conf < 0.35 || deg > 28 {
                // Blend: more bias as confidence drops or deviation grows
                let w = max(0.6, min(0.95, 1.0 - conf * 0.5))
                angle = wrap(p + (1 - w) * d)
                conf = max(conf, 0.5) // increase trust slightly when using prior
            }
        }

        return Result(angleRadians: angle, confidence: conf)
    }

    // Estimate club tip by scanning along the detected shaft direction from the hand center
    // Returns the most distal point with strong edge energy, with reasonable fallbacks
    func estimateTip(in image: UIImage, handCenter: CGPoint, shaftAngle: CGFloat, roi: CGRect) -> CGPoint? {
        guard let edgesOut = makeEdgesCGImage(from: image, roi: roi), let provider = edgesOut.dataProvider else { return nil }
        let bytes = CFDataGetBytePtr(provider.data)
        let width = edgesOut.width
        let height = edgesOut.height
        let bytesPerRow = edgesOut.bytesPerRow
        let bpp = max(1, edgesOut.bitsPerPixel / 8)

        func lum(_ x: Int, _ y: Int) -> CGFloat {
            guard x >= 0, y >= 0, x < width, y < height, let base = bytes else { return 0 }
            let p = base + y * bytesPerRow + x * bpp
            let r = CGFloat(p[0])
            let g = CGFloat(p[min(1, bpp-1)])
            let b = CGFloat(p[min(2, bpp-1)])
            return (0.299*r + 0.587*g + 0.114*b) / 255.0
        }

        // Convert to ROI-local pixel coordinates
        let scale = image.scale
        let startX = Int(((handCenter.x - roi.origin.x) * scale).rounded())
        let startY = Int(((handCenter.y - roi.origin.y) * scale).rounded())
        let maxLenPts: CGFloat = max(roi.width, roi.height) * 1.2
        let stepPts: CGFloat = 2.0
        let dir = CGPoint(x: cos(shaftAngle), y: sin(shaftAngle))
        let energyThresh: CGFloat = 0.18

        func march(sign: CGFloat) -> (found: Bool, tipX: Int, tipY: Int) {
            var lastX = startX
            var lastY = startY
            var found = false
            var s: CGFloat = 0
            while s <= maxLenPts {
                let x = Int(((handCenter.x - roi.origin.x + dir.x * s * sign) * scale).rounded())
                let y = Int(((handCenter.y - roi.origin.y + dir.y * s * sign) * scale).rounded())
                if lum(x, y) > energyThresh { lastX = x; lastY = y; found = true }
                s += stepPts
            }
            return (found, lastX, lastY)
        }

        let forward = march(sign: 1)
        let backward = march(sign: -1)
        let pick = forward.found ? forward : backward
        guard pick.found else { return nil }
        let tipPts = CGPoint(x: CGFloat(pick.tipX) / scale + roi.origin.x, y: CGFloat(pick.tipY) / scale + roi.origin.y)
        return tipPts
    }

    // Auto mode: if no reliable shaft angle, sweep angles and pick the longest high-energy run
    func estimateTipAuto(in image: UIImage, handCenter: CGPoint, roi: CGRect, hintAngle: CGFloat? = nil) -> CGPoint? {
        guard let edgesOut = makeEdgesCGImage(from: image, roi: roi), let provider = edgesOut.dataProvider else { return nil }
        let bytes = CFDataGetBytePtr(provider.data)
        let width = edgesOut.width
        let height = edgesOut.height
        let bytesPerRow = edgesOut.bytesPerRow
        let bpp = max(1, edgesOut.bitsPerPixel / 8)
        let scale = image.scale

        func lum(_ x: Int, _ y: Int) -> CGFloat {
            guard x >= 0, y >= 0, x < width, y < height, let base = bytes else { return 0 }
            let p = base + y * bytesPerRow + x * bpp
            let r = CGFloat(p[0])
            let g = CGFloat(p[min(1, bpp-1)])
            let b = CGFloat(p[min(2, bpp-1)])
            return (0.299*r + 0.587*g + 0.114*b) / 255.0
        }

        let startX = Int(((handCenter.x - roi.origin.x) * scale).rounded())
        let startY = Int(((handCenter.y - roi.origin.y) * scale).rounded())
        let maxLenPts: CGFloat = max(roi.width, roi.height) * 1.2
        let stepPts: CGFloat = 2.0
        let energyThresh: CGFloat = 0.16

        func scan(angle: CGFloat) -> (len: CGFloat, tip: CGPoint)? {
            var lastGoodX = startX
            var lastGoodY = startY
            var found = false
            var s: CGFloat = 0
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            while s <= maxLenPts {
                let x = Int(((handCenter.x - roi.origin.x + dir.x * s) * scale).rounded())
                let y = Int(((handCenter.y - roi.origin.y + dir.y * s) * scale).rounded())
                if lum(x, y) > energyThresh { lastGoodX = x; lastGoodY = y; found = true }
                s += stepPts
            }
            if !found { return nil }
            let tipPts = CGPoint(x: CGFloat(lastGoodX) / scale + roi.origin.x, y: CGFloat(lastGoodY) / scale + roi.origin.y)
            return (len: s, tip: tipPts)
        }

        var candidateAngles: [CGFloat] = []
        if let hint = hintAngle {
            // ±30° around hint, step 5°
            let span: CGFloat = .pi / 6
            let step: CGFloat = .pi / 36
            var a = hint - span
            while a <= hint + span { candidateAngles.append(a); a += step }
        } else {
            // 0..180° sweep
            let step: CGFloat = .pi / 24
            var a: CGFloat = 0
            while a < .pi { candidateAngles.append(a); a += step }
        }

        var best: (len: CGFloat, tip: CGPoint)? = nil
        for a in candidateAngles {
            if let r = scan(angle: a) {
                if best == nil || r.len > best!.len { best = r }
            }
        }

        // Fallback: try opposite directions as well
        if best == nil {
            for a in candidateAngles.map({ $0 + .pi }) {
                if let r = scan(angle: a) {
                    if best == nil || r.len > best!.len { best = r }
                }
            }
        }

        // Final fallback: default length forward
        if let b = best { return b.tip }
        let fallbackLen: CGFloat = min(300, maxLenPts * 0.5)
        let dir = CGPoint(x: cos(hintAngle ?? 0), y: sin(hintAngle ?? 0))
        return CGPoint(x: handCenter.x + dir.x * fallbackLen, y: handCenter.y + dir.y * fallbackLen)
    }

    private func makeEdgesCGImage(from image: UIImage, roi: CGRect) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let pixelRect = CGRect(x: roi.origin.x * scale,
                                y: roi.origin.y * scale,
                                width: roi.size.width * scale,
                                height: roi.size.height * scale).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        // Pre-sharpen for better edge contrast
        let ci = CIImage(cgImage: cropped).applyingFilter("CIUnsharpMask", parameters: [kCIInputIntensityKey: 0.7, kCIInputRadiusKey: 2.0])
        guard let edges = CIFilter(name: "CIEdges") else { return nil }
        edges.setValue(ci, forKey: kCIInputImageKey)
        guard let out = edges.outputImage, let outCG = ciContext.createCGImage(out, from: out.extent) else { return nil }
        return outCG
    }
}

