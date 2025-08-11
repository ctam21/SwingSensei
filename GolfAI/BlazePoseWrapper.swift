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
        // More permissive thresholds to keep detections in challenging frames
        options.minPoseDetectionConfidence = 0.1
        options.minPosePresenceConfidence = 0.1
        options.minTrackingConfidence = 0.1
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
