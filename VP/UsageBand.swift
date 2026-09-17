// audience: machine
// Colour band for a used-fraction, exactly like the upstream
// Sources/Model/UsageBand.swift: under 50% is ample, under 70% is watch,
// 70% and over is critical. (The task brief paraphrased this as "under 75%",
// but the actual upstream thresholds — and the frame they're checked
// against — are 50/70; the code wins per this repo's own convention.)
import AppKit

enum VPUsageBand {
    case ample, watch, critical

    static func band(forPercent pct: Double, watchLimit: Double = 50, criticalLimit: Double = 70) -> VPUsageBand {
        switch pct {
        case ..<watchLimit: return .ample
        case ..<criticalLimit: return .watch
        default: return .critical
        }
    }

    var color: NSColor {
        switch self {
        case .ample:    return VPPalette.ample
        case .watch:    return VPPalette.watch
        case .critical: return VPPalette.critical
        }
    }
}
