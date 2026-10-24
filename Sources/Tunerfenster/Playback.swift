import AppKit
import SwiftUI
import Darwin

typealias VLCRef = UnsafeMutableRawPointer

final class VLC: @unchecked Sendable {
    static let shared = Result { try VLC() }
    let library: UnsafeMutableRawPointer
    let libraryURL: URL
    let version: String
    let instance: VLCRef
    let mediaNew: @convention(c) (VLCRef?, UnsafePointer<CChar>?) -> VLCRef?
    let mediaOption: @convention(c) (VLCRef?, UnsafePointer<CChar>?) -> Void
    let mediaRelease: @convention(c) (VLCRef?) -> Void
    let getMedia: @convention(c) (VLCRef?) -> VLCRef?
    let mediaStats: @convention(c) (VLCRef?, UnsafeMutableRawPointer?) -> Int32
    let playerNew: @convention(c) (VLCRef?) -> VLCRef?
    let playerRelease: @convention(c) (VLCRef?) -> Void
    let setMedia: @convention(c) (VLCRef?, VLCRef?) -> Void
    let setView: @convention(c) (VLCRef?, UnsafeMutableRawPointer?) -> Void
    let play: @convention(c) (VLCRef?) -> Int32
    let stop: @convention(c) (VLCRef?) -> Void
    let state: @convention(c) (VLCRef?) -> Int32
    let mute: @convention(c) (VLCRef?, Int32) -> Void
    let videoSize: @convention(c) (VLCRef?, UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    let getTime: @convention(c) (VLCRef?) -> Int64
    let getLength: @convention(c) (VLCRef?) -> Int64
    let getPosition: @convention(c) (VLCRef?) -> Float
    let setTime: @convention(c) (VLCRef?, Int64) -> Void
    let setPosition: @convention(c) (VLCRef?, Float) -> Void
    let setPause: @convention(c) (VLCRef?, Int32) -> Void
    let isSeekable: @convention(c) (VLCRef?) -> Int32

    private init() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VLCKit.framework/VLCKit")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.message("vlcRequired")
        }
        // VLCKit includes its playback modules. Never search a separately installed
        // VLC, user plugin directory or environment override for executable code.
        unsetenv("VLC_PLUGIN_PATH")
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            throw AppError.message("vlcLoadFailed")
        }
        library = handle
        libraryURL = url
        func bind<T>(_ name: String, _: T.Type) throws -> T {
            guard let symbol = dlsym(handle, name) else { throw AppError.message("vlcUnsupported", [name]) }
            return unsafeBitCast(symbol, to: T.self)
        }
        let create = try bind("libvlc_new", (@convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> VLCRef?).self)
        let getVersion = try bind("libvlc_get_version", (@convention(c) () -> UnsafePointer<CChar>?).self)
        version = getVersion().map { String(cString: $0) } ?? "unknown"
        mediaNew = try bind("libvlc_media_new_location", (@convention(c) (VLCRef?, UnsafePointer<CChar>?) -> VLCRef?).self)
        mediaOption = try bind("libvlc_media_add_option", (@convention(c) (VLCRef?, UnsafePointer<CChar>?) -> Void).self)
        mediaRelease = try bind("libvlc_media_release", (@convention(c) (VLCRef?) -> Void).self)
        getMedia = try bind("libvlc_media_player_get_media", (@convention(c) (VLCRef?) -> VLCRef?).self)
        mediaStats = try bind("libvlc_media_get_stats", (@convention(c) (VLCRef?, UnsafeMutableRawPointer?) -> Int32).self)
        playerNew = try bind("libvlc_media_player_new", (@convention(c) (VLCRef?) -> VLCRef?).self)
        playerRelease = try bind("libvlc_media_player_release", (@convention(c) (VLCRef?) -> Void).self)
        setMedia = try bind("libvlc_media_player_set_media", (@convention(c) (VLCRef?, VLCRef?) -> Void).self)
        setView = try bind("libvlc_media_player_set_nsobject", (@convention(c) (VLCRef?, UnsafeMutableRawPointer?) -> Void).self)
        play = try bind("libvlc_media_player_play", (@convention(c) (VLCRef?) -> Int32).self)
        stop = try bind("libvlc_media_player_stop", (@convention(c) (VLCRef?) -> Void).self)
        state = try bind("libvlc_media_player_get_state", (@convention(c) (VLCRef?) -> Int32).self)
        mute = try bind("libvlc_audio_set_mute", (@convention(c) (VLCRef?, Int32) -> Void).self)
        videoSize = try bind("libvlc_video_get_size", (@convention(c) (VLCRef?, UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32).self)
        getTime = try bind("libvlc_media_player_get_time", (@convention(c) (VLCRef?) -> Int64).self)
        getLength = try bind("libvlc_media_player_get_length", (@convention(c) (VLCRef?) -> Int64).self)
        getPosition = try bind("libvlc_media_player_get_position", (@convention(c) (VLCRef?) -> Float).self)
        setTime = try bind("libvlc_media_player_set_time", (@convention(c) (VLCRef?, Int64) -> Void).self)
        setPosition = try bind("libvlc_media_player_set_position", (@convention(c) (VLCRef?, Float) -> Void).self)
        setPause = try bind("libvlc_media_player_set_pause", (@convention(c) (VLCRef?, Int32) -> Void).self)
        isSeekable = try bind("libvlc_media_player_is_seekable", (@convention(c) (VLCRef?) -> Int32).self)
        var arguments = ["--quiet", "--no-interact", "--keystore=memory", "--no-video-title-show", "--no-video-on-top", "--no-osd", "--avcodec-hw=videotoolbox", "--no-media-library", "--no-sub-autodetect-file"]
        if ProcessInfo.processInfo.arguments.contains("--check-playback") {
            arguments += ["--vout=dummy", "--aout=dummy", "--avcodec-hw=none"]
        }
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        let pointers = strings.map { $0.map { UnsafePointer<CChar>($0) } }
        guard let result = pointers.withUnsafeBufferPointer({ create(Int32(arguments.count), $0.baseAddress) }) else {
            throw AppError.message("vlcStartFailed")
        }
        instance = result
    }

    func statistics(for player: VLCRef) -> StreamStatistics? {
        // get_media retains its result. Call on the player's queue so sampling
        // cannot race our set_media/stop/release operations.
        guard let media = getMedia(player) else { return nil }
        defer { mediaRelease(media) }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: StreamStatistics.byteCount, alignment: 4)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: StreamStatistics.byteCount)
        guard mediaStats(media, buffer) != 0 else { return nil }
        var width: UInt32 = 0, height: UInt32 = 0
        _ = videoSize(player, 0, &width, &height)
        return StreamStatistics(buffer: UnsafeRawBufferPointer(start: buffer, count: StreamStatistics.byteCount),
                                width: width, height: height)
    }
}

