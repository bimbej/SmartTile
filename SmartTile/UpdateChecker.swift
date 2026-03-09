import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "bimbej/SmartTile"
    private var latestDownloadURL: URL?
    private var latestVersion: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public

    /// Check GitHub for a newer release. Shows alert if update available.
    func checkForUpdates(silent: Bool = true) {
        Task {
            do {
                guard let release = try await fetchLatestRelease() else {
                    if !silent {
                        ToastController.shared.show("SmartTile is up to date (v\(currentVersion))", icon: "checkmark.circle.fill")
                    }
                    return
                }
                let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

                guard isNewer(remote: remote, local: currentVersion) else {
                    if !silent {
                        ToastController.shared.show("SmartTile is up to date (v\(currentVersion))", icon: "checkmark.circle.fill")
                    }
                    return
                }

                // Find .dmg asset
                guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                    if !silent {
                        ToastController.shared.show("Update v\(remote) available — no DMG found", icon: "exclamationmark.triangle")
                    }
                    return
                }

                latestDownloadURL = URL(string: dmgAsset.downloadURL)
                latestVersion = remote
                showUpdateAlert(version: remote)
            } catch {
                if !silent {
                    ToastController.shared.show("Update check failed", icon: "wifi.slash")
                }
            }
        }
    }

    // MARK: - GitHub API

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let downloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Version Comparison

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - UI

    private func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "SmartTile v\(version) is available"
        alert.informativeText = "You are running v\(currentVersion). Download and install the update?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstall()
        case .alertSecondButtonReturn:
            let url = URL(string: "https://github.com/\(repo)/releases/latest")!
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    // MARK: - Download & Install

    private func downloadAndInstall() {
        guard let downloadURL = latestDownloadURL, let version = latestVersion else { return }

        ToastController.shared.show("Downloading v\(version)...", icon: "arrow.down.circle")

        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let dmgPath = tempDir.appendingPathComponent("SmartTile-\(version).dmg")

                // Download DMG
                let (data, response) = try await URLSession.shared.data(from: downloadURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    ToastController.shared.show("Download failed", icon: "xmark.circle")
                    return
                }
                try data.write(to: dmgPath)

                // Mount DMG
                let mountPoint = tempDir.appendingPathComponent("SmartTile-mount")
                try? FileManager.default.removeItem(at: mountPoint)
                try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

                let mount = Process()
                mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                mount.arguments = ["attach", dmgPath.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
                try mount.run()
                mount.waitUntilExit()
                guard mount.terminationStatus == 0 else {
                    ToastController.shared.show("Failed to mount DMG", icon: "xmark.circle")
                    return
                }

                // Find .app in mounted DMG
                let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
                guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                    unmount(mountPoint)
                    ToastController.shared.show("No app found in DMG", icon: "xmark.circle")
                    return
                }

                // Replace current app
                let appDest = URL(fileURLWithPath: "/Applications/SmartTile.app")
                let backup = tempDir.appendingPathComponent("SmartTile-old.app")
                try? FileManager.default.removeItem(at: backup)

                if FileManager.default.fileExists(atPath: appDest.path) {
                    try FileManager.default.moveItem(at: appDest, to: backup)
                }
                try FileManager.default.copyItem(at: appBundle, to: appDest)

                // Unmount & cleanup
                unmount(mountPoint)
                try? FileManager.default.removeItem(at: dmgPath)
                try? FileManager.default.removeItem(at: backup)

                // Relaunch
                ToastController.shared.show("Restarting SmartTile...", icon: "arrow.clockwise")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                relaunch()
            } catch {
                ToastController.shared.show("Update failed: \(error.localizedDescription)", icon: "xmark.circle")
            }
        }
    }

    private func unmount(_ mountPoint: URL) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint.path, "-quiet"]
        try? detach.run()
        detach.waitUntilExit()
    }

    private func relaunch() {
        let appPath = "/Applications/SmartTile.app"
        // Terminate first, then open — avoids two instances running simultaneously
        let script = "sleep 1 && open \"\(appPath)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }
}
