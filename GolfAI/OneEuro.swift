import CoreGraphics

// Lightweight One Euro filter for low-lag smoothing
final class OneEuroFilter {
    private var initialized = false
    private var last: CGFloat = 0
    private var lastVel: CGFloat = 0
    private let dt: CGFloat
    private let minCutoff: CGFloat
    private let beta: CGFloat
    private let dCutoff: CGFloat = 1.0

    init(dt: CGFloat = 1.0/60.0, minCutoff: CGFloat = 0.7, beta: CGFloat = 0.02) {
        self.dt = dt
        self.minCutoff = minCutoff
        self.beta = beta
    }

    func filter(_ x: CGFloat) -> CGFloat {
        if !initialized { initialized = true; last = x; lastVel = 0; return x }
        let dx = (x - last) / dt
        let ed = smoothing(cutoff: dCutoff)
        let vel = lerp(lastVel, dx, ed)
        let cutoff = minCutoff + beta * abs(vel)
        let e = smoothing(cutoff: cutoff)
        let y = lerp(last, x, e)
        last = y; lastVel = vel
        return y
    }

    private func smoothing(cutoff: CGFloat) -> CGFloat { let r = 2 * .pi * cutoff * dt; return r / (r + 1) }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