private final class PlayerHandle: @unchecked Sendable {
    let api: VLC
    let pointer: VLCRef
    let queue = DispatchQueue(label: "de.local.Tunerfenster.player", qos: .userInitiated)
    init(api: VLC, pointer: VLCRef) { self.api = api; self.pointer = pointer }
    deinit {
        let api = api, pointer = pointer
        // VLC's stop can wait for its main-thread video teardown. Never block AppKit.
        queue.async {
            api.stop(pointer)
            api.setView(pointer, nil)
            api.playerRelease(pointer)
        }
    }
}

final class VideoCanvas: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.black.setFill(); dirtyRect.fill() }
}

@MainActor
final class Playback: ObservableObject {
    let canvas = VideoCanvas(frame: .zero)
    @Published private var statusMessage: AppError = .message("playbackConnecting")
    var status: String { statusMessage.localizedDescription }
    @Published var isPlaying = false
    @Published private(set) var hasVideo = false
    @Published private(set) var streamRevision = UUID()
    @Published private(set) var isPaused = false
    @Published private(set) var ended = false
    @Published private(set) var failed = false
    @Published private(set) var positionSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var canSeek = false
    @Published private(set) var timelineEstimated = false
    @Published private(set) var restoringPosition = false
    @Published private(set) var resumeFailed = false
    private var resumeTarget: Double?
    private var resumeRequested: Date?
    private var handle: PlayerHandle?
    private var current: String?
    private var lastStart = Date.distantPast
    private var muted = true
    private var retryDelay: TimeInterval = 6

