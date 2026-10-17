import Foundation

/// 测试编排：负责并发调度、进度、汇总与报告
@MainActor
final class ProbeStore: ObservableObject {

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case cn = "国内"
        case us = "国外"
        case fail = "失败"

        var id: String { rawValue }
    }

    struct Stats {
        var ok: Int
        var total: Int
        var median: Double
    }

    @Published var results: [Int: TargetResult] = [:]
    @Published var exits: [ExitInfo] = []
    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var elapsed: Double = 0
    @Published var report = ""
    @Published var verdictLines: [String] = []
    @Published var filter: Filter = .all
    @Published var samplesPerTarget = 3
    @Published var timeoutSeconds = 6
    @Published var concurrency = 10

    let targets = TargetCatalog.all

    private var runTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    /// 每次开始/停止都 +1，旧一轮的循环发现自己的编号过期就退出
    private var runId = 0

    var progress: Double {
        total > 0 ? min(1.0, Double(done) / Double(total)) : 0
    }

    var hasFinished: Bool {
        !running && !report.isEmpty
    }

    // MARK: - 控制

    func toggle() {
        if running {
            stop()
            return
        }
        runId += 1
        let id = runId
        runTask = Task { await self.runAll(id) }
    }

    func stop() {
        runId += 1
        runTask?.cancel()
        runTask = nil
        NetProbe.shared.cancelAll()
        running = false
    }

    // MARK: - 主流程

    private func runAll(_ id: Int) async {
        if id != runId { return }

        running = true
        done = 0
        results = [:]
        exits = []
        verdictLines = []
        report = ""
        elapsed = 0
        total = targets.count + ExitCatalog.all.count

        let startedAt = Date()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        let exitJob = Task { await self.runExits(id) }
        let targetJob = Task { await self.runTargets(id) }
        _ = await exitJob.value
        _ = await targetJob.value

        ticker?.cancel()
        ticker = nil

        if id != runId { return }   // 被停止或新一轮取代，不要覆盖新结果

        running = false
        elapsed = Date().timeIntervalSince(startedAt)
        exits.sort { $0.order < $1.order }
        updateVerdict()
        report = makeReport()
    }

    private func runTargets(_ id: Int) async {
        let list = targets
        let batch = max(1, concurrency)
        var index = 0

        while index < list.count {
            if id != runId { return }
            let end = min(index + batch, list.count)
            let slice = Array(list[index..<end])
            index = end

            var jobs: [Task<Void, Never>] = []
            for target in slice {
                jobs.append(Task { await self.probeTarget(target, id) })
            }
            for job in jobs {
                _ = await job.value
            }
        }
    }

    private func probeTarget(_ target: ProbeTarget, _ id: Int) async {
        var list: [Sample] = []
        var failures = 0
        let need = max(1, samplesPerTarget)

        for attempt in 0..<need {
            if id != runId { break }
            let (sample, _) = await NetProbe.shared.request(target.url, timeout: Double(timeoutSeconds))
            if id != runId { break }
            list.append(sample)
            if !sample.ok { failures += 1 }
            results[target.id] = TargetResult(target: target, samples: list)

            if failures >= 2 && attempt + 1 < need { break }
            if attempt + 1 < need && sample.ok {
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }

        if id == runId {
            done += 1
        }
    }

    private func runExits(_ id: Int) async {
        var jobs: [Task<Void, Never>] = []
        for provider in ExitCatalog.all {
            jobs.append(Task { await self.probeExit(provider, id) })
        }
        for job in jobs {
            _ = await job.value
        }
        if id == runId {
            exits.sort { $0.order < $1.order }
        }
    }

    private func probeExit(_ provider: ExitProvider, _ id: Int) async {
        if id != runId { return }

        let (sample, data) = await NetProbe.shared.request(provider.url, timeout: 10)
        if id != runId { return }

        var info = ExitInfo(id: provider.id, label: provider.label, order: provider.order)
        info.ms = sample.ok ? sample.totalMs : 0

        if sample.ok, let parsed = ExitParser.parse(provider: provider, data: data) {
            info.ip = parsed.ip
            info.geo = parsed.geo
            info.cc = parsed.cc
        } else {
            info.errorText = sample.errorText ?? "不可读"
        }

        exits.append(info)
        done += 1
    }

    // MARK: - 汇总

    private func updateVerdict() {
        let valid = exits.filter { !$0.ip.isEmpty }
        guard !valid.isEmpty else {
            verdictLines = ["没有取到任何出口 IP：可能回显接口都被拦截，或网络还没连上。"]
            return
        }

        var unique: [String] = []
        for item in valid where !unique.contains(item.ip) {
            unique.append(item.ip)
        }

        let cn = valid.filter { $0.cc == "CN" }
        let overseas = valid.filter { !$0.cc.isEmpty && $0.cc != "CN" }
        var lines: [String] = []

        if let first = cn.first {
            let place = first.geo.isEmpty ? "中国大陆" : first.geo
            lines.append("国内出口：" + place + " · " + first.ip)
        } else {
            lines.append("国内出口：没有取到中国大陆 IP")
        }

        if let first = overseas.first {
            let place = first.geo.isEmpty ? first.cc : first.geo
            lines.append("海外出口：" + place + " · " + first.ip)
        } else {
            lines.append("海外出口：没有取到海外 IP（直连被墙，或节点有问题）")
        }

        if !cn.isEmpty && !overseas.isEmpty {
            lines.append("判定：✅ 国内与海外用了不同出口，分流规则生效")
        } else if unique.count == 1 {
            lines.append("判定：⚠️ 只有一个出口 IP，规则没有分流（全局代理或全局直连）")
        } else if !cn.isEmpty {
            lines.append("判定：⚠️ 只测到国内出口，海外链路没验证到")
        } else {
            lines.append("判定：⚠️ 只测到海外出口，国内链路没验证到")
        }

        verdictLines = lines
    }

    var cnStats: Stats { makeStats(cn: true) }
    var usStats: Stats { makeStats(cn: false) }

    private func makeStats(cn: Bool) -> Stats {
        let group = targets.filter { $0.isCN == cn }
        var ok = 0
        var medians: [Double] = []
        for target in group {
            guard let result = results[target.id], let median = result.medianMs else { continue }
            ok += 1
            medians.append(median)
        }
        let average = medians.isEmpty ? 0 : medians.reduce(0, +) / Double(medians.count)
        return Stats(ok: ok, total: group.count, median: average)
    }

    var exitSummary: String {
        let valid = exits.filter { !$0.ip.isEmpty }
        var unique: [String] = []
        for item in valid where !unique.contains(item.ip) {
            unique.append(item.ip)
        }
        return unique.isEmpty ? "" : "\(unique.count) 个出口"
    }

    // MARK: - 报告

    private func makeReport() -> String {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("节点 · 规则探针报告")
        lines.append("时间: " + formatter.string(from: Date()))
        lines.append("")
        lines.append("== 出口 IP ==")
        if exits.isEmpty {
            lines.append("（无数据）")
        }
        for item in exits.sorted(by: { $0.order < $1.order }) {
            let ip = item.ip.isEmpty ? "-" : item.ip
            lines.append(pad(item.label, 18) + pad(ip, 18) + item.geo + "  [" + "\(Int(item.ms))ms]")
        }
        lines.append("")
        lines.append("== 目标延迟（中位数 / 成功次数 / 协议）==")
        for target in targets {
            guard let result = results[target.id] else { continue }
            let tag = target.isCN ? "[国内] " : "[国外] "
            let value = result.medianMs.map { "\(Int($0))ms" } ?? "FAIL"
            var extra = ""
            if let status = result.okSamples.first?.status {
                extra += " HTTP \(status)"
            }
            if let proto = result.protoName {
                extra += " " + proto
            }
            lines.append(tag + pad(target.name, 14) + pad(target.host, 26)
                         + pad(value, 9) + "\(result.okCount)/\(result.samples.count)" + extra)
        }
        lines.append("")
        lines.append("== 判定 ==")
        lines.append(contentsOf: verdictLines)
        return lines.joined(separator: "\n")
    }

    private func pad(_ text: String, _ width: Int) -> String {
        var display = 0
        for scalar in text.unicodeScalars {
            display += scalar.value > 0x2E80 ? 2 : 1
        }
        var result = text
        while display < width {
            result += " "
            display += 1
        }
        return result
    }
}
