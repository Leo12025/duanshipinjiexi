import Foundation

@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    private static let sessionIdentifier = "com.leo.shortslibrary.background"
    private let session: URLSession
    private let delegate = DownloadSessionDelegate.shared
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var activeTasks: [UUID: URLSessionTask] = [:]

    private init() {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func download(
        from url: URL,
        to destination: URL,
        resumeFromPartial: Bool = true,
        taskID: UUID = UUID(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let candidates = Self.fallbackCandidates(for: url)
        var lastError: Error?

        for (index, candidate) in candidates.enumerated() {
            do {
                try await downloadOnce(
                    from: candidate,
                    to: destination,
                    resumeFromPartial: resumeFromPartial,
                    taskID: taskID,
                    progress: progress
                )
                return
            } catch let error as AppError where index < candidates.count - 1
                        && (index == 0 || Self.isFallbackWorthy(error)) {
                lastError = error
            } catch where index == 0 && index < candidates.count - 1 {
                lastError = error
            }
        }

        throw lastError ?? AppError.badStatus(404)
    }

    private func downloadOnce(
        from url: URL,
        to destination: URL,
        resumeFromPartial: Bool,
        taskID: UUID,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let partialURL = destination.appendingPathExtension("part")
        var offset: Int64 = 0
        if resumeFromPartial,
           let attributes = try? fm.attributesOfItem(atPath: partialURL.path),
           let size = attributes[.size] as? NSNumber {
            offset = size.int64Value
        }

        func start(range: Bool) async throws -> (URL, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if let referer = self.referer(for: url) {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }
            if let cookie = await LoginSessionManager.cookieHeader(for: url) {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
            if range && offset > 0 {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            }

            let task = session.downloadTask(with: request)
            activeTasks[taskID] = task
            defer { activeTasks[taskID] = nil }
            delegate.register(
                task: task,
                destination: destination,
                partialURL: partialURL,
                baseOffset: range ? offset : 0,
                shouldRange: range,
                progress: progress
            )
            return try await withCheckedThrowingContinuation { continuation in
                delegate.setContinuation(for: task, continuation: continuation)
                task.resume()
            }
        }

        var shouldRange = offset > 0 && resumeFromPartial
        var result = try await start(range: shouldRange)

        if shouldRange, result.1.statusCode == 416 {
            try? fm.removeItem(at: partialURL)
            offset = 0
            shouldRange = false
            result = try await start(range: false)
        }

        guard (200...299).contains(result.1.statusCode) else {
            throw AppError.badStatus(result.1.statusCode)
        }
        progress?(1)
    }

    private static func isFallbackWorthy(_ error: AppError) -> Bool {
        guard case AppError.badStatus(let status) = error else { return false }
        return status == 404 || status == 403 || status >= 500
    }

    private static func fallbackCandidates(for url: URL) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ candidate: URL) {
            guard seen.insert(candidate.absoluteString).inserted else { return }
            candidates.append(candidate)
        }

        for candidate in url.protocolCandidates {
            append(candidate)

            let host = candidate.host()?.lowercased() ?? ""
            guard host.contains("douyinpic") || host.contains("byteimg") else { continue }

            let absolute = candidate.absoluteString
            let parts = absolute.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let base = String(parts.first ?? "")
            let query = parts.count > 1 ? String(parts[1]) : ""
            guard let templateRange = base.range(of: "~tplv-") else { continue }
            let originalBase = String(base[..<templateRange.lowerBound])

            func makeURL(_ candidateBase: String) -> URL? {
                let value = query.isEmpty ? candidateBase : "\(candidateBase)?\(query)"
                return URL(string: value)
            }

            if let original = makeURL(originalBase) { append(original) }
            if let object = makeURL(originalBase + "~tplv-obj.image") { append(object) }
        }

        return candidates
    }

    func cancel(taskID: UUID) {
        activeTasks[taskID]?.cancel()
    }

    private func referer(for url: URL) -> String? {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("bilibili") || host.contains("bilivideo") || host.contains("hdslb") {
            return "https://www.bilibili.com/"
        }
        if host.contains("douyin") || host.contains("iesdouyin")
            || host.contains("douyinvod") || host.contains("snssdk")
            || host.contains("ixigua") {
            return "https://www.douyin.com/"
        }
        if host.contains("kuaishou") || host.contains("chenzhongtech") || host.contains("gifshow")
            || host.contains("kwaicdn") || host.contains("kwimgs")
            || host.contains("yximgs") || host.contains("ndcimgs") {
            return "https://www.kuaishou.com/"
        }
        if host.contains("xiaohongshu") || host.contains("xhscdn") {
            return "https://www.xiaohongshu.com/"
        }
        return nil
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadSessionDelegate()

    private struct State {
        var destination: URL
        var partialURL: URL
        var baseOffset: Int64
        var shouldRange: Bool
        var progress: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
        var finished = false
    }

    private struct StoredState: Codable {
        let destination: String
        let partial: String
        let baseOffset: Int64
        let shouldRange: Bool
    }

    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private let defaults = UserDefaults.standard

    func register(
        task: URLSessionDownloadTask,
        destination: URL,
        partialURL: URL,
        baseOffset: Int64,
        shouldRange: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) {
        lock.lock()
        states[task.taskIdentifier] = State(
            destination: destination,
            partialURL: partialURL,
            baseOffset: baseOffset,
            shouldRange: shouldRange,
            progress: progress
        )
        lock.unlock()

        let stored = StoredState(
            destination: destination.absoluteString,
            partial: partialURL.absoluteString,
            baseOffset: baseOffset,
            shouldRange: shouldRange
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key(for: task.taskIdentifier))
        }
    }

    func setContinuation(
        for task: URLSessionTask,
        continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>
    ) {
        lock.lock()
        defer { lock.unlock() }
        states[task.taskIdentifier]?.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let state = state(for: downloadTask.taskIdentifier)
        guard totalBytesExpectedToWrite > 0, let state else { return }
        let total = state.baseOffset + totalBytesExpectedToWrite
        let written = state.baseOffset + totalBytesWritten
        state.progress?(Double(written) / Double(total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            finish(task: downloadTask, with: .failure(AppError.parsingFailed("无效的下载响应")))
            return
        }
        guard let state = state(for: downloadTask.taskIdentifier) else {
            finish(task: downloadTask, with: .failure(AppError.parsingFailed("下载状态丢失")))
            return
        }

        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).download")

        do {
            try FileManager.default.copyItem(at: location, to: stable)
            if (200...299).contains(response.statusCode), response.statusCode != 416 {
                try finalize(temporary: stable, response: response, state: state)
            }
            finish(task: downloadTask, with: .success((stable, response)))
        } catch {
            finish(task: downloadTask, with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(task: task, with: .failure(error))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            AppDelegate.shared?.backgroundCompletionHandler?()
            AppDelegate.shared?.backgroundCompletionHandler = nil
        }
    }

    private func finalize(temporary: URL, response: HTTPURLResponse, state: State) throws {
        let fm = FileManager.default
        if state.shouldRange, response.statusCode == 206 {
            try appendFile(at: temporary, to: state.partialURL)
            if fm.fileExists(atPath: state.destination.path) {
                try? fm.removeItem(at: state.destination)
            }
            try fm.moveItem(at: state.partialURL, to: state.destination)
        } else {
            if fm.fileExists(atPath: state.destination.path) {
                try? fm.removeItem(at: state.destination)
            }
            try? fm.removeItem(at: state.partialURL)
            try fm.moveItem(at: temporary, to: state.destination)
        }
    }

    private func appendFile(at source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.copyItem(at: source, to: destination)
            return
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        _ = try output.seekToEnd()

        while true {
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
    }

    private func state(for identifier: Int) -> State? {
        lock.lock()
        if let state = states[identifier] {
            lock.unlock()
            return state
        }
        lock.unlock()

        guard let data = defaults.data(forKey: key(for: identifier)),
              let stored = try? JSONDecoder().decode(StoredState.self, from: data),
              let destination = URL(string: stored.destination),
              let partial = URL(string: stored.partial) else { return nil }

        let restored = State(
            destination: destination,
            partialURL: partial,
            baseOffset: stored.baseOffset,
            shouldRange: stored.shouldRange
        )
        lock.lock()
        states[identifier] = restored
        lock.unlock()
        return restored
    }

    private func finish(
        task: URLSessionTask,
        with result: Result<(URL, HTTPURLResponse), Error>
    ) {
        lock.lock()
        var currentState = states[task.taskIdentifier]
        lock.unlock()

        if currentState == nil {
            currentState = state(for: task.taskIdentifier)
        }

        lock.lock()
        guard var resolved = currentState, !resolved.finished else {
            lock.unlock()
            defaults.removeObject(forKey: key(for: task.taskIdentifier))
            return
        }
        resolved.finished = true
        states[task.taskIdentifier] = nil
        lock.unlock()
        defaults.removeObject(forKey: key(for: task.taskIdentifier))

        switch result {
        case .success(let value):
            resolved.continuation?.resume(returning: value)
        case .failure(let error):
            resolved.continuation?.resume(throwing: error)
        }
    }

    private func key(for identifier: Int) -> String {
        "shorts.download.\(identifier)"
    }
}
