import Foundation

public enum DesktopCoverage {
    /// Subtract opaque window rectangles; supports several windows covering a display together.
    public static func isCovered(_ screen: CGRect, by windows: [CGRect]) -> Bool {
        guard !screen.isEmpty else { return false }
        var remaining = [screen]
        for window in windows {
            remaining = remaining.flatMap { subtract(window, from: $0) }
            if remaining.isEmpty { return true }
            // Avoid pathological fragmentation; uncertainty keeps the wallpaper visible.
            if remaining.count > 256 { return false }
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
