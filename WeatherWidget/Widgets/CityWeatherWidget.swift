//
//  CityWeatherWidget.swift
//  WeatherWidget
//
//  中号小组件：一个城市的概览，样式与 App 里的城市列表卡一致
//  （共用 CityWeatherCardContent 与 WeatherPalette，不是照着描的）。
//
//  城市由小组件配置指定（长按 → 编辑）。选定后就认这个城市，**不跟随 App 的选中项** ——
//  否则「配置」就没意义了。用户想要跟随的话，把 App 的选中城市和小组件配成同一个即可。
//

import SwiftUI
import WidgetKit

struct CityWeatherEntry: TimelineEntry {
    let date: Date
    var title: String = "--"
    var isCurrentLocation: Bool = false
    var report: WeatherReport? = nil
    var isNight: Bool = false
    /// 没有可显示的城市（一个都没添加，或配置指向的城市已被删除）
    var missing: Bool = false
    /// 该卡片对应城市的主键，供点击深链把首页切到这座城市（缺失态为 nil）。
    var cityKey: String? = nil

    var condition: VWCondition { report?.now?.condition ?? .unknown }
}

struct CityWeatherProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> CityWeatherEntry {
        CityWeatherEntry(date: Date(), title: "城市")
    }

    /// 组件库预览与快照：只读缓存，不发请求 —— 这两处要求立刻返回。
    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> CityWeatherEntry {
        guard let city = resolveCity(configuration) else {
            return CityWeatherEntry(date: Date(), missing: true)
        }
        return entry(city, CityWeatherManager.manager.cachedSnapshot(for: city))
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<CityWeatherEntry> {
        guard let city = resolveCity(configuration) else {
            // 没城市可显示时也要给个时间线，否则组件会一直卡在占位态。
            // 隔久一点再看 —— 用户去 App 加城市这件事，不值得频繁轮询。
            return Timeline(entries: [CityWeatherEntry(date: Date(), missing: true)],
                            policy: .after(Date().addingTimeInterval(60 * 60)))
        }

        // 与主 App 共享节流（30 分钟）与缓存，不会因为多一个小组件就多打上游
        let snap = await CityWeatherManager.manager.refresh(for: city)
        let e = entry(city, snap)

        // 30 分钟后再刷。给一条 entry 即可 —— 卡片上没有随时间变化的内容，
        // 排 48 条只是让系统白存一堆一模一样的快照。
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    /// 决定显示哪个城市。
    ///
    /// 三种情况：
    ///   · 配置选了「当前位置」（存哨兵）→ 查当下的当前位置城市，坐标随便变都跟得上
    ///   · 配置选了具体城市（存 cityKey）→ 按 cityKey 查；查不到（被删）→ 返回 nil 显示缺失
    ///   · 未配置（cityKey 为空）→ 回退到当前位置，其次 App 选中的
    private func resolveCity(_ configuration: SelectCityIntent) -> CityModel? {
        _ = DBManager.manager          // 小组件进程里初始化共享库

        if let key = configuration.cityKey {
            // 「当前位置」：不锁坐标，查实时的那条 —— 用户移动后当前位置城市的
            // cityKey 会变，这里跟着最新的走。
            if key == kWidgetCurrentLocation {
                return currentLocationCity()
            }
            // 具体城市：按 cityKey 查。查不到就返回 nil（显示缺失），不静默回退成别的城市。
            // 不加 isDeleted != 1：isDeleted 为 NULL 时该条件在 SQL 里是 NULL 而非 true，
            // 整行会被漏掉。与 CityManager.allCities 一致，改在 Swift 侧判。
            return CityModel.objects(whereSQL: "cityKey = ?", params: [key])
                .first { $0.isDeleted != true }
        }
        // 未配置：优先当前位置，其次 App 选中的。
        return currentLocationCity() ?? CityWeatherManager.manager.selectedCity()
    }

    /// 当下的「当前位置」城市（坐标可能已随移动而变，这里取最新的那条）。
    private func currentLocationCity() -> CityModel? {
        CityModel.objects(order: .ASC("sortOrder"))
            .first { $0.isCurrentLocation == true && $0.isDeleted != true }
    }

    private func entry(_ city: CityModel, _ snapshot: CityWeatherSnapshot?) -> CityWeatherEntry {
        let report = snapshot?.weather
        return CityWeatherEntry(
            date: Date(),
            title: city.displayName,
            isCurrentLocation: city.isCurrentLocation == true,
            report: report,
            // 日出日落取自报告本身，与 App 首页同源
            isNight: report?.isNight(at: Date()) ?? false,
            cityKey: city.cityKey
        )
    }
}

/// 小组件 → App 的深链。点卡片打开 App 后，首页切到这座城市。
/// ⚠️ scheme/host 与主 App 的 SceneDelegate 深链解析保持一致（跨 target，两处各存一份字面量）。
enum WidgetDeepLink {
    static let scheme = "vweather"
    static let host = "city"
    static let keyItem = "key"

    static func url(cityKey: String?) -> URL? {
        guard let cityKey else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        // URLComponents 会对坐标串里的逗号等做百分号编码，App 侧读 queryItems 时自动解回。
        c.queryItems = [URLQueryItem(name: keyItem, value: cityKey)]
        return c.url
    }
}

struct CityWeatherWidgetView: View {
    var entry: CityWeatherEntry

    var body: some View {
        if entry.missing {
            VStack(spacing: 6) {
                Image(systemName: "location.slash").font(.title3)
                Text("暂无城市").font(.subheadline.weight(.medium))
                Text("在 App 中添加后，长按小组件选择")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                LinearGradient(colors: WeatherPalette.colors(for: .unknown, isNight: false),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            CityWeatherCardContent(title: entry.title,
                                   isCurrentLocation: entry.isCurrentLocation,
                                   report: entry.report,
                                   isNight: entry.isNight)
                .containerBackground(for: .widget) {
                    // 底色随该城市的天况变，与列表卡、首页同一套调色板
                    LinearGradient(colors: WeatherPalette.colors(for: entry.condition,
                                                                 isNight: entry.isNight),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                // 点击打开 App 并把首页切到这座城市
                .widgetURL(WidgetDeepLink.url(cityKey: entry.cityKey))
        }
    }
}

struct CityWeatherWidget: Widget {
    let kind: String = "CityWeatherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectCityIntent.self,
                               provider: CityWeatherProvider()) { entry in
            CityWeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("城市天气")
        .description("显示指定城市的实况与未来预报。长按可切换城市。")
        // 只做中号：小号放不下七天预报，大号会剩一大片空白
        .supportedFamilies([.systemMedium])
    }
}
