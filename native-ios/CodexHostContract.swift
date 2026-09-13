import Foundation

/// JSON-shaped value used at the web/native boundary so the host does not
/// depend on InternalBeyond's browser-side model types.
enum IBCYJSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: IBCYJSONValue])
    case array([IBCYJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: IBCYJSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([IBCYJSONValue].self) { self = .array(value); return }
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

struct IBCYHostEvent: Codable, Sendable {
    let requestID: String
    let type: String
    let data: IBCYJSONValue?
}

/// Implement this protocol by adapting the already-validated Ashore auth and
/// transport layer. OpenAI credentials remain owned by the native layer.
protocol IBCYCodexHostProviding: AnyObject {
    func status() async throws -> IBCYJSONValue
    func login() async throws -> IBCYJSONValue
    func logout() async throws
    func models() async throws -> IBCYJSONValue
    func chat(
        request: IBCYJSONValue,
        requestID: String,
        emit: @escaping @Sendable (IBCYHostEvent) -> Void
    ) async throws -> IBCYJSONValue
    func cancel(requestID: String) async
}

/// Authentication adapter boundary. The concrete implementation should call
/// AshoreAuthSession.persist() after login and ModelProvider.freshCredential()
/// before authenticated model/chat operations.
protocol IBCYAuthSessionProviding: AnyObject {
    func status() async throws -> IBCYJSONValue
    func login() async throws -> IBCYJSONValue
    func logout() async throws
    func ensureFreshCredential() async throws
}
