import Foundation
import UIKit

// Off-device lifter client. Posts COCO-17 2D sequences and expects stabilized 2D back.
// If endpoint is not configured or request fails, returns input or a light smoother.
final class LifterService {
    // Set your endpoint here (e.g., https://your.api/lift)
    // Or store in UserDefaults under key "LIFTER_ENDPOINT"
    private let defaultEndpointString: String? = "http://192.168.1.39:5050/lift"
    private let requestTimeout: TimeInterval = 20
    // If true, logs basic request/response info to console for debugging
    private let verbose: Bool = true

    // Exposed status for UI
    private(set) var lastUsedServer: Bool = false
    private(set) var lastStatusMessage: String = ""

    private struct RequestBody: Codable {
        let fps: Double
        let poses2d: [[[Float]]]
    }

    private struct ResponseBody: Codable {
        let poses2d_stabilized: [[[Float]]]? // preferred
        let poses2d: [[[Float]]]?            // fallback field name if server echoes under same key
    }

    private func endpointURL() -> URL? {
        if let s = UserDefaults.standard.string(forKey: "LIFTER_ENDPOINT"), let u = URL(string: s) { return u }
        if let s = defaultEndpointString, let u = URL(string: s) { return u }
        return nil
    }

    private func cocoToBlazeMap() -> [(coco: Int, blaze: Int)] {
        return [
            (0, 0), (1, 2), (2, 5), (3, 7), (4, 8),
            (5, 11), (6, 12), (7, 13), (8, 14), (9, 15), (10, 16),
            (11, 23), (12, 24), (13, 25), (14, 26), (15, 27), (16, 28)
        ]
    }

    private func mapBlazePoseToCOCO17(frames: [(image: UIImage, joints: [Int: CGPoint])]) -> [[[Float]]]{
        let map = cocoToBlazeMap()
        var result: [[[Float]]] = Array(repeating: Array(repeating: Array(repeating: 0, count: 2), count: 17), count: frames.count)
        for (i, f) in frames.enumerated() {
            var row = Array(repeating: [Float](repeating: 0, count: 2), count: 17)
            for (c, b) in map {
                if let p = f.joints[b] { row[c] = [Float(p.x), Float(p.y)] }
            }
            result[i] = row
        }
        return result
    }

    private func blendCOCO17Back(frames: [(image: UIImage, joints: [Int: CGPoint])], coco2d: [[[Float]]]) -> [(image: UIImage, joints: [Int: CGPoint])]{
        let map = cocoToBlazeMap()
        var out = frames
        let t = min(frames.count, coco2d.count)
        for i in 0..<t {
            var joints = out[i].joints
            let row = coco2d[i]
            for (cj, bj) in map where cj < row.count {
                let xy = row[cj]
                if xy.count == 2 { joints[bj] = CGPoint(x: CGFloat(xy[0]), y: CGFloat(xy[1])) }
            }
            // Safeguard wrists: reject obviously bad server outputs
            let LW = 15, RW = 16, LE = 13, RE = 14
            if let origLW = frames[i].joints[LW], let origRW = frames[i].joints[RW],
               let newLW = joints[LW], let newRW = joints[RW] {
                let origDist = max(1, hypot(origRW.x - origLW.x, origRW.y - origLW.y))
                let newDist = hypot(newRW.x - newLW.x, newRW.y - newLW.y)
                let move = max(hypot(newLW.x - origLW.x, newLW.y - origLW.y), hypot(newRW.x - origRW.x, newRW.y - origRW.y))
                let distRatio = newDist / origDist
                if distRatio < 0.98 || distRatio > 1.4 || move > 28 {
                    // Expand toward original separation conservatively
                    let mid = CGPoint(x: (newLW.x + newRW.x) * 0.5, y: (newLW.y + newRW.y) * 0.5)
                    let vec = CGPoint(x: newRW.x - newLW.x, y: newRW.y - newLW.y)
                    let len = max(1e-3, hypot(vec.x, vec.y))
                    let ux = vec.x / len, uy = vec.y / len
                    let target = max(newDist, 0.9 * origDist)
                    let half = target * 0.5
                    joints[LW] = CGPoint(x: mid.x - ux * half, y: mid.y - uy * half)
                    joints[RW] = CGPoint(x: mid.x + ux * half, y: mid.y + uy * half)
                } else if let le = joints[LE], let re = joints[RE] {
                    // Enforce reasonable forearm lengths based on original
                    let origL = max(1e-3, hypot(origLW.x - (frames[i].joints[LE]?.x ?? origLW.x), origLW.y - (frames[i].joints[LE]?.y ?? origLW.y)))
                    let origR = max(1e-3, hypot(origRW.x - (frames[i].joints[RE]?.x ?? origRW.x), origRW.y - (frames[i].joints[RE]?.y ?? origRW.y)))
                    let newLL = max(1, hypot(newLW.x - le.x, newLW.y - le.y))
                    let newRL = max(1, hypot(newRW.x - re.x, newRW.y - re.y))
                    if newLL < 0.98 * origL || newLL > 1.1 * origL { joints[LW] = origLW }
                    if newRL < 0.98 * origR || newRL > 1.1 * origR { joints[RW] = origRW }
                }
            }
            out[i] = (image: out[i].image, joints: joints)
        }
        return out
    }

