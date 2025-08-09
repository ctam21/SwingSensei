import SwiftUI
import AVFoundation
import MediaPipeTasksVision

// MARK: - Root Tab UI (Home, Analyze, Review, Insights, Coach)
struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            AnalyzeViewWrapper()
                .tabItem { Label("Analyze", systemImage: "waveform.badge.magnifyingglass") }
            ReviewViewWrapper()
                .tabItem { Label("Review", systemImage: "play.square.stack") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            CoachView()
                .tabItem { Label("Coach", systemImage: "message.circle.fill") }
        }
        .accentColor(.turf)
    }
}

// Colors helper
extension Color {
    static let slate = Color(hex: "2C3E50")
    static let turf  = Color(hex: "4CAF50")
    static let bg    = Color(hex: "F6F5F2")
    static let ink   = Color(hex: "EAEAEA")
    static let gold  = Color(hex: "C9A86A")
}

// Hex init
extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexSanitized.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: Home
struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Header()
                QuickActionsCard()
                SectionHeader("Recent Analyses")
                RecentAnalysesCarousel()
                SectionHeader("Progress")
                ProgressMiniCharts()
            }
            .padding(20)
            .background(Color.bg.ignoresSafeArea())
        }
        .toolbar { SettingsButton() }
    }
}

// Stubs for components (formatted to avoid brace issues)
struct Header: View {
    var body: some View {
        HStack {
            Image(systemName: "figure.golf").foregroundColor(.slate)
            Text("SwingSensei").font(.title).fontWeight(.bold)
            Spacer()
            ProChip()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
        )
    }
}

struct ProChip: View {
    var body: some View {
        Text("Pro")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.gold.opacity(0.2)))
            .foregroundColor(.slate)
    }
}

struct QuickActionsCard: View {
    var body: some View {
                        VStack(alignment: .leading, spacing: 12) {
            Text("Analyze New Swing").font(.headline)
            HStack { PrimaryButton(title: "Pick Video"); SecondaryButton(title: "Import from Photos") }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 18, y: 6)
        )
    }
}

struct SectionHeader: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        HStack { Text(title).font(.title3).fontWeight(.semibold).foregroundColor(.slate); Spacer() }
    }
}

struct RecentAnalysesCarousel: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<5) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 220, height: 120)
                        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                        .overlay(
                            VStack(alignment: .leading) {
                                Rectangle().fill(Color.bg).frame(height: 70).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text("Jun 12").font(.caption)
                                HStack { Text("Tempo 3:1").font(.caption2); Spacer(); Badge(text: "82") }
                                    .padding(.top, 2)
                            }.padding(10)
                        )
                }
            }
        }
    }
}

struct ProgressMiniCharts: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white)
            .frame(height: 120)
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
            .overlay(Text("Last 7 Days • Tempo / Face / K-Metrics").font(.caption).foregroundColor(.slate))
    }
}

struct SettingsButton: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { Button { } label: { Image(systemName: "gearshape.fill") } }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct PrimaryButton: View { let title: String; var body: some View { Button(title) {}.frame(height:52).frame(maxWidth:.infinity).background(Color.turf).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12)).buttonStyle(PressableButtonStyle()) } }
struct SecondaryButton: View { let title: String; var body: some View { Button(title) {}.frame(height:48).frame(maxWidth:.infinity).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate.opacity(0.6), lineWidth: 1)).foregroundColor(.slate).buttonStyle(PressableButtonStyle()) } }
struct Badge: View { let text:String; var body: some View { Text(text).font(.caption2).padding(.horizontal,8).padding(.vertical,4).background(Capsule().fill(Color.gold.opacity(0.2))) } }

// Analyze tab wraps existing ContentView analyze flow
struct AnalyzeViewWrapper: View { var body: some View { ContentView().navigationBarTitleDisplayMode(.inline) } }
// Review tab shows just the overlay viewer part; for now reuse ContentView until split
struct ReviewViewWrapper: View { var body: some View { ContentView().navigationBarTitleDisplayMode(.inline) } }

// Insights stub
struct InsightsView: View { var body: some View { ScrollView{ VStack(spacing:18){ Text("Insights").font(.title).fontWeight(.bold).foregroundColor(.slate); KPICardsGrid(); TrendCharts(); WorkOnList(); BestFramesGrid() }.padding(16)}.background(Color.bg.ignoresSafeArea()) } }
struct KPICardsGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(height: 90)
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                    .overlay(Text("KPI").foregroundColor(.slate))
            }
        }
    }
}
struct TrendCharts: View { var body: some View { RoundedRectangle(cornerRadius: 16).fill(Color.white).frame(height:160).shadow(color:.black.opacity(0.08),radius:16,y:6).overlay(Text("Trends").foregroundColor(.slate)) } }
struct WorkOnList: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                    .overlay(
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What to work on").font(.headline).foregroundColor(.slate)
                            Text("Drill steps preview").font(.caption)
                        }
                    )
                    .frame(height: 90)
            }
        }
    }
}
struct BestFramesGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(0..<8) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(height: 70)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
        }
    }
}

// Coach stub
struct CoachView: View { var body: some View { VStack{ Text("Coach").font(.title).fontWeight(.bold).foregroundColor(.slate); Spacer() }.padding().background(Color.bg.ignoresSafeArea()) } }

struct ContentView: View {
    @State private var selectedVideoURL: URL?
    @State private var analyzedFrames: [(image: UIImage, joints: [Int: CGPoint])] = []
    private let poseWrapper = BlazePoseWrapper()
    private let handWrapper = HandLandmarkerWrapper()
    // Off-device lifter client
    private let lifterService = LifterService()
    @State private var showVideoPicker = false
    @State private var isProcessing = false
    @State private var isLoading = true
    @State private var processingProgress: Double = 0.0
    @State private var totalFrames: Int = 0
    @State private var processedFrames: Int = 0
    @State private var videoDuration: Double = 0.0
    @State private var estimatedTimeRemaining: Double = 0.0
    @State private var currentFrameIndex: Int = 0
    @State private var swingAnalysis: SwingAnalysis?
    // Enhanced wrist assistance is always ON (no user toggle)
    @State private var detectedFrames: [(image: UIImage, joints: [Int: CGPoint])] = []
    @State private var fusionCount: Int = 0
    @State private var handModelReady: Bool = false

