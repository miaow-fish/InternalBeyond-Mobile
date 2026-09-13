import Foundation
import WebKit

/// Own one instance per WKWebView. The native provider contains the actual
/// authentication, Keychain and Codex transport implementation.
@MainActor
final class CodexWebBridgeHandler: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private let provider: CodexNativeProviding
    private var tasks: [String: Task<Void, Never>] = [:]

    init(webView: WKWebView, provider: CodexNativeProviding) {
        self.webView = webView
        self.provider = provider
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ibCodexBridge",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let methodRaw = body["method"] as? String,
              let method = CodexBridgeMethod(rawValue: methodRaw) else {
            return
        }

        let params = Self.jsonObject(body["params"]) ?? [:]
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks[id] = nil }
            do {
                let result: JSONValue?
                switch method {
                case .status:
                    result = try await provider.status()
                case .login:
                    result = try await provider.login()
                case .logout:
                    try await provider.logout()
                    result = .object(["logged_in": .bool(false)])
                case .models:
                    result = try await provider.models()
                case .chat:
                    result = try await provider.chat(params: params) { [weak self] event in
                        Task { @MainActor in self?.send(event: event) }
                    }
                case .cancel:
                    let requestID: String
                    if case .string(let value)? = params["request_id"] { requestID = value }
                    else { requestID = id }
                    await provider.cancel(requestID: requestID)
                    result = .object(["cancelled": .bool(true)])
                }
                send(reply: CodexBridgeReply(id: id, ok: true, result: result, error: nil))
            } catch {
                send(reply: CodexBridgeReply(id: id, ok: false, result: nil, error: error.localizedDescription))
            }
        }
    }

    func invalidate() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func send(reply: CodexBridgeReply) {
        guard let object = Self.dictionary(reply) else { return }
        callJavaScript(function: "window.IBCodexBridge&&window.IBCodexBridge._resolve", arguments: [reply.id, object])
    }

    private func send(event: CodexBridgeEvent) {
        guard let object = Self.dictionary(event) else { return }
        callJavaScript(function: "window.IBCodexBridge&&window.IBCodexBridge._event", arguments: [event.id, object])
    }

    private func callJavaScript(function: String, arguments: [Any]) {
        guard let webView else { return }
        if #available(iOS 14.0, *) {
            webView.callAsyncJavaScript(
                "return \(function)(id, payload);",
                arguments: ["id": arguments[0], "payload": arguments[1]],
                in: nil,
                in: .page,
                completionHandler: { _ in }
            )
        } else if let data = try? JSONSerialization.data(withJSONObject: arguments),
                  let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("(function(a){\(function)(a[0],a[1]);})(\(json));")
        }
    }

    private static func dictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func jsonObject(_ value: Any?) -> [String: JSONValue]? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return value == nil ? [:] : nil
        }
        return decoded
    }
}
