
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Main View

struct ContentView: View {

    @EnvironmentObject var model: LibraryModel
    @State private var picker = false

    var body: some View {
        VStack(spacing: 0) {

            if let url = model.webURL {
                WDSWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 16) {

                    Text("WDS Offline")
                        .font(.title2)
                        .bold()

                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if model.isImporting {
                        ProgressView("ZIP 복사 중...")
                    } else {
                        Button("리소스 ZIP 선택") {
                            picker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
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

// MARK: - WebView

struct WDSWebView: UIViewRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(startURL: url)
    }

    func makeUIView(context: Context) -> UIView {

        let container = UIView()
        container.backgroundColor = .white

        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences
            .javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator

        webView.scrollView
            .contentInsetAdjustmentBehavior = .never

        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white

        webView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(
                equalTo: container.topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor
            ),
            webView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            )
        ])

        context.coordinator.container = container
        context.coordinator.mainWebView = webView

        // 메인 페이지 실행
        webView.load(
            URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        )

        return container
    }

    func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {}

    static func dismantleUIView(
        _ uiView: UIView,
        coordinator: Coordinator
    ) {
        coordinator.cleanup()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
        WKUIDelegate,
        WKNavigationDelegate {

        let startURL: URL

        weak var container: UIView?
        weak var mainWebView: WKWebView?

        private var popupWebView: WKWebView?
        private var closeButton: UIButton?
        private var resetButton: UIButton?

        private var isResetting = false

        init(startURL: URL) {
            self.startURL = startURL
            super.init()
        }

        // MARK: - New Window

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            guard navigationAction.targetFrame == nil else {
                return nil
            }

            guard let container = container else {
                return nil
            }

            // 기존 팝업이 남아 있으면 먼저 정리
            removePopup()

            let popup = WKWebView(
                frame: .zero,
                configuration: configuration
            )

            popup.uiDelegate = self
            popup.navigationDelegate = self

            popup.scrollView
                .contentInsetAdjustmentBehavior = .never

            popup.isOpaque = false
            popup.backgroundColor = .white
            popup.scrollView.backgroundColor = .white

            popup.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(popup)

            NSLayoutConstraint.activate([
                popup.topAnchor.constraint(
                    equalTo: container.topAnchor
                ),
                popup.bottomAnchor.constraint(
                    equalTo: container.bottomAnchor
                ),
                popup.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor
                ),
                popup.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor
                )
            ])

            popupWebView = popup

            // 플레이어 닫기 버튼
            let button = UIButton(type: .system)

            button.setTitle("✕ 닫기", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor =
                UIColor.black.withAlphaComponent(0.75)

            button.layer.cornerRadius = 12

            button.translatesAutoresizingMaskIntoConstraints = false

            button.addTarget(
                self,
                action: #selector(closePopupTapped),
                for: .touchUpInside
            )

            container.addSubview(button)

            NSLayoutConstraint.activate([
                button.topAnchor.constraint(
                    equalTo: container.safeAreaLayoutGuide.topAnchor,
                    constant: 12
                ),
                button.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor,
                    constant: -16
                ),
                button.widthAnchor.constraint(
                    equalToConstant: 90
                ),
                button.heightAnchor.constraint(
                    equalToConstant: 44
                )
            ])

            closeButton = button
            container.bringSubviewToFront(button)

            print("WDS: 새 플레이어 생성")

            return popup
        }

        // MARK: - Close Player

        @objc private func closePopupTapped() {
            closePlayerAndReset()
        }

        private func closePlayerAndReset() {

            print("WDS: 플레이어 종료 및 상태 초기화")

            removePopup()

            // 이전 JavaScript 상태를 없애기 위해
            // 메인 페이지를 다시 로딩
            resetMainPage()
        }

        private func removePopup() {

            if let popup = popupWebView {

                popup.stopLoading()

                popup.uiDelegate = nil
                popup.navigationDelegate = nil

                // 미디어 및 JavaScript 실행 중지
                popup.loadHTMLString(
                    "<html><body></body></html>",
                    baseURL: nil
                )

                popup.removeFromSuperview()
            }

            popupWebView = nil

            closeButton?.removeFromSuperview()
            closeButton = nil
        }

        // MARK: - Reset Main Page

        private func resetMainPage() {

            guard !isResetting else {
                return
            }

            guard let main = mainWebView else {
                return
            }

            isResetting = true

            // 현재 라우트를 가능한 한 유지
            let currentURL = main.url ?? startURL

            print(
                "WDS: 메인 페이지 초기화:",
                currentURL.absoluteString
            )

            main.stopLoading()

            let request = URLRequest(
                url: currentURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 60
            )

            main.load(request)
        }

        // MARK: - Window Close Event

        func webViewDidClose(
            _ webView: WKWebView
        ) {

            if webView === popupWebView {
                closePlayerAndReset()
            }
        }

        // MARK: - Navigation

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {

            if webView === mainWebView {
                isResetting = false
            }

            print(
                "WDS 로딩 완료:",
                webView.url?.absoluteString ?? ""
            )
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {

            if webView === mainWebView {
                isResetting = false
            }

            print(
                "WDS 로딩 오류:",
                error.localizedDescription
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {

            if webView === mainWebView {
                isResetting = false
            }

            print(
                "WDS 연결 오류:",
                error.localizedDescription
            )
        }

        // MARK: - Cleanup

        func cleanup() {

            removePopup()

            mainWebView?.stopLoading()
            mainWebView?.uiDelegate = nil
            mainWebView?.navigationDelegate = nil

            resetButton?.removeFromSuperview()
            resetButton = nil
        }
    }
}
