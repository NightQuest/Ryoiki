import SwiftUI
import CoreGraphics

private struct CoreAnimationGIFView: View {
    let frames: [GIFFrame]
    let contentMode: ContentMode

    var body: some View {
        Color.clear
            .modifier(AnimatedContentsModifier(frames: frames, contentMode: contentMode))
    }
}

private struct AnimatedContentsModifier: ViewModifier {
    let frames: [GIFFrame]
    let contentMode: ContentMode

    func body(content: Content) -> some View {
        content
            .background(LayerBackedAnimation(frames: frames, contentMode: contentMode))
    }
}

#if canImport(UIKit)
import UIKit
private struct LayerBackedAnimation: UIViewRepresentable {
    let frames: [GIFFrame]
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.layer.masksToBounds = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard !frames.isEmpty else {
            uiView.layer.removeAnimation(forKey: "gif")
            uiView.layer.setValue(nil, forKey: "gifSignature")
            return
        }
        let images = frames.map { $0.image }
        let durations = frames.map { $0.duration }
        let total = max(durations.reduce(0, +), 0.001)
        let signature = "\(frames.count)-\(String(format: "%.6f", total))"
        if let prev = uiView.layer.value(forKey: "gifSignature") as? String, prev == signature {
            // No change; keep existing animation
            switch contentMode {
            case .fit: uiView.layer.contentsGravity = .resizeAspect
            case .fill: uiView.layer.contentsGravity = .resizeAspectFill
            @unknown default: uiView.layer.contentsGravity = .resizeAspect
            }
            return
        }
        var keyTimes: [NSNumber] = []
        var acc: Double = 0
        for d in durations {
            acc += d / total
            keyTimes.append(NSNumber(value: min(acc, 1)))
        }
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.repeatCount = .infinity
        anim.calculationMode = .discrete
        anim.isRemovedOnCompletion = false

        uiView.layer.removeAnimation(forKey: "gif")
        uiView.layer.add(anim, forKey: "gif")
        uiView.layer.setValue(signature, forKey: "gifSignature")

        switch contentMode {
        case .fit: uiView.layer.contentsGravity = .resizeAspect
        case .fill: uiView.layer.contentsGravity = .resizeAspectFill
        @unknown default: uiView.layer.contentsGravity = .resizeAspect
        }
    }
}
#elseif canImport(AppKit)
import AppKit
private struct LayerBackedAnimation: NSViewRepresentable {
    let frames: [GIFFrame]
    let contentMode: ContentMode

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !frames.isEmpty else {
            nsView.layer?.removeAnimation(forKey: "gif")
            nsView.layer?.setValue(nil, forKey: "gifSignature")
            return
        }
        let images = frames.map { $0.image }
        let durations = frames.map { $0.duration }
        let total = max(durations.reduce(0, +), 0.001)
        let signature = "\(frames.count)-\(String(format: "%.6f", total))"
        if let prev = nsView.layer?.value(forKey: "gifSignature") as? String, prev == signature {
            // No change; keep existing animation
            switch contentMode {
            case .fit: nsView.layer?.contentsGravity = .resizeAspect
            case .fill: nsView.layer?.contentsGravity = .resizeAspectFill
            @unknown default: nsView.layer?.contentsGravity = .resizeAspect
            }
            return
        }
        var keyTimes: [NSNumber] = []
        var acc: Double = 0
        for d in durations {
            acc += d / total
            keyTimes.append(NSNumber(value: min(acc, 1)))
        }
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.repeatCount = .infinity
        anim.calculationMode = .discrete
        anim.isRemovedOnCompletion = false

        nsView.layer?.removeAnimation(forKey: "gif")
        nsView.layer?.add(anim, forKey: "gif")
        nsView.layer?.setValue(signature, forKey: "gifSignature")

        switch contentMode {
        case .fit: nsView.layer?.contentsGravity = .resizeAspect
        case .fill: nsView.layer?.contentsGravity = .resizeAspectFill
        @unknown default: nsView.layer?.contentsGravity = .resizeAspect
        }
    }
}
#endif

struct GIFAnimatedImageView: View {
    let url: URL
    let contentMode: ContentMode
    let onFirstFrame: (() -> Void)?

    @State private var frames: [GIFFrame] = []
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoadedFromCache: Bool = false
    @State private var didNotifyFirstFrame = false

    init(url: URL, contentMode: ContentMode = .fill, onFirstFrame: (() -> Void)? = nil) {
        self.url = url
        self.contentMode = contentMode
        self.onFirstFrame = onFirstFrame
    }

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.clear
                    .onAppear(perform: loadFrames)
            } else {
                CoreAnimationGIFView(frames: frames, contentMode: contentMode)
                    .task {
                        if !didNotifyFirstFrame {
                            didNotifyFirstFrame = true
                            onFirstFrame?()
                        }
                    }
            }
        }
    }

    private func loadFrames() {
        // If cached, use immediately (existing fast-path)
        if let cached = GIFFrameCache.shared.frames(for: url), !cached.isEmpty {
            frames = cached
            totalDuration = cached.reduce(0) { $0 + $1.duration }
            isLoadedFromCache = true
            DispatchQueue.main.async { onFirstFrame?() }
            return
        }
        Task.detached(priority: .userInitiated) {
            let loaded = await GIFDecoder.loadFramesCoalesced(from: url, maxDimension: 512)
            let duration = loaded.reduce(0) { $0 + $1.duration }
            if !loaded.isEmpty {
                await GIFFrameCache.shared.setFrames(loaded, for: url)
            }
            await MainActor.run {
                frames = loaded
                totalDuration = duration
                isLoadedFromCache = false
                if !loaded.isEmpty { onFirstFrame?() }
            }
        }
    }
}
