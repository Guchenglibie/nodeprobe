import SwiftUI
import UIKit

struct ContentView: View {

    @StateObject private var store = ProbeStore()
    @State private var showCopied = false

    // 配色
    private let background = Color(red: 0.031, green: 0.043, blue: 0.063)
    private let panel = Color(red: 0.067, green: 0.098, blue: 0.137)
    private let strokeColor = Color(red: 0.114, green: 0.157, blue: 0.212)
    private let dim = Color(red: 0.545, green: 0.596, blue: 0.659)
    private let dimmer = Color(red: 0.357, green: 0.408, blue: 0.471)
    private let accent = Color(red: 0.24, green: 0.86, blue: 0.59)
    private let blue = Color(red: 0.29, green: 0.66, blue: 1.0)
    private let amber = Color(red: 1.0, green: 0.69, blue: 0.18)
    private let red = Color(red: 1.0, green: 0.36, blue: 0.36)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerView
                    optionsView
                    exitView
                    summaryView
                    footerView
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .alert("已复制报告", isPresented: $showCopied) {
            Button("好", role: .cancel) { }
        }
    }

    // MARK: - 头部

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("节点 · 规则探针")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("国内直连 / 海外代理 · 出口 IP 与延迟体检")
                        .font(.system(size: 11))
                        .foregroundColor(dim)
                }
                Spacer()
                Button {
                    store.toggle()
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(store.running ? red : accent)
                        .foregroundColor(store.running ? .white : Color(red: 0.02, green: 0.09, blue: 0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(colors: [accent, blue],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(store.progress)))
                }
            }
            .frame(height: 3)

            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(dimmer)
        }
    }

    private var buttonTitle: String {
        if store.running { return "停止" }
        return store.hasFinished ? "重新测试" : "开始测试"
    }

    private var statusText: String {
        if store.running {
            return "测试中 \(min(store.done, store.total)) / \(store.total)"
        }
        if store.hasFinished {
            return "完成 · 用时 " + String(format: "%.1f", store.elapsed) + "s"
        }
        return "就绪 · \(store.targets.count) 个目标 / \(ExitCatalog.all.count) 个出口接口"
    }

    // MARK: - 参数

    private var optionsView: some View {
        panelCard {
            HStack(spacing: 14) {
                intPicker(title: "每个目标", selection: $store.samplesPerTarget, values: [1, 3, 5], suffix: " 次")
                intPicker(title: "超时", selection: $store.timeoutSeconds, values: [3, 6, 10], suffix: " 秒")
                intPicker(title: "并发", selection: $store.concurrency, values: [6, 10, 16], suffix: "")
                Spacer()
            }
        }
    }

    private func intPicker(title: String, selection: Binding<Int>, values: [Int], suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(dimmer)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)" + suffix).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.white)
        }
    }

    // MARK: - 出口 IP

    private var exitView: some View {
        panelCard {
            HStack(alignment: .firstTextBaseline) {
                Text("出口 IP")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if !store.exitSummary.isEmpty {
                    Text(store.exitSummary)
                        .font(.system(size: 11))
                        .foregroundColor(dimmer)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(store.exits) { info in
                    exitTile(info)
                }
                if store.exits.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        placeholderTile
                    }
                }
            }

            if store.verdictLines.isEmpty {
                Text(store.running ? "正在请求出口 IP 回显接口…" : "点右上角开始测试")
                    .font(.system(size: 11))
                    .foregroundColor(dimmer)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(store.verdictLines.indices, id: \.self) { index in
                        Text(store.verdictLines[index])
                            .font(.system(size: 12))
                            .foregroundColor(dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func exitTile(_ info: ExitInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(info.label)
                    .font(.system(size: 10))
                    .foregroundColor(dimmer)
                    .lineLimit(1)
                Spacer()
                Text(info.ms > 0 ? "\(Int(info.ms)) ms" : "—")
                    .font(.system(size: 10))
                    .foregroundColor(dimmer)
            }

            Text(info.ip.isEmpty ? (info.errorText ?? "—") : info.ip)
                .font(.system(size: info.ip.isEmpty ? 11 : 15,
                              weight: .bold,
                              design: .monospaced))
                .foregroundColor(info.ip.isEmpty ? red : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(info.geo.isEmpty ? " " : info.geo)
                .font(.system(size: 10))
                .foregroundColor(dim)
                .lineLimit(2)
                .frame(height: 26, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(strokeColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var placeholderTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("等待测试")
                .font(.system(size: 10))
                .foregroundColor(dimmer)
            Text("—")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(dimmer)
            Text(" ")
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(strokeColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    // MARK: - 汇总 + 列表

    private var summaryView: some View {
        panelCard {
            HStack(alignment: .firstTextBaseline) {
                Text("连通性与延迟")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(store.running || store.hasFinished ? "\(Int(store.progress * 100))%" : "")
                    .font(.system(size: 11))
                    .foregroundColor(dimmer)
            }

            HStack(spacing: 8) {
                chip(title: "国内", stats: store.cnStats)
                chip(title: "国外", stats: store.usStats)
            }

            Picker("", selection: $store.filter) {
                ForEach(ProbeStore.Filter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 0) {
                if !cnTargets.isEmpty {
                    groupHeader("🇨🇳 国内服务 · 期望直连")
                    ForEach(cnTargets) { target in
                        targetRow(target)
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
                if !usTargets.isEmpty {
                    groupHeader("🌍 国外服务 · 期望走代理")
                    ForEach(usTargets) { target in
                        targetRow(target)
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
                if cnTargets.isEmpty && usTargets.isEmpty {
                    Text("没有符合筛选条件的目标")
                        .font(.system(size: 12))
                        .foregroundColor(dimmer)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var cnTargets: [ProbeTarget] {
        store.targets.filter { matches($0) && $0.isCN }
    }

    private var usTargets: [ProbeTarget] {
        store.targets.filter { matches($0) && !$0.isCN }
    }

    private func matches(_ target: ProbeTarget) -> Bool {
        switch store.filter {
        case .all:
            return true
        case .cn:
            return target.isCN
        case .us:
            return !target.isCN
        case .fail:
            guard let result = store.results[target.id] else { return false }
            return result.allFailed
        }
    }

    private func chip(title: String, stats: ProbeStore.Stats) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(dimmer)
            Text("\(stats.ok)/\(stats.total)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            if stats.median > 0 {
                Text("· 均 \(Int(stats.median))ms")
                    .font(.system(size: 11))
                    .foregroundColor(dimmer)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(dimmer)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func targetRow(_ target: ProbeTarget) -> some View {
        let result = store.results[target.id]
        let median = result?.medianMs
        let failed = result?.allFailed ?? false
        let color: Color = failed ? red : (median.map { grade($0) } ?? strokeColor)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(target.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(target.host)
                    .font(.system(size: 10))
                    .foregroundColor(dimmer)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(failed ? "超时" : (median.map { "\(Int($0)) ms" } ?? "—"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(failed ? red.opacity(0.75) : color)
                            .frame(width: geo.size.width * fraction(median))
                    }
                }
                .frame(height: 4)

                Text(metaText(result))
                    .font(.system(size: 10))
                    .foregroundColor(dimmer)
                    .lineLimit(1)
            }
            .padding(.leading, 14)
        }
        .padding(.vertical, 7)
    }

    private func metaText(_ result: TargetResult?) -> String {
        guard let result = result, !result.samples.isEmpty else { return "未测试" }
        if result.allFailed {
            return "失败 \(result.samples.count)/\(result.samples.count)"
        }
        var parts: [String] = []
        parts.append("成功 \(result.okCount)/\(result.samples.count)")
        if let minValue = result.minMs {
            parts.append("最快 \(Int(minValue))")
        }
        if let jitter = result.jitterMs, result.okCount > 1 {
            parts.append("抖动 \(Int(jitter))")
        }
        if let status = result.okSamples.first?.status {
            parts.append("HTTP \(status)")
        }
        return parts.joined(separator: " · ")
    }

    private func fraction(_ ms: Double?) -> CGFloat {
        guard let ms = ms else { return 0 }
        let normalized = min(ms, 1500) / 1200
        return CGFloat(max(0.04, min(1.0, normalized.squareRoot())))
    }

    private func grade(_ ms: Double) -> Color {
        if ms < 120 { return accent }
        if ms < 300 { return blue }
        if ms < 600 { return amber }
        return Color(red: 1.0, green: 0.48, blue: 0.27)
    }

    // MARK: - 底部

    private var footerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.report.isEmpty {
                ShareLink(item: store.report) {
                    Label("分享 / 保存报告", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }

                Button {
                    UIPasteboard.general.string = store.report
                    showCopied = true
                } label: {
                    Text("复制报告文本")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }

            Text("所有请求由本机直接发出，不经过任何服务器。\n延迟包含 DNS / TCP / TLS 握手，首次会比后续慢。")
                .font(.system(size: 10))
                .foregroundColor(dimmer)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - 卡片容器

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(strokeColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