    var body: some View {
            ZStack {
            if isLoading {
                LoadingView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeInOut(duration: 0.8)) {
                                isLoading = false
                            }
                        }
                    }
            } else {
                // Main App Interface
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                                HStack {
                                Image(systemName: "figure.golf")
                                    .font(.title)
                                    .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                                Text("SwingSensei")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                                    .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                            }
                            Text("Traditional Wisdom, Modern Analysis")
                                        .font(.subheadline)
                                .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                                }
                        .padding(.top, 20)
                                
                        // Video Selection Card
                        if selectedVideoURL == nil {
                            Button(action: {
                                showVideoPicker = true
                            }) {
                                HStack {
                                    Image(systemName: "video.circle.fill")
                                    .font(.title2)
                                        .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                                    VStack(alignment: .leading, spacing: 4) {
                                Text("Select Golf Video")
                                    .font(.headline)
                                            .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                                        Text("Choose a video to analyze your swing")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                                }
                                .padding(20)
                        .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.9))
                                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Selected Video Info
                        if selectedVideoURL != nil {
                            VStack(spacing: 16) {
                            HStack {
                                    Image(systemName: "video.circle.fill")
                                    .font(.title2)
                                        .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Selected Video")
                                    .font(.headline)
                                            .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                                        Text("Duration: \(formatDuration(videoDuration))")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                                        Text("Estimated Frames: \(totalFrames)")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                                    }
                                    Spacer()
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.9))
                                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                )

                                // Processing Section
                                if isProcessing {
                                    ProcessingView(
                                        progress: processingProgress,
                                        processedFrames: processedFrames,
                                        totalFrames: totalFrames,
                                        estimatedTimeRemaining: estimatedTimeRemaining
                                    )
                                } else if !analyzedFrames.isEmpty {
                                    AnalysisCompleteView(
                                        analyzedFrames: analyzedFrames,
                                        currentFrameIndex: $currentFrameIndex,
                                        analysis: swingAnalysis,
                                        lifterStatusText: nil
                                    )
                                    // Toggles removed; Enhanced is always on
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                            .background(
                                LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.99, green: 0.97, blue: 0.95),
                            Color(red: 0.95, green: 0.92, blue: 0.88)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        // Toggles removed
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { url in
                selectedVideoURL = url
                let selectedURL = url
                    Task {
                        // Prepare hand landmarker for enhanced path (always on)
                        handModelReady = await handWrapper.prepareIfNeeded()
                        // Temporal lifter removed
                        // Set video info directly
                        let asset = AVURLAsset(url: selectedURL)
                        do {
                            let duration = try await asset.load(.duration)
                            let durationSeconds = CMTimeGetSeconds(duration)
                            videoDuration = durationSeconds
                            totalFrames = Int(durationSeconds * 20) // 20 FPS
                            estimatedTimeRemaining = durationSeconds * 0.8 // Rough estimate
                        } catch {
                            print("Error loading video info: \(error)")
                        }
                        await processVideoFrames()
                    }
                }
            }
        }
    }



    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

// MARK: - Processing View
struct ProcessingView: View {
    let progress: Double
    let processedFrames: Int
    let totalFrames: Int
    let estimatedTimeRemaining: Double

    var body: some View {
                            VStack(spacing: 16) {
                                    HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing swing...")
                                            .font(.headline)
                        .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                    Text("Frame \(min(processedFrames, totalFrames)) of \(totalFrames)")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                }
                                        Spacer()
            }

            // Progress Bar
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.42, green: 0.30, blue: 0.25)))
                    .scaleEffect(y: 2)
                
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                    Spacer()
                    Text("~\(formatDuration(estimatedTimeRemaining)) remaining")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                }
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Analysis Complete View
struct AnalysisCompleteView: View {
    let analyzedFrames: [(image: UIImage, joints: [Int: CGPoint])]
    @Binding var currentFrameIndex: Int
    let analysis: SwingAnalysis? // deprecated (kept to avoid larger refactor)
    // Debug lifter status text (optional)
    let lifterStatusText: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Complete")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                    Text("\(analyzedFrames.count) frames analyzed with BlazePose Heavy")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                }
                Spacer()
            }

            // Frame Display with Navigation
            VStack(spacing: 12) {
                if !analyzedFrames.isEmpty {
                    PoseOverlayView(frames: [analyzedFrames[currentFrameIndex]])
                        .frame(height: 700)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                    // DEBUG badge: show whether server lifter was used
                    #if DEBUG
                    if let lifterStatusText {
                        Text(lifterStatusText)
                        .font(.caption2)
                        .foregroundColor(lifterStatusText.contains("server") ? .green : .orange)
                        .padding(.bottom, 4)
                    }
                    #endif
                    
                    FrameSlider(count: analyzedFrames.count, index: $currentFrameIndex)
                    
            // Scorecard and phase buttons removed per request
                    
                    // Frame Navigation
                    HStack(spacing: 20) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentFrameIndex = max(0, currentFrameIndex - 1)
                            }
                        }) {
                            Image(systemName: "chevron.left.circle.fill")
                                        .font(.title2)
                                .foregroundColor(currentFrameIndex > 0 ? Color(red: 0.42, green: 0.30, blue: 0.25) : Color.gray)
                        }
                        .disabled(currentFrameIndex <= 0)

                        Text("Frame \(currentFrameIndex + 1) of \(analyzedFrames.count)")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                            .frame(minWidth: 100)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentFrameIndex = min(analyzedFrames.count - 1, currentFrameIndex + 1)
                            }
                        }) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title2)
                                .foregroundColor(currentFrameIndex < analyzedFrames.count - 1 ? Color(red: 0.42, green: 0.30, blue: 0.25) : Color.gray)
                        }
                        .disabled(currentFrameIndex >= analyzedFrames.count - 1)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Frame Slider (extracted to help compiler)
