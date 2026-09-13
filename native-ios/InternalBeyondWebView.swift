import SwiftUI
import WebKit

/// Minimal native host for the existing InternalBeyond web UI.
/// Add `codex-native-bridge.js` and `codex-direct-adapter.js` to the iOS target
/// as bundled resources; the original index.html does not need to be modified.
struct InternalBeyondWebView: UIViewRepresentable {
    let startURL: URL
    let provider: CodexNativeProviding

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController

        for resource in ["codex-native-bridge", "codex-direct-adapter"] {
            if let url = Bundle.main.url(forResource: resource, withExtension: "js"),
               let source = try? String(contentsOf: url, encoding: .utf8) {
                controller.addUserScript(WKUserScript(
                    source: source,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                ))
            }
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let bridge = CodexWebBridgeHandler(webView: webView, provider: provider)
        controller.add(bridge, name: "ibCodexBridge")
        context.coordinator.bridge = bridge
        context.coordinator.controller = controller

        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.bridge?.invalidate()
        coordinator.controller?.removeScriptMessageHandler(forName: "ibCodexBridge")
        coordinator.bridge = nil
        coordinator.controller = nil
    }

    final class Coordinator {
        var bridge: CodexWebBridgeHandler?
        weak var controller: WKUserContentController?
    }
}
