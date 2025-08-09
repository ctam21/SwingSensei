import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL

    var body: some View {
        GeometryReader { geometry in
            VideoPlayer(player: AVPlayer(url: videoURL))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .frame(width: UIScreen.main.bounds.width * 0.855, height: UIScreen.main.bounds.height * 0.7) // Adjust width and height as needed
    }
}
