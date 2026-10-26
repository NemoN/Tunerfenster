import Foundation
import Network
import CryptoKit

indirect enum HTSPValue: Equatable, Sendable {
    case integer(Int64), string(String), binary(Data), list([HTSPValue]), map([String: HTSPValue])
    var integer: Int64? { if case .integer(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
}

enum HTSPCodec {
    static let maximumMessage = 1_048_576

    static func encode(_ message: [String: HTSPValue]) throws -> Data {
        let body = try fields(message.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        guard body.count <= maximumMessage else { throw AppError.message("commercialResponseInvalid") }
        return length(body.count) + body
    }

    private static func length(_ value: Int) -> Data {
        Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private static func fields(_ fields: [(String, HTSPValue)]) throws -> Data {
        var result = Data()
        for (name, value) in fields {
            let key = Data(name.utf8)
            guard key.count <= 255 else { throw AppError.message("commercialResponseInvalid") }
            let type: UInt8, payload: Data
            switch value {
            case .integer(let number):
                type = 2
                var bits = UInt64(bitPattern: number), bytes = Data()
                while bits != 0 { bytes.append(UInt8(truncatingIfNeeded: bits)); bits >>= 8 }
                payload = bytes
            case .string(let text): type = 3; payload = Data(text.utf8)
            case .binary(let data): type = 4; payload = data
            case .map(let map): type = 1; payload = try self.fields(map.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            case .list(let list): type = 5; payload = try self.fields(list.map { ("", $0) })
            }
            guard payload.count <= maximumMessage else { throw AppError.message("commercialResponseInvalid") }
            result.append(type); result.append(UInt8(key.count)); result.append(length(payload.count))
            result.append(key); result.append(payload)
        }
        return result
    }

    static func decode(_ data: Data) throws -> [String: HTSPValue] {
        guard data.count <= maximumMessage else { throw AppError.message("commercialResponseInvalid") }
        return try map(parse(Array(data), depth: 0))
    }

    private static func map(_ fields: [(String, HTSPValue)]) throws -> [String: HTSPValue] {
        var result = [String: HTSPValue]()
        for (name, value) in fields {
            guard !name.isEmpty, result[name] == nil else { throw AppError.message("commercialResponseInvalid") }
            result[name] = value
        }
        return result
    }

    private static func parse(_ bytes: [UInt8], depth: Int) throws -> [(String, HTSPValue)] {
        guard depth <= 12 else { throw AppError.message("commercialResponseInvalid") }
        var offset = 0, result = [(String, HTSPValue)]()
        while offset < bytes.count {
            guard bytes.count - offset >= 6, result.count < 20_000 else { throw AppError.message("commercialResponseInvalid") }
            let type = bytes[offset], nameLength = Int(bytes[offset + 1])
            let count = bytes[(offset + 2)..<(offset + 6)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 6
            guard count <= maximumMessage, nameLength <= bytes.count - offset,
                  count <= bytes.count - offset - nameLength,
                  let name = String(bytes: bytes[offset..<(offset + nameLength)], encoding: .utf8) else {
                throw AppError.message("commercialResponseInvalid")
            }
            offset += nameLength
            let payload = Array(bytes[offset..<(offset + count)])
            offset += count
            let value: HTSPValue
            switch type {
            case 1: value = .map(try map(parse(payload, depth: depth + 1)))
            case 2:
                guard count <= 8 else { throw AppError.message("commercialResponseInvalid") }
                let bits = payload.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
                value = .integer(Int64(bitPattern: bits))
            case 3:
                guard let text = String(bytes: payload, encoding: .utf8) else { throw AppError.message("commercialResponseInvalid") }
                value = .string(text)
            case 4, 6, 8: value = .binary(Data(payload))
            case 5: value = .list(try parse(payload, depth: depth + 1).map(\.1))
            case 7:
                guard count <= 1 else { throw AppError.message("commercialResponseInvalid") }
                value = .integer(payload.first == 1 ? 1 : 0)
            default: throw AppError.message("commercialResponseInvalid")
            }
            result.append((name, value))
        }
        return result
    }
}

/// One short metadata connection; recording playback continues over HTTP/VLC.
final class HTSPSocket: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "Tunerfenster.commercials")
    private var receivedBytes = 0

    init(endpoint: CommercialEndpoint) {
        connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.port)!, using: .tcp)
    }

    func start() { connection.start(queue: queue) }
    func cancel() { connection.cancel() }

    func send(_ message: [String: HTSPValue]) async throws {
        let data = try HTSPCodec.encode(message)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func receive(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let part: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: AppError.message("commercialConnectionFailed")) }
                }
            }
            result.append(part)
        }
        return result
    }

    func message() async throws -> [String: HTSPValue] {
        let header = try await receive(4)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length <= HTSPCodec.maximumMessage, receivedBytes + length <= 32_000_000 else {
            throw AppError.message("commercialResponseInvalid")
        }
        receivedBytes += length
        return try HTSPCodec.decode(try await receive(length))
    }
}