struct FrameSlider: View {
    let count: Int
    @Binding var index: Int

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { newVal in
                        let maxIdx = max(count - 1, 0)
                        let clamped = min(max(Int(newVal.rounded()), 0), maxIdx)
                        index = clamped
                    }
                ),
                in: 0...Double(max(count - 1, 0)),
                step: 1
            )
            HStack {
                Text("Frame \(index + 1)")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
            }
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.99, green: 0.97, blue: 0.95),
                    Color(red: 0.95, green: 0.92, blue: 0.88)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // Animated Golf Icon
                Image(systemName: "figure.golf")
                    .font(.system(size: 80))
                    .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 2)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )

                VStack(spacing: 16) {
                    Text("SwingSensei")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))

                    Text("Traditional Wisdom, Modern Analysis")
                        .font(.title3)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                        .multilineTextAlignment(.center)

                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
                        .opacity(isAnimating ? 0.5 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Video Processing
extension ContentView {
    // Re-run the post-processing stack from the last detected frames when toggling experimental path
    func rebuildFromDetected() {
        guard !detectedFrames.isEmpty else { return }
        Task {
            let raw = detectedFrames
            // Enhanced (no temporal lifter): wrist gap fill → identity guard → hand landmarker fusion → club cue → low‑lag smoothing
            let wristGapFilled = fillWristGaps(frames: raw, maxGap: 3)
            let idFixed = enforceArmIdentity(frames: wristGapFilled)
            handModelReady = await handWrapper.prepareIfNeeded()
            let wristsRefined = refineWristsWithHandsKalman(frames: idFixed, fps: 20)
            let withCue = nudgeWristsWithClubCue(frames: wristsRefined, fps: 20)
            let stabilized = stabilizeLowLag(frames: withCue, fps: 20)
            let finalFrames = stabilized.isEmpty ? withCue : stabilized
            // Count fused frames
            var fused = 0
            for i in 0..<min(idFixed.count, wristsRefined.count) {
                let aL = idFixed[i].joints[15]; let bL = wristsRefined[i].joints[15]
                let aR = idFixed[i].joints[16]; let bR = wristsRefined[i].joints[16]
                let movedL = (aL != nil && bL != nil) ? (hypot(aL!.x - bL!.x, aL!.y - bL!.y) > 0.75) : false
                let movedR = (aR != nil && bR != nil) ? (hypot(aR!.x - bR!.x, aR!.y - bR!.y) > 0.75) : false
                if movedL || movedR { fused += 1 }
            }
            fusionCount = fused
            let liftedFrames = finalFrames
            let computedAnalysis: SwingAnalysis? = nil
            await MainActor.run {
                analyzedFrames = liftedFrames
                swingAnalysis = computedAnalysis
                currentFrameIndex = min(currentFrameIndex, max(liftedFrames.count - 1, 0))
            }
        }
    }
    func processVideoFrames() async {
        guard let videoURL = selectedVideoURL else { return }
        
        isProcessing = true
        processingProgress = 0.0
        processedFrames = 0
        analyzedFrames = []
        currentFrameIndex = 0
        
        let asset = AVURLAsset(url: videoURL)
        let reader = try? AVAssetReader(asset: asset)
        
        guard let reader = reader else {
            print("Failed to create AVAssetReader")
            isProcessing = false
            return
        }

                let outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]

        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            print("Failed to load video tracks: \(error)")
            isProcessing = false
            return
        }
        
        guard let track = tracks.first else {
            print("No video tracks found")
            isProcessing = false
            return
        }
        
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )
        
                reader.add(output)
                reader.startReading()

                let interval = CMTimeMakeWithSeconds(0.05, preferredTimescale: 600)
        var currentTime = CMTime.zero
        let startTime = Date()
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if CMTimeCompare(presentationTime, currentTime) >= 0 {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    var ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    ciImage = ciImage.oriented(forExifOrientation: 6)

                        let context = CIContext()
                    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { continue }
                    
                            let uiImage = UIImage(cgImage: cgImage)
                    _ = CGSize(width: uiImage.size.width, height: uiImage.size.height)
                    
                    if let landmarks = poseWrapper.detectPose(in: uiImage) {
                        analyzedFrames.append((image: uiImage, joints: landmarks))
                    }
                    
                    processedFrames += 1
                    // Clamp to avoid off-by-one display and out-of-bounds progress
                    if processedFrames > totalFrames { processedFrames = totalFrames }
                    if totalFrames > 0 {
                        processingProgress = min(1.0, max(0.0, Double(processedFrames) / Double(totalFrames)))
                    } else {
                        processingProgress = 0.0
                    }
                    
                    // Update estimated time remaining
                    let elapsed = Date().timeIntervalSince(startTime)
                    if processedFrames > 0 {
                        let timePerFrame = elapsed / Double(processedFrames)
                        let remainingFrames = totalFrames - processedFrames
                        estimatedTimeRemaining = Double(remainingFrames) * timePerFrame
                    }
                    
                        await MainActor.run {
                        // Update UI on main thread
                    }
                }
                
                currentTime = CMTimeAdd(currentTime, interval)
            }
        }
        // Cache raw detections so toggles can rebuild instantly without re-reading video
        detectedFrames = analyzedFrames
        // Enhanced (no temporal lifter): wrist gap fill → identity guard → hand landmarker fusion → club cue → low‑lag smoothing
        let raw = analyzedFrames
        let wristGapFilled = fillWristGaps(frames: raw, maxGap: 3)
        let idFixed = enforceArmIdentity(frames: wristGapFilled)
        handModelReady = await handWrapper.prepareIfNeeded()
        let wristsRefined = refineWristsWithHandsKalman(frames: idFixed, fps: 20)
        let withCue = nudgeWristsWithClubCue(frames: wristsRefined, fps: 20)
        let stabilized = stabilizeLowLag(frames: withCue, fps: 20)
        let finalFrames: [(image: UIImage, joints: [Int: CGPoint])] = stabilized.isEmpty ? withCue : stabilized
        var fused = 0
        for i in 0..<min(idFixed.count, wristsRefined.count) {
            let aL = idFixed[i].joints[15]; let bL = wristsRefined[i].joints[15]
            let aR = idFixed[i].joints[16]; let bR = wristsRefined[i].joints[16]
            let movedL = (aL != nil && bL != nil) ? (hypot(aL!.x - bL!.x, aL!.y - bL!.y) > 0.75) : false
            let movedR = (aR != nil && bR != nil) ? (hypot(aR!.x - bR!.x, aR!.y - bR!.y) > 0.75) : false
            if movedL || movedR { fused += 1 }
        }
        fusionCount = fused
        let liftedFrames = finalFrames
            let computedAnalysis: SwingAnalysis? = nil
                await MainActor.run {
            isProcessing = false
                analyzedFrames = liftedFrames
            swingAnalysis = computedAnalysis
            if analyzedFrames.isEmpty {
                analyzedFrames = [(image: UIImage(), joints: [:])]
            }
        }
    }
}

