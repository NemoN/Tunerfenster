import Foundation
import Security

struct Connection: Codable, Equatable, Sendable {
    var address: String
    var username: String
    var password: String
    var auth: String = "digest"

    var baseURL: URL? {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("api") else { return nil }
        return parts.url
    }

    static func initial() -> Connection {
        let arguments = ProcessInfo.processInfo.arguments
        // Read the installer's authorised configuration from a pipe to keep
        // credentials out of argv and avoid another Documents read.
        if arguments.contains("--import-connection-stdin") {
            return (try? fromImportData(FileHandle.standardInput.readDataToEndOfFile())) ??
                Connection(address: "", username: "", password: "")
        }
        if let index = arguments.firstIndex(of: "--env-file"), arguments.indices.contains(index + 1),
           let text = try? String(contentsOfFile: arguments[index + 1], encoding: .utf8) {
            return fromEnvironment(text)
        }
        if let address = UserDefaults.standard.string(forKey: "serverAddress") {
            let user = UserDefaults.standard.string(forKey: "serverUser") ?? ""
            return Connection(address: address, username: user, password: Keychain.load(account: address + "|" + user), auth: UserDefaults.standard.string(forKey: "serverAuth") ?? "digest")
        }
        if let path = Bundle.main.url(forResource: "Bootstrap", withExtension: "plist"),
           let data = try? Data(contentsOf: path),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
           let envPath = dict["EnvironmentFile"], let env = try? String(contentsOfFile: envPath, encoding: .utf8) {
            return fromEnvironment(env)
        }
        return Connection(address: "http://tvheadend.local:9981", username: "", password: "")
    }

    static func fromImportData(_ data: Data) throws -> Connection {
        let connection = try JSONDecoder().decode(Connection.self, from: data)
        guard connection.baseURL != nil, ["digest", "basic", "none"].contains(connection.auth) else {
            throw AppError.message("invalidAddressInput")
        }
        return connection
    }

    static func fromEnvironment(_ text: String) -> Connection {
        var values = [String: String]()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].replacingOccurrences(of: "export ", with: "").trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.first == "\"" && value.last == "\"" || value.first == "'" && value.last == "'") {
                value.removeFirst(); value.removeLast()
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            values[key] = value
        }
        return Connection(address: values["TVH_URL"] ?? "", username: values["TVH_USER"] ?? "", password: values["TVH_PASS"] ?? "", auth: values["TVH_AUTH"] ?? "digest")
    }

    func save() throws {
        guard baseURL != nil else { throw AppError.message("invalidAddressInput") }
        try Keychain.save(password: password, account: address + "|" + username)
        UserDefaults.standard.set(address, forKey: "serverAddress")
        UserDefaults.standard.set(username, forKey: "serverUser")
        UserDefaults.standard.set(auth, forKey: "serverAuth")
    }
}

enum Keychain {
    static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "de.local.Tunerfenster", kSecAttrAccount as String: account]
    }
    static func load(account: String) -> String {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(password: String, account: String) throws {
        let query = query(account: account)
        let attributes = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppError.message("keychainSaveFailed") }
        } else if status != errSecSuccess {
            throw AppError.message("keychainUnavailable")
        }
    }
}

enum AppError: LocalizedError {
    case message(String, [String] = [])
    indirect case context(String, AppError)
    var errorDescription: String? { description(language: L10n.language) }
    func description(language: AppLanguage) -> String {
        switch self {
        case .message(let key, let arguments): return L10n.text(key, arguments: arguments, language: language)
        case .context(let key, let error): return L10n.text(key, arguments: [error.description(language: language)], language: language)
        }
    }
    static func wrapping(_ error: Error) -> AppError {
        if let error = error as? AppError { return error }
        if error is URLError { return .message("networkUnavailable") }
        let error = error as NSError
        return .message("unexpectedError", [error.domain, String(error.code)])
    }
}