enum HTSPCommercials {
    static func digest(password: String, challenge: Data) -> Data {
        // SHA-1 challenge/response is specified by HTSP; the password is not sent.
        Data(Insecure.SHA1.hash(data: Data(password.utf8) + challenge))
    }

    static func recordingID(_ recording: SavedRecording, metadata: [[String: HTSPValue]]) throws -> Int64 {
        let exact = metadata.filter { $0["idStr"]?.string?.lowercased() == recording.id.lowercased() }
        if exact.count == 1, let id = exact.first?["id"]?.integer, (0...Int64(UInt32.max)).contains(id) { return id }
        // TVHeadend 4.2 exposes only its native-endian short UUID. Confirm it
        // against the recording's dates and channel, rather than guessing.
        guard RecordingProgressOutbox.validUUID(recording.id) else { throw AppError.message("commercialRecordingMissing") }
        let hex = Array(recording.id.prefix(8)), bytes = stride(from: 0, to: 8, by: 2).compactMap {
            UInt32(String(hex[$0...($0 + 1)]), radix: 16)
        }
        let big = bytes.reduce(UInt32(0)) { ($0 << 8) | $1 } & 0x7fff_ffff
        let little = bytes.reversed().reduce(UInt32(0)) { ($0 << 8) | $1 } & 0x7fff_ffff
        let matches = metadata.filter { item in
            guard item["idStr"] == nil, let id = item["id"]?.integer, [Int64(big), Int64(little)].contains(id),
                  let start = recording.start, let stop = recording.stop,
                  item["start"]?.integer.map({ Double($0) == start }) == true,
                  item["stop"]?.integer.map({ Double($0) == stop }) == true,
                  let channel = recording.channelname, !channel.isEmpty, item["channelName"]?.string == channel else { return false }
            return true
        }
        guard matches.count == 1, let id = matches.first?["id"]?.integer else { throw AppError.message("commercialRecordingMissing") }
        return id
    }

    static func breaks(_ response: [String: HTSPValue]) throws -> [CommercialBreak] {
        guard let value = response["cutpoints"] else { return [] }
        guard case .list(let points) = value, points.count <= 5000 else { throw AppError.message("commercialResponseInvalid") }
        return CommercialBreak.normalized(points.compactMap { value in
            guard case .map(let point) = value, let start = point["start"]?.integer, let end = point["end"]?.integer,
                  let type = point["type"]?.integer, type == 0 || type == 3, start >= 0, end > start,
                  end <= Int64(UInt32.max) else { return nil }
            return CommercialBreak(start: Double(start) / 1000, end: Double(end) / 1000)
        })
    }

    static func fileDuration(_ metadata: [String: HTSPValue]) -> Double? {
        // The HTTP DVR "duration" is scheduled time. Comskip uses the file clock.
        // Only a single file gives these markers an unambiguous file clock.
        guard case .list(let files) = metadata["files"], files.count == 1,
              case .map(let file) = files[0], let start = file["start"]?.integer,
              let stop = file["stop"]?.integer, start > 0, stop > start,
              stop - start <= Int64(UInt32.max) / 1000 else { return nil }
        return Double(stop) - Double(start)
    }

