import XCTest
@testable import Tunerfenster

final class StreamStatisticsTests: XCTestCase {
    func testLibVLC3BufferDecodesCountersRatesAndUnsignedByteCounts() {
        // Public C ABI: int, float, int, float, followed by eleven 32-bit fields.
        // Byte counters are unsigned here to keep values above 2 GiB readable.
        let words: [UInt32] = [3_000_000_000, Float(1.25).bitPattern, 2_000_000, Float(0.75).bitPattern,
                               4, 5, 60, 70, 58, 2, 69, 1, 0, 0, Float(0).bitPattern]
        let stats = words.withUnsafeBytes { StreamStatistics(buffer: $0, width: 1920, height: 1080) }
        XCTAssertEqual(stats.readBytes, 3_000_000_000)
        XCTAssertEqual(stats.inputMbps, 10)
        XCTAssertEqual(stats.demuxBytes, 2_000_000)
        XCTAssertEqual(stats.demuxMbps, 6)
        XCTAssertEqual(stats.corrupted, 4)
        XCTAssertEqual(stats.discontinuities, 5)
        XCTAssertEqual(stats.decodedVideo, 60)
        XCTAssertEqual(stats.decodedAudio, 70)
        XCTAssertEqual(stats.displayedPictures, 58)
        XCTAssertEqual(stats.lostPictures, 2)
        XCTAssertEqual(stats.playedAudioBuffers, 69)
        XCTAssertEqual(stats.lostAudioBuffers, 1)
        XCTAssertEqual(stats.width, 1920)
        XCTAssertEqual(stats.height, 1080)
    }

    func testInvalidNativeRatesDoNotLeakNaNOrInfinityIntoUI() {
        for rate in [Float.nan, .infinity, -1] {
            var words = [UInt32](repeating: 0, count: 15)
            words[1] = rate.bitPattern; words[3] = rate.bitPattern
            let stats = words.withUnsafeBytes { StreamStatistics(buffer: $0) }
            XCTAssertEqual(stats.inputMbps, 0)
            XCTAssertEqual(stats.demuxMbps, 0)
        }
    }
}
