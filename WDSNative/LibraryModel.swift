import Foundation
import ZIPFoundation
import Swifter

@MainActor
final class LibraryModel: ObservableObject {
    @Published var status = "resources.zip 파일을 선택하세요."
    @Published var isImporting = false
    @Published var ready = false
    @Published var webURL: URL?

    private var server: HttpServer?
    private let port: UInt16 = 8765
    private var archiveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resources.zip")
    }

    init() {
        ready = FileManager.default.fileExists(atPath: archiveURL.path)
        if ready { startServer() }
    }

    func importZIP(_ source: URL) {
        guard !isImporting else { return }
        isImporting = true
        status = "ZIP을 앱 저장 공간으로 복사하고 있습니다. 앱을 종료하지 마세요."
        let destination = archiveURL
        Task.detached(priority: .userInitiated) {
            let granted = source.startAccessingSecurityScopedResource()
            defer { if granted { source.stopAccessingSecurityScopedResource() } }
            let temp = destination.deletingLastPathComponent().appendingPathComponent("resources-importing.zip")
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: temp.path) { try fm.removeItem(at: temp) }
                try fm.copyItem(at: source, to: temp)
                guard let archive = Archive(url: temp, accessMode: .read) else {
                    throw NSError(domain: "WDS", code: 1, userInfo: [NSLocalizedDescriptionKey: "ZIP 파일을 열 수 없습니다."])
                }
                let hasEntry = archive["index.html"] != nil
                    && archive["data/manifest/Episode.json"] != nil
                    && archive["adv-player/index.html"] != nil
                guard hasEntry else {
                    throw NSError(domain: "WDS", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP 루트에 index.html, data/manifest/Episode.json, adv-player/index.html이 있어야 합니다."])
                }
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: temp, to: destination)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutable = destination
                try? mutable.setResourceValues(values)
                await MainActor.run {
                    self.ready = true
                    self.isImporting = false
                    self.status = "ZIP 준비 완료 — 압축 해제 없이 실행합니다."
                    self.startServer()
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                await MainActor.run {
                    self.isImporting = false
                    self.status = "가져오기 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    func startServer() {
        guard ready, server == nil else { return }
        let zipURL = archiveURL
        let overrides = Bundle.main.url(forResource: "Overrides", withExtension: nil)
        let http = HttpServer()
        // Swifter's regex router matches nested resource paths.
        http["/(.*)"] = { request in
            let rawPath = request.path.removingPercentEncoding ?? request.path
            var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty { path = "index.html" }
            let segments = path.split(separator: "/")
            guard !segments.contains(".."), !path.contains("\\"), !path.contains("\0") else {
                return .badRequest(nil)
            }
            let mime = Self.mimeType(for: path)
            // The APK's Android-specific overrides are intentionally NOT activated:
            // they reference an Android JavaScript bridge that iOS does not provide.
            // Their files are bundled for inspection and selective porting.
            _ = overrides
            guard let archive = Archive(url: zipURL, accessMode: .read),
                  let entry = archive[path] else { return .notFound }
            do {
                var data = Data()
                data.reserveCapacity(Int(min(entry.uncompressedSize, 8 * 1024 * 1024)))
                _ = try archive.extract(entry, consumer: { chunk in
                    data.append(chunk)
                })
                return .ok(data, contentType: mime)
            } catch {
                return .internalServerError
            }
        }
        do {
            try http.start(port, forceIPv4: true)
            server = http
            webURL = URL(string: "http://127.0.0.1:\(port)/index.html#/Main")
            status = "오프라인 서버 실행 중 — ZIP에서 필요한 파일만 읽습니다."
        } catch {
            status = "로컬 서버 시작 실패: \(error.localizedDescription)"
        }
    }

    nonisolated static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "otf": return "font/otf"
        case "ttf": return "font/ttf"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "wds": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}