// MARK: - Minimal, low-lag stabilization
extension ContentView {
    // Keep wrists consistent across frames to avoid L/R swaps
    func enforceArmIdentity(frames: [(image: UIImage, joints: [Int: CGPoint])]) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 1 else { return frames }
        var result = frames
        let LWR = 15, RWR = 16
        for i in 1..<result.count {
            var cur = result[i].joints
            let prev = result[i-1].joints
            guard let pLW = prev[LWR], let pRW = prev[RWR], var cLW = cur[LWR], var cRW = cur[RWR] else { continue }
            let costNo = hypot(cLW.x - pLW.x, cLW.y - pLW.y) + hypot(cRW.x - pRW.x, cRW.y - pRW.y)
            let costSw = hypot(cLW.x - pRW.x, cLW.y - pRW.y) + hypot(cRW.x - pLW.x, cRW.y - pLW.y)
            if costSw + 2 < costNo {
                swap(&cLW, &cRW); cur[LWR] = cLW; cur[RWR] = cRW
                result[i] = (image: result[i].image, joints: cur)
            }
        }
        return result
    }
    
    // Speed-gated One Euro smoothing for non-wrist joints (avoids lag during fast motion)
    func stabilizeLowLag(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 1, fps > 0 else { return frames }
        var result = frames
        let wrists: Set<Int> = [15, 16]
        let dt: CGFloat = 1.0 / fps
        var fx: [OneEuroFilter] = (0..<33).map { _ in OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02) }
        var fy: [OneEuroFilter] = (0..<33).map { _ in OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02) }
        let speedBypass: CGFloat = 45
        
        // initialize with first frame
        for idx in 0..<33 where !wrists.contains(idx) {
            if let p = result[0].joints[idx] {
                _ = fx[idx].filter(p.x)
                _ = fy[idx].filter(p.y)
            }
        }
        
        for i in 1..<result.count {
            var joints = result[i].joints
            let prev = result[i-1].joints
            for idx in 0..<33 where !wrists.contains(idx) {
                guard let cur = joints[idx], let pre = prev[idx] else { continue }
                let speed = hypot(cur.x - pre.x, cur.y - pre.y)
                if speed > speedBypass { continue }
                joints[idx] = CGPoint(x: fx[idx].filter(cur.x), y: fy[idx].filter(cur.y))
            }
            result[i] = (image: result[i].image, joints: joints)
        }
        return result
    }
}

// MARK: - Wrist-only short-gap interpolation
extension ContentView {
    func fillWristGaps(frames: [(image: UIImage, joints: [Int: CGPoint])], maxGap: Int) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 2, maxGap > 0 else { return frames }
        var result = frames
        let wrists = [15, 16]
        // For wrists only, find gaps of length <= maxGap and linearly interpolate between surrounding valid keyframes
        for jointIdx in wrists {
            var lastValid: Int? = nil
            var i = 0
            while i < result.count {
                if let _ = result[i].joints[jointIdx] {
                    lastValid = i
                    i += 1
                    continue
                }
                // start of gap
                let gapStart = i
                while i < result.count, result[i].joints[jointIdx] == nil { i += 1 }
                let gapEnd = i - 1
                let gapLen = gapEnd - gapStart + 1
                let nextValid = i < result.count ? i : nil

                if gapLen <= maxGap, let s = lastValid, let e = nextValid, let ps = result[s].joints[jointIdx], let pe = result[e].joints[jointIdx] {
                    let span = CGFloat(e - s)
                    for k in gapStart...gapEnd {
                        let t = CGFloat(k - s) / span
                        let x = ps.x + (pe.x - ps.x) * t
                        let y = ps.y + (pe.y - ps.y) * t
                        var j = result[k].joints
                        j[jointIdx] = CGPoint(x: x, y: y)
                        result[k] = (image: result[k].image, joints: j)
                    }
                }
            }
        }
        return result
    }
}

