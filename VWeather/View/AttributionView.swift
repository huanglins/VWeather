//
//  AttributionView.swift
//  VWeather
//
//  数据来源归因。
//
//  ⚠️ 合规：Apple 对 WeatherKit 的要求（https://developer.apple.com/weatherkit/get-started/）：
//  「If your apps ... display any weather data from Apple ... you must clearly display the
//   Apple Weather trademark, as well as the legal link to other data sources.」
//  即**商标**与**其他数据来源的法律链接**两者都必须展示，缺一不可。
//  商标图片不能自己画，必须用 `WeatherAttribution` 给的 mark URL；链接用其 `legalPageURL`。
//
//  和风天气（补充数据来源）按其品牌规范注明即可，不强制用图标。
//

import SwiftUI
import WeatherKit

/// WeatherKit 归因信息的加载与缓存。
///
/// 归因要走一次网络，且全 App 共用同一份、内容不随城市变化，故取一次就够。
/// 单例 + 主线程发布，避免每个页面各自去拉。
@MainActor
final class WeatherAttributionStore: ObservableObject {
    static let shared = WeatherAttributionStore()

    @Published private(set) var attribution: WeatherAttribution?

    private var loading = false

    /// Apple 要求中直接给出的「其他数据来源」页面。
    /// 仅在归因接口取不到时兜底：合规要求的是链接必须在，不能因为离线就整个不显示。
    static let fallbackLegalURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!

    func load() async {
        guard attribution == nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            attribution = try await VHLAppleWeather.shared.getAttribution()
        } catch {
            // 取不到就用兜底链接的纯文字版，不阻塞页面
            print("[Attribution] 获取归因失败：\(error.localizedDescription)")
        }
    }
}

/// Apple Weather 商标 + 「其他数据来源」链接。
///
/// 合规要求商标与链接同时出现，故做成一个整体：整行可点，点进 `legalPageURL`。
/// 拿不到商标图时降级为文字 "Apple Weather"——宁可少个图，也不能连链接一起没了。
struct AppleWeatherAttribution: View {
    @StateObject private var store = WeatherAttributionStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    /// 商标高度。Apple 未规定具体尺寸，取与正文相称且清晰可辨的大小。
    var markHeight: CGFloat = 16

    private var markURL: URL? {
        guard let attribution = store.attribution else { return nil }
        // dark / light 两个变体分别对应深色与浅色背景
        return colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL
    }

    private var legalURL: URL {
        store.attribution?.legalPageURL ?? WeatherAttributionStore.fallbackLegalURL
    }

    var body: some View {
        // 用 Button + openURL 而非 Link：Link 在 List 行里点不动（实测无响应），
        // 且整行自定义排版本就更适合 Button。
        Button {
            openURL(legalURL)
        } label: {
            HStack(spacing: 8) {
                if let markURL {
                    AsyncImage(url: markURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(height: markHeight)
                } else {
                    Text("Apple Weather")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("其他数据来源")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await store.load() }
    }
}
