import SwiftUI
import WebKit

// MARK: - Root View
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            MasaryWebView()
                .ignoresSafeArea()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash
struct SplashView: View {
    @State private var scale: CGFloat = 0.75
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.04, green: 0.11, blue: 0.30),
                    Color(red: 0.08, green: 0.28, blue: 0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("🚌")
                    .font(.system(size: 86))

                Text("مساري")
                    .font(.system(size: 44, weight: .black))
                    .foregroundColor(.white)

                Text("نظام النقل المدرسي الذكي")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                scale = 1.0
                opacity = 1.0
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - WebView
struct MasaryWebView: UIViewRepresentable {
    // ← غيّر هذا الرابط بعد رفع موقعك على Firebase Hosting
    private let urlString = "https://masary-b9727.web.app"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(context.coordinator, name: "masaryBridge")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.bounces = false
        wv.scrollView.bouncesZoom = false
        wv.allowsBackForwardNavigationGestures = false

        if let url = URL(string: urlString) {
            wv.load(URLRequest(url: url))
        }
        context.coordinator.webView = wv
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var webView: WKWebView?

        // JS Bridge
        func userContentController(_ ctrl: WKUserContentController,
                                    didReceive msg: WKScriptMessage) {
            guard msg.name == "masaryBridge",
                  let body = msg.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            if action == "notification",
               let title = body["title"] as? String,
               let text = body["message"] as? String {
                sendLocalNotification(title: title, body: text)
            }
        }

        func sendLocalNotification(title: String, body: String) {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            let r = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: c,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            UNUserNotificationCenter.current().add(r)
        }

        // Allow navigation
        func webView(_ wv: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let host = action.request.url?.host ?? ""
            if action.navigationType == .linkActivated &&
               !host.contains("masary") &&
               !host.contains("firebase") &&
               !host.contains("openstreetmap") {
                if let url = action.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // JS alert()
        func webView(_ wv: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "مساري", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "حسناً", style: .default) { _ in completionHandler() })
            topVC()?.present(alert, animated: true)
        }

        // JS confirm()
        func webView(_ wv: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "مساري", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "نعم", style: .default)  { _ in completionHandler(true) })
            alert.addAction(UIAlertAction(title: "لا",  style: .cancel)   { _ in completionHandler(false) })
            topVC()?.present(alert, animated: true)
        }

        private func topVC() -> UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.rootViewController
        }
    }
}