// MARK: - Wrist refinement helpers (used in experimental path)
extension ContentView {
    func refineWristsWithHandsKalman(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard fps > 0, !frames.isEmpty else { return frames }
        var result = frames
        let leftWrist = 15, rightWrist = 16
        let leftElbow = 13, rightElbow = 14
        let dt: CGFloat = 1.0 / fps

        // Forearm median lengths
        func median(_ values: [CGFloat]) -> CGFloat {
            guard !values.isEmpty else { return 0 }
            let s = values.sorted(); let m = s.count/2
            return s.count % 2 == 0 ? (s[m-1] + s[m]) * 0.5 : s[m]
        }
        var lLens: [CGFloat] = [], rLens: [CGFloat] = []
        var wristDists: [CGFloat] = []
        for f in frames {
            if let e = f.joints[leftElbow], let w = f.joints[leftWrist] { lLens.append(hypot(w.x - e.x, w.y - e.y)) }
            if let e = f.joints[rightElbow], let w = f.joints[rightWrist] { rLens.append(hypot(w.x - e.x, w.y - e.y)) }
            if let l = f.joints[leftWrist], let r = f.joints[rightWrist] { wristDists.append(hypot(r.x - l.x, r.y - l.y)) }
        }
        let lMed = median(lLens), rMed = median(rLens)
        let wrMed = max(1, median(wristDists))

        // Speeds
        var lSp: [CGFloat] = Array(repeating: 0, count: result.count)
        var rSp: [CGFloat] = Array(repeating: 0, count: result.count)
        for i in 1..<result.count {
            if let p = result[i-1].joints[leftWrist], let c = result[i].joints[leftWrist] { lSp[i] = hypot(c.x - p.x, c.y - p.y) / dt }
            if let p = result[i-1].joints[rightWrist], let c = result[i].joints[rightWrist] { rSp[i] = hypot(c.x - p.x, c.y - p.y) / dt }
        }

        let speedBypass: CGFloat = 130
        let roiRadius: CGFloat = 72
        let acceptRadius: CGFloat = 40
        let maxDelta: CGFloat = 8
        let emaAlphaSlow: CGFloat = 0.35
        let emaAlphaFast: CGFloat = 0.15
        var emaLeft: CGPoint? = nil
        var emaRight: CGPoint? = nil

        for i in 0..<result.count {
            if lSp[i] < speedBypass || rSp[i] < speedBypass {
                var joints = result[i].joints
                func clampForearm(idxE: Int, idxW: Int, medianLen: CGFloat) {
                    guard medianLen > 0, let e = joints[idxE], let w = joints[idxW] else { return }
                    let len = hypot(w.x - e.x, w.y - e.y)
                    if len > 0, (len < 0.8 * medianLen || len > 1.25 * medianLen) {
                        let ux = (w.x - e.x) / len, uy = (w.y - e.y) / len
                        joints[idxW] = CGPoint(x: e.x + ux * medianLen, y: e.y + uy * medianLen)
                    }
                }
                clampForearm(idxE: leftElbow, idxW: leftWrist, medianLen: lMed)
                clampForearm(idxE: rightElbow, idxW: rightWrist, medianLen: rMed)

                func blend(idxW: Int, speed: CGFloat) {
                    guard let w = joints[idxW] else { return }
                    let idxE = (idxW == leftWrist) ? leftElbow : rightElbow
                    let idxOtherE = (idxW == leftWrist) ? rightElbow : leftElbow
                    let idxOtherW = (idxW == leftWrist) ? rightWrist : leftWrist
                    guard let e = joints[idxE] else { return }
                    let roi = CGRect(x: w.x - roiRadius, y: w.y - roiRadius, width: roiRadius*2, height: roiRadius*2)
                    let hands = handWrapper.detectHandLandmarks(in: result[i].image, roi: roi)
                    guard !hands.isEmpty else { return }
                    let anchors = hands.compactMap { hd -> CGPoint? in
                        guard hd.landmarks.count >= 18 else { return nil }
                        let pickIdx = [0,5,9,13,17]
                        var sx: CGFloat = 0, sy: CGFloat = 0
                        for idx in pickIdx { let p = hd.landmarks[idx]; sx += p.x; sy += p.y }
                        let c = CGFloat(pickIdx.count)
                        return CGPoint(x: sx/c, y: sy/c)
                    }
                    // Choose anchor consistent with elbow->wrist direction and same-side limb
                    var cand: CGPoint? = nil
                    var bestD: CGFloat = .greatestFiniteMagnitude
                    let vW = CGPoint(x: w.x - e.x, y: w.y - e.y)
                    let vWLen = max(1e-3, hypot(vW.x, vW.y))
                    let otherE = joints[idxOtherE]
                    let otherW = joints[idxOtherW]
                    for a in anchors {
                        let d = hypot(a.x - w.x, a.y - w.y)
                        if d >= acceptRadius { continue }
                        let vA = CGPoint(x: a.x - e.x, y: a.y - e.y)
                        let vALen = max(1e-3, hypot(vA.x, vA.y))
                        let cos = (vW.x * vA.x + vW.y * vA.y) / (vWLen * vALen)
                        if cos < 0.6 { continue } // angle too different from elbow->wrist
                        // Do not move inward: reject anchors that are closer to elbow than current wrist
                        let curLen = vWLen
                        let aLen = vALen
                        if aLen + 4 < curLen { continue }
                        if let oe = otherE {
                            let dOwn = hypot(a.x - e.x, a.y - e.y)
                            let dOther = hypot(a.x - oe.x, a.y - oe.y)
                            if dOther + 8 < dOwn { continue } // closer to other elbow → likely other hand
                        }
                        if let ow = otherW {
                            let dToOtherW = hypot(a.x - ow.x, a.y - ow.y)
                            if dToOtherW + 6 < d { continue } // closer to the other wrist than this wrist
                        }
                        if d < bestD { bestD = d; cand = a }
                    }
                    guard let cand else { return }
                    let alpha = speed < 70 ? emaAlphaSlow : emaAlphaFast
                    let prev = (idxW == leftWrist) ? (emaLeft ?? w) : (emaRight ?? w)
                    var ema = CGPoint(x: prev.x + alpha * (cand.x - prev.x), y: prev.y + alpha * (cand.y - prev.y))
                    let dx = max(-maxDelta, min(maxDelta, ema.x - w.x))
                    let dy = max(-maxDelta, min(maxDelta, ema.y - w.y))
                    ema = CGPoint(x: w.x + dx, y: w.y + dy)
                    // After blend, clamp forearm length close to clip median to avoid inward pull
                    if let e2 = joints[idxE] {
                        let vx = ema.x - e2.x, vy = ema.y - e2.y
                        let len = max(1e-3, hypot(vx, vy))
                        let target = (idxW == leftWrist) ? max(0.95 * lMed, min(1.08 * lMed, len)) : max(0.95 * rMed, min(1.08 * rMed, len))
                        let ux = vx / len, uy = vy / len
                        ema = CGPoint(x: e2.x + ux * target, y: e2.y + uy * target)
                    }
                    if idxW == leftWrist { emaLeft = ema } else { emaRight = ema }
                    joints[idxW] = ema
                }
                // Early guard near-address: if both wrists are below shoulder line and very close, skip fusion (avoid pulling in at setup)
                if let lw0 = joints[leftWrist], let rw0 = joints[rightWrist], let ls0 = joints[11], let rs0 = joints[12] {
                    let shoulderY0 = min(ls0.y, rs0.y)
                    let wristsLow = lw0.y > shoulderY0 && rw0.y > shoulderY0
                    let veryClose = hypot(rw0.x - lw0.x, rw0.y - lw0.y) < 0.5 * wrMed
                    if wristsLow && veryClose {
                        result[i] = (image: result[i].image, joints: joints)
                        continue
                    }
                }
                // Blend each wrist separately using its own elbow direction.
                blend(idxW: leftWrist, speed: lSp[i])
                blend(idxW: rightWrist, speed: rSp[i])

                // Safety: avoid crossed arms or collapsed wrist distance. If detected, revert wrists to original for this frame.
                // Additional skip: if both wrists are high (above shoulder line) and close together, skip fusion entirely (top of swing)
                if let lw = joints[leftWrist], let rw = joints[rightWrist], let ls = joints[11], let rs = joints[12] {
                    let shoulderY = min(ls.y, rs.y)
                    let wristsHigh = lw.y < shoulderY && rw.y < shoulderY
                    let close = hypot(rw.x - lw.x, rw.y - lw.y) < 0.4 * wrMed
                    if wristsHigh && close {
                        joints[leftWrist] = frames[i].joints[leftWrist]
                        joints[rightWrist] = frames[i].joints[rightWrist]
                    }
                }
                func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
                    func ccw(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Bool {
                        return (p3.y - p1.y) * (p2.x - p1.x) > (p2.y - p1.y) * (p3.x - p1.x)
                    }
                    return ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d)
                }
                if let le = joints[leftElbow], let re = joints[rightElbow],
                   let lw = joints[leftWrist], let rw = joints[rightWrist],
                   let origLW = frames[i].joints[leftWrist], let origRW = frames[i].joints[rightWrist] {
                    let crossed = segmentsIntersect(le, lw, re, rw)
                    let distNow = hypot(rw.x - lw.x, rw.y - lw.y)
                    if crossed || distNow < 0.95 * wrMed {
                        // If current result collapses wrists, try to expand around midpoint toward original separation
                        let mid = CGPoint(x: (lw.x + rw.x) * 0.5, y: (lw.y + rw.y) * 0.5)
                        let vec = CGPoint(x: rw.x - lw.x, y: rw.y - lw.y)
                        let len = max(1e-3, hypot(vec.x, vec.y))
                        let ux = vec.x / len, uy = vec.y / len
                        let target = max(distNow, 0.98 * wrMed)
                        let half = target * 0.5
                        let newLW = CGPoint(x: mid.x - ux * half, y: mid.y - uy * half)
                        let newRW = CGPoint(x: mid.x + ux * half, y: mid.y + uy * half)
                        joints[leftWrist] = newLW
                        joints[rightWrist] = newRW
                    }
                }
                result[i] = (image: result[i].image, joints: joints)
            }
        }
        return result
    }
}

