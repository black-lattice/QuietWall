import SwiftUI

/// Shared native surfaces keep the library and preferences consistent in both appearances.
enum WallpaperTheme {
    static let accent = Color.blue
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let contentWidth: CGFloat = 1120
    static let cornerRadius: CGFloat = 12
}

extension View {
    func wallpaperSurface() -> some View {
        background(WallpaperTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius)
                .strokeBorder(WallpaperTheme.border.opacity(0.5), lineWidth: 1))
    }
}

struct WallpaperThumbnailButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}
