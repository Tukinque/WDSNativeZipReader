
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {

    @EnvironmentObject var model: LibraryModel
    @State private var picker = false

    var body: some View {

        VStack(spacing: 0) {

            if let url = model.webURL {

                WDSWebView(url: url)
                    .ignoresSafeArea(
                        edges: .bottom
                    )

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

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true

        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.scrollView.contentInsetAdjustmentBehavior = .never

        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white

        webView.load(
            URLRequest(url: url)
        )

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
    }
}