// MARK: - Alternative Kalman-based wrist fusion and club cue
extension ContentView {
    // Kalman fusion using hand landmarks as measurement with dynamic noise
    func refineWristsWithHandsKalmanKF(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard fps > 0, !frames.isEmpty else { return frames }
        var result = frames
        let dt: CGFloat = 1.0 / fps
        let L = 15, R = 16
        var kfL: KalmanFilter2D? = nil
        var kfR: KalmanFilter2D? = nil
        let speedBypass: CGFloat = 120 // tighter
        let roiRadius: CGFloat = 64    // tighter
        let acceptRadius: CGFloat = 44 // tighter
        let baseMeasVar: CGFloat = 14  // tighter
        var prevL: CGPoint? = result.first?.joints[L]
        var prevR: CGPoint? = result.first?.joints[R]
        for i in 0..<result.count {
            var joints = result[i].joints
            let curL = joints[L]
            let curR = joints[R]
            // init filters lazily
            if kfL == nil, let p = curL { kfL = KalmanFilter2D(initial: p, dt: dt) }
            if kfR == nil, let p = curR { kfR = KalmanFilter2D(initial: p, dt: dt) }
            // speeds
            let vL: CGFloat = (prevL != nil && curL != nil) ? hypot(curL!.x - prevL!.x, curL!.y - prevL!.y) / dt : 0
            let vR: CGFloat = (prevR != nil && curR != nil) ? hypot(curR!.x - prevR!.x, curR!.y - prevR!.y) / dt : 0
            prevL = curL; prevR = curR
            // Predict
            kfL?.predict(); kfR?.predict()
            // Measurements from hand anchors
            func measure(from w: CGPoint?) -> CGPoint? {
                guard let w else { return nil }
                let roi = CGRect(x: w.x - roiRadius, y: w.y - roiRadius, width: roiRadius*2, height: roiRadius*2)
                let hands = handWrapper.detectHandLandmarks(in: result[i].image, roi: roi)
                guard !hands.isEmpty else { return nil }
                // Anchor = mean of [wrist(0), idx MCP(5), mid MCP(9), ring MCP(13), pinky MCP(17)]
                let pick = [0,5,9,13,17]
                var best: CGPoint? = nil
                var bestD: CGFloat = .greatestFiniteMagnitude
                for hd in hands {
                    guard hd.landmarks.count > 17 else { continue }
                    var sx: CGFloat = 0, sy: CGFloat = 0
                    for idx in pick { let p = hd.landmarks[idx]; sx += p.x; sy += p.y }
                    let c = CGFloat(pick.count)
                    let anchor = CGPoint(x: sx/c, y: sy/c)
                    let d = hypot(anchor.x - w.x, anchor.y - w.y)
                    if d < bestD { bestD = d; best = anchor }
                }
                guard let anchor = best, bestD < acceptRadius else { return nil }
                return anchor
            }
            if vL < speedBypass, let w = curL, let meas = measure(from: w) {
                let noise = baseMeasVar * max(1, vL / 70)
                kfL?.update(measurement: meas, measurementVariance: noise)
                joints[L] = kfL?.currentPosition()
            }
            if vR < speedBypass, let w = curR, let meas = measure(from: w) {
                let noise = baseMeasVar * max(1, vR / 70)
                kfR?.update(measurement: meas, measurementVariance: noise)
                joints[R] = kfR?.currentPosition()
            }
            result[i] = (image: result[i].image, joints: joints)
        }
        return result
    }

