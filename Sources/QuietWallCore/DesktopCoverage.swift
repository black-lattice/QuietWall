import Foundation
import CoreGraphics

public enum DesktopCoverage {
    public static let defaultThreshold = 0.95

    public static func savedThreshold(_ value: Double) -> Double {
        [0.90, 0.95, 1.0].contains(value) ? value : defaultThreshold
    }

    public static func canCoverDesktop(layer: Int, alpha: Double, isWallpaper: Bool,
                                       isDesktopShell: Bool = false) -> Bool {
        !isWallpaper && !isDesktopShell && layer >= 0 && alpha.isFinite && alpha >= 0.99
    }

    /// Subtract rectangles to measure their union without counting overlaps twice.
    public static func isCovered(_ screen: CGRect, by windows: [CGRect],
                                 threshold: Double = defaultThreshold) -> Bool {
        let area = screen.width * screen.height
        guard !screen.isEmpty, area.isFinite, area > 0,
              threshold.isFinite, threshold > 0, threshold <= 1 else { return false }
        var remaining = [screen]
        for window in windows {
            guard window.minX.isFinite, window.minY.isFinite,
                  window.width.isFinite, window.height.isFinite else { continue }
            remaining = remaining.flatMap { subtract(window, from: $0) }
            if remaining.isEmpty { return true }
            // Avoid pathological fragmentation; uncertainty keeps the wallpaper visible.
            if remaining.count > 256 { return false }
            let visibleArea = remaining.reduce(0) { $0 + $1.width * $1.height }
            if 1 - visibleArea / area >= threshold { return true }
        }
        return false
    }

    private static func subtract(_ cover: CGRect, from rect: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cover)
        guard !overlap.isNull && !overlap.isEmpty else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height)
        ].filter { !$0.isEmpty }
    }
}
