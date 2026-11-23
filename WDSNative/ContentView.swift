import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject var model: LibraryModel
    @State private var picker = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("WDS Offline").font(.headline)
                Spacer()
                Button("ZIP 가져오기") { picker = true }
                    .disabled(model.isImporting)
            }.padding(.horizontal)
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            if let url = model.webURL {
                WDSWebView(url: url)
            } else {
                Spacer()
                Text("기존 리소스 ZIP을 iPad의 파일 앱에서 선택하세요.")
                    .multilineTextAlignment(.center)
                Button("리소스 ZIP 선택") { picker = true }
                    .disabled(model.isImporting)
                if model.isImporting { ProgressView("압축 해제 중…") }
                Spacer()
            }
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url): model.importZIP(url)
            case .failure(let error): model.status = "선택 실패: \(error.localizedDescription)"
            }
        }
    }
}

struct WDSWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
