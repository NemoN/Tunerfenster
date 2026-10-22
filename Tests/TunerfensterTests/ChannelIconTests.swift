import XCTest
@testable import Tunerfenster

final class ChannelIconTests: XCTestCase {
    func testCacheReferenceResolvesWithinConfiguredWebroot() {
        let api = API(connection: Connection(address: "http://localhost:9981/tvh", username: "test", password: "test"))
        defer { api.close() }
        for reference in ["imagecache/221", "/tvh/imagecache/221", "http://localhost:9981/tvh/imagecache/221"] {
            let channel = Channel(uuid: "arte", name: "arte HD", icon_public_url: reference)
            XCTAssertEqual(api.channelIconURL(for: channel)?.absoluteString, "http://localhost:9981/tvh/imagecache/221")
        }
    }

    func testIconDoesNotSendServerCredentialsToAnotherOriginOrLocalFile() {
        let api = API(connection: Connection(address: "http://localhost:9981/tvh", username: "test", password: "test"))
        defer { api.close() }
        for reference in [nil, "", "picon://logo.png", "file:///tmp/logo.png", "https://localhost:9981/tvh/imagecache/1",
                          "http://other.invalid/tvh/imagecache/1", "//other.invalid/logo.png", "http://localhost:80/tvh/imagecache/1",
                          "http://user:secret@localhost:9981/tvh/imagecache/1", "/outside/logo.png", "../logo.png"] as [String?] {
            XCTAssertNil(api.channelIconURL(for: Channel(uuid: "channel", name: "Channel", icon_public_url: reference)))
        }
    }

    func testChannelsWithAndWithoutConfiguredIconsDecode() throws {
        let channels = try JSONDecoder().decode([Channel].self, from: Data(#"[{"uuid":"arte","name":"arte HD","icon_public_url":"imagecache/221"},{"uuid":"missing","name":"Missing"}]"#.utf8))
        XCTAssertEqual(channels[0].icon_public_url, "imagecache/221")
        XCTAssertNil(channels[1].icon_public_url)
    }
}
