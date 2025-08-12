import SwiftUI
import AVKit
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

// MARK: - Forearm length clamp (prevents inward collapse)
extension ContentView {
    // Limit per-frame elbow->wrist direction change to avoid sudden flips
    func guardWristAngleChange(frames: [(image: UIImage, joints: [Int: CGPoint])], maxAngleDeg: CGFloat = 55) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 1 else { return frames }
        var result = frames
        let LW = 15, RW = 16, LE = 13, RE = 14
        let cosThresh = cos(maxAngleDeg * .pi / 180)
        for i in 1..<result.count {
            var j = result[i].joints
            let jp = result[i-1].joints
            func clampOne(wIdx: Int, eIdx: Int) {
                guard let e = j[eIdx], var w = j[wIdx], let ep = jp[eIdx], let wp = jp[wIdx] else { return }
                let vPrev = CGPoint(x: wp.x - ep.x, y: wp.y - ep.y)
                let vCurr = CGPoint(x: w.x - e.x, y: w.y - e.y)
                let lp = max(1e-3, hypot(vPrev.x, vPrev.y))
                let lc = max(1e-3, hypot(vCurr.x, vCurr.y))
                let up = CGPoint(x: vPrev.x / lp, y: vPrev.y / lp)
                let uc = CGPoint(x: vCurr.x / lc, y: vCurr.y / lc)
                let cosang = up.x * uc.x + up.y * uc.y
                if cosang < cosThresh {
                    // Too large a turn: keep previous direction, preserve current length
                    let target = CGPoint(x: e.x + up.x * lc, y: e.y + up.y * lc)
                    w = target
                    j[wIdx] = w
                }
            }
            clampOne(wIdx: LW, eIdx: LE)
            clampOne(wIdx: RW, eIdx: RE)
            result[i] = (image: result[i].image, joints: j)
        }
        return result
    }
    // Predictive outlier guard for wrists: rejects sudden jumps vs constant-velocity prediction
    func guardWristOutliers(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 2, fps > 0 else { return frames }
        var result = frames
        let LW = 15, RW = 16
        let dt: CGFloat = 1.0 / fps
        let maxJump: CGFloat = 24 // if jump exceeds this vs prediction, clamp to prediction
        for i in 2..<result.count {
            var j = result[i].joints
            let j1 = result[i-1].joints
            let j2 = result[i-2].joints
            func guardOne(_ idx: Int) {
                guard let p1 = j1[idx], let p2 = j2[idx], let cur = j[idx] else { return }
                let vx = (p1.x - p2.x) / dt
                let vy = (p1.y - p2.y) / dt
                let pred = CGPoint(x: p1.x + vx * dt, y: p1.y + vy * dt)
                let d = hypot(cur.x - pred.x, cur.y - pred.y)
                if d > maxJump {
                    // clamp toward prediction, keep at most maxJump away
                    let ux = (cur.x - pred.x) / d
                    let uy = (cur.y - pred.y) / d
                    j[idx] = CGPoint(x: pred.x + ux * maxJump, y: pred.y + uy * maxJump)
                }
            }
            guardOne(LW)
            guardOne(RW)
            result[i] = (image: result[i].image, joints: j)
        }
        return result
    }
    // Hand Assist: use hand landmarker in tiny ROI near each wrist with strict acceptance rules
    func handAssistWrists(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) async -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard fps > 0, !frames.isEmpty else { return frames }
        // Ensure model is ready
        _ = await handWrapper.prepareIfNeeded()
        var result = frames
        let LW = 15, RW = 16, LE = 13, RE = 14
        let roiRadius: CGFloat = 72
        let acceptRadius: CGFloat = 38
        let speedBypass: CGFloat = 70
        for i in 1..<result.count {
            var j = result[i].joints
            let prev = result[i-1].joints
            func assist(wIdx: Int, eIdx: Int) {
                guard let w = j[wIdx], let e = j[eIdx] else { return }
                // Speed gate
                if let pw = prev[wIdx] {
                    let sp = hypot(w.x - pw.x, w.y - pw.y) * fps
                    if sp > speedBypass { return }
                }
                let roi = CGRect(x: w.x - roiRadius, y: w.y - roiRadius, width: roiRadius*2, height: roiRadius*2)
                let hands = handWrapper.detectHandLandmarks(in: result[i].image, roi: roi)
                guard !hands.isEmpty else { return }
                // Choose anchor = mean of wrist+MCPs
                let pick = [0,5,9,13,17]
                var best: CGPoint? = nil
                var bestScore: CGFloat = .greatestFiniteMagnitude
                let vW = CGPoint(x: w.x - e.x, y: w.y - e.y)
                let vWLen = max(1e-3, hypot(vW.x, vW.y))
                for hd in hands {
                    guard hd.landmarks.count > 17 else { continue }
                    var sx: CGFloat = 0, sy: CGFloat = 0
                    for idx in pick { let p = hd.landmarks[idx]; sx += p.x; sy += p.y }
                    let c = CGFloat(pick.count)
                    let a = CGPoint(x: sx/c, y: sy/c)
                    let d = hypot(a.x - w.x, a.y - w.y)
                    if d >= acceptRadius { continue }
                    let vA = CGPoint(x: a.x - e.x, y: a.y - e.y)
                    let vALen = max(1e-3, hypot(vA.x, vA.y))
                    let cos = (vW.x * vA.x + vW.y * vA.y) / (vWLen * vALen)
                    if cos < 0.6 { continue }
                    if d < bestScore { bestScore = d; best = a }
                }
                guard let anchor = best else { return }
                // Small blend toward anchor
                let maxDelta: CGFloat = 6
                var target = CGPoint(x: w.x + max(-maxDelta, min(maxDelta, anchor.x - w.x)),
                                      y: w.y + max(-maxDelta, min(maxDelta, anchor.y - w.y)))
                // Clamp forearm length softly to current length to avoid inward pull; final hard clamp happens later
                let vx = target.x - e.x, vy = target.y - e.y
                let len = max(1e-3, hypot(vx, vy))
                let ux = vx / len, uy = vy / len
                let keepLen = vWLen
                target = CGPoint(x: e.x + ux * keepLen, y: e.y + uy * keepLen)
                j[wIdx] = target
            }
            assist(wIdx: LW, eIdx: LE)
            assist(wIdx: RW, eIdx: RE)
            result[i] = (image: result[i].image, joints: j)
        }
        return result
    }
    func clampForearmLengths(frames: [(image: UIImage, joints: [Int: CGPoint])]) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard !frames.isEmpty else { return frames }
        var result = frames
        let LE = 13, RE = 14, LW = 15, RW = 16
        func median(_ v: [CGFloat]) -> CGFloat {
            let s = v.sorted(); let m = s.count/2
            return s.isEmpty ? 0 : (s.count % 2 == 0 ? (s[m-1]+s[m]) * 0.5 : s[m])
        }
        var lLens: [CGFloat] = [], rLens: [CGFloat] = []
        for f in result {
            if let e = f.joints[LE], let w = f.joints[LW] { lLens.append(hypot(w.x - e.x, w.y - e.y)) }
            if let e = f.joints[RE], let w = f.joints[RW] { rLens.append(hypot(w.x - e.x, w.y - e.y)) }
        }
        let lMed = max(1, median(lLens)), rMed = max(1, median(rLens))
        // Tighter clamp to prevent forearm collapse/over-extension
        let minScale: CGFloat = 0.97, maxScale: CGFloat = 1.05
        for i in 0..<result.count {
            var j = result[i].joints
            if let e = j[LE], var w = j[LW] {
                let vx = w.x - e.x, vy = w.y - e.y
                let len = max(1e-3, hypot(vx, vy))
                if len < minScale*lMed || len > maxScale*lMed {
                    let ux = vx/len, uy = vy/len
                    let target = min(max(len, minScale*lMed), maxScale*lMed)
                    w = CGPoint(x: e.x + ux*target, y: e.y + uy*target)
                    j[LW] = w
                }
            }
            if let e = j[RE], var w = j[RW] {
                let vx = w.x - e.x, vy = w.y - e.y
                let len = max(1e-3, hypot(vx, vy))
                if len < minScale*rMed || len > maxScale*rMed {
                    let ux = vx/len, uy = vy/len
                    let target = min(max(len, minScale*rMed), maxScale*rMed)
                    w = CGPoint(x: e.x + ux*target, y: e.y + uy*target)
                    j[RW] = w
                }
            }
            result[i] = (image: result[i].image, joints: j)
        }
        return result
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