    init() {
        do {
            let api = try VLC.shared.get()
            guard let pointer = api.playerNew(api.instance) else { throw AppError.message("vlcPlayerFailed") }
            handle = PlayerHandle(api: api, pointer: pointer)
            api.setView(pointer, Unmanaged.passUnretained(canvas).toOpaque())
        } catch { statusMessage = .wrapping(error) }
    }

    func start(url: URL, key: String, resumeAt: Double = 0) {
        guard let handle else { return }
        let changed = current != key
        let state = handle.api.state(handle.pointer)
        let stalled = [0, 5, 6, 7].contains(state) || Date().timeIntervalSince(lastStart) > 20 && [1, 2].contains(state)
        guard changed || stalled && Date().timeIntervalSince(lastStart) > retryDelay else { updateStatus(); return }
        retryDelay = changed ? 6 : min(60, retryDelay * 2)
        current = key
        streamRevision = UUID()
        lastStart = Date()
        statusMessage = .message(changed ? "playbackConnecting" : "playbackReconnecting")
        isPlaying = false; hasVideo = false
        isPaused = false; ended = false; failed = false; positionSeconds = 0; durationSeconds = 0; canSeek = false; timelineEstimated = false
        resumeTarget = resumeAt.isFinite && resumeAt > 0 ? resumeAt : nil
        resumeRequested = nil; restoringPosition = resumeTarget != nil; resumeFailed = false
        let muted = muted
        handle.queue.async {
            let api = handle.api, player = handle.pointer
            api.stop(player)
            // TVHeadend's short-lived ticket authorizes VLC without exposing a password.
            guard let media = url.absoluteString.withCString({ api.mediaNew(api.instance, $0) }) else { return }
            let options = [":network-caching=1000", ":http-user-agent=\(previewClient)", ":no-video-title-show", ":no-audio-time-stretch"]
            for option in options { option.withCString { api.mediaOption(media, $0) } }
            api.setMedia(player, media)
            api.mediaRelease(media)
            api.mute(player, muted ? 1 : 0)
            _ = api.play(player)
            api.mute(player, muted ? 1 : 0)
        }
    }

    func setMuted(_ value: Bool) {
        muted = value
        guard let handle else { return }
        handle.queue.async { handle.api.mute(handle.pointer, value ? 1 : 0) }
    }

    func stop() {
        guard current != nil else { return }
        current = nil
        streamRevision = UUID()
        isPlaying = false; hasVideo = false
        isPaused = false; ended = false; failed = false; positionSeconds = 0; durationSeconds = 0; canSeek = false; timelineEstimated = false
        resumeTarget = nil; resumeRequested = nil; restoringPosition = false; resumeFailed = false
        statusMessage = .message("playbackStopped")
        guard let handle else { return }
        handle.queue.async { handle.api.stop(handle.pointer) }
    }

    func statisticsSnapshot() async -> StreamStatistics? {
        guard current != nil, let handle, !Task.isCancelled else { return nil }
        let revision = streamRevision
        let result: StreamStatistics? = await withCheckedContinuation { continuation in
            handle.queue.async {
                continuation.resume(returning: handle.api.statistics(for: handle.pointer))
            }
        }
        guard !Task.isCancelled, revision == streamRevision, current != nil else { return nil }
        return result
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ value: Bool) {
        guard current != nil, let handle else { return }
        isPaused = value
        handle.queue.async { handle.api.setPause(handle.pointer, value ? 1 : 0) }
    }

    func seek(to seconds: Double, manually: Bool = true) {
        guard current != nil, canSeek, seconds.isFinite, let handle else { return }
        if manually { resumeTarget = nil; resumeRequested = nil; restoringPosition = false; resumeFailed = false }
        let value = max(0, min(durationSeconds, seconds))
        positionSeconds = value
        let fraction = Float(value / durationSeconds), estimated = timelineEstimated
        handle.queue.async {
            if estimated { handle.api.setPosition(handle.pointer, fraction) }
            else { handle.api.setTime(handle.pointer, Int64(value * 1000)) }
        }
    }

