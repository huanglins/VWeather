//
//  SunEventWidget.swift
//  WeatherWidget
//
//  「日出日落」小组件：追逐下一个日相事件（蓝调 / 日出 / 黄金 / 日落…），
//  显示事件时刻、实时倒计时，以及一条带辉光的地平线曲线 + 当前进度白点。
//
//  数据全部由 VHLSunMoonManager 本地即时计算（SunKit，无需联网），
//  故小组件进程里现算昨天 / 今天 / 明天的事件，取 now 之后最近的一个。
//
//  样式参考设计图：上浅下深的两段蓝，地平线以下为「海」，曲线柔和起伏并带模糊辉光，
//  白点严格落在曲线上（与曲线共用同一 horizonY 采样函数，保证不脱线）。
//

import SwiftUI
import WidgetKit
import CoreLocation

// MARK: - 天空阶段配色

/// 当下天空阶段 —— 决定整块渐变的冷暖。
enum SkyPhase {
    case day, goldenHour, blueHour, night

    struct Palette {
        let skyTop: Color, skyBottom: Color     // 地平线以上（天空）
        let seaTop: Color, seaBottom: Color      // 地平线以下（海）
    }

    /// 四段配色。day 一段对齐设计图（上浅蓝、下深蓝）。
    var palette: Palette {
        switch self {
        case .day:
            return .init(skyTop: Color(hex4: 0x4F99EF), skyBottom: Color(hex4: 0x3A80DC),
                         seaTop: Color(hex4: 0x2A6AD0), seaBottom: Color(hex4: 0x184A93))
        case .goldenHour:
            return .init(skyTop: Color(hex4: 0xF4B267), skyBottom: Color(hex4: 0xE68A55),
                         seaTop: Color(hex4: 0x8A5E8E), seaBottom: Color(hex4: 0x3E3C7A))
        case .blueHour:
            return .init(skyTop: Color(hex4: 0x496CB8), skyBottom: Color(hex4: 0x33509C),
                         seaTop: Color(hex4: 0x22397C), seaBottom: Color(hex4: 0x122455))
        case .night:
            return .init(skyTop: Color(hex4: 0x1D2F58), skyBottom: Color(hex4: 0x142246),
                         seaTop: Color(hex4: 0x0E1A3C), seaBottom: Color(hex4: 0x070E24))
        }
    }
}

// MARK: - 地平线曲线

/// 地平线在给定 x 处的 y（曲线与白点共用，保证白点严格贴线）。
/// 两个不同频率的正弦叠加 → 有机起伏，而非机械单波。
private func horizonY(x: CGFloat, width w: CGFloat, height h: CGFloat) -> CGFloat {
    guard w > 0 else { return h * 0.56 }
    let t = x / w
    let base = h * 0.56          // 地平线大致高度
    let amp = h * 0.05           // 主波振幅（克制，贴近设计图的和缓起伏）
    let main = amp * sin(t * .pi * 2 * 1.0 + 0.7)
    let ripple = amp * 0.45 * sin(t * .pi * 2 * 2.3 + 2.1)
    return base + main + ripple
}

/// 地平线曲线。closed=true 时向下闭合成「海」的填充面，false 时只是那条线。
private struct HorizonShape: Shape {
    var closed: Bool
    /// 整条线的竖直偏移（画次级淡波纹时上移一点，增加层次）。
    var yOffset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let step: CGFloat = 2                 // 2pt 采样，足够顺滑又有细节
        p.move(to: CGPoint(x: 0, y: horizonY(x: 0, width: w, height: h) + yOffset))
        var x: CGFloat = step
        while x <= w {
            p.addLine(to: CGPoint(x: x, y: horizonY(x: x, width: w, height: h) + yOffset))
            x += step
        }
        if closed {
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
        return p
    }
}

/// 天空 + 海 + 地平线辉光 + 进度白点。铺在 containerBackground 里，边到边。
private struct SunEventSky: View {
    let phase: SkyPhase
    let progress: Double        // 0...1 白点水平进度

