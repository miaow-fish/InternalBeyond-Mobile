import Foundation

struct CodexSessionSnapshot: Sendable {
    let accountID: String
    let expiresAt: Date?
}

protocol CodexAuthCoordinating: AnyObject {
    func statusPayload() async throws -> JSONValue
    func login() async throws -> JSONValue
    func logout() async throws
    func ensureValidSession() async throws -> CodexSessionSnapshot
}

/// Transport boundary for the already-validated Codex HTTP implementation.
/// Keeping it separate means OAuth details, credentials and service URLs never
/// need to cross into the WebKit bridge or InternalBeyond JavaScript.
protocol CodexTransporting: AnyObject {
    func listModels() async throws -> JSONValue
    func streamChat(
        request: JSONValue,
        requestID: String,
        emit: @escaping @Sendable (CodexBridgeEvent) -> Void
    ) async throws -> JSONValue
    func cancel(requestID: String) async
}

final class NativeCodexProvider: CodexNativeProviding, @unchecked Sendable {
    private let auth: CodexAuthCoordinating
    private let transport: CodexTransporting

    init(auth: CodexAuthCoordinating, transport: CodexTransporting) {
        self.auth = auth
        self.transport = transport
    }

    func status() async throws -> JSONValue {
        try await auth.statusPayload()
    }

    func login() async throws -> JSONValue {
        try await auth.login()
    }

    func logout() async throws {
        try await auth.logout()
    }

    func models() async throws -> JSONValue {
        _ = try await auth.ensureValidSession()
        return try await transport.listModels()
    }

    func chat(
        params: [String: JSONValue],
        emit: @escaping @Sendable (CodexBridgeEvent) -> Void
    ) async throws -> JSONValue {
        _ = try await auth.ensureValidSession()
        guard let request = params["request"] else {
            throw NSError(
                domain: "InternalBeyond.Codex",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Missing chat request body"]
            )
        }
        let requestID = UUID().uuidString.lowercased()
        return try await transport.streamChat(request: request, requestID: requestID, emit: emit)
    }

    func cancel(requestID: String) async {
        await transport.cancel(requestID: requestID)
    }
}
