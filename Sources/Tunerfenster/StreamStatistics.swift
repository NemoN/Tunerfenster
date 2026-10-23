import Foundation

/// Numeric counters from the bundled libVLC 3.x libvlc_media_stats_t.
struct StreamStatistics: Sendable {
    // Fifteen four-byte int/float fields in the public libVLC 3.x ABI.
    static let byteCount = 60
    let readBytes: UInt32
    let inputMbps: Double
    let demuxBytes: UInt32
    let demuxMbps: Double
    let corrupted: UInt32
    let discontinuities: UInt32
    let decodedVideo: UInt32
    let decodedAudio: UInt32
    let displayedPictures: UInt32
    let lostPictures: UInt32
    let playedAudioBuffers: UInt32
    let lostAudioBuffers: UInt32
    let width: UInt32
    let height: UInt32

    init(buffer: UnsafeRawBufferPointer, width: UInt32 = 0, height: UInt32 = 0) {
        precondition(buffer.count >= Self.byteCount)
        func counter(_ field: Int) -> UInt32 { buffer.loadUnaligned(fromByteOffset: field * 4, as: UInt32.self) }
        func rate(_ field: Int) -> Double {
            let value = buffer.loadUnaligned(fromByteOffset: field * 4, as: Float.self)
            // VLC reports decimal MB/s; eight bits per byte gives Mbit/s.
            return value.isFinite && value >= 0 ? Double(value) * 8 : 0
        }
        readBytes = counter(0); inputMbps = rate(1)
        demuxBytes = counter(2); demuxMbps = rate(3)
        corrupted = counter(4); discontinuities = counter(5)
        decodedVideo = counter(6); decodedAudio = counter(7)
        displayedPictures = counter(8); lostPictures = counter(9)
        playedAudioBuffers = counter(10); lostAudioBuffers = counter(11)
        self.width = width; self.height = height
    }
}
