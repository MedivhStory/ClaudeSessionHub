import Foundation

public enum MilestoneSamplerConstants {
    public static let kFloor = 4
    public static let kCeiling = 8
    public static let kDivisor = 10
}

public enum MilestoneSampler {
    public static func adaptiveK(historyCount: Int) -> Int {
        if historyCount <= 0 { return 0 }
        let raw = max(MilestoneSamplerConstants.kFloor, historyCount / MilestoneSamplerConstants.kDivisor)
        let capped = min(MilestoneSamplerConstants.kCeiling, raw)
        return min(historyCount, capped)
    }
}
