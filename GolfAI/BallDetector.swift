import Foundation
import UIKit
import CoreImage

struct BallDetection {
    let center: CGPoint
    let radius: CGFloat
    let confidence: CGFloat
}

final class BallDetector {
    private let context = CIContext(options: nil)

    func detect(in image: UIImage, searchBelow yMin: CGFloat? = nil) -> BallDetection? {
        guard let cg = image.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)
        // Mild color bias toward white ball
        ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.6, kCIInputContrastKey: 1.1])
        // Edge enhance
        ci = ci.applyingFilter("CIUnsharpMask", parameters: [kCIInputIntensityKey: 0.7, kCIInputRadiusKey: 1.6])
        guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }

        let width = out.width
        let height = out.height
        let bytesPerRow = out.bytesPerRow
        let bpp = max(1, out.bitsPerPixel / 8)
        guard let base = out.dataProvider?.data, let bytes = CFDataGetBytePtr(base) else { return nil }

        // Simple circular Hough-like score by sampling intensity around candidate centers
        let minR = max(6, min(width, height) / 80)
        let maxR = max(10, min(width, height) / 30)
        let step = 6
        var best: (cx:Int, cy:Int, r:Int, score:Double)? = nil
        let yStart = yMin != nil ? Int(yMin! * image.scale) : 0
        for cy in stride(from: yStart, to: height, by: step) {
            for cx in stride(from: 0, to: width, by: step) {
                var localBest: (r:Int, s:Double) = (0, 0)
                var r = minR
                while r <= maxR {
                    var s: Double = 0
                    let samples = 24
                    for k in 0..<samples {
                        let theta = Double(k) * 2.0 * .pi / Double(samples)
                        let px = cx + Int(Double(r) * cos(theta))
                        let py = cy + Int(Double(r) * sin(theta))
                        if px < 0 || py < 0 || px >= width || py >= height { continue }
                        let p = bytes + py * bytesPerRow + px * bpp
                        // prefer bright pixels (white ball)
                        let r8 = Double(p[0]); let g8 = Double(p[min(1,bpp-1)]); let b8 = Double(p[min(2,bpp-1)])
                        let lum = 0.299*r8 + 0.587*g8 + 0.114*b8
                        s += lum
                    }
                    if s > localBest.s { localBest = (r, s) }
                    r += 2
                }
                if best == nil || localBest.s > best!.score {
                    best = (cx, cy, localBest.r, localBest.s)
                }
            }
        }
        guard let b = best else { return nil }
        let scale = image.scale
        return BallDetection(center: CGPoint(x: CGFloat(b.cx) / scale, y: CGFloat(b.cy) / scale), radius: CGFloat(b.r) / scale, confidence: 1.0)
    }
}


