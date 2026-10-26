import XCTest
import Network
@testable import Tunerfenster

private final class HTSPFixture: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "CommercialTests.fixture")
    private var connections = [NWConnection]()
    let handler: @Sendable (Peer) async throws -> Void

    init(handler: @escaping @Sendable (Peer) async throws -> Void) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.handler = handler
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                if case .ready = state, let port = listener.port {
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port.rawValue)
                } else if case .failed(let error) = state {
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connections.append(connection)
                connection.start(queue: queue)
                Task {
                    do { try await handler(Peer(connection: connection)) }
                    catch { connection.cancel() }
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in connections.forEach { $0.cancel() }; connections = [] }
    }

    struct Peer: Sendable {
        let connection: NWConnection
        func read(_ count: Int) async throws -> Data {
            var data = Data()
            while data.count < count {
                let remaining = count - data.count
                let part: Data = try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let data, !data.isEmpty { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: URLError(.networkConnectionLost)) }
                    }
                }
                data.append(part)
            }
            return data
        }
        func message() async throws -> [String: HTSPValue] {
            let header = try await read(4), length = header.reduce(0) { ($0 << 8) | Int($1) }
            guard length < 1_000_000 else { throw URLError(.badServerResponse) }
            return try HTSPCodec.decode(try await read(length))
        }
        func send(_ data: Data) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }
        func reply(_ message: [String: HTSPValue]) async throws {
            let data = try HTSPCodec.encode(message)
            // Split the length prefix across TCP writes as real networks can.
            try await send(Data(data.prefix(2)))
            try await send(Data(data.dropFirst(2)))
        }
    }
}

final class HTSPTests: XCTestCase {
    let recording = SavedRecording(uuid: String(repeating: "a", count: 32), start: 100, stop: 200)
    let connection = Connection(address: "http://localhost:9981", username: "fixture", password: "fixture-password")

    func testFileDurationsUseOneMetadataSyncWithoutOpeningFilesOrRequestingCutpoints() async throws {
        let first = recording, second = SavedRecording(uuid: String(repeating: "b", count: 32), duration: 10800)
        let closed = expectation(description: "Metadata-only connection closed")
        let server = try HTSPFixture { peer in
            let hello = try await peer.message()
            XCTAssertEqual(hello["method"], .string("hello"))
            try await peer.reply(["seq": .integer(1), "htspversion": .integer(44)])
            let request = try await peer.message()
            XCTAssertEqual(request["method"], .string("enableAsyncMetadata"))
            for (index, item) in [first, second].enumerated() {
                let duration: Int64 = index == 0 ? 6757 : 32
                try await peer.reply(["method": .string("dvrEntryAdd"), "id": .integer(Int64(index + 1)),
                                      "idStr": .string(item.id), "files": .list([
                                        .map(["start": .integer(1000), "stop": .integer(1000 + duration)])
                                      ])])
            }
            try await peer.reply(["method": .string("initialSyncCompleted")])
            let unexpected = try? await peer.message()
            XCTAssertNil(unexpected, "Reading durations must not request a stream or cutpoints")
            closed.fulfill()
        }
        let port = try await server.start()
        defer { server.stop() }
        let values = try await HTSPCommercials.loadFileDurations(recordings: [first, second],
            connection: .init(address: "http://localhost:9981", username: "", password: "", auth: "none"),
            endpoint: .init(host: "127.0.0.1", port: port))
        XCTAssertEqual(values, [first.id: 6757, second.id: 32])
        await fulfillment(of: [closed], timeout: 3)
    }

