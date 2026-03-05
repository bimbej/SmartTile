import Foundation

/// Manages local LLM inference via llama-cli (brew install llama.cpp)
class LocalModelManager {
    static let shared = LocalModelManager()

    private let modelDir: URL
    private let modelFileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    private let modelURL = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    private let modelSize = "~1 GB"

    private var isDownloading = false
    private var downloadProgress: Double = 0

    enum Status {
        case ready
        case missingLlamaCli
        case missingModel
        case downloading(progress: Double)
        case error(String)
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelDir = appSupport.appendingPathComponent("SmartTile/models")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    }

    var modelPath: URL {
        modelDir.appendingPathComponent(modelFileName)
    }

    var hasModel: Bool {
        FileManager.default.fileExists(atPath: modelPath.path)
    }

    // MARK: - llama-cli detection

    func findLlamaCli() -> String? {
        let candidates = [
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
            "/opt/homebrew/bin/llama",
            "/usr/local/bin/llama"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try `which`
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["llama-cli"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func checkStatus() -> Status {
        guard findLlamaCli() != nil else { return .missingLlamaCli }
        if isDownloading { return .downloading(progress: downloadProgress) }
        guard hasModel else { return .missingModel }
        return .ready
    }

    // MARK: - Model Download

    func downloadModel(onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<Void, Error>) -> Void) {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0

        guard let url = URL(string: modelURL) else {
            isDownloading = false
            onComplete(.failure(LayoutError.apiError("Invalid model URL")))
            return
        }

        let delegate = DownloadDelegate(onProgress: { [weak self] progress in
            self?.downloadProgress = progress
            onProgress(progress)
        }, onComplete: { [weak self] tempURL, error in
            guard let self else { return }
            self.isDownloading = false

            if let error {
                onComplete(.failure(error))
                return
            }
            guard let tempURL else {
                onComplete(.failure(LayoutError.apiError("Download failed — no file")))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: self.modelPath.path) {
                    try FileManager.default.removeItem(at: self.modelPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: self.modelPath)
                onComplete(.success(()))
            } catch {
                onComplete(.failure(error))
            }
        })

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }

    // MARK: - Inference

    func runInference(prompt: String, systemPrompt: String) async throws -> String {
        guard let llamaPath = findLlamaCli() else {
            throw LayoutError.apiError("llama-cli not found. Run: brew install llama.cpp")
        }
        guard hasModel else {
            throw LayoutError.apiError("Model not downloaded yet")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: llamaPath)
            process.arguments = [
                "-m", modelPath.path,
                "-sys", systemPrompt,
                "-p", prompt,
                "-n", "1024",
                "-t", "\(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))",
                "--temp", "0.3",
                "-ngl", "99",      // offload all layers to GPU (Metal)
                "--no-display-prompt",
                "--no-conversation",
                "--single-turn"
            ]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.currentDirectoryURL = modelDir

            process.terminationHandler = { proc in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if proc.terminationStatus != 0 {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    NSLog("SmartTile: llama-cli error: %@", errStr)
                    continuation.resume(throwing: LayoutError.apiError("llama-cli failed: \(errStr.prefix(200))"))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void

    init(onProgress: @escaping (Double) -> Void, onComplete: @escaping (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete(location, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onComplete(nil, error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async { self.onProgress(progress) }
        }
    }
}