    var body: some View {
        let g = phase.palette
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let clamped = max(0, min(1, progress))
            let dotX = w * CGFloat(clamped)
            let dotY = horizonY(x: dotX, width: w, height: h)

            ZStack {
                // 天空
                LinearGradient(colors: [g.skyTop, g.skyBottom],
                               startPoint: .top, endPoint: .bottom)

                // 海（地平线以下）
                HorizonShape(closed: true)
                    .fill(LinearGradient(colors: [g.seaTop, g.seaBottom],
                                         startPoint: .top, endPoint: .bottom))

                // 次级淡波纹：上移一点、低透明、轻模糊 —— 增加曲线细节层次
                HorizonShape(closed: false, yOffset: -h * 0.03)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
                    .blur(radius: 2)

                // 地平线辉光：先一层粗而模糊的白，再叠一层细而清晰的白
                HorizonShape(closed: false)
                    .stroke(.white.opacity(0.5), lineWidth: 3)
                    .blur(radius: 4)
                HorizonShape(closed: false)
                    .stroke(.white.opacity(0.9), lineWidth: 1.4)

                // 进度白点：外圈柔光 + 实心点
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .blur(radius: 6)
                    .position(x: dotX, y: dotY)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .position(x: dotX, y: dotY)
            }
        }
    }
}

// MARK: - Entry

struct SunEventEntry: TimelineEntry {
    let date: Date
    var timeText: String = "--:--"      // 目标事件时刻 HH:mm
    var label: String = ""              // 事件名，如「黄金开始」
    var symbol: String = "sun.horizon.fill"
    var eventDate: Date = Date()        // 目标事件时间（用于实时倒计时）
    var phase: SkyPhase = .day          // 当下天空阶段（配色）
    var progress: Double = 0            // 白点进度（上一事件 → 下一事件）
    var cityKey: String? = nil          // 供点击深链跳到对应城市
    var missing: Bool = false
}

// MARK: - 事件构建

private struct SunEvent {
    let label: String
    let date: Date
    let symbol: String
}

private enum SunEvents {
    /// 一天 VHLSunInfo → 关键事件（按发生顺序）。
    static func of(_ s: VHLSunInfo) -> [SunEvent] {
        [
            SunEvent(label: "蓝调开始", date: s.morningBlueHourStart, symbol: "moon.stars.fill"),
            SunEvent(label: "日出",     date: s.sunrise,              symbol: "sunrise.fill"),
            SunEvent(label: "黄金结束", date: s.morningGoldenHourEnd, symbol: "sun.max.fill"),
            SunEvent(label: "黄金开始", date: s.eveningGoldenHourStart, symbol: "sun.horizon.fill"),
            SunEvent(label: "日落",     date: s.sunset,               symbol: "sunset.fill"),
            SunEvent(label: "蓝调结束", date: s.eveningBlueHourEnd,   symbol: "moon.stars.fill"),
        ]
    }

    /// now 附近（昨天/今天/明天）按时间排好的事件序列。跨天首尾相接，便于取前后相邻事件。
    static func around(_ now: Date, location: CLLocation) -> [SunEvent] {
        let cal = Calendar.current
        var all: [SunEvent] = []
        for off in -1...1 {
            guard let day = cal.date(byAdding: .day, value: off, to: now) else { continue }
            let s = VHLSunMoonManager.manager.sunInfo(location: location, date: day)
            all.append(contentsOf: of(s))
        }
        return all.sorted { $0.date < $1.date }
    }

    /// 某时刻的天空阶段（用当刻的 SunKit 状态位判定，配色随之变冷暖）。
    static func phase(at date: Date, location: CLLocation) -> SkyPhase {
        let s = VHLSunMoonManager.manager.sunInfo(location: location, date: date)
        if s.isGoldenHour { return .goldenHour }
        if s.isBlueHour { return .blueHour }
        if s.isNight { return .night }
        return .day
    }
}

// MARK: - Provider

