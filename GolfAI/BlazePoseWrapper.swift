import Foundation
import UIKit
import MediaPipeTasksVision
import CoreMedia

class BlazePoseWrapper {
    private var poseLandmarker: PoseLandmarker?
    private let queue = DispatchQueue(label: "pose.detection", qos: .userInitiated)
    
    init() {
        setupPoseLandmarker()
    }
    
    private func setupPoseLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            fatalError("BlazePose Heavy model file not found")
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video  // Since we are processing video frames
        // Balanced thresholds; we will correct wrists with post-processing
        options.minPoseDetectionConfidence = 0.3
        options.minPosePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3
        options.numPoses = 1  // We expect one golfer in the video
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ BlazePose Heavy model loaded successfully")
        } catch {
            print("❌ Failed to initialize BlazePose: \(error)")
        }
    }
    
    func detectPose(in image: UIImage) -> [Int: CGPoint]? {
        guard let poseLandmarker = poseLandmarker else {
            print("❌ PoseLandmarker not initialized")
            return nil
        }
        
        do {
            // Create MPImage from UIImage (MediaPipe will handle orientation)
            let mpImage = try MPImage(uiImage: image)
            
            // For single image detection, we can use a dummy timestamp
            let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
            
            // Run pose detection
            let result = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
            
            return processPoseResult(result, imageSize: image.size)
            
        } catch {
            print("❌ Pose detection failed: \(error)")
            return nil
        }
    }

    // Detect pose within a ROI. Crops to ROI, upscales short side to ~960px, runs inference, then maps back to full-image coords.
    func detectPose(in image: UIImage, roi: CGRect) -> [Int: CGPoint]? {
        guard let poseLandmarker = poseLandmarker else { return nil }
        // Clamp ROI to image bounds
        let imgRect = CGRect(origin: .zero, size: image.size)
        let cropRect = imgRect.intersection(roi)
        guard !cropRect.isNull, cropRect.width >= 8, cropRect.height >= 8 else {
            return detectPose(in: image)
        }

        // Crop
        guard let cropped = Self.crop(image: image, to: cropRect) else {
            return detectPose(in: image)
        }

        // Upscale short side to ~960px for better keypoint precision
        let shortSide = min(cropped.size.width, cropped.size.height)
        let targetShort: CGFloat = 960
        let scale: CGFloat = shortSide > 0 ? max(1.0, targetShort / shortSide) : 1.0
        let resized = scale > 1.01 ? Self.resize(image: cropped, scale: scale) : cropped
        let resizedSize = resized.size

        do {
            let mpImage = try MPImage(uiImage: resized)
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            let result = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: ts)
            guard let poseLandmarks = result.landmarks.first else { return nil }

            var out: [Int: CGPoint] = [:]
            for (idx, lm) in poseLandmarks.enumerated() {
                // map normalized → resized pixels
                let rx = CGFloat(lm.x) * resizedSize.width
                let ry = CGFloat(lm.y) * resizedSize.height
                // map resized → cropped pixels
                let cx = rx / scale
                let cy = ry / scale
                // map cropped → full-frame pixels
                let gx = cx + cropRect.origin.x
                let gy = cy + cropRect.origin.y
                // clamp to image bounds
                let gxClamped = min(max(gx, 0), image.size.width)
                let gyClamped = min(max(gy, 0), image.size.height)
                out[idx] = CGPoint(x: gxClamped, y: gyClamped)
            }
            return out
        } catch {
            print("❌ ROI pose detection failed: \(error)")
            return detectPose(in: image)
        }
    }

    // MARK: - Helpers
    private static func crop(image: UIImage, to rect: CGRect) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let img = renderer.image { ctx in
            image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        }
        return img
    }

    private static func resize(image: UIImage, scale: CGFloat) -> UIImage {
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let img = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return img
    }
    
    func detectPoseInVideoFrame(_ image: UIImage, timestamp: CMTime) -> [Int: CGPoint]? {
        guard let poseLandmarker = poseLandmarker else {
            print("❌ PoseLandmarker not initialized")
            return nil
        }
        
        do {
            // Create MPImage from UIImage
            let mpImage = try MPImage(uiImage: image)
            
            // Convert CMTime to milliseconds for MediaPipe
            let timestampMs = Int(CMTimeGetSeconds(timestamp) * 1000.0)
            
            // Run pose detection with proper timestamp for video mode
            let result = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
            
            return processPoseResult(result, imageSize: image.size)
            
        } catch {
            print("❌ Video pose detection failed: \(error)")
            return nil
        }
    }
    
    private func processPoseResult(_ result: PoseLandmarkerResult, imageSize: CGSize) -> [Int: CGPoint]? {
        guard let poseLandmarks = result.landmarks.first else {
            print("❌ No pose landmarks detected in frame")
            return nil
        }
        // The result provides 33 landmarks for the detected pose
        // MediaPipe provides normalized coordinates (0-1), so we need to convert to pixel coordinates
        var landmarkPoints: [Int: CGPoint] = [:]
        
        for (index, landmark) in poseLandmarks.enumerated() {
            let pixelX = CGFloat(landmark.x) * imageSize.width
            let pixelY = CGFloat(landmark.y) * imageSize.height
            landmarkPoints[index] = CGPoint(x: pixelX, y: pixelY)
        }
        return landmarkPoints
    }
}
