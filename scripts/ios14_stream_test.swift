// Concatenate with ios14_stream.swift and compile on the macOS CI host.
private final class MinisMockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "minis-backport.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/cancel" { return }
        if request.url?.path == "/failure" {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for byte in "data: 你\r\n\r\nlast\rnext\npartial".utf8 {
            client?.urlProtocol(self, didLoad: Data([byte]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct MinisStreamChecks {
    static func operation() -> MinisLegacyLineRequest {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MinisMockProtocol.self]
        return MinisLegacyLineRequest(configuration: config)
    }
    static func main() async throws {
        let (stream, response) = try await operation().start(URLRequest(url: URL(string: "https://minis-backport.invalid/lines")!))
        precondition(response.statusCode == 200)
        var received: [String] = []
        for try await line in stream { received.append(line) }
        precondition(received == ["data: 你", "", "last", "next", "partial"], "SSE line boundaries or Unicode corrupted")
        do {
            _ = try await operation().start(URLRequest(url: URL(string: "https://minis-backport.invalid/failure")!))
            preconditionFailure("Network failure did not propagate")
        } catch let error as URLError {
            precondition(error.code == .networkConnectionLost)
        }
        let pending = Task {
            try await operation().start(URLRequest(url: URL(string: "https://minis-backport.invalid/cancel")!))
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        pending.cancel()
        do {
            _ = try await pending.value
            preconditionFailure("Cancellation did not propagate")
        } catch let error as URLError {
            precondition(error.code == .cancelled)
        }
        print("PASS: fragmented Unicode, SSE line endings, transport failure and cancellation")
    }
}
