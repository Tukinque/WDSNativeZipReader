
import Foundation
import ZIPFoundation
import Swifter

@MainActor
final class LibraryModel: ObservableObject {

    @Published var status = "resources.zip 파일을 선택하세요."
    @Published var isImporting = false
    @Published var ready = false
    @Published var webURL: URL?

    // 오류 진단 기록
    @Published var errorLogs: [String] = []

    private var server: HttpServer?
    private let port: UInt16 = 8765

    private var archiveURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resources.zip")
    }

    init() {
        ready = FileManager.default.fileExists(
            atPath: archiveURL.path
        )

        if ready {
            startServer()
        }
    }

    // MARK: - 진단 기록

    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"

        errorLogs.append(line)

        if errorLogs.count > 200 {
            errorLogs.removeFirst(errorLogs.count - 200)
        }

        print("WDS: \(line)")
    }

    func clearLogs() {
        errorLogs.removeAll()
    }

    var allLogs: String {
        if errorLogs.isEmpty {
            return "아직 기록된 요청이나 오류가 없습니다."
        }

        return errorLogs.joined(separator: "\n")
    }

    nonisolated private static func record(
        _ message: String,
        model: LibraryModel?
    ) {
        Task { @MainActor in
            model?.addLog(message)
        }
    }

    // MARK: - ZIP 가져오기

    func importZIP(_ source: URL) {
        guard !isImporting else { return }

        isImporting = true
        status = "ZIP 복사 중입니다. 앱을 종료하지 마세요."

        let destination = archiveURL

        Task.detached(priority: .userInitiated) {
            let granted =
                source.startAccessingSecurityScopedResource()

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
                    self.addLog("ZIP 가져오기 완료")
                    self.startServer()
                }

            } catch {
                try? FileManager.default.removeItem(at: temp)

                await MainActor.run {
                    self.isImporting = false
                    self.status =
                        "가져오기 실패: \(error.localizedDescription)"
                    self.addLog(self.status)
                }
            }
        }
    }

    // MARK: - 서버 중지

    private func stopServer() {
        server?.stop()
        server = nil
        webURL = nil
    }

    // MARK: - 로컬 서버 시작

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

        http["/health"] = { _ in
            return .ok(.text("WDS SERVER OK"))
        }

        // 기존에 정상 작동했던 요청 처리 방식 유지
        http.notFoundHandler = { [weak self] request in

            // MARK: 1. 요청 경로 정리

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

            // MARK: 2. adv-player 경로 자동 수정
            //
            // 예:
            // adv-player/data/spine/10101.png
            // -> data/spine/10101.png
            //
            // 모든 에피소드에 자동 적용됩니다.

            if path.hasPrefix("adv-player/data/") {

                let originalPath = path

                path = String(
                    path.dropFirst("adv-player/".count)
                )

                Self.record(
                    "경로 자동 수정: \(originalPath) → \(path)",
                    model: self
                )
            }

            // MARK: 3. 안전성 검사

            let segments = path.split(separator: "/")

            guard
                !segments.contains(".."),
                !path.contains("\\"),
                !path.contains("\0")
            else {
                Self.record(
                    "잘못된 경로: \(path)",
                    model: self
                )

                return .badRequest(nil)
            }

            // MARK: 4. 주요 리소스 요청 기록

            if path.hasPrefix("data/episode/")
                || path.hasPrefix("data/voice/")
                || path.hasPrefix("data/movie/") {

                Self.record(
                    "요청: \(path)",
                    model: self
                )
            }

            let mime = Self.mimeType(for: path)

            // MARK: 5. Overrides 우선 적용

            if let root = Bundle.main.resourceURL {

                let overrideURL = root
                    .appendingPathComponent("Overrides")
                    .appendingPathComponent(path)

                if FileManager.default.fileExists(
                    atPath: overrideURL.path
                ) {
                    do {
                        let data = try Data(
                            contentsOf: overrideURL
                        )

                        return .ok(
                            .data(
                                data,
                                contentType: mime
                            )
                        )

                    } catch {
                        Self.record(
                            "OVERRIDE 읽기 실패: \(path) / \(error.localizedDescription)",
                            model: self
                        )
                    }
                }
            }

            // MARK: 6. ZIP 열기

            guard let archive = Archive(
                url: zipURL,
                accessMode: .read
            ) else {

                Self.record(
                    "ZIP 열기 실패",
                    model: self
                )

                return .raw(
                    500,
                    "Internal Server Error",
                    [
                        "Content-Type":
                            "text/plain; charset=utf-8"
                    ]
                ) { writer in
                    try writer.write(
                        Array("ZIP OPEN FAILED".utf8)
                    )
                }
            }

            // MARK: 7. ZIP 파일 검색

            guard let entry = archive[path] else {

                Self.record(
                    "404 파일 없음: \(path)",
                    model: self
                )

                let message = """
                ZIP ENTRY NOT FOUND
                Requested: \(request.path)
                Converted: \(path)
                ZIP exists: \(FileManager.default.fileExists(atPath: zipURL.path))
                """

                return .raw(
                    404,
                    "Not Found",
                    [
                        "Content-Type":
                            "text/plain; charset=utf-8"
                    ]
                ) { writer in
                    try writer.write(
                        Array(message.utf8)
                    )
                }
            }

            // MARK: 8. ZIP 파일 추출

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
                    .data(
                        data,
                        contentType: mime
                    )
                )

            } catch {

                Self.record(
                    "500 파일 추출 실패: \(path) / \(error.localizedDescription)",
                    model: self
                )

                let message =
                    "ZIP EXTRACT FAILED: \(error.localizedDescription)"

                return .raw(
                    500,
                    "Internal Server Error",
                    [
                        "Content-Type":
                            "text/plain; charset=utf-8"
                    ]
                ) { writer in
                    try writer.write(
                        Array(message.utf8)
                    )
                }
            }
        }

        // MARK: 9. 서버 실행

        do {
            status = "로컬 서버 시작 중..."

            try http.start(
                port,
                forceIPv4: true
            )

            server = http

            guard let url = URL(
                string:
                    "http://127.0.0.1:\(port)/index.html#/Main"
            ) else {
                status = "웹페이지 주소 생성 실패"
                return
            }

            webURL = url

            status =
                "로컬 서버 실행 중 — ZIP 직접 읽기"

            addLog("서버 시작 완료")

        } catch {
            status =
                "서버 시작 오류: \(error.localizedDescription)"

            addLog(status)
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
