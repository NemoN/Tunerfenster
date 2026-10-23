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
        api.setMedia(player, media)
        api.mute(player, 1)
        guard api.play(player) == 0 else { throw AppError.message("vlcStartFailed") }
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if let stats = api.statistics(for: player) {
                if stats.decodedVideo > 0, stats.decodedAudio > 0, stats.readBytes > 0, stats.demuxBytes > 0 {
                    print("Playback passed: \(stats.decodedVideo) video frames, \(stats.decodedAudio) audio frames, \(stats.width)×\(stats.height), \(stats.readBytes) input bytes.")
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline && api.state(player) != 7
        throw AppError.message("playbackFailed")
    }
}
