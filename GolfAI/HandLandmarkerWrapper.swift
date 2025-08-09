import Foundation
import UIKit
import MediaPipeTasksVision

final class HandLandmarkerWrapper {
    private var landmarker: HandLandmarker?
    private let modelURLString = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
    private var isPrepared = false
    private var preparingTask: Task<Void, Never>?

    @discardableResult
    func prepareIfNeeded() async -> Bool {
        if isPrepared { return true }
        if let existing = preparingTask { await existing.value; return isPrepared }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let localPath: String
                if let bundled = self.modelPathInBundle() {
                    localPath = bundled
                } else {
                    // Fallback: download to Application Support so it just works
                    localPath = try await self.ensureModelOnDisk()
                }
                let options = HandLandmarkerOptions()
                options.baseOptions.modelAssetPath = localPath
                options.runningMode = .image
                options.minHandDetectionConfidence = 0.5
                options.minHandPresenceConfidence = 0.5
                options.minTrackingConfidence = 0.5
                options.numHands = 2
                self.landmarker = try HandLandmarker(options: options)
                self.isPrepared = true
            } catch {
                print("HandLandmarker prepare failed: \(error)")
                self.landmarker = nil
                self.isPrepared = false
            }
        }
        preparingTask = task
        await task.value
        preparingTask = nil
        return isPrepared
    }

    // Returns up to 2 wrist points in image coordinates (closest to image wrists later)
    func detectWrists(in image: UIImage) -> [CGPoint] {
        guard let landmarker = landmarker else { return [] }
        do {
            let mpImage = try MPImage(uiImage: image)
            let result = try landmarker.detect(image: mpImage)
            var wrists: [CGPoint] = []
            let width = image.size.width
            let height = image.size.height
            for hand in result.landmarks {
                if let wrist = hand.first { // index 0 is wrist
                    let p = CGPoint(x: CGFloat(wrist.x) * width, y: CGFloat(wrist.y) * height)
                    wrists.append(p)
                }
            }
            return wrists
        } catch {
            print("HandLandmarker detect failed: \(error)")
            return []
        }
    }

    // ROI-based detection to reduce false positives and speed up; returns points in full-image coordinates
    func detectWrists(in image: UIImage, roi: CGRect) -> [CGPoint] {
        guard let landmarker = landmarker else { return [] }
        // Clamp ROI to image bounds
        let imgRect = CGRect(origin: .zero, size: image.size)
        let clamped = imgRect.intersection(roi)
        guard !clamped.isNull, clamped.width > 4, clamped.height > 4 else { return [] }
        guard let cropped = crop(image: image, to: clamped) else { return [] }
        do {
            let mpImage = try MPImage(uiImage: cropped)
            let result = try landmarker.detect(image: mpImage)
            var wrists: [CGPoint] = []
            let width = cropped.size.width
            let height = cropped.size.height
            for hand in result.landmarks {
                if let wrist = hand.first {
                    let local = CGPoint(x: CGFloat(wrist.x) * width, y: CGFloat(wrist.y) * height)
                    // Map back to full image coords
                    let global = CGPoint(x: local.x + clamped.origin.x, y: local.y + clamped.origin.y)
                    wrists.append(global)
                }
            }
            return wrists
        } catch {
            print("HandLandmarker detect(roi) failed: \(error)")
            return []
        }
    }

    struct HandDetection {
        let landmarks: [CGPoint] // 21 hand landmarks in image coordinates
    }

    // Returns full 21-point landmarks for each detected hand in the ROI, mapped to full image coordinates
    func detectHandLandmarks(in image: UIImage, roi: CGRect) -> [HandDetection] {
        guard let landmarker = landmarker else { return [] }
        let imgRect = CGRect(origin: .zero, size: image.size)
        let clamped = imgRect.intersection(roi)
        guard !clamped.isNull, clamped.width > 4, clamped.height > 4 else { return [] }
        guard let cropped = crop(image: image, to: clamped) else { return [] }
        do {
            let mpImage = try MPImage(uiImage: cropped)
            let result = try landmarker.detect(image: mpImage)
            var detections: [HandDetection] = []
            let width = cropped.size.width
            let height = cropped.size.height
            for hand in result.landmarks {
                var pts: [CGPoint] = []
                pts.reserveCapacity(hand.count)
                for lm in hand {
                    let local = CGPoint(x: CGFloat(lm.x) * width, y: CGFloat(lm.y) * height)
                    let global = CGPoint(x: local.x + clamped.origin.x, y: local.y + clamped.origin.y)
                    pts.append(global)
                }
                detections.append(HandDetection(landmarks: pts))
            }
            return detections
        } catch {
            print("HandLandmarker detectHandLandmarks(roi) failed: \(error)")
            return []
        }
    }

    private func crop(image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func modelPathInBundle() -> String? {
        return Bundle.main.path(forResource: "hand_landmarker", ofType: "task")
    }

    // Fallback downloader to Application Support for seamless first run
    private func ensureModelOnDisk() async throws -> String {
        let fm = FileManager.default
        let supportDir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let modelURL = supportDir.appendingPathComponent("hand_landmarker.task")
        if fm.fileExists(atPath: modelURL.path) {
            return modelURL.path
        }
        guard let remote = URL(string: modelURLString) else { throw NSError(domain: "HandModel", code: -1) }
        let (data, _) = try await URLSession.shared.data(from: remote)
        try data.write(to: modelURL, options: .atomic)
        return modelURL.path
    }
}

