
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject var model: LibraryModel

    @State private var picker = false
    @State private var diagnostics = "웹페이지 진단 대기 중..."

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("WDS Offline")
                    .font(.headline)

                Spacer()

                Button("ZIP 가져오기") {
                    picker = true
                }
                .disabled(model.isImporting)
            }
            .padding(.horizontal)

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let url = model.webURL {
                ScrollView {
                    Text(diagnostics)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 220)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)

                WDSWebView(
                    url: url,
                    diagnostics: $diagnostics
                )
            } else {
                Spacer()

                Text("기존 리소스 ZIP을 iPad의 파일 앱에서 선택하세요.")
                    .multilineTextAlignment(.center)

                Button("리소스 ZIP 선택") {
                    picker = true
                }
                .disabled(model.isImporting)

                if model.isImporting {
                    ProgressView("ZIP 복사 중...")
                }

                Spacer()
            }
        }
        .fileImporter(
            isPresented: $picker,
            allowedContentTypes: [.zip]
        ) { result in
            switch result {
            case .success(let url):
                model.importZIP(url)

            case .failure(let error):
                model.status =
                    "선택 실패: \(error.localizedDescription)"
            }
        }
    }
}

struct WDSWebView: UIViewRepresentable {
    let url: URL
    @Binding var diagnostics: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()

        let script = """
        (function() {
            function report(value) {
                window.webkit.messageHandlers.wdsDebug.postMessage(
                    String(value)
                );
            }

            window.addEventListener("error", function(e) {
                report(
                    "JS ERROR: " + e.message +
                    " @ " + e.filename + ":" + e.lineno
                );
            }, true);

            window.addEventListener(
                "unhandledrejection",
                function(e) {
                    report("PROMISE ERROR: " + String(e.reason));
                }
            );

            const originalFetch = window.fetch;

            window.fetch = function() {
                const target = arguments[0];

                return originalFetch.apply(this, arguments)
                    .then(function(response) {
                        if (!response.ok) {
                            report(
                                "FETCH HTTP " + response.status +
                                ": " + response.url
                            );
                        }
                        return response;
                    })
                    .catch(function(error) {
                        report(
                            "FETCH FAILED: " +
                            String(target) + " / " + String(error)
                        );
                        throw error;
                    });
            };
        })();
        """

        controller.addUserScript(
            WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        controller.add(
            context.coordinator,
            name: "wdsDebug"
        )

        configuration.userContentController = controller

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler {

        var parent: WDSWebView
        private var messages: [String] = []

        init(_ parent: WDSWebView) {
            self.parent = parent
        }

        private func log(_ message: String) {
            DispatchQueue.main.async {
                self.messages.append(message)

                if self.messages.count > 35 {
                    self.messages.removeFirst()
                }

                self.parent.diagnostics =
                    self.messages.joined(separator: "\n")
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            log("START: \(webView.url?.absoluteString ?? "nil")")
        }

        func webView(
            _ webView: WKWebView,
            didReceive response: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let http = response.response as? HTTPURLResponse {
                log(
                    "MAIN HTTP: \(http.statusCode) " +
                    "\(http.url?.absoluteString ?? "")"
                )
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            log("DID FINISH")

            let js = """
            (async function() {
                const lines = [];

                lines.push("URL: " + location.href);
                lines.push("TITLE: " + document.title);
                lines.push(
                    "READY: " + document.readyState
                );

                lines.push(
                    "HTML LENGTH: " +
                    (document.documentElement?.outerHTML.length ?? 0)
                );

                lines.push(
                    "APP EXISTS: " +
                    Boolean(document.getElementById("app"))
                );

                lines.push(
                    "APP CONTENT LENGTH: " +
                    (document.getElementById("app")?.innerHTML.length ?? -1)
                );

                const paths = [
                    "/index.html",
                    "/assets/index-RGQwKqYa.js",
                    "/assets/index-D3QgVVEv.css",
                    "/data/manifest/Episode.json"
                ];

                for (const path of paths) {
                    try {
                        const response = await fetch(path, {
                            cache: "no-store"
                        });

                        const content = await response.arrayBuffer();

                        lines.push(
                            "RESOURCE " + response.status +
                            " / " + content.byteLength +
                            " bytes: " + path
                        );
                    } catch (error) {
                        lines.push(
                            "RESOURCE ERROR: " + path +
                            " / " + String(error)
                        );
                    }
                }

                return lines.join("\\n");
            })();
            """

            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    self.log(
                        "DIAGNOSTIC ERROR: " +
                        error.localizedDescription
                    )
                } else {
                    self.log(
                        String(describing: result ?? "nil")
                    )
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            log("CONNECT ERROR: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            log("LOAD ERROR: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            log("WEB CONTENT PROCESS TERMINATED")
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            log(String(describing: message.body))
        }
    }
}
