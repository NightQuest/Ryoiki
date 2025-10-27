import Foundation
import ImageIO
import CoreGraphics

struct GIFFrame {
    let image: CGImage
    let duration: TimeInterval
}

enum GIFDecoder {
    private static var inflight: [URL: [CheckedContinuation<[GIFFrame], Never>]] = [:]

    static func loadFramesCoalesced(from url: URL, maxDimension: CGFloat = 512) async -> [GIFFrame] {
        // If cached frames exist, return immediately
        if let cached = GIFFrameCache.shared.frames(for: url), !cached.isEmpty {
            return cached
        }
        // Coalesce concurrent requests
        if inflight[url] != nil {
            return await withCheckedContinuation { continuation in
                inflight[url, default: []].append(continuation)
            }
        }
        // Register leader
        return await withCheckedContinuation { leader in
            inflight[url] = []
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = GIFDecoder.loadFrames(from: url, maxDimension: maxDimension)
                if !loaded.isEmpty {
                    GIFFrameCache.shared.setFrames(loaded, for: url)
                }
                DispatchQueue.main.async {
                    // Resume leader
                    leader.resume(returning: loaded)
                    // Fan out to waiters
                    if let waiters = inflight[url] {
                        waiters.forEach { $0.resume(returning: loaded) }
                    }
                    inflight[url] = nil
                }
            }
        }
    }

    static func loadFrames(from url: URL, maxDimension: CGFloat = 512) -> [GIFFrame] {
        // Skip obviously empty or non-existent files to avoid ImageIO EOF warnings
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if resourceValues?.isRegularFile == false { return [] }
        if (resourceValues?.fileSize ?? 0) <= 0 { return [] }

        guard let data = try? Data(contentsOf: url) else { return [] }
        return loadFrames(from: data, maxDimension: maxDimension)
    }

    static func loadFrames(from data: Data, maxDimension: CGFloat = 512) -> [GIFFrame] {
        guard !data.isEmpty else { return [] }

        // Validate GIF signature: first 3 bytes should be "GIF"
        if data.count >= 3 {
            let sig0 = data[data.startIndex]
            let sig1 = data[data.startIndex.advanced(by: 1)]
            let sig2 = data[data.startIndex.advanced(by: 2)]
            let isGIF = (sig0 == 0x47 /* G */ && sig1 == 0x49 /* I */ && sig2 == 0x46 /* F */)
            if !isGIF { return [] }
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return [] }

        var frames: [GIFFrame] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let duration = frameDuration(at: index, source: source)
            let scaled = downscaled(cgImage, maxDimension: maxDimension)
            frames.append(GIFFrame(image: scaled, duration: duration))
        }
        return normalizeDurations(frames)
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        let defaultFrameDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultFrameDuration
        }

        if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            let v = unclamped.doubleValue
            return v > 0.011 ? v : defaultFrameDuration
        }
        if let clamped = gifDict[kCGImagePropertyGIFDelayTime] as? NSNumber {
            let v = clamped.doubleValue
            return v > 0.011 ? v : defaultFrameDuration
        }
        return defaultFrameDuration
    }

    private static func normalizeDurations(_ frames: [GIFFrame]) -> [GIFFrame] {
        guard !frames.isEmpty else { return frames }
        let minFrame: TimeInterval = 0.02 // ~50 FPS cap
        let maxFrame: TimeInterval = 10 // prevent pathological long delays
        return frames.map { (f: GIFFrame) -> GIFFrame in
            let duration: TimeInterval = min(max(f.duration, minFrame), maxFrame)
            return GIFFrame(image: f.image, duration: duration)
        }
    }

    private static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let maxSide = max(width, height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newW = max(Int(width * scale), 1)
        let newH = max(Int(height * scale), 1)

        // Use a standard sRGB RGBA8 premultiplied context to avoid ambiguity
        let bitsPerComponent: Int = 8
        let bytesPerPixel: Int = 4
        let bytesPerRow: Int = newW * bytesPerPixel
        let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? image.colorSpace
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo.byteOrder32Big
            .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

        guard let ctx: CGContext = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }
}