// MARK: - Trim UI (portrait)
import AVKit
struct TrimView: View {
    let url: URL
    let onCancel: () -> Void
    let onUse: (CMTimeRange?) -> Void

    @State private var player: AVPlayer = AVPlayer()
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var isPlaying: Bool = true

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Video fills most of the screen
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: player)
                        .frame(width: geo.size.width, height: geo.size.height * 0.74)
                        .clipped()

                    // Speech-bubble hint
                    Text("Select swing portion of the video")
                        .font(.subheadline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        )
                        .padding(.bottom, 8)
                }

                // Bottom control panel pinned
                VStack(spacing: 14) {
                    // Filmstrip centered
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.85))
                            .frame(height: 56)

                        // Yellow filmstrip track
                        HStack(spacing: 8) {
                            Button(action: { nudgeStart(-0.05) }) {
                                Image(systemName: "chevron.left").font(.headline).foregroundColor(.black)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.yellow)
                                RangeSlider(minValue: 0, maxValue: max(0.1, duration), lowerValue: $start, upperValue: $end)
                                    .padding(.horizontal, 12)
                            }
                            Button(action: { nudgeEnd(0.05) }) {
                                Image(systemName: "chevron.right").font(.headline).foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: min(geo.size.width * 0.9, 560))
                    .frame(maxWidth: .infinity)

                    // Centered play/pause
                    HStack { Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.8)))
                    } }

                    // Centered actions
                    HStack(spacing: 16) {
                        Button("Change") { onCancel() }
                            .foregroundColor(.white)
                        Button(action: { onUse(makeRange()) }) {
                            HStack(spacing: 6) {
                                Text("Continue").fontWeight(.semibold)
                                Text(">>>")
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan))
                            .foregroundColor(.black)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .frame(width: geo.size.width)
                .background(Color.black.opacity(0.95))
            }
            .padding(.top, 8)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .onAppear {
            let asset = AVURLAsset(url: url)
            Task {
                do {
                    let d = try await asset.load(.duration)
                    let secs = CMTimeGetSeconds(d)
                    duration = secs
                    if end == 0 { end = secs }
                    player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                    player.play()
                    isPlaying = true
                } catch { }
            }
        }
        .onChange(of: start) { newVal in
            // Scrub preview to new start while dragging
            player.pause(); isPlaying = false
            seek(to: newVal)
        }
        .onChange(of: end) { newVal in
            // Scrub preview to new end while dragging
            player.pause(); isPlaying = false
            seek(to: newVal)
        }
    }

    private func makeRange() -> CMTimeRange? {
        guard duration > 0, end > start else { return nil }
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        return CMTimeRange(start: startTime, end: endTime)
    }

    private func format(_ s: Double) -> String {
        let m = Int(s) / 60
        let r = Int(s) % 60
        return String(format: "%d:%02d", m, r)
    }

    private func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
    private func nudgeStart(_ delta: Double) {
        start = max(0, min(start + delta, end))
        seek(to: start)
    }
    private func nudgeEnd(_ delta: Double) {
        end = min(duration, max(end + delta, start))
        seek(to: end)
    }
    private func seek(to seconds: Double) {
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

struct RangeSlider: View {
    let minValue: Double
    let maxValue: Double
    @Binding var lowerValue: Double
    @Binding var upperValue: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.opacity(0.6)).frame(height: 6)
                let width = geo.size.width
                let span = max(0.0001, maxValue - minValue)
                let lX = CGFloat((lowerValue - minValue) / span) * width
                let uX = CGFloat((upperValue - minValue) / span) * width
                Capsule().fill(Color.gold).frame(width: max(uX - lX, 6), height: 6).offset(x: lX)
                Circle().fill(Color.white).overlay(Circle().stroke(Color.gold, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .position(x: max(12, min(width - 12, lX)), y: 12)
                    .gesture(DragGesture().onChanged { g in
                        let t = max(0, min(1, (g.location.x / width)))
                        lowerValue = min(upperValue, minValue + Double(t) * span)
                    })
                Circle().fill(Color.white).overlay(Circle().stroke(Color.gold, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .position(x: max(12, min(width - 12, uX)), y: 12)
                    .gesture(DragGesture().onChanged { g in
                        let t = max(0, min(1, (g.location.x / width)))
                        upperValue = max(lowerValue, minValue + Double(t) * span)
                    })
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
    @State private var showTrimUI = false
    @State private var trimmedTimeRange: CMTimeRange? = nil
    @State private var isProcessing = false
    @State private var isLoading = true
    @State private var processingProgress: Double = 0.0
    @State private var totalFrames: Int = 0
    @State private var processedFrames: Int = 0
    @State private var videoDuration: Double = 0.0
    @State private var estimatedTimeRemaining: Double = 0.0
    @State private var currentFrameIndex: Int = 0
    // Phase analysis removed
    // Enhanced wrist assistance is always ON (no user toggle)
    @State private var detectedFrames: [(image: UIImage, joints: [Int: CGPoint])] = []
    @State private var fusionCount: Int = 0
    @State private var handModelReady: Bool = false
    // New: detectors and tracker
    private let clubKP = ClubKeypointDetector()
    private let ballDetector = BallDetector()
    @State private var clubTracker = MultiPointKalman(dt: 1.0/20.0)
    // Performance tuning
    private let analysisFPS: Double = 60.0
    private let ciContextShared = CIContext()
    // Enforce portrait-only usage for capture/analysis UI
    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        if UIDevice.current.orientation.isLandscape {
            // Simple visual hint can be added via UI; logic-wise we continue but design targets portrait
        }
    }
    // Phase labeling for dataset export
    enum PhaseName: String, CaseIterable { case address, takeaway, midBackswing, top, midDownswing, impact, followThrough, finish }
    struct PhaseLabels { var address: Int?; var takeaway: Int?; var midBackswing: Int?; var top: Int?; var midDownswing: Int?; var impact: Int?; var followThrough: Int?; var finish: Int? }
    @State private var phaseLabels = PhaseLabels()

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
                                        lifterStatusText: nil,
                                        phaseDone: [
                                            .address: phaseLabels.address != nil,
                                            .takeaway: phaseLabels.takeaway != nil,
                                            .midBackswing: phaseLabels.midBackswing != nil,
                                            .top: phaseLabels.top != nil,
                                            .midDownswing: phaseLabels.midDownswing != nil,
                                            .impact: phaseLabels.impact != nil,
                                            .followThrough: phaseLabels.followThrough != nil,
                                            .finish: phaseLabels.finish != nil
                                        ],
                                        onMarkPhase: { phase in
                                            markPhase(phase)
                                        },
                                        onExport: {
                                            exportCurrentAnalysis()
                                        },
                                        onAnalyzeAnother: {
                                            // Reset state and open picker again
                                            selectedVideoURL = nil
                                            analyzedFrames = []
                                            detectedFrames = []
                                            fusionCount = 0
                                            processingProgress = 0
                                            processedFrames = 0
                                            totalFrames = 0
                                            videoDuration = 0
                                            estimatedTimeRemaining = 0
                                            currentFrameIndex = 0
                                            showVideoPicker = true
                                        }
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
                .fullScreenCover(isPresented: $showTrimUI) {
                    if let url = selectedVideoURL {
                        TrimView(url: url, onCancel: {
                            showTrimUI = false
                            Task { await processVideoFrames() }
                        }, onUse: { range in
                            trimmedTimeRange = range
                            showTrimUI = false
                            Task { await processVideoFrames() }
                        })
                        .statusBar(hidden: true)
                        .ignoresSafeArea()
                    }
                }
            }
        }
        // Toggles removed
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { url in
                selectedVideoURL = url
                let selectedURL = url
                    Task {
                        // Using BlazePose Heavy only (no hand model / post-processing)
                        // Present a simple trim UI first (portrait only)
                        await MainActor.run { showTrimUI = true }
                        let asset = AVURLAsset(url: selectedURL)
                        do {
                            let duration = try await asset.load(.duration)
                            let durationSeconds = CMTimeGetSeconds(duration)
                    videoDuration = durationSeconds
                    totalFrames = Int(durationSeconds * analysisFPS)
                            estimatedTimeRemaining = durationSeconds * 0.8 // Rough estimate
                        } catch {
                            print("Error loading video info: \(error)")
                        }
                        // Wait until user trims; if no trim chosen we analyze full clip
                        if showTrimUI == false {
                            await processVideoFrames()
                        }
                    }
                }
            }
        }
        // Trim sheet handled via overlay above
    }



    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    // MARK: - Phase labeling and export
    extension ContentView {
        fileprivate func markPhase(_ phase: PhaseName) {
            switch phase {
            case .address: phaseLabels.address = currentFrameIndex
            case .takeaway: phaseLabels.takeaway = currentFrameIndex
            case .midBackswing: phaseLabels.midBackswing = currentFrameIndex
            case .top: phaseLabels.top = currentFrameIndex
            case .midDownswing: phaseLabels.midDownswing = currentFrameIndex
            case .impact: phaseLabels.impact = currentFrameIndex
            case .followThrough: phaseLabels.followThrough = currentFrameIndex
            case .finish: phaseLabels.finish = currentFrameIndex
            }
        }

        fileprivate func exportCurrentAnalysis() {
            guard !analyzedFrames.isEmpty else { return }
            func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5) }
            var features: [[Double]] = []
            var prevNorm: [CGPoint]? = nil
            for f in analyzedFrames {
                let j = f.joints
                let hipL = j[23] ?? .zero
                let hipR = j[24] ?? .zero
                let shL = j[11] ?? .zero
                let shR = j[12] ?? .zero
                let c = mid(hipL, hipR)
                let s = max(1e-3, hypot(shR.x - shL.x, shR.y - shL.y))
                var row: [Double] = []
                var curNorm: [CGPoint] = []
                for idx in 0..<33 {
                    if let p = j[idx] {
                        let nx = (p.x - c.x)/s
                        let ny = (p.y - c.y)/s
                        curNorm.append(CGPoint(x: nx, y: ny))
                    } else { curNorm.append(.zero) }
                }
                // Light smoothing
                if let prev = prevNorm {
                    let alpha: CGFloat = 0.2
                    for i in 0..<33 {
                        curNorm[i] = CGPoint(
                            x: prev[i].x + alpha * (curNorm[i].x - prev[i].x),
                            y: prev[i].y + alpha * (curNorm[i].y - prev[i].y)
                        )
                    }
                }
                // XY
                for i in 0..<33 { row.append(Double(curNorm[i].x)); row.append(Double(curNorm[i].y)) }
                // Velocities
                if let prev = prevNorm {
                    for i in 0..<33 {
                        let vx = (curNorm[i].x - prev[i].x) * CGFloat(analysisFPS)
                        let vy = (curNorm[i].y - prev[i].y) * CGFloat(analysisFPS)
                        row.append(Double(vx)); row.append(Double(vy))
                    }
                } else {
                    for _ in 0..<33 { row.append(0); row.append(0) }
                }
                // Simple angles (elbow/wrist)
                func ang(_ a: CGPoint, _ b: CGPoint) -> Double { Double(atan2(a.y - b.y, a.x - b.x)) }
                let lEl = curNorm[13], lWr = curNorm[15], lShN = curNorm[11]
                let rEl = curNorm[14], rWr = curNorm[16], rShN = curNorm[12]
                row.append(ang(lEl, lShN)); row.append(ang(lWr, lEl)); row.append(ang(rEl, rShN)); row.append(ang(rWr, rEl))
                prevNorm = curNorm
                features.append(row)
            }
            let phases: [String: Int] = [
                "address": phaseLabels.address ?? 0,
                "takeaway": phaseLabels.takeaway ?? max(0, analyzedFrames.count/12),
                "midBackswing": phaseLabels.midBackswing ?? max(0, analyzedFrames.count/6),
                "top": phaseLabels.top ?? max(0, analyzedFrames.count/3),
                "midDownswing": phaseLabels.midDownswing ?? max(0, analyzedFrames.count/2),
                "impact": phaseLabels.impact ?? max(0, analyzedFrames.count*2/3),
                "followThrough": phaseLabels.followThrough ?? max(0, analyzedFrames.count*5/6),
                "finish": phaseLabels.finish ?? max(0, analyzedFrames.count-1)
            ]
            let payload: [String: Any] = [
                "fps": analysisFPS,
                "numFrames": analyzedFrames.count,
                "features": features,
                "phases": phases
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let url = dir.appendingPathComponent("swing_features_\(Int(Date().timeIntervalSince1970)).json")
                try data.write(to: url)
                print("✅ Exported features: \(url.path)")
            } catch {
                print("❌ Export failed: \(error)")
            }
        }
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
    // Debug lifter status text (optional)
    let lifterStatusText: String?
    let phaseDone: [ContentView.PhaseName: Bool]
    let onMarkPhase: (ContentView.PhaseName) -> Void
    let onExport: () -> Void
    let onAnalyzeAnother: () -> Void
    @State private var showToast: Bool = false
    @State private var toastText: String = ""

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
                    // Phase markers and export controls
                    Menu("Mark Phase") {
                        Button("Address") { mark(.address) }
                        Button("Takeaway") { mark(.takeaway) }
                        Button("Mid-Backswing") { mark(.midBackswing) }
                        Button("Top") { mark(.top) }
                        Button("Mid-Downswing") { mark(.midDownswing) }
                        Button("Impact") { mark(.impact) }
                        Button("Follow-Through") { mark(.followThrough) }
                        Button("Finish") { mark(.finish) }
                    }
                    .buttonStyle(.bordered)
                    // Also keep a horizontally scrollable strip for quick taps
                                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("Address") { mark(.address) }
                            Button("Takeaway") { mark(.takeaway) }
                            Button("Mid-Back") { mark(.midBackswing) }
                            Button("Top") { mark(.top) }
                            Button("Mid-Down") { mark(.midDownswing) }
                            Button("Impact") { mark(.impact) }
                            Button("Follow") { mark(.followThrough) }
                            Button("Finish") { mark(.finish) }
                        }
                        .buttonStyle(.bordered)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                    }
                    // Checklist view
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            phaseBadge("Address", done: phaseDone[.address] ?? false)
                            phaseBadge("Takeaway", done: phaseDone[.takeaway] ?? false)
                            phaseBadge("Mid-Back", done: phaseDone[.midBackswing] ?? false)
                            phaseBadge("Top", done: phaseDone[.top] ?? false)
                        }
                        HStack(spacing: 10) {
                            phaseBadge("Mid-Down", done: phaseDone[.midDownswing] ?? false)
                            phaseBadge("Impact", done: phaseDone[.impact] ?? false)
                            phaseBadge("Follow", done: phaseDone[.followThrough] ?? false)
                            phaseBadge("Finish", done: phaseDone[.finish] ?? false)
                        }
                    }
                    Button("Export Features JSON") { onExport() }
                        .buttonStyle(.bordered)
                    
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
                    // Phase auto-play removed
                }
            }
            // Analyze Another Video button
            Button(action: { onAnalyzeAnother() }) {
                Text("Analyze Another Video")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.turf)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            // Toast overlay
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastText)
                        .font(.caption)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
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

    private func mark(_ phase: ContentView.PhaseName) {
        onMarkPhase(phase)
        toastText = "Set \(label(for: phase)) at frame \(currentFrameIndex + 1)"
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showToast = false }
        }
    }

    private func label(for phase: ContentView.PhaseName) -> String {
        switch phase {
        case .address: return "Address"
        case .takeaway: return "Takeaway"
        case .midBackswing: return "Mid-Backswing"
        case .top: return "Top"
        case .midDownswing: return "Mid-Downswing"
        case .impact: return "Impact"
        case .followThrough: return "Follow-Through"
        case .finish: return "Finish"
        }
    }

    @ViewBuilder private func phaseBadge(_ text: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? .green : .gray)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(done ? Color.green.opacity(0.6) : Color.gray.opacity(0.3)))
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
            // BlazePose-only: no post-processing
            let finalFrames = detectedFrames
            await MainActor.run {
                analyzedFrames = finalFrames
                currentFrameIndex = min(currentFrameIndex, max(finalFrames.count - 1, 0))
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
        // If a trim range exists, set timeRange on the reader output
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
        if let range = trimmedTimeRange { output.alwaysCopiesSampleData = false; reader.timeRange = range }
        
                reader.add(output)
                reader.startReading()

        // Prefer higher sampling for smoother tracking (aim for ~60 FPS)
        let interval = CMTimeMakeWithSeconds(1.0/60.0, preferredTimescale: 600)
        // If trimmed, set slider/frames to trimmed duration
        if let range = trimmedTimeRange {
            let dur = CMTimeGetSeconds(range.duration)
            videoDuration = dur
            totalFrames = Int(dur * analysisFPS)
        }
        var currentTime = CMTime.zero
        let startTime = Date()
        var frameIndex = 0
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if CMTimeCompare(presentationTime, currentTime) >= 0 {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    var ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    ciImage = ciImage.oriented(forExifOrientation: 6)

                    guard let cgImage = ciContextShared.createCGImage(ciImage, from: ciImage.extent) else { continue }
                    
                            let uiImage = UIImage(cgImage: cgImage)
                    _ = CGSize(width: uiImage.size.width, height: uiImage.size.height)
                    
                    if let landmarks = poseWrapper.detectPose(in: uiImage) {
                        var joints = landmarks
                        // Club/ball detection (best-effort); use hands to define ROI
                        if let lw = joints[15], let rw = joints[16] {
                            let handCenter = CGPoint(x: (lw.x + rw.x) * 0.5, y: (lw.y + rw.y) * 0.5)
                            let roi = CGRect(x: handCenter.x - 180, y: handCenter.y - 180, width: 360, height: 360)
                            // Club/ball overlays removed for now
                        }
                        analyzedFrames.append((image: uiImage, joints: joints))
                    }
                    
                    processedFrames += 1
                        await MainActor.run {
                        // Push UI progress updates immediately
                        let clamped = min(processedFrames, totalFrames)
                        if totalFrames > 0 {
                            processingProgress = min(1.0, max(0.0, Double(clamped) / Double(totalFrames)))
                        } else {
                            processingProgress = 0.0
                        }
                    }
                    frameIndex += 1
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
                    
                    if frameIndex % 6 == 0 { await Task.yield() }
                }
                
                currentTime = CMTimeAdd(currentTime, interval)
            }
        }
        // BlazePose-only: pass through detections
        detectedFrames = analyzedFrames
        let liftedFrames = analyzedFrames
                await MainActor.run {
            isProcessing = false
                analyzedFrames = liftedFrames
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
    
    // Speed-gated One Euro smoothing for all joints, with looser gating for body and stricter for wrists
    func stabilizeWristAware(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 1, fps > 0 else { return frames }
        var result = frames
        let LWR = 15, RWR = 16
        let dt: CGFloat = 1.0 / fps
        var fx: [OneEuroFilter] = (0..<33).map { _ in OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02) }
        var fy: [OneEuroFilter] = (0..<33).map { _ in OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02) }
        let speedBypassBody: CGFloat = 45
        let speedBypassWrist: CGFloat = 55
        
        // initialize with first frame
        for idx in 0..<33 {
            if let p = result[0].joints[idx] {
                _ = fx[idx].filter(p.x)
                _ = fy[idx].filter(p.y)
            }
        }
        
        for i in 1..<result.count {
            var joints = result[i].joints
            let prev = result[i-1].joints
            for idx in 0..<33 {
                guard let cur = joints[idx], let pre = prev[idx] else { continue }
                let speed = hypot(cur.x - pre.x, cur.y - pre.y)
                if (idx == LWR || idx == RWR) {
                    if speed > speedBypassWrist { continue }
                } else {
                    if speed > speedBypassBody { continue }
                }
                joints[idx] = CGPoint(x: fx[idx].filter(cur.x), y: fy[idx].filter(cur.y))
            }
            result[i] = (image: result[i].image, joints: joints)
        }
        return result
    }
}

