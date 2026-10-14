import AppKit
import AVFoundation

struct VideoAsset {
    let url: URL
    let asset: AVURLAsset
    let poster: CGImage
    let details: String
    let warning: String?

    static func load(_ url: URL) async throws -> VideoAsset {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw VideoError.unplayable }
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.noVideo
        }
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        let (poster, _) = try await generator.image(at: .zero)
        let large = max(size.width, size.height) > 1920 || min(size.width, size.height) > 1080
        return VideoAsset(
            url: url, asset: asset, poster: poster,
            details: "\(Int(size.width)) × \(Int(size.height)) · \(Int(fps.rounded())) 帧/秒",
            warning: large || fps > 30.5
                ? "这个视频的分辨率或帧率较高，可能增加耗电。建议换用 1080p、24–30 帧素材。" : nil
        )
    }
}

enum VideoError: LocalizedError {
    case unplayable, noVideo
    var errorDescription: String? {
        switch self {
        case .unplayable: return "系统无法播放这个视频，请选择兼容的 MP4 或 MOV 文件。"
        case .noVideo: return "文件没有有效的视频画面或时长。"
        }
    }
}
