import Foundation
import Darwin

// An end-to-end release check: use the shipped libVLC, demux a local clip and
// require decoded audio/video frames. It never reads server credentials or prefs.
enum PlaybackCheck {
    static func run(api: VLC, file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path),
              let media = file.absoluteString.withCString({ api.mediaNew(api.instance, $0) }) else {
            throw AppError.message("vlcPlayerFailed")
        }
        defer { api.mediaRelease(media) }
        guard let player = api.playerNew(api.instance) else { throw AppError.message("vlcPlayerFailed") }
        defer { api.stop(player); api.playerRelease(player) }
        guard let symbol = dlsym(api.library, "libvlc_media_get_stats") else {
            throw AppError.message("vlcUnsupported", ["libvlc_media_get_stats"])
        }
        let stats = unsafeBitCast(symbol, to: (@convention(c) (VLCRef?, UnsafeMutableRawPointer?) -> Int32).self)
        // libvlc_media_stats_t in libVLC 3.x consists of fifteen 32-bit fields.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 60, alignment: 4)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 60)
        api.setMedia(player, media)
        api.mute(player, 1)
        guard api.play(player) == 0 else { throw AppError.message("vlcStartFailed") }
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if stats(media, buffer) != 0 {
                let video = buffer.load(fromByteOffset: 6 * 4, as: Int32.self)
                let audio = buffer.load(fromByteOffset: 7 * 4, as: Int32.self)
                if video > 0, audio > 0 {
                    var width: UInt32 = 0, height: UInt32 = 0
                    _ = api.videoSize(player, 0, &width, &height)
                    print("Playback passed: \(video) video frames, \(audio) audio frames, \(width)×\(height).")
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline && api.state(player) != 7
        throw AppError.message("playbackFailed")
    }
}