// MARK: - Wrist-only short-gap interpolation
extension ContentView {
    // Wrist-only OneEuro smoother with speed bypass (body untouched)
    func stabilizeWristsOnly(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) -> [(image: UIImage, joints: [Int: CGPoint])] {
        guard frames.count > 1, fps > 0 else { return frames }
        var result = frames
        let LW = 15, RW = 16
        let dt: CGFloat = 1.0 / fps
        var fxL = OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02)
        var fyL = OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02)
        var fxR = OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02)
        var fyR = OneEuroFilter(dt: dt, minCutoff: 0.7, beta: 0.02)
        // Tighten stability: lower bypass and clamp per-frame motion
        let speedBypass: CGFloat = 40
        let maxStep: CGFloat = 5
        if let p = result[0].joints[LW] { _ = fxL.filter(p.x); _ = fyL.filter(p.y) }
        if let p = result[0].joints[RW] { _ = fxR.filter(p.x); _ = fyR.filter(p.y) }
        for i in 1..<result.count {
            var j = result[i].joints
            let prev = result[i-1].joints
            if let cur = j[LW], let pre = prev[LW] {
                let sp = hypot(cur.x - pre.x, cur.y - pre.y)
                if sp <= speedBypass {
                    let sx = fxL.filter(cur.x), sy = fyL.filter(cur.y)
                    let dx = sx - pre.x, dy = sy - pre.y
                    let d = hypot(dx, dy)
                    if d > maxStep {
                        let ux = dx / d, uy = dy / d
                        j[LW] = CGPoint(x: pre.x + ux * maxStep, y: pre.y + uy * maxStep)
                    } else {
                        j[LW] = CGPoint(x: sx, y: sy)
                    }
                }
            }
            if let cur = j[RW], let pre = prev[RW] {
                let sp = hypot(cur.x - pre.x, cur.y - pre.y)
                if sp <= speedBypass {
                    let sx = fxR.filter(cur.x), sy = fyR.filter(cur.y)
                    let dx = sx - pre.x, dy = sy - pre.y
                    let d = hypot(dx, dy)
                    if d > maxStep {
                        let ux = dx / d, uy = dy / d
                        j[RW] = CGPoint(x: pre.x + ux * maxStep, y: pre.y + uy * maxStep)
                    } else {
                        j[RW] = CGPoint(x: sx, y: sy)
                    }
                }
            }
            result[i] = (image: result[i].image, joints: j)
        }
        return result
    }
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
            func measure(from w: CGPoint?, preferLeft: Bool) -> CGPoint? {
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
                    // Prefer correct side if available
                    let sidePenalty: CGFloat = {
                        switch hd.side {
                        case .left: return preferLeft ? 0 : 12
                        case .right: return preferLeft ? 12 : 0
                        case .unknown: return 6
                        }
                    }()
                    let d = hypot(anchor.x - w.x, anchor.y - w.y) + sidePenalty
                    if d < bestD { bestD = d; best = anchor }
                }
                guard let anchor = best, bestD < acceptRadius else { return nil }
                return anchor
            }
            if vL < speedBypass, let w = curL, let meas = measure(from: w, preferLeft: true) {
                let noise = baseMeasVar * max(1, vL / 70)
                kfL?.update(measurement: meas, measurementVariance: noise)
                joints[L] = kfL?.currentPosition()
            }
            if vR < speedBypass, let w = curR, let meas = measure(from: w, preferLeft: false) {
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

// (Removed final wrist-only Kalman smoother per user request)

// Removed elbow/knee refinement per user request

// Phase analysis types and helpers removed

// (Removed duplicate Color.init(hex:) to avoid redeclaration)