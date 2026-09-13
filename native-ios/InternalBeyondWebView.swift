import SwiftUI
import WebKit

@MainActor
struct InternalBeyondWebView: UIViewRepresentable {
    let startURL: URL
    let provider: IBCYCodexHostProviding

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: Self.bridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let handler = IBCYWebBridgeHandler(webView: webView, provider: provider)
        controller.add(handler, name: "ibcyHost")
        context.coordinator.handler = handler
        context.coordinator.controller = controller

        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.handler?.invalidate()
        coordinator.controller?.removeScriptMessageHandler(forName: "ibcyHost")
        coordinator.handler = nil
        coordinator.controller = nil
    }

    final class Coordinator {
        var handler: IBCYWebBridgeHandler?
        weak var controller: WKUserContentController?
    }

    private static let bridgeJavaScript = #"""
    (function () {
      'use strict';
      var pending = new Map();
      var seq = 0;

      function handler() {
        return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ibcyHost;
      }

      function nextID(prefix) {
        seq += 1;
        return String(prefix || 'ibcy') + '-' + Date.now().toString(36) + '-' + seq.toString(36);
      }

      function post(id, method, params, onEvent, timeout) {
        var target = handler();
        if (!target || typeof target.postMessage !== 'function') {
          return Promise.reject(new Error('Native host bridge is unavailable'));
        }
        return new Promise(function (resolve, reject) {
          var timer = window.setTimeout(function () {
            pending.delete(id);
            reject(new Error('Native host request timed out'));
          }, Number(timeout || 120000));
          pending.set(id, { resolve: resolve, reject: reject, onEvent: onEvent || null, timer: timer });
          target.postMessage({ id: id, method: method, params: params || {} });
        });
      }

      window.__IBCYNativeReceive = function (kind, id, payload) {
        var entry = pending.get(String(id || ''));
        if (!entry) return;
        if (kind === 'event') {
          if (entry.onEvent) entry.onEvent(payload || {});
          return;
        }
        pending.delete(String(id));
        window.clearTimeout(entry.timer);
        if (payload && payload.ok) entry.resolve(payload.result == null ? null : payload.result);
        else entry.reject(new Error(payload && payload.error ? String(payload.error) : 'Native host request failed'));
      };

      function request(method, params, timeout) {
        return post(nextID(method), method, params || {}, null, timeout);
      }

      function chunk(id, model, text, finishReason) {
        return {
          id: id,
          object: 'chat.completion.chunk',
          created: Math.floor(Date.now() / 1000),
          model: model,
          choices: [{ index: 0, delta: text ? { content: text } : {}, finish_reason: finishReason || null }]
        };
      }

      function chat(body) {
        var nativeID = nextID('chat');
        var responseID = 'chatcmpl-' + nativeID;
        var model = String(body && body.model || '');
        var encoder = new TextEncoder();
        var stream = new ReadableStream({
          start: function (controller) {
            var closed = false;
            function push(value) { if (!closed) controller.enqueue(encoder.encode(value)); }
            function finish() {
              if (closed) return;
              push('data: ' + JSON.stringify(chunk(responseID, model, '', 'stop')) + '\n\n');
              push('data: [DONE]\n\n');
              closed = true;
              controller.close();
            }
            function fail(error) {
              if (closed) return;
              closed = true;
              controller.error(error instanceof Error ? error : new Error(String(error)));
            }

            post(nativeID, 'chat', { request: body }, function (event) {
              var type = String(event && event.type || '');
              var data = event && event.data;
              if (type === 'delta') {
                var text = data && data.delta ? String(data.delta) : '';
                if (text) push('data: ' + JSON.stringify(chunk(responseID, model, text, null)) + '\n\n');
              } else if (type === 'completed') {
                if (data && data.model) model = String(data.model);
                finish();
              } else if (type === 'error') {
                fail(new Error(data && data.message ? String(data.message) : 'Native chat failed'));
              }
            }, 300000).then(function (result) {
              if (result && result.model) model = String(result.model);
              finish();
            }).catch(fail);
          },
          cancel: function () {
            var target = handler();
            if (target && typeof target.postMessage === 'function') {
              target.postMessage({ id: nextID('cancel'), method: 'cancel', params: { request_id: nativeID } });
            }
          }
        });
        return Promise.resolve(new Response(stream, {
          status: 200,
          headers: { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache' }
        }));
      }

      window.IBCY_PREFERRED_TRANSPORT = 'host';
      window.IBCYHostTransport = {
        available: function () { return !!handler(); },
        status: function () { return request('status'); },
        login: function () { return request('login', {}, 300000); },
        logout: function () { return request('logout'); },
        models: function () { return request('models'); },
        chat: chat,
        cancel: function (requestID) { return request('cancel', { request_id: String(requestID || '') }); }
      };
    }());
    """#
}

@MainActor
final class IBCYWebBridgeHandler: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private let provider: IBCYCodexHostProviding
    private var tasks: [String: Task<Void, Never>] = [:]

    init(webView: WKWebView, provider: IBCYCodexHostProviding) {
        self.webView = webView
        self.provider = provider
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ibcyHost",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let method = body["method"] as? String else { return }

        let params = Self.decodeObject(body["params"]) ?? [:]
        if method == "cancel" {
            let targetID: String
            if case .string(let value)? = params["request_id"] { targetID = value } else { targetID = id }
            tasks[targetID]?.cancel()
            Task { await provider.cancel(requestID: targetID) }
            sendReply(id: id, result: .object(["cancelled": .bool(true)]))
            return
        }

        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { tasks[id] = nil }
            do {
                let result: IBCYJSONValue?
                switch method {
                case "status": result = try await provider.status()
                case "login": result = try await provider.login()
                case "logout":
                    try await provider.logout()
                    result = .object(["logged_in": .bool(false)])
                case "models": result = try await provider.models()
                case "chat":
                    guard let request = params["request"] else { throw ProviderError.protocolViolation }
                    result = try await provider.chat(request: request, requestID: id) { [weak self] event in
                        Task { @MainActor in self?.sendEvent(event) }
                    }
                default:
                    throw ProviderError.protocolViolation
                }
                sendReply(id: id, result: result)
            } catch is CancellationError {
                sendFailure(id: id, message: "Cancelled")
            } catch {
                sendFailure(id: id, message: error.localizedDescription)
            }
        }
    }

    func invalidate() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func sendReply(id: String, result: IBCYJSONValue?) {
        send(kind: "reply", id: id, payload: ["ok": true, "result": Self.any(result ?? .null)])
    }

    private func sendFailure(id: String, message: String) {
        send(kind: "reply", id: id, payload: ["ok": false, "error": message])
    }

    private func sendEvent(_ event: IBCYHostEvent) {
        send(kind: "event", id: event.requestID, payload: Self.any(.object([
            "type": .string(event.type),
            "data": event.data ?? .null
        ])))
    }

    private func send(kind: String, id: String, payload: Any) {
        guard let webView else { return }
        webView.callAsyncJavaScript(
            "window.__IBCYNativeReceive(kind, id, payload);",
            arguments: ["kind": kind, "id": id, "payload": payload],
            in: nil,
            in: .page,
            completionHandler: { _ in }
        )
    }

    private static func decodeObject(_ value: Any?) -> [String: IBCYJSONValue]? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode([String: IBCYJSONValue].self, from: data) else {
            return value == nil ? [:] : nil
        }
        return decoded
    }

    private static func any(_ value: IBCYJSONValue) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return object
    }
}
