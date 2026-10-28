import Foundation

/// A serial delegate queue owns response bytes; completion and cancellation run on main.
final class ArtworkDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let byteLimit = 30 * 1024 * 1024
    private var completion: ((Result<Data, Error>) -> Void)?
    private var data = Data()
    private var session: URLSession!

    init(url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        super.init()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        session.dataTask(with: url).resume()
    }

    func cancel() {
        completion = nil
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(BootleggerError.message("Image download failed (HTTP \(http.statusCode)).")))
            completionHandler(.cancel)
        } else if response.expectedContentLength > Self.byteLimit {
            finish(.failure(BootleggerError.message("Choose an image smaller than 30 MB.")))
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= Self.byteLimit else {
            finish(.failure(BootleggerError.message("Choose an image smaller than 30 MB.")))
            dataTask.cancel()
            return
        }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error.map { .failure($0) } ?? .success(data))
    }

    private func finish(_ result: Result<Data, Error>) {
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async {
            guard let completion = self.completion else { return }
            self.completion = nil
            completion(result)
        }
    }
}
