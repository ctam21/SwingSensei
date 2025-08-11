import SwiftUI
import CoreGraphics

struct PoseOverlayView: View {
    let frames: [(image: UIImage, joints: [Int: CGPoint])]

    var body: some View {
        ZStack {
            // Background image - changed to .fill to make it bigger
            Image(uiImage: frames[0].image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()

            // Pose overlay
            Canvas { context, size in
                let joints = frames[0].joints
                
                // Debug: Print what we have
                print("🔍 PoseOverlayView - Canvas size: \(size), Joints count: \(joints.count)")
                
                // Only draw if we have landmarks
                guard !joints.isEmpty else { 
                    print("❌ No joints to draw")
                    return 
                }
                
                // Calculate the actual image bounds within the Canvas
                // This accounts for letterboxing from aspectRatio(contentMode: .fill)
                let imageSize = frames[0].image.size
                let imageAspectRatio = imageSize.width / imageSize.height
                let canvasAspectRatio = size.width / size.height
                
                let imageBounds: CGRect
                if imageAspectRatio > canvasAspectRatio {
                    // Image is wider than canvas - fit to height (crop sides)
                    let imageHeight = size.height
                    let imageWidth = imageHeight * imageAspectRatio
                    let xOffset = (size.width - imageWidth) / 2
                    imageBounds = CGRect(x: xOffset, y: 0, width: imageWidth, height: imageHeight)
                } else {
                    // Image is taller than canvas - fit to width (crop top/bottom)
                    let imageWidth = size.width
                    let imageHeight = imageWidth / imageAspectRatio
                    let yOffset = (size.height - imageHeight) / 2
                    imageBounds = CGRect(x: 0, y: yOffset, width: imageWidth, height: imageHeight)
                }
                
                print("🔍 Image size: \(imageSize), Canvas size: \(size)")
                print("🔍 Image bounds in Canvas: \(imageBounds)")
                
                // Helper to scale points to the actual image bounds
                func scaledPoint(_ point: CGPoint) -> CGPoint {
                    let scaledX = (point.x / imageSize.width) * imageBounds.width + imageBounds.minX
                    let scaledY = (point.y / imageSize.height) * imageBounds.height + imageBounds.minY
                    let scaled = CGPoint(x: scaledX, y: scaledY)
                    print("🔍 Converting pixel (\(point.x), \(point.y)) -> Canvas (\(scaled.x), \(scaled.y))")
                    return scaled
                }
                
                // Helper to validate if a point is within reasonable bounds
                func isValidPoint(_ point: CGPoint) -> Bool {
                    // Check if point is within image bounds with some tolerance
                    let tolerance: CGFloat = 50
                    return point.x >= -tolerance && 
                           point.x <= imageSize.width + tolerance &&
                           point.y >= -tolerance && 
                           point.y <= imageSize.height + tolerance
                }
                
                // Define shorthand for points by index, filtering out invalid points
                var pts: [Int: CGPoint] = [:]
                for (index, point) in joints {
                    if isValidPoint(point) {
                        pts[index] = scaledPoint(point)
                        print("✅ Valid joint \(index): (\(point.x), \(point.y))")
                    } else {
                        print("❌ Invalid joint \(index): (\(point.x), \(point.y)) - SKIPPING")
                    }
                }
                
                var path = Path()
                
                // Draw skeleton connections (deep blue) - removed head connections
                let connections: [(Int, Int)] = [
                    // Shoulders
                    (11, 12), // Left to right shoulder
                    
                    // Arms
                    (11, 13), (13, 15), // Left shoulder -> elbow -> wrist
                    (12, 14), (14, 16), // Right shoulder -> elbow -> wrist
                    
                    // Torso
                    (11, 23), (12, 24), // Shoulders to hips
                    (23, 24), // Left to right hip
                    
                    // Legs
                    (23, 25), (25, 27), (27, 29), // Left hip -> knee -> ankle
                    (24, 26), (26, 28), (28, 30), // Right hip -> knee -> ankle
                ]
                
                for connection in connections {
                    if let p1 = pts[connection.0], let p2 = pts[connection.1] {
                        print("🔗 Drawing connection \(connection.0) -> \(connection.1): (\(p1.x), \(p1.y)) to (\(p2.x), \(p2.y))")
                        path.move(to: p1)
                        path.addLine(to: p2)
                    } else {
                        print("❌ Skipping connection \(connection.0) -> \(connection.1) - missing points")
                    }
                }
                
                context.stroke(path, with: .color(Color(hex: "4CAF50")), lineWidth: 3) // Light Green

                // Draw joints (white) - only key joints
                let keyJoints = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28] // Head, shoulders, elbows, wrists, hips, knees, ankles
                for jointIndex in keyJoints {
                    if let point = pts[jointIndex] {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(Color.white)) // White dots
                    }
                }

                // Club overlays removed
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
