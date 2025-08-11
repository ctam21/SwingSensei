import Foundation
import CoreGraphics

final class MultiPointKalman {
    private let dt: CGFloat
    private var filters: [String: KalmanFilter2D] = [:]
    private let processVar: CGFloat
    private let baseMeasVar: CGFloat

    init(dt: CGFloat, processVariance: CGFloat = 2.0, measurementVariance: CGFloat = 9.0) {
        self.dt = dt
        self.processVar = processVariance
        self.baseMeasVar = measurementVariance
    }

    func update(label: String, measurement: CGPoint?, speedHint: CGFloat = 0) -> CGPoint? {
        if filters[label] == nil, let m = measurement {
            filters[label] = KalmanFilter2D(initial: m, dt: dt)
        }
        guard let kf = filters[label] else { return nil }
        kf.predict()
        if let m = measurement {
            let varAdj = baseMeasVar * max(1, speedHint / 80)
            kf.update(measurement: m, measurementVariance: varAdj)
        }
        return kf.currentPosition()
    }
}


