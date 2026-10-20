import AppKit
import Combine
import CryptoKit
import Foundation

struct AppRelease: Identifiable, Equatable, Sendable {
    let version: String
    let tag: String
    let title: String
    let notes: String
    let pageURL: URL
    let assetURL: URL
    let assetName: String
    let assetSize: Int64
    let digest: String

    var id: String { tag }
}

@MainActor
final class UpdateService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case preparing
        case readyToInstall
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: AppRelease?
    @Published private(set) var progress: Double = 0
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String
    var isUpdateAvailable: Bool {
        if case .available = phase { return true }
        return false
    }

    var showsUpdateAttention: Bool {
        switch phase {
        case .available, .downloading, .preparing, .readyToInstall, .installing:
            return true
        default:
            return false
        }
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .preparing, .installing:
            return true
        default:
            return false
        }
    }

    private struct PreparedUpdate: Sendable {
        let appURL: URL
        let stagingURL: URL
        let zipURL: URL
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: String
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name, size, digest
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case name, body, assets
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private enum UpdateError: LocalizedError {
        case network(String)
        case invalidResponse
        case noCompatibleAsset
        case missingDigest
        case checksumMismatch
        case invalidPackage(String)
        case installLocation(String)

        var errorDescription: String? {
            switch self {
            case .network(let message):
                return "无法连接更新服务：\(message)"
            case .invalidResponse:
                return "更新服务返回了无法识别的数据"
            case .noCompatibleAsset:
                return "最新版本没有适用于 Apple Silicon 的安装包"
            case .missingDigest:
                return "安装包缺少校验摘要，已拒绝更新"
            case .checksumMismatch:
                return "安装包校验失败，已停止更新"
            case .invalidPackage(let reason):
                return "安装包验证失败：\(reason)"
            case .installLocation(let reason):
                return reason
            }
        }
    }

    private let releasesAPI = URL(string: "https://api.github.com/repos/A2ureeE/CrazyAutoDL/releases/latest")!
    private let defaults = UserDefaults.standard
    private let autoCheckKey = "hunao.autoUpdateLastCheck"
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var progressObservation: NSKeyValueObservation?
    private var prepared: PreparedUpdate?
    private var downloadGeneration = 0

    init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func autoCheckIfNeeded() async {
        guard !ProcessInfo.processInfo.arguments.contains("--demo") else { return }
        if let last = defaults.object(forKey: autoCheckKey) as? Date,
           Date().timeIntervalSince(last) < 86_400 {
            return
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool = true) async {
        guard !isBusy, phase != .readyToInstall else { return }

        phase = .checking
        do {
            let latest = try await fetchLatestRelease()
            lastCheckedAt = Date()
            defaults.set(lastCheckedAt, forKey: autoCheckKey)

            if Self.compareVersions(latest.version, currentVersion) > 0 {
                release = latest
                phase = .available
            } else {
                release = nil
                phase = .upToDate
            }
        } catch {
            if userInitiated {
                phase = .failed(error.localizedDescription)
            } else {
                phase = release == nil ? .idle : .available
            }
        }
    }

    func download() {
        guard let release else { return }
        switch phase {
        case .available, .failed:
            break
        default:
            return
        }
        guard let host = release.assetURL.host,
              host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
        else {
            phase = .failed("下载地址不是 GitHub 官方域名")
            return
        }

        downloadGeneration &+= 1
        let generation = downloadGeneration

        phase = .downloading
        progress = 0
        receivedBytes = 0
        totalBytes = release.assetSize

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        downloadSession = session

        let task = session.downloadTask(with: release.assetURL) { [weak self] location, response, error in
            if let error {
                let isCancelled = (error as NSError).code == NSURLErrorCancelled
                Task { @MainActor in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.finishDownload(error: isCancelled ? nil : error)
                }
                return
            }
            guard let location,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200
            else {
                Task { @MainActor in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.finishDownload(error: UpdateError.invalidResponse)
                }
                return
            }

            do {
                let directory = try Self.updatesDirectory()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let destination = directory.appendingPathComponent("download-\(UUID().uuidString).zip")
                try FileManager.default.copyItem(at: location, to: destination)
                Task { @MainActor in
                    guard let self, self.downloadGeneration == generation else { return }
                    await self.prepareDownloadedZip(at: destination, release: release)
                }
            } catch {
                Task { @MainActor in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.finishDownload(error: error)
                }
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
            let fraction = value.fractionCompleted
            Task { @MainActor in
                guard let self,
                      self.downloadGeneration == generation,
                      case .downloading = self.phase
                else { return }
                let clamped = min(max(fraction, 0), 1)
                self.progress = clamped
                self.totalBytes = release.assetSize
                self.receivedBytes = Int64(Double(release.assetSize) * clamped)
            }
        }

        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        guard case .downloading = phase else { return }
        downloadGeneration &+= 1
        downloadTask?.cancel()
        cleanupDownload()
        phase = .available
        progress = 0
        receivedBytes = 0
    }

    func retry() {
        guard release != nil else {
            Task { await check() }
            return
        }
        if case .failed = phase {
            phase = .available
        }
        if case .available = phase {
            download()
        } else {
            Task { await check() }
        }
    }

    func install() {
        guard case .readyToInstall = phase, let prepared else { return }

        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard appURL.pathExtension == "app" else {
            phase = .failed("当前不是以 .app 方式运行，无法自动安装")
            return
        }
        guard !appURL.path.contains("/AppTranslocation/"), !appURL.path.hasPrefix("/Volumes/") else {
            phase = .failed("请先把胡闹AutoDL 拖入「应用程序」文件夹，再检查更新")
            return
        }
        let parentURL = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            phase = .failed("应用所在目录没有写入权限，请将应用移动到「应用程序」文件夹")
            return
        }

        do {
            let scriptURL = try makeInstallScript(
                currentApp: appURL,
                prepared: prepared,
                logURL: try Self.logFileURL()
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path]
            try process.run()

            phase = .installing
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                NSApplication.shared.terminate(nil)
            }
        } catch {
            phase = .failed("无法启动安装程序：\(error.localizedDescription)")
        }
    }

    // MARK: - Networking

    private func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("HuNaoAutoDL/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.network("GitHub 返回 HTTP \(http.statusCode)")
        }

        let payload: GitHubRelease
        do {
            payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.invalidResponse
        }

        guard let asset = payload.assets.first(where: {
            let name = $0.name.lowercased()
            return name.hasSuffix(".zip") && name.contains("arm64")
        }) else {
            throw UpdateError.noCompatibleAsset
        }
        guard let digest = asset.digest?.lowercased(), digest.hasPrefix("sha256:") else {
            throw UpdateError.missingDigest
        }
        guard let assetURL = URL(string: asset.browserDownloadURL),
              let pageURL = URL(string: payload.htmlURL)
        else {
            throw UpdateError.invalidResponse
        }

        return AppRelease(
            version: payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            tag: payload.tagName,
            title: payload.name ?? payload.tagName,
            notes: payload.body ?? "本次更新暂无详细说明。",
            pageURL: pageURL,
            assetURL: assetURL,
            assetName: asset.name,
            assetSize: asset.size,
            digest: digest
        )
    }

    private func prepareDownloadedZip(at zipURL: URL, release: AppRelease) async {
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        progressObservation?.invalidate()
        progressObservation = nil
        downloadTask = nil

        phase = .preparing
        progress = 1

        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try UpdateService.prepareInstall(zipURL: zipURL, release: release)
            }.value
            self.prepared = prepared
            phase = .readyToInstall
        } catch {
            try? FileManager.default.removeItem(at: zipURL)
            phase = .failed(error.localizedDescription)
        }
    }

    private func finishDownload(error: Error?) {
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        progressObservation?.invalidate()
        progressObservation = nil
        downloadTask = nil

        guard let error else { return }
        phase = .failed(error.localizedDescription)
    }

    private func cleanupDownload() {
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
    }

    // MARK: - Package preparation

    private nonisolated static func prepareInstall(zipURL: URL, release: AppRelease) throws -> PreparedUpdate {
        let fileManager = FileManager.default
        let updates = try updatesDirectory()
        let staging = updates.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let bytes = try Data(contentsOf: zipURL, options: .mappedIfSafe)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard "sha256:\(digest)" == release.digest.lowercased() else {
                throw UpdateError.checksumMismatch
            }

            try runProcess(
                "/usr/bin/ditto",
                arguments: ["-x", "-k", zipURL.path, staging.path]
            )

            let entries = try fileManager.contentsOfDirectory(
                at: staging,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            guard let appURL = entries.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.invalidPackage("压缩包中未找到应用")
            }

            let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
            guard let infoData = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
            else {
                throw UpdateError.invalidPackage("无法读取版本信息")
            }
            let identifier = plist["CFBundleIdentifier"] as? String
            guard identifier == "com.hunao.autodl" else {
                throw UpdateError.invalidPackage("应用标识不匹配")
            }
            let version = plist["CFBundleShortVersionString"] as? String
            guard version == release.version else {
                throw UpdateError.invalidPackage("版本号为 \(version ?? "未知")，与发布版本不一致")
            }
            guard fileManager.isExecutableFile(
                atPath: appURL.appendingPathComponent("Contents/MacOS/HuNaoAutoDL").path
            ) else {
                throw UpdateError.invalidPackage("未找到主程序")
            }

            try runProcess(
                "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", appURL.path]
            )

            return PreparedUpdate(appURL: appURL, stagingURL: staging, zipURL: zipURL)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func makeInstallScript(
        currentApp: URL,
        prepared: PreparedUpdate,
        logURL: URL
    ) throws -> URL {
        let scriptURL = prepared.stagingURL
            .deletingLastPathComponent()
            .appendingPathComponent("install-\(UUID().uuidString).sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        let quote = Self.shellQuote

        let script = """
        #!/bin/zsh
        set -u
        LOG=\(quote(logURL.path))
        exec >>"$LOG" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始安装更新"
        PID=\(pid)
        OLD=\(quote(currentApp.path))
        NEW=\(quote(prepared.appURL.path))
        STAGING=\(quote(prepared.stagingURL.path))
        ZIP=\(quote(prepared.zipURL.path))

        EXITED=0
        for i in {1..150}; do
          if ! kill -0 "$PID" 2>/dev/null; then EXITED=1; break; fi
          sleep 0.2
        done
        if [[ "$EXITED" -ne 1 ]]; then
          echo "应用未退出，取消安装"
          exit 1
        fi
        sleep 0.4

        BACKUP="${OLD}.backup-$(date +%s)"
        if ! mv "$OLD" "$BACKUP"; then
          echo "无法备份旧版本"
          exit 1
        fi

        if ! /usr/bin/ditto --noextattr --norsrc "$NEW" "$OLD"; then
          echo "复制新版本失败"
          rm -rf "$OLD"
          mv "$BACKUP" "$OLD"
          /usr/bin/open "$OLD"
          exit 1
        fi

        /usr/bin/xattr -cr "$OLD"
        if ! /usr/bin/codesign --verify --deep --strict "$OLD"; then
          echo "新版本签名校验失败"
          rm -rf "$OLD"
          mv "$BACKUP" "$OLD"
          /usr/bin/open "$OLD"
          exit 1
        fi

        /usr/bin/open "$OLD"
        sleep 1
        rm -rf "$BACKUP" "$STAGING" "$ZIP" "$LOG" "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    // MARK: - Helpers

    private nonisolated static func updatesDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HuNaoAutoDL", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let updates = root.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: updates,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: updates.path)
        return updates
    }

    private nonisolated static func logFileURL() throws -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/HuNaoAutoDL", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("update.log")
    }

    private nonisolated static func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.invalidPackage(message?.isEmpty == false ? message! : "命令执行失败")
        }
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? 1 : -1 }
        }
        return 0
    }

    private nonisolated static func versionComponents(_ value: String) -> [Int] {
        var components: [Int] = []
        var digits = ""
        for character in value.lowercased() {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                components.append(Int(digits) ?? 0)
                digits = ""
            }
        }
        if !digits.isEmpty {
            components.append(Int(digits) ?? 0)
        }
        return components
    }
}