    // Very light club cue: near impact, detect line in hand ROI and nudge wrists along it
    func nudgeWristsWithClubCue(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard !frames.isEmpty else { return frames }
        // Approximate impact by maximum wrist speed
        let L = 15, R = 16
        var maxSpeed: CGFloat = 0
        var impact = frames.count / 2
        for i in 1..<frames.count {
            if let pl = frames[i-1].joints[L], let cl = frames[i].joints[L] {
                maxSpeed = max(maxSpeed, hypot(cl.x - pl.x, cl.y - pl.y))
            }
            if let pr = frames[i-1].joints[R], let cr = frames[i].joints[R] {
                let sp = hypot(cr.x - pr.x, cr.y - pr.y)
                if sp > maxSpeed { maxSpeed = sp; impact = i }
            }
        }
        let win = 2
        let start = max(0, impact - win)
        let end = min(frames.count - 1, impact + win)
        var result = frames
        let detector = ClubCueDetector()
        for i in start...end {
            var joints = result[i].joints
            guard let l = joints[L], let r = joints[R] else { continue }
            let handCenter = CGPoint(x: (l.x + r.x) * 0.5, y: (l.y + r.y) * 0.5)
            let roi = CGRect(x: handCenter.x - 120, y: handCenter.y - 120, width: 240, height: 240)
            if let res = detector.detectDominantLine(in: result[i].image, roi: roi), res.confidence > 0.25 {
                let dir = CGPoint(x: cos(res.angleRadians), y: sin(res.angleRadians))
                let pull: CGFloat = 4
                joints[L] = CGPoint(x: l.x + dir.x * pull, y: l.y + dir.y * pull)
                joints[R] = CGPoint(x: r.x + dir.x * pull, y: r.y + dir.y * pull)
                result[i] = (image: result[i].image, joints: joints)
            }
        }
        return result
    }
}

// Removed elbow/knee refinement per user request

// MARK: - Phase Jump Row and Metrics Summary
struct PhaseJumpRow: View {
    let analysis: SwingAnalysis
    @Binding var currentFrameIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            PhaseJumpButton(label: "Address", frame: analysis.events.addressFrame, currentFrameIndex: $currentFrameIndex)
            PhaseJumpButton(label: "Top", frame: analysis.events.topFrame, currentFrameIndex: $currentFrameIndex)
            PhaseJumpButton(label: "Impact", frame: analysis.events.impactFrame, currentFrameIndex: $currentFrameIndex)
            PhaseJumpButton(label: "Finish", frame: analysis.events.finishFrame, currentFrameIndex: $currentFrameIndex)
        }
        .padding(.top, 4)
    }
}

struct PhaseJumpButton: View {
    let label: String
    let frame: Int
    @Binding var currentFrameIndex: Int

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentFrameIndex = max(0, frame)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.caption)
                Text(label).font(.caption)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.76, green: 0.60, blue: 0.42)))
        }
        .buttonStyle(.plain)
    }
}

struct MetricsSummaryView: View {
    let analysis: SwingAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swing Scorecard").font(.headline).foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
            HStack {
                MetricPill(title: "Tempo", value: String(format: "%.1f:1", analysis.metrics.tempoRatio))
                MetricPill(title: "Backswing", value: String(format: "%.2fs", analysis.metrics.backswingSeconds))
                MetricPill(title: "Downswing", value: String(format: "%.2fs", analysis.metrics.downswingSeconds))
            }
            HStack {
                MetricPill(title: "Shoulder Tilt (Addr)", value: String(format: "%.0f°", analysis.metrics.shoulderTiltAddress))
                MetricPill(title: "Shoulder Tilt (Imp)", value: String(format: "%.0f°", analysis.metrics.shoulderTiltImpact))
                MetricPill(title: "X-Factor (Top)", value: String(format: "%.0f°", analysis.metrics.xFactorTop))
            }
            HStack {
                MetricPill(title: "Pelvis Sway (Top)", value: String(format: "%.0f px", analysis.metrics.pelvisSwayTopPx))
                MetricPill(title: "Head Move", value: String(format: "%.0f px", analysis.metrics.headDisplacementPx))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(Color(red: 0.42, green: 0.30, blue: 0.25))
            Text(value).font(.footnote).fontWeight(.semibold).foregroundColor(Color(red: 0.76, green: 0.60, blue: 0.42))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.95, green: 0.92, blue: 0.88)))
    }
}

// MARK: - Swing Phases and Metrics (summary)
struct SwingEvents {
    let addressFrame: Int
    let startFrame: Int
    let topFrame: Int
    let impactFrame: Int
    let finishFrame: Int
}

