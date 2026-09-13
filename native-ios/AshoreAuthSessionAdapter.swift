import Foundation

@MainActor
final class AshoreAuthSessionAdapter: IBCYAuthSessionProviding {
    private let session: AshoreAuthSession
    private let store: CredentialStoring
    private let client: OpenAIAuthClient

    init(
        store: CredentialStoring = KeychainCredentialStore(),
        client: OpenAIAuthClient = OpenAIAuthClient()
    ) {
        self.store = store
        self.client = client
        self.session = AshoreAuthSession(client: client, store: store)
    }

    func status() async throws -> IBCYJSONValue {
        await session.restoreIfNeeded()
        return Self.payload(for: session.state, message: session.message)
    }

    func login() async throws -> IBCYJSONValue {
        await session.startBrowserAuthorization()
        switch session.state {
        case .valid:
            return Self.payload(for: session.state, message: session.message)
        case .signedOut, .browserAuthorizing, .refreshing, .reauthenticationRequired:
            throw NSError(
                domain: "InternalBeyond.AshoreAuth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: session.message ?? "Login did not complete."]
            )
        }
    }

    func logout() async throws {
        session.logout()
    }

    func ensureFreshCredential() async throws {
        _ = try await CodexProvider.freshCredential(store: store, auth: client)
        await session.restore()
    }

    private static func payload(for state: AshoreAuthSession.State, message: String?) -> IBCYJSONValue {
        var value: [String: IBCYJSONValue] = [
            "message": message.map(IBCYJSONValue.string) ?? .null
        ]

        switch state {
        case .valid(let accountID, let expiresAt):
            value["logged_in"] = .bool(true)
            value["account"] = .object([
                "id": .string(accountID),
                "type": .string("ChatGPT")
            ])
            value["expires_at"] = .number(expiresAt.timeIntervalSince1970)
            value["source"] = .string("ashore-native")
        case .browserAuthorizing:
            value["logged_in"] = .bool(false)
            value["state"] = .string("authorizing")
        case .refreshing:
            value["logged_in"] = .bool(false)
            value["state"] = .string("refreshing")
        case .reauthenticationRequired(let reason):
            value["logged_in"] = .bool(false)
            value["state"] = .string("reauthentication_required")
            value["reason"] = .string(reason)
        case .signedOut:
            value["logged_in"] = .bool(false)
            value["state"] = .string("signed_out")
        }

        return .object(value)
    }
}