    func testFullChallengeHandshakeMetadataMatchingAndFragmentedCutpointResponse() async throws {
        let uuid = recording.id
        let verified = expectation(description: "Read-only HTSP request validated")
        let server = try HTSPFixture { peer in
            let hello = try await peer.message()
            XCTAssertEqual(hello["method"], .string("hello"))
            XCTAssertEqual(hello["seq"], .integer(1))
            try await peer.reply(["seq": .integer(1), "htspversion": .integer(44), "challenge": .binary(Data(0..<32)),
                                  "servercapability": .list([.string("fixture")])])
            let auth = try await peer.message()
            XCTAssertEqual(auth["method"], .string("authenticate"))
            XCTAssertEqual(auth["username"], .string("fixture"))
            XCTAssertEqual(auth["digest"], .binary(HTSPCommercials.digest(password: "fixture-password", challenge: Data(0..<32))))
            XCTAssertNil(auth["password"])
            try await peer.reply(["seq": .integer(2), "dvr": .integer(1)])
            let metadata = try await peer.message()
            XCTAssertEqual(metadata["method"], .string("enableAsyncMetadata"))
            XCTAssertEqual(metadata["epg"], .integer(0))
            try await peer.reply(["seq": .integer(3)])
            try await peer.reply(["method": .string("channelAdd"), "channelName": .string("Unrelated channel")])
            try await peer.reply(["method": .string("dvrEntryAdd"), "idStr": .string(uuid), "id": .integer(99)])
            try await peer.reply(["method": .string("initialSyncCompleted")])
            let cuts = try await peer.message()
            XCTAssertEqual(cuts["method"], .string("getDvrCutpoints"))
            XCTAssertEqual(cuts["id"], .integer(99))
            try await peer.reply(["method": .string("dvrEntryUpdate"), "id": .integer(17)])
            try await peer.reply(["seq": .integer(4), "cutpoints": .list([
                .map(["start": .integer(10_000), "end": .integer(25_000), "type": .integer(3)])
            ])])
            verified.fulfill()
        }
        let port = try await server.start()
        defer { server.stop() }
        let values = try await HTSPCommercials.load(recording: recording, connection: connection, endpoint: .init(host: "127.0.0.1", port: port))
        XCTAssertEqual(values.breaks, [.init(start: 10, end: 25)])
        await fulfillment(of: [verified], timeout: 3)
    }

    func testAuthenticationDenialDoesNotProceedToRecordingMetadata() async throws {
        let server = try HTSPFixture { peer in
            _ = try await peer.message()
            try await peer.reply(["seq": .integer(1), "htspversion": .integer(44), "challenge": .binary(Data(0..<32))])
            _ = try await peer.message()
            try await peer.reply(["seq": .integer(2), "noaccess": .integer(1)])
        }
        let port = try await server.start()
        defer { server.stop() }
        do {
            _ = try await HTSPCommercials.load(recording: recording, connection: connection, endpoint: .init(host: "127.0.0.1", port: port))
            XCTFail("Denied metadata must not load")
        } catch let error as AppError { XCTAssertTrue(error.description(language: .english).contains("denied")) }
    }

    func testOversizedAndTruncatedFramesFailInsteadOfAllocatingOrHanging() async throws {
        for packet in [Data([0x7f, 0xff, 0xff, 0xff]), Data([0, 0, 0, 20, 3, 1])] {
            let server = try HTSPFixture { peer in
                _ = try await peer.message()
                try await peer.send(packet)
                peer.connection.cancel()
            }
            let port = try await server.start()
            do {
                _ = try await HTSPCommercials.load(recording: recording, connection: connection, endpoint: .init(host: "127.0.0.1", port: port))
                XCTFail("Invalid frame must fail")
            } catch {}
            server.stop()
        }
    }

    func testCancellingSelectionClosesAPendingHTSPRead() async throws {
        let waiting = expectation(description: "Client waits for hello")
        let server = try HTSPFixture { peer in _ = try await peer.message(); waiting.fulfill() }
        let port = try await server.start()
        defer { server.stop() }
        let task = Task { try await HTSPCommercials.load(recording: recording, connection: connection,
                                                       endpoint: .init(host: "127.0.0.1", port: port)) }
        await fulfillment(of: [waiting], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request must end") } catch {}
    }
}
