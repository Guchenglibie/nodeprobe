# 节点 · 规则探针（NodeProbe）

一个原生 iOS App：测你自己的节点和分流规则到底有没有生效。

- **出口 IP**：6 个回显接口（国内 ipip.net + ipwho.is / ip.sb / ipify / ipinfo.io / Cloudflare）。规则正确时，国内接口显示大陆 IP、海外接口显示落地节点 IP；全都一样说明没分流。
- **延迟**：45 个国内外服务，每个采样 1/3/5 次，给中位数、最快、抖动、成功数；失败标红。
- **分段耗时**：原生实现独有的 DNS / TCP / TLS / TTFB 拆解（`URLSessionTaskMetrics`），网页版做不到。
- **判定**：底部直接给「分流生效 / 只有一个出口 / 只测到国内或海外」的结论。
- **导出**：分享或复制文本报告。

## 目录

```
NodeProbe/
├── NodeProbe.xcodeproj/     # 已生成好的 Xcode 工程，可直接打开
├── NodeProbe/               # Swift 源码
│   ├── NodeProbeApp.swift
│   ├── ContentView.swift    # 界面（SwiftUI）
│   ├── Models.swift         # 数据模型
│   ├── NetProbe.swift       # URLSession 探测 + 指标拆解 + 出口 IP 解析
│   ├── ProbeStore.swift     # 并发调度、汇总、报告
│   ├── Targets.swift        # 45 个目标清单 + 6 个回显接口
│   └── Assets.xcassets      # 图标 / 主题色
├── project.yml              # XcodeGen 配置（备用，重建工程用）
├── build-ipa.sh             # macOS 上一键出未签名 IPA
└── .github/workflows/build-ipa.yml   # 云端出 IPA（不需要 Mac）
```

最低支持 iOS 16，Swift 5 语言模式。需要 **Xcode 15 或更新**（CI 用的 `macos-14` 自带 Xcode 15/16）。

## 方式一：GitHub 云端编译（没有 Mac 就用这个）

1. 新建一个空仓库，把 **NodeProbe 这个目录**整个传上去（`.github` 也要，它是隐藏目录）。
2. 打开仓库 → Actions → 左侧 `Build unsigned IPA` → `Run workflow`。
3. 等 3~5 分钟，进入这次运行，在页面底部 **Artifacts** 下载 `NodeProbe-unsigned-ipa`，解压得到 `NodeProbe-unsigned.ipa`。
4. 用你自己的方式签名安装（TrollStore / Esign / Sideloadly / 证书重签都行）。

> 产物是**未签名** IPA，这正是自签工具需要的形态。CI 不碰签名，也不需要 Apple 账号或证书。

## 方式二：有 Mac

```bash
cd NodeProbe
chmod +x build-ipa.sh
./build-ipa.sh
```

得到 `NodeProbe-unsigned.ipa`。

或者直接用 Xcode 打开 `NodeProbe.xcodeproj`，Signing & Capabilities 里选自己的 Team，连真机 ⌘R 直接跑。

## 装不上 / 想改

- **改 Bundle ID**：`project.pbxproj` 里搜 `com.example.nodeprobe` 全部替换；或在 Xcode 的 Signing 面板里改。用 TrollStore 装可以不改。
- **改应用名**：`INFOPLIST_KEY_CFBundleDisplayName`（现在是「节点探针」）。
- **改测试清单**：编辑 `NodeProbe/Targets.swift`，加一行即可，界面和报告会自动带上。
- **改回显接口**：同上文件的 `ExitCatalog`。

## 怎么读结果

| 现象 | 含义 |
|---|---|
| 国内接口 = 大陆 IP，海外接口 = 境外 IP | 分流生效 ✅ |
| 所有接口同一个 IP | 全局代理或全局直连，规则没生效 ⚠️ |
| 海外接口全部「不可读 / 超时」 | 海外没走代理（或节点挂了） |
| 国内接口是境外 IP | 国内流量也被代理了，规则方向反了 |

延迟数值是**完整请求耗时**（含 DNS/TCP/TLS），首次会比后续慢；判断节点质量看「最快」和「抖动」，判断是否被墙看成功数。

## 说明

- App 只发 HTTPS 请求，不加任何分析、不上报、不经过第三方服务器。
- 测的是 HTTP(S) 往返，不是 ICMP ping；也测不了 UDP/QUIC、真实丢包率、DNS 泄漏。
- 跨域限制在这里不存在（原生请求），所以能读到真实 HTTP 状态码和响应体。