    func updateTimeline(fallbackDuration: Double = 0) async {
        guard current != nil, let handle else { return }
        let revision = streamRevision
        let values: (Int64, Int64, Bool, Float) = await withCheckedContinuation { continuation in
            handle.queue.async {
                continuation.resume(returning: (handle.api.getTime(handle.pointer), handle.api.getLength(handle.pointer),
                                                handle.api.isSeekable(handle.pointer) != 0, handle.api.getPosition(handle.pointer)))
            }
        }
        guard !Task.isCancelled, revision == streamRevision, current != nil else { return }
        timelineEstimated = values.1 <= 0 && fallbackDuration > 0
        durationSeconds = values.1 > 0 ? Double(values.1) / 1000 : max(0, fallbackDuration)
        positionSeconds = max(0, Double(values.0) / 1000)
        // MPEG-TS may have no VLC duration and its clock can restart after a
        // byte-position seek. Use the file position with TVHeadend's estimate.
        if timelineEstimated, values.3.isFinite, values.3 > 0, values.3 <= 1 {
            positionSeconds = Double(values.3) * durationSeconds
        }
        canSeek = values.2 && durationSeconds > 0
        updateStatus()
        if let target = resumeTarget {
            if resumeRequested == nil, canSeek, isPlaying || isPaused {
                if target >= durationSeconds {
                    resumeTarget = nil; restoringPosition = false
                } else {
                    seek(to: target, manually: false)
                    resumeRequested = Date()
                }
            } else if resumeRequested != nil, positionSeconds > 0,
                      abs(positionSeconds - target) < max(2, min(5, target * 0.1)), isPlaying || isPaused {
                resumeTarget = nil; resumeRequested = nil; restoringPosition = false
            }
            if restoringPosition, Date().timeIntervalSince(resumeRequested ?? lastStart) > 12 {
                resumeTarget = nil; resumeRequested = nil; restoringPosition = false; resumeFailed = true
            }
        }
    }

    func updateStatus() {
        guard current != nil, let handle else { return }
        let state = handle.api.state(handle.pointer)
        var width: UInt32 = 0, height: UInt32 = 0
        _ = handle.api.videoSize(handle.pointer, 0, &width, &height)
        hasVideo = width > 0 && height > 0
        isPlaying = state == 3 && width > 0
        isPaused = state == 4
        ended = state == 6
        failed = state == 7
        switch state {
        case 3: statusMessage = width > 0 ? .message("videoResolution", [String(width), String(height)]) : .message("playbackNoVideo")
        case 4: statusMessage = .message("paused")
        case 5, 6: statusMessage = .message("playbackEnded")
        case 7: statusMessage = .message("playbackFailed")
        default: statusMessage = .message("playbackBuffering")
        }
    }
}

/// SwiftUI may keep the previous surface alive during a full-screen transition.
/// Give each surface its own host so only the current parent sizes VLC's canvas.
final class VideoHost: NSView {
    let canvas: VideoCanvas
    init(canvas: VideoCanvas) {
        self.canvas = canvas
        super.init(frame: .zero)
        addSubview(canvas)
        canvas.autoresizingMask = [.width, .height]
        canvas.frame = bounds
    }
    required init?(coder: NSCoder) { nil }
    func setCornerRadius(_ radius: CGFloat) {
        guard radius > 0 || layer != nil else { return }
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = radius > 0
    }
    override func layout() {
        super.layout()
        if canvas.superview === self { canvas.frame = bounds }
    }
}

struct VideoSurface: NSViewRepresentable {
    let playback: Playback
    var cornerRadius: CGFloat = 0
    func makeNSView(context: Context) -> VideoHost {
        let view = VideoHost(canvas: playback.canvas)
        view.setCornerRadius(cornerRadius)
        return view
    }
    func updateNSView(_ nsView: VideoHost, context: Context) {
        nsView.setCornerRadius(cornerRadius)
        nsView.needsLayout = true
    }
}
