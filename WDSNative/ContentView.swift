
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import UIKit

// MARK: - 메인 화면

struct ContentView: View {

    @EnvironmentObject var model: LibraryModel

    @State private var picker = false
    @State private var showLogs = false

    var body: some View {

        ZStack(alignment: .topTrailing) {

            if let url = model.webURL {

                WDSWebView(url: url)
                    .ignoresSafeArea()

                // 숨겨진 디버그 영역
                // 오른쪽 위를 3초간 누르면 로그 창 열기
                Color.clear
                    .frame(width: 65, height: 65)
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 3
                    ) {
                        showLogs = true
                    }
                    .padding(.top, 5)
                    .padding(.trailing, 5)

            } else {

                VStack(spacing: 16) {

                    Text("WDS-StoryViewer")
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
        .sheet(isPresented: $showLogs) {
            WDSLogView()
                .environmentObject(model)
        }
    }
}

// MARK: - 디버그 로그 화면

struct WDSLogView: View {

    @EnvironmentObject var model: LibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {

        NavigationStack {

            VStack(spacing: 12) {

                Text("스토리 재생 오류 기록")
                    .font(.headline)

                Text("오른쪽 위를 3초간 누르면 이 화면을 다시 열 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ScrollView {

                    Text(model.allLogs)
                        .font(
                            .system(
                                size: 12,
                                design: .monospaced
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .textSelection(.enabled)
                        .padding()
                }
                .background(
                    Color(.secondarySystemBackground)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 12)
                )

                HStack {

                    Button("기록 지우기") {
                        model.clearLogs()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("전체 복사") {
                        UIPasteboard.general.string =
                            model.allLogs
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("WDS 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 웹뷰

struct WDSWebView: UIViewRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(
        context: Context
    ) -> WKWebView {

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

        context.coordinator.mainWebView = webView

        webView.load(
            URLRequest(url: url)
        )

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        // SwiftUI 갱신 시 웹페이지를 다시 로드하지 않음
    }

    // MARK: - 웹뷰 이벤트

    final class Coordinator:
        NSObject,
        WKUIDelegate,
        WKNavigationDelegate {

        weak var mainWebView: WKWebView?

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            guard
                navigationAction.targetFrame == nil,
                let url = navigationAction.request.url
            else {
                return nil
            }

            webView.load(
                URLRequest(url: url)
            )

            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (
                WKNavigationActionPolicy
            ) -> Void
        ) {
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            print(
                "WDS 페이지 로딩 완료:",
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
