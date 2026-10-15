import AppKit
import AVFoundation

enum WallpaperDisplayMode: String, CaseIterable, Identifiable {
    case fill, fit, stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "填充"
        case .fit: return "适应"
        case .stretch: return "拉伸"
        }
    }

    var explanation: String {
        switch self {
        case .fill: return "保持比例铺满屏幕，超出部分居中裁剪。"
        case .fit: return "保持比例完整显示，空余区域显示黑色。"
        case .stretch: return "拉伸铺满屏幕，不裁剪，画面比例可能改变。"
        }
    }

    var imageGravity: CALayerContentsGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}
