
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

// MARK: - WDS WebView

struct WDSWebView: UIViewRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {

        let container = UIView()
        container.backgroundColor = .white

        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator

        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white

        webView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        context.coordinator.container = container
        context.coordinator.mainWebView = webView

        webView.load(URLRequest(url: url))

        return container
    }

    func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {
    }

    static func dismantleUIView(
        _ uiView: UIView,
        coordinator: Coordinator
    ) {
        coordinator.closePopup()
        coordinator.mainWebView?.stopLoading()
        coordinator.mainWebView?.uiDelegate = nil
        coordinator.mainWebView?.navigationDelegate = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
        WKUIDelegate,
        WKNavigationDelegate {

        weak var container: UIView?
        weak var mainWebView: WKWebView?

        private var popupWebView: WKWebView?
        private var closeButton: UIButton?

        // MARK: - Open Popup

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

            // 이전 플레이어 정리
            closePopup()

            // 새 플레이어 생성
            let popup = WKWebView(
                frame: .zero,
                configuration: configuration
            )

            popup.uiDelegate = self
            popup.navigationDelegate = self

            popup.scrollView.contentInsetAdjustmentBehavior = .never
            popup.backgroundColor = .white
            popup.isOpaque = false

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

            // 닫기 버튼
            let button = UIButton(type: .system)

            button.setTitle("✕ 닫기", for: .normal)

            button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            button.setTitleColor(.white, for: .normal)

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

            // WKWebView가 반환된 popup에 직접 요청을 로드함
            return popup
        }

        // MARK: - Close Popup

        @objc func closePopupTapped() {
            closePopup()
        }

        func closePopup() {

            popupWebView?.stopLoading()

            popupWebView?.uiDelegate = nil
            popupWebView?.navigationDelegate = nil

            popupWebView?.loadHTMLString(
                "",
                baseURL: nil
            )

            popupWebView?.removeFromSuperview()
            popupWebView = nil

            closeButton?.removeFromSuperview()
            closeButton = nil
        }

        // MARK: - Window Close

        func webViewDidClose(
            _ webView: WKWebView
        ) {
            if webView === popupWebView {
                closePopup()
            }
        }

        // MARK: - Navigation

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
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
            print(
                "WDS 연결 오류:",
                error.localizedDescription
            )
        }
    }
}