final class API: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let connection: Connection
    private var session: URLSession!

    init(connection: Connection, configuration: URLSessionConfiguration = .ephemeral) {
        self.connection = connection
        super.init()
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": previewClient]
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func close() { session.invalidateAndCancel() }

    func url(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let base = connection.baseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw AppError.message("invalidAddressSettings")
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw AppError.message("invalidAddress") }
        return url
    }

    func read<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await session.data(from: url(path: "api/" + path, query: query))
        guard let response = response as? HTTPURLResponse else { throw AppError.message("invalidResponse") }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw AppError.message("missingPermissions")
        default: throw AppError.message("httpError", [String(response.statusCode), path])
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AppError.message("responseUnreadable", [path]) }
    }

    func post<T: Decodable>(_ path: String, form: [URLQueryItem]) async throws -> T {
        var request = URLRequest(url: try url(path: "api/" + path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form
        // In a form body '+' means a space; URLComponents otherwise leaves it literal.
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppError.message("invalidResponse") }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw AppError.message("missingPermissions")
        default: throw AppError.message("httpError", [String(response.statusCode), path])
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AppError.message("responseUnreadable", [path]) }
    }

    func all<T: Decodable>(_ path: String) async throws -> [T] {
        var items = [T]()
        while true {
            let response: GridResponse<T> = try await read(path, query: [URLQueryItem(name: "start", value: String(items.count)), URLQueryItem(name: "limit", value: "1000")])
            items.append(contentsOf: response.entries)
            let total = response.total ?? response.totalCount
            if response.entries.isEmpty || total.map({ items.count >= $0 }) == true || (total == nil && response.entries.count < 1000) { return items }
            guard items.count < 100_000 else { throw AppError.message("catalogTooLarge") }
        }
    }

    func streamURL(for preview: Preview) throws -> URL {
        try url(path: preview.path, query: [URLQueryItem(name: "profile", value: "pass"), URLQueryItem(name: "weight", value: "1")])
    }

    func channelIconURL(for channel: Channel) -> URL? {
        guard let base = connection.baseURL, let reference = channel.icon_public_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty else { return nil }
        // Relative image-cache links belong to the configured TVHeadend webroot.
        // Absolute links must have that same origin before using this session.
        let root = base.appendingPathComponent("")
        guard let candidate = URL(string: reference, relativeTo: root)?.absoluteURL,
              candidate.scheme == base.scheme, candidate.host == base.host, candidate.port == base.port,
              candidate.user == nil, candidate.password == nil, candidate.fragment == nil else { return nil }
        let prefix = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = candidate.path
        guard prefix.isEmpty || path.hasPrefix("/" + prefix + "/") else { return nil }
        return candidate
    }

    func channelIconData(from url: URL) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              !data.isEmpty, data.count <= 5_000_000 else { return nil }
        // TVHeadend imagecache can omit Content-Type even for a valid PNG.
        return data
    }

    func ticketURL(for preview: Preview) async throws -> URL {
        let requestURL = try url(path: "play/ticket/" + preview.path, query: [URLQueryItem(name: "profile", value: "pass")])
        let (data, response) = try await session.data(from: requestURL)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let playlist = String(data: data, encoding: .utf8) else {
            throw AppError.message("streamNotAuthorized")
        }
        return try Self.authorizedStreamURL(playlist: playlist, expected: streamURL(for: preview))
    }

    static func authorizedStreamURL(playlist: String, expected: URL) throws -> URL {
        let lines = playlist.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
              let candidate = URL(string: line, relativeTo: expected)?.absoluteURL,
              candidate.scheme == expected.scheme, candidate.host == expected.host, candidate.port == expected.port,
              candidate.user == nil, candidate.password == nil,
              var parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              parts.queryItems?.contains(where: { $0.name == "ticket" && !($0.value ?? "").isEmpty }) == true else {
            throw AppError.message("missingTicket")
        }
        var query = (parts.queryItems ?? []).filter { !["profile", "weight"].contains($0.name) }
        query.append(URLQueryItem(name: "profile", value: "pass"))
        query.append(URLQueryItem(name: "weight", value: "1"))
        parts.queryItems = query
        guard let result = parts.url else { throw AppError.message("invalidTicket") }
        return result
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let allowed = connection.auth == "basic" ? [NSURLAuthenticationMethodHTTPBasic] : [NSURLAuthenticationMethodHTTPDigest]
        if connection.auth != "none", allowed.contains(method), challenge.previousFailureCount == 0,
           challenge.protectionSpace.host == connection.baseURL?.host {
            completionHandler(.useCredential, URLCredential(user: connection.username, password: connection.password, persistence: .forSession))
        } else if [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest].contains(method) {
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
