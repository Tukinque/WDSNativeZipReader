
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
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("resources.zip")
    }

    init() {
        ready = FileManager.default.fileExists(
            atPath: archiveURL.path
        )

        if ready {
            startServer()
        }
    }

    // MARK: - ZIP 가져오기

    func importZIP(_ source: URL) {
        guard !isImporting else { return }

        isImporting = true
        status = "ZIP 복사 중입니다. 앱을 종료하지 마세요."

        let destination = archiveURL

        Task.detached(priority: .userInitiated) {

            let granted = source.startAccessingSecurityScopedResource()

            defer {
                if granted {
                    source.stopAccessingSecurityScopedResource()
                }
            }

            let temp = destination
                .deletingLastPathComponent()
                .appendingPathComponent("resources-importing.zip")

            do {
                let fm = FileManager.default

                if fm.fileExists(atPath: temp.path) {
                    try fm.removeItem(at: temp)
                }

                try fm.copyItem(at: source, to: temp)

                guard let archive = Archive(
                    url: temp,
                    accessMode: .read
                ) else {
                    throw NSError(
                        domain: "WDS",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "ZIP 파일을 열 수 없습니다."
                        ]
                    )
                }

                let requiredFiles = [
                    "index.html",
                    "data/manifest/Episode.json",
                    "adv-player/index.html"
                ]

                for file in requiredFiles {
                    guard archive[file] != nil else {
                        throw NSError(
                            domain: "WDS",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "ZIP 내부 파일 누락: \(file)"
                            ]
                        )
                    }
                }

                await MainActor.run {
                    self.stopServer()
                }

                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }

                try fm.moveItem(at: temp, to: destination)

                var values = URLResourceValues()
                values.isExcludedFromBackup = true

                var mutable = destination
                try? mutable.setResourceValues(values)

                await MainActor.run {
                    self.ready = true
                    self.isImporting = false
                    self.startServer()
                }

            } catch {
                try? FileManager.default.removeItem(at: temp)

                await MainActor.run {
                    self.isImporting = false
                    self.status =
                        "가져오기 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 서버 종료

    private func stopServer() {
        server?.stop()
        server = nil
        webURL = nil
    }

    // MARK: - 서버 시작

    func startServer() {

        guard ready else {
            status = "ZIP 파일이 준비되지 않았습니다."
            return
        }

        guard server == nil else {
            status = "로컬 서버 실행 중"
            return
        }

        let zipURL = archiveURL
        let http = HttpServer()

        http.listenAddressIPv4 = "127.0.0.1"

        // 기본 서버 연결 테스트
        http["/health"] = { _ in
            return .ok(.text("WDS SERVER OK"))
        }

        // 라우터에서 처리되지 않은 모든 파일 요청 처리
        http.notFoundHandler = { request in

            let rawPath =
                request.path.removingPercentEncoding
                ?? request.path

            var path = rawPath

            if let question = path.firstIndex(of: "?") {
                path = String(path[..<question])
            }

            while path.hasPrefix("/") {
                path.removeFirst()
            }

            if path.isEmpty {
                path = "index.html"
            } else if path.hasSuffix("/") {
                path += "index.html"
            }

            let segments = path.split(separator: "/")

            guard !segments.contains(".."),
                  !path.contains("\\"),
                  !path.contains("\0") else {
                return .badRequest(nil)
            }

            let mime = LibraryModel.mimeType(for: path)

            guard let archive = Archive(
                url: zipURL,
                accessMode: .read
            ) else {
                return .raw(
                    500,
                    "Internal Server Error",
                    ["Content-Type": "text/plain; charset=utf-8"]
                ) { writer in
                    try writer.write(
                        Array("ZIP OPEN FAILED".utf8)
                    )
                }
            }

            guard let entry = archive[path] else {
                let message = """
                ZIP ENTRY NOT FOUND
                Requested: \(request.path)
                Converted: \(path)
                ZIP exists: \(FileManager.default.fileExists(atPath: zipURL.path))
                """

                return .raw(
                    404,
                    "Not Found",
                    ["Content-Type": "text/plain; charset=utf-8"]
                ) { writer in
                    try writer.write(Array(message.utf8))
                }
            }

            do {
                var data = Data()

                data.reserveCapacity(
                    Int(
                        min(
                            entry.uncompressedSize,
                            8 * 1024 * 1024
                        )
                    )
                )

                _ = try archive.extract(
                    entry,
                    consumer: { chunk in
                        data.append(chunk)
                    }
                )

                return .ok(
                    .data(data, contentType: mime)
                )

            } catch {
                let message =
                    "ZIP EXTRACT FAILED: \(error.localizedDescription)"

                return .raw(
                    500,
                    "Internal Server Error",
                    ["Content-Type": "text/plain; charset=utf-8"]
                ) { writer in
                    try writer.write(Array(message.utf8))
                }
            }
        }

        // MARK: - 서버 실행

        do {
            status = "로컬 서버 시작 중..."

            try http.start(
                port,
                forceIPv4: true
            )

            server = http

            guard let url = URL(
                string: "http://127.0.0.1:\(port)/index.html#/Main"
            ) else {
                status = "웹페이지 주소 생성 실패"
                return
            }

            webURL = url
            status = "로컬 서버 실행 중 — ZIP 직접 읽기"

        } catch {
            status =
                "서버 시작 오류: \(error.localizedDescription)"
        }
    }

    // MARK: - MIME 타입

    nonisolated static func mimeType(
        for path: String
    ) -> String {

        switch (path as NSString)
            .pathExtension
            .lowercased() {

        case "html":
            return "text/html; charset=utf-8"

        case "js", "mjs":
            return "text/javascript; charset=utf-8"

        case "css":
            return "text/css; charset=utf-8"

        case "json":
            return "application/json"

        case "png":
            return "image/png"

        case "jpg", "jpeg":
            return "image/jpeg"

        case "webp":
            return "image/webp"

        case "svg":
            return "image/svg+xml"

        case "woff":
            return "font/woff"

        case "woff2":
            return "font/woff2"

        case "otf":
            return "font/otf"

        case "ttf":
            return "font/ttf"

        case "mp3":
            return "audio/mpeg"

        case "ogg":
            return "audio/ogg"

        case "wav":
            return "audio/wav"

        case "mp4":
            return "video/mp4"

        case "wds":
            return "application/octet-stream"

        default:
            return "application/octet-stream"
        }
    }
}
