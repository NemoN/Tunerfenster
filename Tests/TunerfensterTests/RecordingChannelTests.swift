import XCTest
@testable import Tunerfenster

final class RecordingChannelTests: XCTestCase {
    func testRecordingUsesChannelIDBeforeName() throws {
        let recording = try JSONDecoder().decode(SavedRecording.self, from: Data(#"{"uuid":"recording","channel":"b","channelname":"Old name"}"#.utf8))
        let channels = [Channel(uuid: "a", name: "Old name"), Channel(uuid: "b", name: "New name")]
        XCTAssertEqual(RecordingChannel.resolve(recording, channels: channels)?.uuid, "b")
        XCTAssertNil(RecordingChannel.resolve(recording, channels: [channels[0]]))
    }

    func testLegacyNameMatchingRequiresAnUnambiguousChannel() {
        let recording = SavedRecording(uuid: "recording", channelname: " RTL ")
        XCTAssertEqual(RecordingChannel.resolve(recording, channels: [Channel(uuid: "a", name: "rtl")])?.uuid, "a")
        XCTAssertNil(RecordingChannel.resolve(recording, channels: [Channel(uuid: "a", name: "RTL"), Channel(uuid: "b", name: "rtl")]))
        XCTAssertNil(RecordingChannel.resolve(SavedRecording(uuid: "missing"), channels: [Channel(uuid: "a", name: "RTL")]))
    }
}