    private func smoothFallback(frames: [(image: UIImage, joints: [Int: CGPoint])], window: Int = 5) -> [(image: UIImage, joints: [Int: CGPoint])]{
        guard window > 1, frames.count > window else { return frames }
        var result = frames
        let jointCount = 33
        var xs = Array(repeating: [CGFloat](repeating: 0, count: frames.count), count: jointCount)
        var ys = xs
        var present = Array(repeating: [Bool](repeating: false, count: frames.count), count: jointCount)
        for (i, f) in frames.enumerated() {
            for j in 0..<jointCount { if let p = f.joints[j] { xs[j][i] = p.x; ys[j][i] = p.y; present[j][i] = true } }
        }
        func movAvg(_ v: [CGFloat], _ m: [Bool], _ w: Int) -> [CGFloat] {
            let n = v.count; if n <= w { return v }
            var out = v; var sum: CGFloat = 0; var cnt = 0; let h = w/2
            for i in 0..<w { if m[i] { sum += v[i]; cnt += 1 } }
            if cnt > 0 { out[h] = sum / CGFloat(cnt) }
            for i in w..<n {
                if m[i] { sum += v[i]; cnt += 1 }
                if m[i-w] { sum -= v[i-w]; cnt -= 1 }
                let c = i - h; if c < n, cnt > 0 { out[c] = sum / CGFloat(cnt) }
            }
            return out
        }
        for j in 0..<jointCount {
            let sx = movAvg(xs[j], present[j], window)
            let sy = movAvg(ys[j], present[j], window)
            for i in 0..<frames.count where present[j][i] {
                var joints = result[i].joints
                joints[j] = CGPoint(x: sx[i], y: sy[i])
                result[i] = (image: result[i].image, joints: joints)
            }
        }
        return result
    }

    func liftOffDevice(frames: [(image: UIImage, joints: [Int: CGPoint])], fps: CGFloat) async -> [(image: UIImage, joints: [Int: CGPoint])]{
        guard let url = endpointURL() else {
            lastUsedServer = false
            lastStatusMessage = "local (no endpoint)"
            return smoothFallback(frames: frames)
        }
        let coco = mapBlazePoseToCOCO17(frames: frames)
        let body = RequestBody(fps: Double(fps), poses2d: coco)
        guard let data = try? JSONEncoder().encode(body) else { return frames }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = requestTimeout
        req.httpBody = data
        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            if verbose { print("LifterService: response status =", (resp as? HTTPURLResponse)?.statusCode ?? -1) }
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastUsedServer = false
                lastStatusMessage = "local (bad status)"
                return frames
            }
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: respData)
            let out = decoded.poses2d_stabilized ?? decoded.poses2d
            guard let outSeq = out else {
                lastUsedServer = false
                lastStatusMessage = "local (empty response)"
                return frames
            }
            lastUsedServer = true
            lastStatusMessage = "server"
            return blendCOCO17Back(frames: frames, coco2d: outSeq)
        } catch {
            if verbose { print("LifterService: request failed, falling back ->", error.localizedDescription) }
            lastUsedServer = false
            lastStatusMessage = "local (error)"
            return smoothFallback(frames: frames)
        }
    }
}

