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
import CoreLocation

/// 小组件端的「当前位置」刷新。
///
/// 小组件本身**能**拿位置：Info.plist 里 `NSWidgetWantsLocation = true` 后，系统会在
/// 显著移动时刷新小组件，并让时间线里读到最新位置。这里取系统位置、必要时更新共享库里
/// 的「当前位置」记录（坐标 + 反查地名），使小组件不必等主 App 打开也能跟随移动。
enum WidgetLocation {
    /// 已存的「当前位置」城市记录。
    static func storedCity() -> CityModel? {
        CityModel.objects(order: .ASC("sortOrder"))
            .first { $0.isCurrentLocation == true && $0.isDeleted != true }
    }

    /// 取系统位置刷新「当前位置」：与已存坐标相差较大才反查地名并写库，否则沿用已存记录。
    static func refreshedCity() async -> CityModel? {
        let stored = storedCity()

        let mgr = CLLocationManager()
        // 小组件不能弹权限，只在已授权且系统给了缓存位置时用；否则沿用已存记录。
        let status = mgr.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let loc = mgr.location else { return stored }

        // 与已存坐标相差 <500m 视为没动：省一次反查 + 写库。
        if let s = stored, let la = s.latitude, let lo = s.longitude,
           loc.distance(from: CLLocation(latitude: la, longitude: lo)) < 500 {
            return stored
        }

        // 移动了：以稳定主键原地更新记录（当前位置不参与同步，直接写库即可）。
        var c = stored ?? CityModel()
        c.cityKey = CityModel.currentLocationKey
        c.latitude = loc.coordinate.latitude
        c.longitude = loc.coordinate.longitude
        c.isCurrentLocation = true
        c.isDeleted = false
        c.sortOrder = 0
        if c.createDate == nil { c.createDate = Date() }
        c.updateDate = Date()
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
            c.name = pm.subLocality ?? pm.locality ?? pm.subAdministrativeArea
                ?? pm.administrativeArea ?? pm.name ?? c.name
            c.province = pm.administrativeArea
            c.country = pm.country
            c.fullAddress = [pm.country, pm.administrativeArea, pm.locality, pm.subLocality]
                .compactMap { $0 }.joined()
        }
        c.saveOrUpdate()
        return c
    }
}

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
        guard let city = await resolveCity(configuration) else {
            return CityWeatherEntry(date: Date(), missing: true)
        }
        return entry(city, CityWeatherManager.manager.cachedSnapshot(for: city))
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<CityWeatherEntry> {
        guard let city = await resolveCity(configuration) else {
            // 没城市可显示时也要给个时间线，否则组件会一直卡在占位态。
            // 隔久一点再看 —— 用户去 App 加城市这件事，不值得频繁轮询。
            return Timeline(entries: [CityWeatherEntry(date: Date(), missing: true)],
                            policy: .after(Date().addingTimeInterval(60 * 60)))
        }

        // 与主 App 共享缓存，不会因为多一个小组件就多打上游
        let snap = await CityWeatherManager.manager.refresh(for: city)
        let e = entry(city, snap)

        // 60 分钟后再刷。小组件全天候刷新是上游调用的主要来源，天气组件按小时更新足够，
        // 拉长到 1 小时可近乎减半小组件驱动的请求量。给一条 entry 即可 —— 卡片无随时间变化的内容。
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60 * 60)))
    }

    /// 决定显示哪个城市。
    ///
    /// 三种情况：
    ///   · 配置选了「当前位置」（存哨兵）→ 查当下的当前位置城市，坐标随便变都跟得上
    ///   · 配置选了具体城市（存 cityKey）→ 按 cityKey 查；查不到（被删）→ 返回 nil 显示缺失
    ///   · 未配置（cityKey 为空）→ 回退到当前位置，其次 App 选中的
    private func resolveCity(_ configuration: SelectCityIntent) async -> CityModel? {
        _ = DBManager.manager          // 小组件进程里初始化共享库

        if let key = configuration.cityKey {
            // 「当前位置」：取系统位置刷新后返回 —— 移动后不必等主 App 打开也能跟上。
            if key == kWidgetCurrentLocation {
                return await WidgetLocation.refreshedCity()
            }
            // 具体城市：按 cityKey 查。查不到就返回 nil（显示缺失），不静默回退成别的城市。
            // 不加 isDeleted != 1：isDeleted 为 NULL 时该条件在 SQL 里是 NULL 而非 true，
            // 整行会被漏掉。与 CityManager.allCities 一致，改在 Swift 侧判。
            return CityModel.objects(whereSQL: "cityKey = ?", params: [key])
                .first { $0.isDeleted != true }
        }
        // 未配置：优先当前位置，其次 App 选中的。
        return await WidgetLocation.refreshedCity() ?? CityWeatherManager.manager.selectedCity()
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
    @Environment(\.widgetFamily) private var family
    var entry: CityWeatherEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(entry.missing ? nil : WidgetDeepLink.url(cityKey: entry.cityKey))
    }

    @ViewBuilder
    private var content: some View {
        if entry.missing {
            missingView
        } else if family == .systemSmall {
            CityWeatherSmallView(entry: entry)   // 小号：紧凑实况，放不下七天预报
        } else if family == .systemLarge {
            CityWeatherLargeView(entry: entry)   // 大号：实况 + 逐小时 + 七天 + 空气质量
        } else {
            // 中号：城市卡（含迷你七天预报），与列表卡、首页同源
            CityWeatherCardContent(title: entry.title,
                                   isCurrentLocation: entry.isCurrentLocation,
                                   report: entry.report,
                                   isNight: entry.isNight)
        }
    }

    private var missingView: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash").font(.title3)
            Text("暂无城市").font(.subheadline.weight(.medium))
            Text("在 App 中添加后，长按小组件选择")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }

    /// 底色随该城市的天况变，与列表卡、首页同一套调色板。
    private var background: some View {
        let condition: VWCondition = entry.missing ? .unknown : entry.condition
        let night = entry.missing ? false : entry.isNight
        return LinearGradient(colors: WeatherPalette.colors(for: condition, isNight: night),
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 小号布局：城市名 + 天气图标 · 大温度 · 天况 + 高低温。
struct CityWeatherSmallView: View {
    var entry: CityWeatherEntry

    var body: some View {
        let now = entry.report?.now
        let today = entry.report?.daily?.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if entry.isCurrentLocation {
                    Image(systemName: "location.fill").font(.caption2)
                }
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: entry.condition.symbol(isNight: entry.isNight))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 18))
            }

            Text(AppSettings.shared.tempText(now?.temperature))
                .font(.system(size: 48, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.top, 2)

            Spacer(minLength: 0)

            Text(now?.conditionText ?? "--")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            if let hi = today?.tempMax, let lo = today?.tempMin {
                Text("↓\(AppSettings.shared.tempText(lo))  ↑\(AppSettings.shared.tempText(hi))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Widget 本地格式化（QWeatherFormat 在主 App target，widget 用不到，取所需复刻）。
private enum WidgetFmt {
    /// 逐小时的「小时」文案，当前这一小时显示「现在」。
    static func hour(_ raw: String?) -> String {
        guard let raw, let d = WeatherTime.date(raw) else { return "--" }
        if Calendar.current.isDate(d, equalTo: Date(), toGranularity: .hour) { return "现在" }
        return d.formatted(.dateTime.hour())
    }
    /// 后台的 "rgba(r,g,b,a)" → Color。
    static func rgba(_ raw: String?) -> Color? {
        guard let raw, raw.hasPrefix("rgba("), raw.hasSuffix(")") else { return nil }
        let parts = raw.dropFirst(5).dropLast()
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return Color(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts[3])
    }
}

/// 大号布局：实况头部 + 逐小时 + 未来七天 + 空气质量。
/// WeatherKit 兜底时没有逐小时 / 空气质量，那两段按「有才显示」自动省略。
struct CityWeatherLargeView: View {
    var entry: CityWeatherEntry

    var body: some View {
        let report = entry.report
        let now = report?.now
        let today = report?.daily?.first
        return VStack(alignment: .leading, spacing: 10) {
            header(now: now, today: today)

            if let hours = report?.hourly, !hours.isEmpty {
                divider
                section("逐小时", "clock") { hourlyStrip(Array(hours.prefix(6)), report: report) }
            }
            if let days = report?.daily, !days.isEmpty {
                divider
                section("未来几天", "calendar") { dailyStrip(Array(days.prefix(7))) }
            }
            Spacer(minLength: 0)
            if let air = report?.air {
                divider
                aqiLine(air)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: 头部

    private func header(now: WeatherNow?, today: WeatherDay?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.isCurrentLocation {
                        Image(systemName: "location.fill").font(.caption2)
                    }
                    Text(entry.title).font(.headline).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(now?.conditionText ?? "--")
                    if let hi = today?.tempMax, let lo = today?.tempMin {
                        Text("↓\(AppSettings.shared.tempText(lo))  ↑\(AppSettings.shared.tempText(hi))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 8)
            Text(AppSettings.shared.tempText(now?.temperature))
                .font(.system(size: 46, weight: .semibold))
        }
    }

    // MARK: 分区外壳

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(height: 0.5)
    }

    private func section<Content: View>(_ title: String, _ icon: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            content()
        }
    }

    // MARK: 逐小时 / 逐日

    // 两段横向都用 space-between：首列贴左、末列贴右，列间等宽 Spacer 撑开 ——
    // 均分且间距一致，两端顶到边。

    private func hourlyStrip(_ hours: [WeatherHour], report: WeatherReport?) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { i, h in
                let night = WeatherTime.date(h.time).map { report?.isNight(at: $0) ?? false } ?? false
                VStack(spacing: 5) {
                    Text(WidgetFmt.hour(h.time))
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Image(systemName: (h.condition ?? .unknown).symbol(isNight: night))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 16)).frame(height: 20)
                    Text(AppSettings.shared.tempText(h.temperature))
                        .font(.caption.weight(.medium))
                }
                if i < hours.count - 1 { Spacer(minLength: 0) }
            }
        }
    }

    private func dailyStrip(_ days: [WeatherDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 4) {
                    Text(CityWeatherCardContent.shortWeekday(d.date))
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Image(systemName: (d.condition ?? .unknown).symbol())
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 16)).frame(height: 20)
                    Text(AppSettings.shared.tempText(d.tempMax))
                        .font(.caption.weight(.semibold))
                    Text(AppSettings.shared.tempText(d.tempMin))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                if i < days.count - 1 { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: 空气质量

    private func aqiLine(_ air: AirQuality) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "aqi.medium").font(.caption)
            Text("空气质量").font(.caption).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 8)
            // 用色点而非填充色块：上游等级色是给「黑字大色块」设计的，
            // 直接铺到深色小组件上对比度不稳，色点 + 白字始终清晰。
            Circle().fill(WidgetFmt.rgba(air.color) ?? .gray).frame(width: 8, height: 8)
            Text(air.aqiText ?? air.aqi.map { String(Int($0)) } ?? "--")
                .font(.caption.weight(.bold))
            if let cat = air.category {
                Text(cat).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
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
        // 小号：紧凑实况；中号：含迷你七天预报；大号：实况 + 逐小时 + 七天 + 空气质量。
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
