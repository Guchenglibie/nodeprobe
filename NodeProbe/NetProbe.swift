import Foundation

/// 原生探测核心：用 URLSession 直接发请求，并从 URLSessionTaskMetrics 里
/// 拆出 DNS / TCP / TLS / TTFB 各段耗时（网页版做不到这件事）。
final class NetProbe: NSObject, URLSessionDataDelegate {

    static let shared = NetProbe()

    private struct Pending {
        let continuation: CheckedContinuation<(Sample, Data), Never>
        let startedAt: Date
        var status: Int?
        var body: Data
        var metrics: URLSessionTaskMetrics?
        var error: Error?
        var completed: Bool
    }

    private var pending: [Int: Pending] = [:]
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// 停止测试时把在途请求全部掐掉
    func cancelAll() {
        session.getAllTasks { tasks in
            for task in tasks {
                task.cancel()
            }
        }
    }

    /// 发一个请求，返回采样数据（含响应体，供出口 IP 解析用）
    func request(_ urlString: String, timeout: TimeInterval) async -> (Sample, Data) {
        guard let url = URL(string: urlString) else {
            let sample = Sample(ok: false, totalMs: 0, dnsMs: nil, tcpMs: nil, tlsMs: nil,
                                ttfbMs: nil, status: nil, remoteIP: nil, proto: nil,
                                errorText: "URL 无效")
            return (sample, Data())
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = max(2, timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NodeProbe/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let task = session.dataTask(with: request)
        let key = task.taskIdentifier
        let start = Date()

        return await withCheckedContinuation { continuation in
            lock.lock()
            pending[key] = Pending(continuation: continuation,
                                   startedAt: start,
                                   status: nil,
                                   body: Data(),
                                   metrics: nil,
                                   error: nil,
                                   completed: false)
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - URLSession delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        if var item = pending[task.taskIdentifier] {
            item.metrics = metrics
            pending[task.taskIdentifier] = item
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        if var item = pending[dataTask.taskIdentifier] {
            item.status = (response as? HTTPURLResponse)?.statusCode
            pending[dataTask.taskIdentifier] = item
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if var item = pending[dataTask.taskIdentifier], item.body.count < 262_144 {
            item.body.append(data)
            pending[dataTask.taskIdentifier] = item
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let key = task.taskIdentifier
        var ready = false

        lock.lock()
        if var item = pending[key] {
            item.error = error
            item.completed = true
            ready = (item.metrics != nil) || (error != nil)
            pending[key] = item
        }
        lock.unlock()

        if ready {
            finish(key)
        } else {
            // 极少数情况下 metrics 比 didComplete 晚到，等一小会儿再收尾
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.finish(key)
            }
        }
    }

    private func finish(_ key: Int) {
        lock.lock()
        guard let item = pending[key], item.completed else {
            lock.unlock()
            return
        }
        pending.removeValue(forKey: key)
        lock.unlock()

        let sample = makeSample(item)
        item.continuation.resume(returning: (sample, item.body))
    }

    // MARK: - 结果加工

    private func makeSample(_ item: Pending) -> Sample {
        let total = Date().timeIntervalSince(item.startedAt) * 1000

        var dns: Double?
        var tcp: Double?
        var tls: Double?
        var ttfb: Double?
        var remote: String?
        var proto: String?

        if let metrics = item.metrics, let last = metrics.transactionMetrics.last {
            dns = span(last.domainLookupStartDate, last.domainLookupEndDate)
            tcp = span(last.connectStartDate, last.connectEndDate)
            tls = span(last.secureConnectionStartDate, last.secureConnectionEndDate)
            ttfb = span(last.requestStartDate, last.responseStartDate)
            remote = last.remoteAddress
            proto = last.networkProtocolName
        }

        if let error = item.error {
            return Sample(ok: false, totalMs: total, dnsMs: dns, tcpMs: tcp, tlsMs: tls,
                          ttfbMs: ttfb, status: item.status, remoteIP: remote, proto: proto,
                          errorText: describe(error))
        }

        guard let status = item.status else {
            return Sample(ok: false, totalMs: total, dnsMs: dns, tcpMs: tcp, tlsMs: tls,
                          ttfbMs: ttfb, status: nil, remoteIP: remote, proto: proto,
                          errorText: "没有响应")
        }

        return Sample(ok: true, totalMs: total, dnsMs: dns, tcpMs: tcp, tlsMs: tls,
                      ttfbMs: ttfb, status: status, remoteIP: remote, proto: proto,
                      errorText: nil)
    }

    private func span(_ from: Date?, _ to: Date?) -> Double? {
        guard let from = from, let to = to else { return nil }
        let value = to.timeIntervalSince(from) * 1000
        return value >= 0 ? value : nil
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return ns.localizedDescription }
        switch ns.code {
        case NSURLErrorTimedOut:                 return "超时"
        case NSURLErrorCannotFindHost:           return "DNS 解析失败"
        case NSURLErrorDNSLookupFailed:          return "DNS 解析失败"
        case NSURLErrorCannotConnectToHost:      return "连接被拒绝"
        case NSURLErrorNetworkConnectionLost:    return "连接被重置"
        case NSURLErrorNotConnectedToInternet:   return "无网络"
        case NSURLErrorSecureConnectionFailed:   return "TLS 握手失败"
        case NSURLErrorServerCertificateUntrusted: return "证书不受信任"
        case NSURLErrorCancelled:                return "已取消"
        case NSURLErrorBadURL:                   return "URL 无效"
        default:                                 return "错误 \(ns.code)"
        }
    }
}

// MARK: - 出口 IP 解析

struct ExitRecord {
    let ip: String
    let geo: String
    let cc: String
}

enum ExitParser {

    static func parse(provider: ExitProvider, data: Data) -> ExitRecord? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        if provider.id == "ipip" {
            return parseChinese(text)
        }
        if provider.id == "cf" {
            return parseTrace(text)
        }
        return parseJSON(text)
    }

    private static func parseChinese(_ text: String) -> ExitRecord? {
        guard let ip = firstIPv4(text) else { return nil }
        var geo = ""
        if let range = text.range(of: "来自于") {
            geo = String(text[range.upperBound...])
        } else if let range = text.range(of: "来自") {
            geo = String(text[range.upperBound...])
        }
        geo = geo.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,\r\n\t"))
        while geo.contains("  ") {
            geo = geo.replacingOccurrences(of: "  ", with: " ")
        }
        let lowered = geo.lowercased()
        let cc = (geo.contains("中国") || lowered.contains("china")) ? "CN" : ""
        return ExitRecord(ip: ip, geo: geo, cc: cc)
    }

    private static func parseTrace(_ text: String) -> ExitRecord? {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let index = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<index])
            let value = String(line[line.index(after: index)...])
            map[key] = value
        }
        guard let ip = map["ip"], !ip.isEmpty else { return nil }
        let loc = map["loc"] ?? ""
        let colo = map["colo"] ?? ""
        var parts: [String] = []
        if !loc.isEmpty { parts.append(loc) }
        if !colo.isEmpty { parts.append("colo " + colo) }
        return ExitRecord(ip: ip, geo: parts.joined(separator: " · "), cc: loc)
    }

    private static func parseJSON(_ text: String) -> ExitRecord? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else { return nil }

        guard let ip = dict["ip"] as? String, !ip.isEmpty else { return nil }

        var cc = ""
        if let value = dict["country_code"] as? String {
            cc = value.uppercased()
        } else if let value = dict["country"] as? String, value.count == 2 {
            cc = value.uppercased()
        } else if let value = dict["cc"] as? String {
            cc = value.uppercased()
        }

        var parts: [String] = []
        if let value = dict["country"] as? String { parts.append(value) }
        if let value = dict["region"] as? String { parts.append(value) }
        if let value = dict["city"] as? String { parts.append(value) }

        if let value = dict["isp"] as? String {
            parts.append(value)
        } else if let value = dict["org"] as? String {
            parts.append(value)
        } else if let connection = dict["connection"] as? [String: Any],
                  let value = connection["isp"] as? String {
            parts.append(value)
        }

        return ExitRecord(ip: ip, geo: dedupe(parts).joined(separator: " · "), cc: cc)
    }

    private static func firstIPv4(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\d{1,3}(?:\\.\\d{1,3}){3}") else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: full),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var result: [String] = []
        for item in items where !item.isEmpty && !result.contains(item) {
            result.append(item)
        }
        return result
    }
}
