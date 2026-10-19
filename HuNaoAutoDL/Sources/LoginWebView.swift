import SwiftUI
import WebKit

enum LoginWebSession {
    static func clear() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            URLCache.shared.removeAllCachedResponses()
        }
    }
}

struct LoginWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    let onTokenCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 每次登录都必须从干净会话开始，否则退出后 AutoDL 的 Cookie
        // 会把登录页直接重定向回上一次的账户。
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContentController = WKUserContentController()
        let proxy = WeakScriptMessageHandler(delegate: context.coordinator)
        context.coordinator.messageProxy = proxy
        userContentController.add(proxy, name: "autodlToken")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.captureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.08, alpha: 1)
        context.coordinator.webView = webView

        if let url = URL(string: "https://www.autodl.com/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "autodlToken")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var parent: LoginWebView
        weak var webView: WKWebView?
        var messageProxy: WeakScriptMessageHandler?

        init(parent: LoginWebView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "autodlToken" else { return }
            let token: String?
            if let value = message.body as? String {
                token = value
            } else if let dict = message.body as? [String: Any] {
                token = dict["token"] as? String
            } else {
                token = nil
            }
            guard let token else { return }
            let cleaned = token
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard cleaned.count >= 12,
                  !cleaned.contains(" "),
                  !cleaned.hasPrefix("{")
            else { return }
            parent.onTokenCaptured(cleaned)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            parent.loadError = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }

    final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var delegate: WKScriptMessageHandler?

        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    private static let captureScript = """
    (function() {
      if (window.__hunaoTokenBridge) { return; }
      window.__hunaoTokenBridge = true;

      function postToken(raw) {
        try {
          if (!raw || typeof raw !== 'string') { return; }
          var token = raw.trim().replace(/^["']|["']$/g, '');
          if (token.length < 12 || token.indexOf(' ') >= 0 || token.charAt(0) === '{') { return; }
          if (window.__hunaoLastToken === token) { return; }
          window.__hunaoLastToken = token;
          window.webkit.messageHandlers.autodlToken.postMessage(token);
        } catch (e) {}
      }

      function scan() {
        try {
          var path = String(window.location.pathname || '');
          if (path.indexOf('/login') === 0 || path.indexOf('/register') === 0 || path.indexOf('/forget') === 0) { return; }
          var keys = ['token', 'Token', 'access_token', 'autodl_token', 'Authorization'];
          for (var i = 0; i < keys.length; i++) {
            var value = window.localStorage.getItem(keys[i]);
            if (value) { postToken(value); }
          }
        } catch (e) {}
      }

      try {
        var originalFetch = window.fetch;
        if (originalFetch) {
          window.fetch = function() {
            var args = arguments;
            return originalFetch.apply(this, args).then(function(response) {
              try {
                var url = String((args[0] && args[0].url) || args[0] || '');
                if (url.indexOf('/api/v1/passport') >= 0) {
                  response.clone().json().then(function(data) {
                    if (data && data.data && data.data.token) {
                      postToken(String(data.data.token));
                    }
                  }).catch(function() {});
                }
              } catch (e) {}
              return response;
            });
          };
        }
      } catch (e) {}

      try {
        var originalOpen = XMLHttpRequest.prototype.open;
        var originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__hunaoURL = String(url || '');
          return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          var xhr = this;
          if (xhr.__hunaoURL && xhr.__hunaoURL.indexOf('/api/v1/passport') >= 0) {
            xhr.addEventListener('load', function() {
              try {
                var data = JSON.parse(xhr.responseText);
                if (data && data.data && data.data.token) {
                  postToken(String(data.data.token));
                }
              } catch (e) {}
            });
          }
          return originalSend.apply(this, arguments);
        };
      } catch (e) {}

      document.addEventListener('DOMContentLoaded', scan);
      window.addEventListener('load', scan);
      document.addEventListener('visibilitychange', scan);
      setInterval(scan, 1200);
      scan();
    })();
    """
}
