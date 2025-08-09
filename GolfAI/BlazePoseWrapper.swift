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
        options.minPoseDetectionConfidence = 0.1  // Much lower threshold to detect poses in challenging frames
        options.minPosePresenceConfidence = 0.1   // Much lower threshold to detect poses in challenging frames
        options.minTrackingConfidence = 0.1       // Much lower threshold to detect poses in challenging frames
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
        
        print("🔍 Detected \(poseLandmarks.count) landmarks")
        print("🔍 Image size in processPoseResult: \(imageSize)")
        
        // The result provides 33 landmarks for the detected pose
        // MediaPipe provides normalized coordinates (0-1), so we need to convert to pixel coordinates
        var landmarkPoints: [Int: CGPoint] = [:]
        
        for (index, landmark) in poseLandmarks.enumerated() {
            // Debug: Print the raw values from MediaPipe
            print("🔍 Raw MediaPipe landmark \(index): x=\(landmark.x), y=\(landmark.y)")
            
            // Convert normalized coordinates (0-1) to pixel coordinates
            let pixelX = CGFloat(landmark.x) * imageSize.width
            let pixelY = CGFloat(landmark.y) * imageSize.height
            
            // Much more permissive validation - allow coordinates outside image bounds
            // This ensures all dots show up, even if they seem to be in unusual positions
            let tolerance: CGFloat = 200 // Much larger tolerance for edge cases
            let isValidX = pixelX >= -tolerance && pixelX <= imageSize.width + tolerance
            let isValidY = pixelY >= -tolerance && pixelY <= imageSize.height + tolerance
            
            // Always include the landmark, even if coordinates seem unusual
            // This ensures all dots are visible for analysis
            let cgPoint = CGPoint(x: pixelX, y: pixelY)
            landmarkPoints[index] = cgPoint
            print("✅ Landmark \(index): (\(pixelX), \(pixelY))")
        }
        
        print("✅ Processed \(landmarkPoints.count) valid landmarks")
        return landmarkPoints
    }
}