    static func load(recording: SavedRecording, connection: Connection, endpoint: CommercialEndpoint) async throws -> RecordingCommercialData {
        try await withMetadata(connection: connection, endpoint: endpoint) { socket, metadata in
            let id = try recordingID(recording, metadata: metadata)
            try await socket.send(["method": .string("getDvrCutpoints"), "id": .integer(id), "seq": .integer(4)])
            for _ in 0..<20_000 {
                try Task.checkCancellation()
                let response = try await socket.message()
                guard response["seq"]?.integer == 4 else { continue }
                guard response["error"] == nil, response["noaccess"]?.integer != 1 else { throw AppError.message("commercialAccessDenied") }
                let entry = metadata.first { $0["id"]?.integer == id } ?? [:]
                return RecordingCommercialData(breaks: try breaks(response), fileDuration: fileDuration(entry))
            }
            throw AppError.message("commercialResponseInvalid")
        }
    }

    static func fileDurations(recordings: [SavedRecording], metadata: [[String: HTSPValue]]) -> [String: Double] {
        let entries = Dictionary(grouping: metadata, by: { $0["id"]?.integer })
        var result = [String: Double]()
        for recording in recordings {
            guard let id = try? recordingID(recording, metadata: metadata),
                  let matches = entries[id], matches.count == 1,
                  let duration = fileDuration(matches[0]) else { continue }
            result[recording.id] = duration
        }
        return result
    }

    static func loadFileDurations(recordings: [SavedRecording], connection: Connection, endpoint: CommercialEndpoint) async throws -> [String: Double] {
        try await withMetadata(connection: connection, endpoint: endpoint) { _, metadata in
            fileDurations(recordings: recordings, metadata: metadata)
        }
    }

    private static func withMetadata<T>(connection: Connection, endpoint: CommercialEndpoint,
                                        perform: (HTSPSocket, [[String: HTSPValue]]) async throws -> T) async throws -> T {
        let socket = HTSPSocket(endpoint: endpoint)
        let timeout = DispatchWorkItem { socket.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: timeout)
        defer { timeout.cancel(); socket.cancel() }
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                socket.start()
                try await socket.send(["method": .string("hello"), "htspversion": .integer(44),
                                       "clientname": .string("Tunerfenster"), "seq": .integer(1)])
                let hello = try await socket.message()
                guard hello["seq"]?.integer == 1, (hello["htspversion"]?.integer ?? 0) >= 12 else {
                    throw AppError.message("commercialResponseInvalid")
                }
                if connection.auth != "none" {
                    guard case .binary(let challenge) = hello["challenge"], challenge.count == 32 else {
                        throw AppError.message("commercialResponseInvalid")
                    }
                    try await socket.send(["method": .string("authenticate"), "username": .string(connection.username),
                                           "digest": .binary(digest(password: connection.password, challenge: challenge)), "seq": .integer(2)])
                    let auth = try await socket.message()
                    guard auth["seq"]?.integer == 2, auth["noaccess"]?.integer != 1,
                          auth["error"] == nil, auth["dvr"]?.integer != 0 else { throw AppError.message("commercialAccessDenied") }
                }
                try await socket.send(["method": .string("enableAsyncMetadata"), "epg": .integer(0), "seq": .integer(3)])
                var metadata = [[String: HTSPValue]](), synced = false
                for _ in 0..<20_000 {
                    try Task.checkCancellation()
                    let message = try await socket.message()
                    if message["error"] != nil || message["noaccess"]?.integer == 1 { throw AppError.message("commercialAccessDenied") }
                    if message["method"]?.string == "dvrEntryAdd" { metadata.append(message) }
                    if message["method"]?.string == "initialSyncCompleted" { synced = true; break }
                }
                guard synced else { throw AppError.message("commercialResponseInvalid") }
                return try await perform(socket, metadata)
            } catch is CancellationError { throw CancellationError() }
            catch let error as AppError { throw error }
            catch { throw AppError.message("commercialConnectionFailed") }
        } onCancel: { socket.cancel() }
    }
}
