import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {

    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()

        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}

struct RootView: View {

    private let urlString = "https://masarapp.online"

    var body: some View {
        WebView(urlString: urlString)
            .ignoresSafeArea()
    }
}

#Preview {
    RootView()
}
