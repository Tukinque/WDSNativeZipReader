
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {

    @EnvironmentObject var model: LibraryModel
    @State private var picker = false
    @State private var webStatus = "웹페이지 대기 중..."
    @State private var webError = ""

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

                VStack(spacing: 4) {

                    Text(webStatus)
                        .font(.caption)
                        .foregroundStyle(.blue)

                    if !webError.isEmpty {
                        ScrollView {
                            Text(webError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 130)
                        .padding(8)
                    }
                }
                .padding(.horizontal)

                WDSWebView(
                    url: url,
                    status: $webStatus,
                    error: $webError
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

// MARK: - WKWebView

struct WDSWebView: UIViewRepresentable {

    let url: URL
    @Binding var status: String
    @Binding var error: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let contentController = WKUserContentController()

        let diagnosticScript = """
        (function() {
            function report(message) {
                window.webkit.messageHandlers.wdsDiagnostics.postMessage(
                    String(message)
                );
            }

            window.addEventListener('error', function(event) {
                report(
                    'JS 오류: ' +
                    event.message +
                    ' / ' +
                    event.filename +
                    ':' +
                    event.lineno
                );
            });

            window.addEventListener(
                'unhandledrejection',
                function(event) {
                    report(
                        'Promise 오류: ' +
                        String(event.reason)
                    );
                }
            );
        })();
        """

        contentController.addUserScript(
            WKUserScript(
                source: diagnosticScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        contentController.add(
            context.coordinator,
            name: "wdsDiagnostics"
        )

        configuration.userContentController = contentController

        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never

        view.load(URLRequest(url: url))

        return view
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        context.coordinator.parent = self
    }

    // MARK: - 진단 처리

    final class Coordinator: NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler {

        var parent: WDSWebView

        init(_ parent: WDSWebView) {
            self.parent = parent
        }

        private func updateStatus(_ message: String) {
            DispatchQueue.main.async {
                self.parent.status = message
            }
        }

        private func updateError(_ message: String) {
            DispatchQueue.main.async {
                self.parent.error = message
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            updateStatus("웹페이지 연결 시도 중...")
        }

        func webView(
            _ webView: WKWebView,
            didReceive response: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {

            if let http = response.response as? HTTPURLResponse {

                let code = http.statusCode

                updateStatus("HTTP 응답 코드: \(code)")

                if code >= 400 {
                    updateError(
                        "HTTP 오류 \(code): \(http.url?.absoluteString ?? "")"
                    )
                }
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            updateStatus("HTML 로딩 완료")

            webView.evaluateJavaScript(
                "document.title"
            ) { result, error in

                if let error = error {
                    self.updateError(
                        "JavaScript 확인 오류: \(error.localizedDescription)"
                    )
                } else {
                    self.updateStatus(
                        "HTML 로딩 완료 / 제목: \(result ?? "")"
                    )
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            updateStatus("웹페이지 연결 실패")
            updateError(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            updateStatus("웹페이지 로딩 실패")
            updateError(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            updateStatus("웹 콘텐츠 프로세스 종료")
            updateError(
                "WKWebView 프로세스가 종료되었습니다. 메모리 부족이나 웹 콘텐츠 오류일 수 있습니다."
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            updateError(
                String(describing: message.body)
            )
        }
    }
}
