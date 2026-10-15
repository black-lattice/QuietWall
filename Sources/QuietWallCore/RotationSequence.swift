import Foundation

/// A persisted shuffle bag and navigation history. Merely browsing candidates never advances it.
public struct RotationSequence: Codable {
    public var remaining: [URL] = []
    public var past: [URL] = []
    public var future: [URL] = []
    public init() {}

    public mutating func candidates(_ files: [URL], current: URL?, random: Bool) -> [URL] {
        let valid = Set(files)
        remaining.removeAll { !valid.contains($0) }
        future.removeAll { !valid.contains($0) }
        if let next = future.last { return [next] + files.filter { $0 != next } }
        if random {
            if remaining.isEmpty {
                remaining = files.shuffled()
                if remaining.count > 1, remaining.first == current {
                    remaining.swapAt(0, remaining.count - 1)
                }
            }
            return remaining
        }
        guard let current, let index = files.firstIndex(of: current) else { return files }
        return Array(files.dropFirst(index + 1)) + Array(files.prefix(index + 1))
    }

    public func previous(in files: [URL], current: URL?) -> URL? {
        if let previous = past.last(where: { files.contains($0) && $0 != current }) { return previous }
        guard let current, let index = files.firstIndex(of: current), !files.isEmpty else { return files.last }
        return files[(index + files.count - 1) % files.count]
    }

    public mutating func used(_ url: URL, previous: URL?, backwards: Bool = false) {
        remaining.removeAll { $0 == url }
        if backwards {
            if let previous { future.append(previous) }
            if let index = past.lastIndex(of: url) { past = Array(past.prefix(index)) }
        } else {
            if let previous, previous != url { past.append(previous) }
            past = Array(past.suffix(100))
            if future.last == url { future.removeLast() } else { future.removeAll() }
        }
    }
}
