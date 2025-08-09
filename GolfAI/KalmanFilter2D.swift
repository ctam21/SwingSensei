import Foundation
import CoreGraphics

// Constant-velocity 2D Kalman filter for wrist tracking
// State: [x, y, vx, vy]
final class KalmanFilter2D {
    private var dt: CGFloat
    private var x: [CGFloat] = [0, 0, 0, 0] // state vector
    private var P: [[CGFloat]] = Array(repeating: Array(repeating: 0, count: 4), count: 4) // covariance

    init(initial: CGPoint, dt: CGFloat, positionVariance: CGFloat = 25, velocityVariance: CGFloat = 400) {
        self.dt = dt
        x[0] = initial.x
        x[1] = initial.y
        x[2] = 0
        x[3] = 0
        // Initial covariance
        P = [[positionVariance, 0, 0, 0],
             [0, positionVariance, 0, 0],
             [0, 0, velocityVariance, 0],
             [0, 0, 0, velocityVariance]]
    }

    func predict() {
        // State transition
        // x' = x + vx*dt; y' = y + vy*dt
        x[0] = x[0] + x[2] * dt
        x[1] = x[1] + x[3] * dt
        // F
        // P' = F P F^T + Q
        let F: [[CGFloat]] = [[1, 0, dt, 0],
                               [0, 1, 0, dt],
                               [0, 0, 1, 0],
                               [0, 0, 0, 1]]
        let Qpos: CGFloat = 9 // process noise for position
        let Qvel: CGFloat = 49 // process noise for velocity
        let Q: [[CGFloat]] = [[Qpos, 0, 0, 0],
                               [0, Qpos, 0, 0],
                               [0, 0, Qvel, 0],
                               [0, 0, 0, Qvel]]
        P = addMatMat(multiplyMatMat(F, multiplyMatMat(P, transpose(F))), Q)
    }

    func update(measurement z: CGPoint, measurementVariance r: CGFloat) {
        // Measurement matrix H (observe x,y only)
        let H: [[CGFloat]] = [[1, 0, 0, 0],
                               [0, 1, 0, 0]]
        let zVec: [CGFloat] = [z.x, z.y]
        let xPred: [CGFloat] = x
        let yPred = multiplyMatVec(H, xPred)
        let yRes = subtractVecVec(zVec, yPred)
        let S = addMatMat(multiplyMatMat(H, multiplyMatMat(P, transpose(H))), [[r, 0],[0, r]])
        // K = P H^T S^{-1}
        let HT = transpose(H)
        let PHt = multiplyMatMat(P, HT)
        let Sinv = invert2x2(S)
        let K = multiplyMatMat(PHt, Sinv) // 4x2
        let Ky = multiplyMatVec(K, yRes)   // 4x1
        x = addVecVec(xPred, Ky)
        let I: [[CGFloat]] = [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
        let KH = multiplyMatMat(K, H)
        P = multiplyMatMat(subtractMatMat(I, KH), P)
    }

    func currentPosition() -> CGPoint { CGPoint(x: x[0], y: x[1]) }

    // MARK: - Small linear algebra helpers (tiny dims)
    private func transpose(_ A: [[CGFloat]]) -> [[CGFloat]] {
        guard !A.isEmpty else { return A }
        let m = A.count, n = A[0].count
        var T = Array(repeating: Array(repeating: CGFloat(0), count: m), count: n)
        for i in 0..<m { for j in 0..<n { T[j][i] = A[i][j] } }
        return T
    }

    private func multiplyMatMat(_ A: [[CGFloat]], _ B: [[CGFloat]]) -> [[CGFloat]] {
        let m = A.count, n = B[0].count, p = B.count
        var C = Array(repeating: Array(repeating: CGFloat(0), count: n), count: m)
        for i in 0..<m {
            for j in 0..<n {
                var sum: CGFloat = 0
                for k in 0..<p { sum += A[i][k] * B[k][j] }
                C[i][j] = sum
            }
        }
        return C
    }

    private func multiplyMatVec(_ A: [[CGFloat]], _ v: [CGFloat]) -> [CGFloat] {
        let m = A.count, n = v.count
        var out = Array(repeating: CGFloat(0), count: m)
        for i in 0..<m { var sum: CGFloat = 0; for j in 0..<n { sum += A[i][j] * v[j] } ; out[i] = sum }
        return out
    }

    private func addMatMat(_ A: [[CGFloat]], _ B: [[CGFloat]]) -> [[CGFloat]] {
        let m = A.count, n = A[0].count
        var C = Array(repeating: Array(repeating: CGFloat(0), count: n), count: m)
        for i in 0..<m { for j in 0..<n { C[i][j] = A[i][j] + B[i][j] } }
        return C
    }

    private func subtractMatMat(_ A: [[CGFloat]], _ B: [[CGFloat]]) -> [[CGFloat]] {
        let m = A.count, n = A[0].count
        var C = Array(repeating: Array(repeating: CGFloat(0), count: n), count: m)
        for i in 0..<m { for j in 0..<n { C[i][j] = A[i][j] - B[i][j] } }
        return C
    }

    private func addVecVec(_ a: [CGFloat], _ b: [CGFloat]) -> [CGFloat] {
        zip(a,b).map(+)
    }

    private func subtractVecVec(_ a: [CGFloat], _ b: [CGFloat]) -> [CGFloat] {
        zip(a,b).map(-)
    }

    private func invert2x2(_ S: [[CGFloat]]) -> [[CGFloat]] {
        let a = S[0][0], b = S[0][1], c = S[1][0], d = S[1][1]
        let det = a*d - b*c
        let invDet: CGFloat = det != 0 ? 1.0/det : 0
        return [[ d*invDet, -b*invDet],
                [-c*invDet,  a*invDet]]
    }
}

