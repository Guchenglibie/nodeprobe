import Foundation

/// 测试目标清单：国内走直连，国外走代理
enum TargetCatalog {
    static let all: [ProbeTarget] = {
        // name, host, url, isCN
        let raw: [(String, String, String, Bool)] = [
            ("微信",       "weixin.qq.com",         "https://weixin.qq.com/",                   true),
            ("QQ",         "www.qq.com",            "https://www.qq.com/robots.txt",            true),
            ("百度",       "www.baidu.com",         "https://www.baidu.com/robots.txt",         true),
            ("淘宝",       "www.taobao.com",        "https://www.taobao.com/robots.txt",        true),
            ("京东",       "www.jd.com",            "https://www.jd.com/robots.txt",            true),
            ("支付宝",     "www.alipay.com",        "https://www.alipay.com/robots.txt",        true),
            ("哔哩哔哩",   "www.bilibili.com",      "https://www.bilibili.com/robots.txt",      true),
            ("抖音",       "www.douyin.com",        "https://www.douyin.com/favicon.ico",       true),
            ("小红书",     "www.xiaohongshu.com",   "https://www.xiaohongshu.com/favicon.ico",  true),
            ("知乎",       "www.zhihu.com",         "https://www.zhihu.com/robots.txt",         true),
            ("微博",       "weibo.com",             "https://weibo.com/robots.txt",             true),
            ("美团",       "www.meituan.com",       "https://www.meituan.com/robots.txt",       true),
            ("拼多多",     "www.pinduoduo.com",     "https://www.pinduoduo.com/robots.txt",     true),
            ("网易云音乐", "music.163.com",         "https://music.163.com/robots.txt",         true),
            ("12306",      "www.12306.cn",          "https://www.12306.cn/index/",              true),
            ("爱奇艺",     "www.iqiyi.com",         "https://www.iqiyi.com/robots.txt",         true),
            ("阿里云",     "www.aliyun.com",        "https://www.aliyun.com/robots.txt",        true),
            ("高德地图",   "www.amap.com",          "https://www.amap.com/",                    true),
            ("中国政府网", "www.gov.cn",            "https://www.gov.cn/robots.txt",            true),

            ("Google",      "www.google.com",        "https://www.google.com/generate_204",      false),
            ("YouTube",     "www.youtube.com",       "https://www.youtube.com/generate_204",     false),
            ("ChatGPT",     "chatgpt.com",           "https://chatgpt.com/favicon.ico",          false),
            ("OpenAI API",  "api.openai.com",        "https://api.openai.com/v1/models",         false),
            ("Claude",      "claude.ai",             "https://claude.ai/favicon.ico",            false),
            ("Gemini",      "gemini.google.com",     "https://gemini.google.com/favicon.ico",    false),
            ("GitHub",      "github.com",            "https://github.com/robots.txt",            false),
            ("Cloudflare",  "www.cloudflare.com",    "https://www.cloudflare.com/cdn-cgi/trace", false),
            ("X / Twitter", "x.com",                 "https://x.com/favicon.ico",                false),
            ("Facebook",    "www.facebook.com",      "https://www.facebook.com/robots.txt",      false),
            ("Instagram",   "www.instagram.com",     "https://www.instagram.com/robots.txt",     false),
            ("Telegram",    "telegram.org",          "https://telegram.org/robots.txt",          false),
            ("WhatsApp",    "web.whatsapp.com",      "https://web.whatsapp.com/favicon.ico",     false),
            ("Wikipedia",   "www.wikipedia.org",     "https://www.wikipedia.org/robots.txt",     false),
            ("Apple",       "www.apple.com",         "https://www.apple.com/robots.txt",         false),
            ("Microsoft",   "www.microsoft.com",     "https://www.microsoft.com/robots.txt",     false),
            ("Steam",       "store.steampowered.com", "https://store.steampowered.com/robots.txt", false),
            ("Spotify",     "open.spotify.com",      "https://open.spotify.com/robots.txt",      false),
            ("Discord",     "discord.com",           "https://discord.com/robots.txt",           false),
            ("Twitch",      "www.twitch.tv",         "https://www.twitch.tv/robots.txt",         false),
            ("Netflix",     "www.netflix.com",       "https://www.netflix.com/robots.txt",       false),
            ("Amazon",      "www.amazon.com",        "https://www.amazon.com/robots.txt",        false),
            ("Reddit",      "www.reddit.com",        "https://www.reddit.com/robots.txt",        false),
            ("TikTok",      "www.tiktok.com",        "https://www.tiktok.com/robots.txt",        false),
            ("HuggingFace", "huggingface.co",        "https://huggingface.co/robots.txt",        false),
            ("Speedtest",   "www.speedtest.net",     "https://www.speedtest.net/favicon.ico",    false)
        ]

        return raw.enumerated().map { pair in
            let item = pair.element
            return ProbeTarget(id: pair.offset,
                               name: item.0,
                               host: item.1,
                               url: item.2,
                               isCN: item.3)
        }
    }()

    static var cnCount: Int { all.filter { $0.isCN }.count }
    static var usCount: Int { all.filter { !$0.isCN }.count }
}

/// 出口 IP 回显接口
enum ExitCatalog {
    static let all: [ExitProvider] = [
        ExitProvider(id: "ipip",   label: "ipip.net · 国内", order: 0, url: "https://myip.ipip.net/"),
        ExitProvider(id: "ipwho",  label: "ipwho.is",        order: 1, url: "https://ipwho.is/"),
        ExitProvider(id: "ipsb",   label: "ip.sb",           order: 2, url: "https://api.ip.sb/geoip"),
        ExitProvider(id: "ipify",  label: "ipify",           order: 3, url: "https://api.ipify.org?format=json"),
        ExitProvider(id: "ipinfo", label: "ipinfo.io",       order: 4, url: "https://ipinfo.io/json"),
        ExitProvider(id: "cf",     label: "Cloudflare",      order: 5, url: "https://www.cloudflare.com/cdn-cgi/trace")
    ]
}
