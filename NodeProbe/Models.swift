import Foundation

/// 一个待测目标
struct ProbeTarget: Identifiable, Hashable {
    let id: Int
    let name: String
    let host: String
    let url: String
    let isCN: Bool
}

/// 一次请求的采样结果
struct Sample: Identifiable {
    let id = UUID()
    let ok: Bool
    let totalMs: Double
    let dnsMs: Double?
    let tcpMs: Double?
    let tlsMs: Double?
    let ttfbMs: Double?
    let status: Int?
    let remoteIP: String?
    let proto: String?
    let errorText: String?
}

/// 一个目标的聚合结果
struct TargetResult: Identifiable {
    let target: ProbeTarget
    var samples: [Sample]

    var id: Int { target.id }

    var okSamples: [Sample] {
        samples.filter { $0.ok }
    }

    var okCount: Int { okSamples.count }

    var allFailed: Bool {
        !samples.isEmpty && okSamples.isEmpty
    }

    var minMs: Double? {
        okSamples.map { $0.totalMs }.min()
    }

    var maxMs: Double? {
        okSamples.map { $0.totalMs }.max()
    }

    var medianMs: Double? {
        let values = okSamples.map { $0.totalMs }.sorted()
        if values.isEmpty { return nil }
        return values[values.count / 2]
    }

    var jitterMs: Double? {
        guard let low = minMs, let high = maxMs else { return nil }
        return high - low
    }

    var protoName: String? {
        okSamples.compactMap { $0.proto }.first
    }
}

/// 出口 IP 回显接口
struct ExitProvider: Identifiable {
    let id: String
    let label: String
    let order: Int
    let url: String
}

/// 一次出口探测的结果
struct ExitInfo: Identifiable {
    let id: String
    let label: String
    let order: Int
    var ip: String = ""
    var geo: String = ""
    var cc: String = ""
    var ms: Double = 0
    var errorText: String?
}
