import Foundation

final class AshoreStreamTransportAdapter: IBCYCodexTransportProviding, @unchecked Sendable {
    private let store: CredentialStoring
    private let transport: AshoreTransport
    private let modelIDs: [String]

    init(
        store: CredentialStoring = KeychainCredentialStore(),
        transport: AshoreTransport = AshoreTransport(),
        modelIDs: [String]
    ) {
        self.store = store
        self.transport = transport
        self.modelIDs = modelIDs
    }

    func models() async throws -> IBCYJSONValue {
        .array(modelIDs.map { .object(["id": .string($0)]) })
    }

    func chat(
        request: IBCYJSONValue,
        requestID: String,
        emit: @escaping @Sendable (IBCYHostEvent) -> Void
    ) async throws -> IBCYJSONValue {
        guard let credential = try store.load(), credential.isStructurallyValid else {
            throw ProviderError.authenticationRequired
        }

        let payload = try BridgeChatPayload(request)
        var usagePayload: IBCYJSONValue?

        for try await event in transport.stream(
            modelID: payload.modelID,
            credential: credential,
            instructions: payload.instructions,
            history: [],
            userText: payload.userText
        ) {
            try Task.checkCancellation()
            switch event {
            case .delta(_, let text):
                emit(IBCYHostEvent(
                    requestID: requestID,
                    type: "delta",
                    data: .object(["delta": .string(text)])
                ))
            case .usage(let usage):
                var object: [String: IBCYJSONValue] = [:]
                if let value = usage.inputTokens { object["input_tokens"] = .number(Double(value)) }
                if let value = usage.outputTokens { object["output_tokens"] = .number(Double(value)) }
                if let value = usage.totalTokens { object["total_tokens"] = .number(Double(value)) }
                if let value = usage.model { object["model"] = .string(value) }
                usagePayload = .object(object)
                emit(IBCYHostEvent(requestID: requestID, type: "usage", data: usagePayload))
            }
        }

        emit(IBCYHostEvent(
            requestID: requestID,
            type: "completed",
            data: .object(["model": .string(payload.modelID)])
        ))

        return .object([
            "model": .string(payload.modelID),
            "usage": usagePayload ?? .null
        ])
    }

    func cancel(requestID: String) async {
        // The WebKit handler owns the Task for each request and cancels that
        // task directly. AshoreTransport propagates termination to its stream.
    }
}

private struct BridgeChatPayload {
    let modelID: String
    let instructions: String
    let userText: String

    init(_ value: IBCYJSONValue) throws {
        guard case .object(let root) = value else { throw ProviderError.protocolViolation }
        guard case .string(let model)? = root["model"], !model.isEmpty else {
            throw ProviderError.protocolViolation
        }
        modelID = model

        let messages = Self.messages(from: root["messages"])
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == "user" }) else {
            throw ProviderError.protocolViolation
        }
        userText = messages[lastUserIndex].text

        var blocks: [String] = []
        if case .object(let prompt)? = root["prompt_blocks"] {
            if case .string(let identity)? = prompt["identity"], !identity.isEmpty { blocks.append(identity) }
            if case .string(let developer)? = prompt["developer"], !developer.isEmpty { blocks.append(developer) }
        }

        let prior = messages[..<lastUserIndex]
            .filter { !$0.text.isEmpty }
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")
        if !prior.isEmpty {
            blocks.append("Conversation context:\n" + prior)
        }
        instructions = blocks.joined(separator: "\n\n")
    }

    private static func messages(from value: IBCYJSONValue?) -> [(role: String, text: String)] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap { item in
            guard case .object(let object) = item,
                  case .string(let role)? = object["role"] else { return nil }
            let text = contentText(object["content"])
            return (role, text)
        }
    }

    private static func contentText(_ value: IBCYJSONValue?) -> String {
        if case .string(let text)? = value { return text }
        guard case .array(let parts)? = value else { return "" }
        return parts.compactMap { part in
            guard case .object(let object) = part else { return nil }
            if case .string(let text)? = object["text"] { return text }
            if case .string(let text)? = object["content"] { return text }
            return nil
        }.joined(separator: "\n")
    }
}

@MainActor
enum IBCYNativeHostFactory {
    static func make(modelIDs: [String]) -> IBCYCodexHostProviding {
        let store = KeychainCredentialStore()
        let auth = AshoreAuthSessionAdapter(store: store)
        let transport = AshoreStreamTransportAdapter(store: store, modelIDs: modelIDs)
        return AshoreCodexHostAdapter(auth: auth, transport: transport)
    }
}