struct SunEventProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> SunEventEntry {
        SunEventEntry(date: Date(), timeText: "18:41", label: "黄金开始",
                      eventDate: Date().addingTimeInterval(47 * 60 + 39), progress: 0.68)
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> SunEventEntry {
        _ = DBManager.manager
        return makeEntries(configuration, now: Date()).first
            ?? SunEventEntry(date: Date(), missing: true)
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<SunEventEntry> {
        _ = DBManager.manager
        let entries = makeEntries(configuration, now: Date())
        guard let last = entries.last, !last.missing else {
            return Timeline(entries: [SunEventEntry(date: Date(), missing: true)],
                            policy: .after(Date().addingTimeInterval(60 * 60)))
        }
        // 事件到点后重算下一个
        return Timeline(entries: entries, policy: .after(last.eventDate))
    }

    /// 生成从 now 到「下一个事件」之间、每隔一段的一串 entry：
    /// 大时间/事件名/倒计时全程不变，只有白点进度与配色随时间推进 → 白点会缓慢前移。
    private func makeEntries(_ configuration: SelectCityIntent, now: Date) -> [SunEventEntry] {
        guard let city = resolveCity(configuration) else {
            return [SunEventEntry(date: now, missing: true)]
        }
        let location = city.location
        let events = SunEvents.around(now, location: location)
        guard let idx = events.firstIndex(where: { $0.date > now }) else {
            return [SunEventEntry(date: now, missing: true)]
        }
        let next = events[idx]
        let prev = idx > 0 ? events[idx - 1] : next
        let segStart = prev.date
        let segLen = max(1, next.date.timeIntervalSince(segStart))

        let timeText = VHLSunMoonManager.timeString(next.date)
        let span = max(1, next.date.timeIntervalSince(now))
        // ~5 分钟一帧推进白点，最多 60 帧（跨夜的长段也不至于爆量）
        let steps = min(60, max(1, Int(span / 300)))
        let stepLen = span / Double(steps)

        var entries: [SunEventEntry] = []
        for i in 0..<steps {
            let d = now.addingTimeInterval(stepLen * Double(i))
            let progress = d.timeIntervalSince(segStart) / segLen
            entries.append(SunEventEntry(
                date: d,
                timeText: timeText,
                label: next.label,
                symbol: next.symbol,
                eventDate: next.date,
                phase: SunEvents.phase(at: d, location: location),
                progress: max(0, min(1, progress)),
                cityKey: city.cityKey
            ))
        }
        return entries
    }

    /// 与「城市天气」小组件同一套解析：配置指定城市 / 当前位置 / 未配置回退。
    private func resolveCity(_ configuration: SelectCityIntent) -> CityModel? {
        if let key = configuration.cityKey {
            if key == kWidgetCurrentLocation { return currentLocationCity() }
            return CityModel.objects(whereSQL: "cityKey = ?", params: [key])
                .first { $0.isDeleted != true }
        }
        return currentLocationCity() ?? CityWeatherManager.manager.selectedCity()
    }

    private func currentLocationCity() -> CityModel? {
        CityModel.objects(order: .ASC("sortOrder"))
            .first { $0.isCurrentLocation == true && $0.isDeleted != true }
    }
}

// MARK: - View

struct SunEventWidgetView: View {
    var entry: SunEventEntry

    var body: some View {
        if entry.missing {
            missingView
        } else {
            contentView
        }
    }

    private var contentView: some View {
        VStack(spacing: 2) {
            Image(systemName: entry.symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 1)

            Text(entry.timeText)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(entry.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

            countdown
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .containerBackground(for: .widget) {
            SunEventSky(phase: entry.phase, progress: entry.progress)
        }
        .widgetURL(WidgetDeepLink.url(cityKey: entry.cityKey))
    }

    /// 实时倒计时。系统计时文本每秒自走，零时间线开销；到点后 Provider 重算下一个事件。
    @ViewBuilder
    private var countdown: some View {
        if entry.eventDate > entry.date {
            Text(timerInterval: entry.date...entry.eventDate, countsDown: true)
                .multilineTextAlignment(.center)
        } else {
            Text("即将到来")
        }
    }

    private var missingView: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash").font(.title3)
            Text("暂无位置").font(.subheadline.weight(.medium))
            Text("在 App 中添加城市后，长按选择")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            SunEventSky(phase: .night, progress: 0.5)
        }
    }
}

// MARK: - Widget

struct SunEventWidget: Widget {
    let kind: String = "SunEventWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectCityIntent.self,
                               provider: SunEventProvider()) { entry in
            SunEventWidgetView(entry: entry)
        }
        .configurationDisplayName("日出日落")
        .description("追逐日出日落等相关事件。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
