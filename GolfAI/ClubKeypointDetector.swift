import Foundation
import UIKit
#if canImport(Vision)
import Vision
#endif

struct ClubKeypointsResult {
    let butt: CGPoint
    let mid: CGPoint
    let face: CGPoint
    let toe: CGPoint?
    let confidence: CGFloat
}

final class ClubKeypointDetector {
    #if canImport(Vision)
    private var vnModel: VNCoreMLModel?
    #endif
    private var isPrepared: Bool = false

    func prepareIfNeeded() async -> Bool {
        if isPrepared { return true }
        #if canImport(Vision)
        // Attempt to load a compiled CoreML model if present in bundle
        if let url = Bundle.main.url(forResource: "ClubKeypoints", withExtension: "mlmodelc") {
            do {
                let coreMLModel = try MLModel(contentsOf: url)
                vnModel = try VNCoreMLModel(for: coreMLModel)
                isPrepared = true
            } catch {
                isPrepared = false
            }
        }
        #endif
        return isPrepared
    }

    func detect(in image: UIImage, roi: CGRect?) -> ClubKeypointsResult? {
        // If model is available, run it via Vision; otherwise return nil to allow fallback
        #if canImport(Vision)
        if let vnModel {
            let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
            let request = VNCoreMLRequest(model: vnModel)
            do {
                try handler.perform([request])
                if let observations = request.results as? [VNRecognizedPointsObservation], let obs = observations.first {
                    // Expect 3-4 labeled points: butt, mid, face, toe
                    var dict: [String: VNRecognizedPoint] = [:]
                    // VNRecognizedPointsObservation exposes points by key string
                    for rawKey in obs.availableKeys {
                        if let p = try? obs.recognizedPoint(forKey: rawKey) { dict[rawKey.rawValue] = p }
                    }
                    func toPt(_ rp: VNRecognizedPoint?) -> CGPoint? {
                        guard let rp else { return nil }
                        // VN points are normalized (0..1) with origin bottom-left for CGImage
                        let w = image.size.width
                        let h = image.size.height
                        return CGPoint(x: CGFloat(rp.x) * w, y: CGFloat(1 - rp.y) * h)
                    }
                    let butt = toPt(dict["butt"]) ?? .zero
                    let mid = toPt(dict["mid"]) ?? .zero
                    let face = toPt(dict["face"]) ?? .zero
                    let toe = toPt(dict["toe"]) 
                    let c1 = dict["butt"]?.confidence ?? 0
                    let c2 = dict["mid"]?.confidence ?? 0
                    let c3 = dict["face"]?.confidence ?? 0
                    let conf = CGFloat(min(1.0, max(0.0, (c1 + c2 + c3) / 3.0)))
                    return ClubKeypointsResult(butt: butt, mid: mid, face: face, toe: toe, confidence: conf)
                }
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}


