import SwiftUI
import WebKit
import CoreLocation

struct WebView: UIViewRepresentable {

    let urlString: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(Self.nativeLocationScript)
        configuration.userContentController.add(context.coordinator, name: "masaryLocation")

        let webView = WKWebView(frame: .zero, configuration: configuration)

        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = URL(string: urlString) {
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )
            WKWebsiteDataStore.default().removeData(
                ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
                modifiedSince: .distantPast
            ) {
                webView.load(request)
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "masaryLocation")
        coordinator.stopLocationUpdates()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage)
    }

    static let nativeLocationScript = WKUserScript(
        source: """
        (() => {
          if (window.__masaryNativeGeoInstalled) return;
          window.__masaryNativeGeoInstalled = true;

          let nextId = 1;
          const successCallbacks = {};
          const errorCallbacks = {};

          function post(type, id, options) {
            window.webkit.messageHandlers.masaryLocation.postMessage({
              type,
              id,
              options: options || {}
            });
          }

          window.__masaryNativeGeoSuccess = function(id, coords) {
            const callback = successCallbacks[id];
            if (!callback) return;

            callback({
              coords: {
                latitude: coords.latitude,
                longitude: coords.longitude,
                accuracy: coords.accuracy,
                altitude: coords.altitude,
                altitudeAccuracy: coords.altitudeAccuracy,
                heading: coords.heading,
                speed: coords.speed
              },
              timestamp: coords.timestamp || Date.now()
            });

            if (!String(id).startsWith("watch-")) {
              delete successCallbacks[id];
              delete errorCallbacks[id];
            }
          };

          window.__masaryNativeGeoError = function(id, message, code) {
            const callback = errorCallbacks[id];
            if (callback) {
              callback({
                code: code || 2,
                message: message || "Location unavailable"
              });
            }

            if (!String(id).startsWith("watch-")) {
              delete successCallbacks[id];
              delete errorCallbacks[id];
            }
          };

          const nativeGeo = {
            getCurrentPosition(success, error, options) {
              const id = "once-" + nextId++;
              successCallbacks[id] = success;
              errorCallbacks[id] = error;
              post("getCurrentPosition", id, options);
            },
            watchPosition(success, error, options) {
              const id = "watch-" + nextId++;
              successCallbacks[id] = success;
              errorCallbacks[id] = error;
              post("watchPosition", id, options);
              return id;
            },
            clearWatch(id) {
              delete successCallbacks[id];
              delete errorCallbacks[id];
              post("clearWatch", id);
            }
          };

          Object.defineProperty(navigator, "geolocation", {
            value: nativeGeo,
            configurable: true
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, CLLocationManagerDelegate {
        @Binding private var isLoading: Bool
        @Binding private var errorMessage: String?
        weak var webView: WKWebView?

        private let locationManager = CLLocationManager()
        private var pendingSingleRequests = Set<String>()
        private var activeWatchRequests = Set<String>()

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            _isLoading = isLoading
            _errorMessage = errorMessage
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 10
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            show(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            show(error)
        }

        private func show(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }

            isLoading = false
            errorMessage = error.localizedDescription
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                message.name == "masaryLocation",
                let body = message.body as? [String: Any],
                let type = body["type"] as? String,
                let id = body["id"] as? String
            else {
                return
            }

            switch type {
            case "getCurrentPosition":
                pendingSingleRequests.insert(id)
                requestLocation()
            case "watchPosition":
                activeWatchRequests.insert(id)
                requestLocation()
                locationManager.startUpdatingLocation()
            case "clearWatch":
                activeWatchRequests.remove(id)
                if activeWatchRequests.isEmpty {
                    locationManager.stopUpdatingLocation()
                }
            default:
                break
            }
        }

        private func requestLocation() {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            case .denied, .restricted:
                sendLocationError("لم يتم السماح للتطبيق باستخدام الموقع.", code: 1)
            @unknown default:
                sendLocationError("تعذر تحديد صلاحية الموقع.", code: 2)
            }
        }

        func stopLocationUpdates() {
            pendingSingleRequests.removeAll()
            activeWatchRequests.removeAll()
            locationManager.stopUpdatingLocation()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
                if !activeWatchRequests.isEmpty {
                    manager.startUpdatingLocation()
                }
            case .denied, .restricted:
                sendLocationError("لم يتم السماح للتطبيق باستخدام الموقع.", code: 1)
            default:
                break
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else {
                return
            }

            let ids = pendingSingleRequests.union(activeWatchRequests)
            pendingSingleRequests.removeAll()
            sendLocation(location, to: ids)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            sendLocationError(error.localizedDescription, code: 2)
        }

        private func sendLocation(_ location: CLLocation, to ids: Set<String>) {
            guard !ids.isEmpty else {
                return
            }

            let coords: [String: Any?] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "altitude": location.verticalAccuracy >= 0 ? location.altitude : nil,
                "altitudeAccuracy": location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
                "heading": location.course >= 0 ? location.course : nil,
                "speed": location.speed >= 0 ? location.speed : nil,
                "timestamp": location.timestamp.timeIntervalSince1970 * 1000
            ]

            guard
                let jsonData = try? JSONSerialization.data(withJSONObject: coords.compactMapValues { $0 }),
                let json = String(data: jsonData, encoding: .utf8)
            else {
                return
            }

            ids.forEach { id in
                evaluate("__masaryNativeGeoSuccess('\(escape(id))', \(json));")
            }
        }

        private func sendLocationError(_ message: String, code: Int) {
            let ids = pendingSingleRequests.union(activeWatchRequests)
            pendingSingleRequests.removeAll()

            ids.forEach { id in
                evaluate("__masaryNativeGeoError('\(escape(id))', '\(escape(message))', \(code));")
            }
        }

        private func evaluate(_ script: String) {
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(script)
            }
        }

        private func escape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }
    }
}

struct RootView: View {

    private let urlString = "https://masary.online?v=22"
    @State private var reloadToken = UUID()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {

        ZStack {
            WebView(urlString: urlString, isLoading: $isLoading, errorMessage: $errorMessage)
                .id(reloadToken)

            if isLoading {
                ProgressView("جاري تحميل مساري...")
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("تعذر فتح مساري")
                        .font(.headline)

                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("إعادة المحاولة") {
                        isLoading = true
                        self.errorMessage = nil
                        reloadToken = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(radius: 18)
                .padding()
            }
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    RootView()
}
