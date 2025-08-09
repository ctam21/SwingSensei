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

    func detectDominantLine(in image: UIImage, roi: CGRect) -> Result? {
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
        let angle = 0.5 * atan2(2*sxy, sxx - syy)
        // Confidence from anisotropy: (lambda1 - lambda2) / (lambda1 + lambda2)
        // For 2x2 covariance, trace = sxx + syy, det = sxx*syy - sxy^2
        let trace = sxx + syy
        let temp = sqrt(max(0, (sxx - syy)*(sxx - syy) + 4*sxy*sxy))
        let lambda1 = 0.5 * (trace + temp)
        let lambda2 = 0.5 * (trace - temp)
        let ani = (lambda1 + lambda2) > 0 ? (lambda1 - lambda2) / (lambda1 + lambda2) : 0
        let conf = min(1, max(0, ani))

        return Result(angleRadians: angle, confidence: conf)
    }
}

