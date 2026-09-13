import Foundation

/// Transport-facing adapter boundary for the already-validated Ashore network
/// implementation. The concrete type should wrap the existing AshoreTransport
/// without moving credentials into the web layer.
protocol IBCYCodexTransportProviding: AnyObject {
    func models() async throws -> IBCYJSONValue
    func chat(
        request: IBCYJSONValue,
        requestID: String,
        emit: @escaping @Sendable (IBCYHostEvent) -> Void
    ) async throws -> IBCYJSONValue
    func cancel(requestID: String) async
}

/// Small coordinator that preserves the validated credential lifecycle:
/// login persists a CredentialEnvelope, authenticated operations obtain a
/// fresh credential first, and logout clears the native credential store.
final class AshoreCodexHostAdapter: IBCYCodexHostProviding, @unchecked Sendable {
    private let auth: IBCYAuthSessionProviding
    private let transport: IBCYCodexTransportProviding

    init(auth: IBCYAuthSessionProviding, transport: IBCYCodexTransportProviding) {
        self.auth = auth
        self.transport = transport
    }

    func status() async throws -> IBCYJSONValue {
        try await auth.status()
    }

    func login() async throws -> IBCYJSONValue {
        try await auth.login()
    }

    func logout() async throws {
        try await auth.logout()
    }

    func models() async throws -> IBCYJSONValue {
        try await auth.ensureFreshCredential()
        return try await transport.models()
    }

    func chat(
        request: IBCYJSONValue,
        requestID: String,
        emit: @escaping @Sendable (IBCYHostEvent) -> Void
    ) async throws -> IBCYJSONValue {
        try await auth.ensureFreshCredential()
        return try await transport.chat(request: request, requestID: requestID, emit: emit)
    }

    func cancel(requestID: String) async {
        await transport.cancel(requestID: requestID)
    }
}
