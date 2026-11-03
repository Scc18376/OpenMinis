// iOS 14 URLSession line-stream backport for SwiftAnthropic 2.2.0.
import Foundation

private final class MinisLegacyLineRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Lines = AsyncThrowingStream<String, Error>
    private let configuration: URLSessionConfiguration
    private let lines: Lines
    private let output: Lines.Continuation
    private let lock = NSLock()
    private var waiter: CheckedContinuation<(Lines, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var completed = false
    // Delegate callbacks run on one serial operation queue.
    private var pending = Data()
    private var skipLF = false

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
        var continuation: Lines.Continuation!
        self.lines = Lines { continuation = $0 }
        self.output = continuation
        super.init()
        output.onTermination = { [weak self] _ in self?.cancel() }
    }

    func start(_ request: URLRequest) async throws -> (Lines, HTTPURLResponse) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if completed {
                    lock.unlock()
                    continuation.resume(throwing: URLError(.cancelled))
                    return
                }
                waiter = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.cancel() })
    }

    private func cancel() { finish(URLError(.cancelled), cancelTask: true) }

    private func finish(_ error: Error?, cancelTask: Bool = false) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let waiter = self.waiter
        self.waiter = nil
        let session = self.session
        let task = self.task
        self.session = nil
        self.task = nil
        lock.unlock()
        // Finishing may synchronously invoke onTermination: never hold the lock.
        waiter?.resume(throwing: error ?? URLError(.badServerResponse))
        if let error { output.finish(throwing: error) }
        else { output.finish() }
        if cancelTask {
            task?.cancel()
            session?.invalidateAndCancel()
        } else {
            session?.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(URLError(.badServerResponse), cancelTask: true)
            return
        }
        lock.lock()
        let stopped = completed
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        guard !stopped else { completionHandler(.cancel); return }
        waiter?.resume(returning: (lines, response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for byte in data {
            if skipLF {
                skipLF = false
                if byte == 10 { continue }
            }
            if byte == 10 || byte == 13 {
                output.yield(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
                skipLF = byte == 13
            } else {
                pending.append(byte)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil && !pending.isEmpty {
            output.yield(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        finish(error)
    }
}
