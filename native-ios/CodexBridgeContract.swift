import Foundation

/// Small JSON value used by the WebKit bridge. Keeping the bridge JSON-shaped
/// avoids coupling the native provider to InternalBeyond's internal models.
enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct CodexBridgeRequest: Codable, Sendable {
    let id: String
    let method: CodexBridgeMethod
    let params: [String: JSONValue]?
}

struct CodexBridgeReply: Codable, Sendable {
    let id: String
    let ok: Bool
    let result: JSONValue?
    let error: String?
}

/// Streaming notifications share the request id so the web layer can route
/// multiple simultaneous conversations safely.
struct CodexBridgeEvent: Codable, Sendable {
    let id: String
    let type: String
    let data: JSONValue?
}

enum CodexBridgeMethod: String, Codable, Sendable {
    case status
    case login
    case logout
    case models
    case chat
    case cancel
}

/// Native implementation boundary. OAuth/secure storage and Codex networking
/// live behind this protocol; WebKit never receives refresh credentials.
protocol CodexNativeProviding: AnyObject {
    func status() async throws -> JSONValue
    func login() async throws -> JSONValue
    func logout() async throws
    func models() async throws -> JSONValue
    func chat(
        params: [String: JSONValue],
        emit: @escaping @Sendable (CodexBridgeEvent) -> Void
    ) async throws -> JSONValue
    func cancel(requestID: String) async
}