struct SwingMetrics {
    let tempoRatio: Double
    let backswingSeconds: Double
    let downswingSeconds: Double
    let shoulderTiltAddress: Double
    let shoulderTiltImpact: Double
    let xFactorTop: Double
    let pelvisSwayTopPx: Double
    let headDisplacementPx: Double
}

struct SwingAnalysis {
    let events: SwingEvents
    let metrics: SwingMetrics
}

extension ContentView {
    // Analyze hand-center motion to segment swing and compute core metrics
    func analyzeSwing(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> SwingAnalysis? {
        guard frames.count > 8, fps > 0 else { return nil }

        let dt = 1.0 / Double(fps)
        let wristLeft = 15
        let wristRight = 16
        let shoulderLeft = 11
        let shoulderRight = 12
        let hipLeft = 23
        let hipRight = 24
        let nose = 0

        // Build time series
        var hand: [CGPoint] = []
        hand.reserveCapacity(frames.count)
        for f in frames {
            let j = f.joints
            let wl = j[wristLeft] ?? .zero
            let wr = j[wristRight] ?? .zero
            let hcHand = CGPoint(x: (wl.x + wr.x) * 0.5, y: (wl.y + wr.y) * 0.5)
            hand.append(hcHand)
        }

        // Speed of hands
        var speed: [Double] = Array(repeating: 0, count: hand.count)
        for i in 1..<hand.count {
            speed[i] = Double(hypot(hand[i].x - hand[i-1].x, hand[i].y - hand[i-1].y)) / dt
        }
        // Smooth speed (simple moving average)
        speed = movingAverage(speed, window: 3)

        // Thresholds relative to early baseline
        let baselineCount = max(5, min(20, speed.count / 10))
        let base = speed.prefix(baselineCount).reduce(0, +) / Double(baselineCount)
        let startThresh = max(base * 3.0, 20.0)
        let quietThresh = max(base * 1.5, 10.0)

        // Detect start of takeaway
        var startIdx = 0
        for i in baselineCount..<speed.count {
            if speed[i] > startThresh { startIdx = i; break }
        }

        // Find top as speed valley after start before global post-start max
        let postStart = Array(speed.suffix(from: max(startIdx, 1)))
        guard let maxAfterStart = postStart.max(), let maxIdxLocal = postStart.firstIndex(of: maxAfterStart) else {
            return nil
        }
        let maxIdx = max(startIdx, 1) + maxIdxLocal
        var topIdx = startIdx
        if maxIdx - startIdx > 4 {
            var minVal = Double.greatestFiniteMagnitude
            var minIdx = startIdx
            for i in startIdx..<(maxIdx) {
                if speed[i] < minVal { minVal = speed[i]; minIdx = i }
            }
            topIdx = minIdx
        }

        // Impact ~ global max speed after top
        let postTop = Array(speed.suffix(from: min(topIdx + 1, speed.count - 1)))
        guard let impactMax = postTop.max(), let impactLocal = postTop.firstIndex(of: impactMax) else {
            return nil
        }
        let impactIdx = min(topIdx + 1, speed.count - 1) + impactLocal

        // Finish when speed falls below quiet threshold and stays low
        var finishIdx = impactIdx
        for i in impactIdx..<speed.count {
            if speed[i] < quietThresh { finishIdx = i; break }
        }

        // Times and tempo
        let backswingTime = max(0, Double(topIdx - startIdx)) * dt
        let downswingTime = max(0, Double(impactIdx - topIdx)) * dt
        let tempo = downswingTime > 0 ? backswingTime / downswingTime : 0

        // Angles/metrics
        func lineAngleDeg(_ a: CGPoint, _ b: CGPoint) -> Double {
            let ang = atan2(Double(b.y - a.y), Double(b.x - a.x))
            return ang * 180.0 / .pi
        }
        let shouldersAddr = lineAngleDeg(frames[0].joints[12] ?? .zero, frames[0].joints[11] ?? .zero)
        let shouldersImp = lineAngleDeg(frames[impactIdx].joints[12] ?? .zero, frames[impactIdx].joints[11] ?? .zero)
        let hipsTop = lineAngleDeg(frames[topIdx].joints[24] ?? .zero, frames[topIdx].joints[23] ?? .zero)
        let shouldersTop = lineAngleDeg(frames[topIdx].joints[12] ?? .zero, frames[topIdx].joints[11] ?? .zero)
        let xFactor = abs(shouldersTop - hipsTop)

        let pelvisAddr = midPoint(frames[0].joints[23] ?? .zero, frames[0].joints[24] ?? .zero)
        let pelvisTop = midPoint(frames[topIdx].joints[23] ?? .zero, frames[topIdx].joints[24] ?? .zero)
        let pelvisSwayTop = Double(pelvisTop.x - pelvisAddr.x)

        let headAddr = frames[0].joints[0] ?? .zero
        let headFin = frames[min(finishIdx, frames.count - 1)].joints[0] ?? .zero
        let headMove = Double(hypot(headFin.x - headAddr.x, headFin.y - headAddr.y))

        let events = SwingEvents(addressFrame: 0, startFrame: startIdx, topFrame: topIdx, impactFrame: impactIdx, finishFrame: finishIdx)
        let metrics = SwingMetrics(
            tempoRatio: tempo,
            backswingSeconds: backswingTime,
            downswingSeconds: downswingTime,
            shoulderTiltAddress: shouldersAddr,
            shoulderTiltImpact: shouldersImp,
            xFactorTop: xFactor,
            pelvisSwayTopPx: pelvisSwayTop,
            headDisplacementPx: headMove
        )
        return SwingAnalysis(events: events, metrics: metrics)
    }

    private func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > window else { return values }
        var result = values
        var sum = values.prefix(window).reduce(0, +)
        result[window/2] = sum / Double(window)
        for i in window..<values.count {
            sum += values[i] - values[i - window]
            let center = i - window/2
            if center < result.count {
                result[center] = sum / Double(window)
            }
        }
        return result
    }

    private func midPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}

// (Removed duplicate Color.init(hex:) to avoid redeclaration)