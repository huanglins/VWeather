//
//  WeatherSectionViews.swift
//  VWeather
//
//  首页各天气 Section：逐小时 / 多天 / 分钟降水 / 生活指数 / 逐小时空气质量。
//  与 ContentView 拆开：这些自成一体，而 ContentView 已承担首页骨架与日月展示。
//
//  各 Section 都按「有数据才出现」组织——任一项缺失只会让对应 Section 消失，
//  不影响其它项（后台是分项失败的，见 WeatherReport.errors；
//  WeatherKit 兜底时空气质量与生活指数则整块没有）。
//

import Charts
import SwiftUI
import UIKit

// MARK: - 和风数据的通用格式化

/// 后台归一化后仍保留了和风的两个原始约定：颜色是 "rgba(...)" 字符串、时间不带秒。
/// 这两处解析在预警 / 空气质量 / 分钟降水里都要用，故集中在此。
enum QWeatherFormat {
    /// 解析后台给的 "rgba(r,g,b,a)" 字符串
    static func color(_ raw: String?) -> Color? {
        guard let raw,
              raw.hasPrefix("rgba("), raw.hasSuffix(")") else { return nil }
        let body = raw.dropFirst(5).dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return Color(.sRGB,
                     red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255,
                     opacity: parts[3])
    }

    /// 和风的时间**不带秒**，且两种时区写法都出现过（实测同一响应里两种都有）：
    ///   - UTC：`2026-07-15T10:00Z`（airHourly / 预警）
    ///   - 东八区：`2026-07-15T17:00+08:00`（minutely）
    /// 故不能用 ISO8601DateFormatter（其 withInternetDateTime 要求有秒，会解析失败）。
    /// `ZZZZZ` 两种写法都能吃。

    /// 上游等级色是给「大色块 + 黑字」设计的，如「良」是纯黄 rgba(255,255,0)。
    /// 这种色画成细柱放在浅色卡片上几乎看不见（实测）。
    /// 故保留色相与饱和度、只在亮度过高时压暗：色仍与 AQI 等级严格同源，
    /// 不会出现「色和级对不上」，只是把对比度补回来。深色模式下卡片是深底，无需处理。
    static func legible(_ color: Color, isDark: Bool) -> Color {
        guard !isDark else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        // sRGB 相对亮度，阈值 0.55 约等于「在白底上还看得清」的下限
        while b > 0.25, luminance(hue: h, saturation: s, brightness: b) > 0.55 {
            b *= 0.92
        }
        return Color(UIColor(hue: h, saturation: s, brightness: b, alpha: a))
    }

    private static func luminance(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
            .getRed(&r, green: &g, blue: &bl, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * bl
    }

    /// 解析实现在模型层（WeatherTime）—— Widget 也要用，而视图文件只在主 App target。
    static func date(_ raw: String?) -> Date? { WeatherTime.date(raw) }

    /// 日期 + 时间。解析失败时原样返回，好过显示 "--"
    /// （预警的发布时间是合规必需项，宁可显示原始串也不能吞掉）。
    static func timeText(_ raw: String?) -> String {
        guard let raw else { return "--" }
        guard let date = date(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// 只要小时，给逐小时预报用。当前这一小时显示「现在」。
    ///
    /// 不能用 `timeText`：它带完整日期，24 格横排会把每格撑到 200pt 宽，
    /// 布局直接失控。逐小时的语境里日期是冗余的。
    static func hourText(_ raw: String?) -> String {
        guard let raw, let date = date(raw) else { return "--" }
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .hour) { return "现在" }
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - 逐小时预报

/// 未来 24 小时，横向滚动。
///
/// 用横向滚动而非 List 行：24 项竖着排会把首页其它内容全挤到屏幕外，
/// 而逐小时是「扫一眼趋势」的信息，不需要逐条阅读。
struct HourlyForecastSection: View {
    let hours: [WeatherHour]
    /// 整份报告 —— 逐小时的昼夜要按当天的日出日落判断，那数据在 daily 里。
    /// 跨越 24 小时必然跨昼夜，全部共用一个 isNight 会让凌晨挂着太阳。
    let report: WeatherReport

    private func isNight(_ hour: WeatherHour) -> Bool {
        guard let t = WeatherTime.date(hour.time) else { return false }
        return report.isNight(at: t)
    }

    var body: some View {
        WeatherCard(title: "小时天气预报", systemImage: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        VStack(spacing: 6) {
                            Text(QWeatherFormat.hourText(hour.time))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)

                            Image(systemName: (hour.condition ?? .unknown).symbol(isNight: isNight(hour)))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                                .frame(height: 24)

                            // 只在有降水可能时显示概率，否则每格都挂个 0% 是纯噪音
                            if let pop = hour.precipitationChance, pop > 0 {
                                Text("\(Int(pop))%")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            } else {
                                Text(" ").font(.caption2)
                            }

                            Text(AppSettings.shared.tempText(hour.temperature))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        // 首格内容左对齐，贴到卡片 14pt 内边距，与其他左对齐面板齐平；
                        // 其余格居中，保持逐小时的列状节奏。
                        .frame(minWidth: 44, alignment: index == 0 ? .leading : .center)
                    }
                }
                .padding(.vertical, 2)
            }
            // 用卡片自身的 14 内边距把滚动区左右**对称**框住：静止时首/末格两侧间距一致，
            // 滚动时也在两侧 14pt 处对称裁切。（不做贴边溢出——溢出内容会让静止时右侧
            // 无间距、与左侧不一致，那正是之前的问题。）
        }
    }
}

// MARK: - 多天预报

/// 未来数天。每行：星期 + 天况 + 降水概率 + 温度区间条。
struct DailyForecastSection: View {
    let days: [WeatherDay]

    /// 全部天数的温度跨度，用于把每天的区间条画在同一标尺上 ——
    /// 各自归一化的话，条形长度就失去了横向可比性。
    private var range: (min: Double, max: Double)? {
        let lows = days.compactMap { $0.tempMin }
        let highs = days.compactMap { $0.tempMax }
        guard let lo = lows.min(), let hi = highs.max(), hi > lo else { return nil }
        return (lo, hi)
    }

    var body: some View {
        WeatherCard(title: "\(days.count) 日天气预报", systemImage: "calendar") {
          VStack(spacing: 10) {
            ForEach(days) { day in
                HStack(spacing: 10) {
                    Text(Self.weekdayText(day.date))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 42, alignment: .leading)

                    Image(systemName: (day.condition ?? .unknown).symbol())
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17))
                        .frame(width: 24)

                    // 天况文案：设计里日期与温度之间有一列文字
                    Text(day.conditionText ?? "--")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .frame(width: 44, alignment: .leading)

                    // 降水概率：没有就留空，不占视觉
                    Group {
                        if let pop = day.precipitationChance, pop > 0 {
                            Text("\(Int(pop))%")
                        } else {
                            Text(" ")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 30, alignment: .leading)

                    Text(AppSettings.shared.tempText(day.tempMin))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 34, alignment: .trailing)

                    if let r = range, let lo = day.tempMin, let hi = day.tempMax {
                        TempRangeBar(low: lo, high: hi, scaleMin: r.min, scaleMax: r.max)
                            .frame(height: 4)
                    } else {
                        Spacer()
                    }

                    Text(AppSettings.shared.tempText(day.tempMax))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, alignment: .leading)
                }
            }
          }
        }
    }

    /// 日期形如 "2026-07-16"。今天/明天用中文词，其余用星期。
    static func weekdayText(_ raw: String?) -> String {
        guard let raw, let date = dayParser.date(from: raw) else { return raw ?? "--" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// 逐日预报的 date 是纯日期（无时区），按本地时区解析
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// 温度区间条。所有天共用一个标尺，故条形的位置与长度可横向对比。
private struct TempRangeBar: View {
    let low: Double
    let high: Double
    let scaleMin: Double
    let scaleMax: Double

    var body: some View {
        GeometryReader { geo in
            let span = scaleMax - scaleMin
            let x = (low - scaleMin) / span * geo.size.width
            let w = max((high - low) / span * geo.size.width, 3)   // 太窄会看不见
            ZStack(alignment: .leading) {
                // 底槽用白色半透明：.quaternary 会跟随浅色/深色模式变灰，
                // 落在有色渐变上显脏
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex4: 0x6FC2FF), Color(hex4: 0xFF9A4D)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w)
                    .offset(x: x)
            }
        }
    }
}

// MARK: - 分钟级降水

/// 未来 2 小时、5 分钟粒度的降水。
struct MinutelyPrecipSection: View {
    let minutely: MinutelyPrecip

    private struct Point: Identifiable {
        let time: Date
        let precip: Double
        let isSnow: Bool
        var id: Date { time }
    }

    private var points: [Point] {
        (minutely.items ?? []).compactMap { item in
            // 后台的中立 schema 已把降水量归一化为数字（各源原始表示不一，
            // 和风给的是字符串），这里不必再自己转换。
            guard let time = QWeatherFormat.date(item.time),
                  let precip = item.precipitation else { return nil }
            return Point(time: time, precip: precip, isSnow: item.type == "snow")
        }
    }

    var body: some View {
        let points = points
        // 无降水时全是 0，画出来是条贴底的直线，纯噪音——此时只留 summary 那句话。
        let hasPrecip = points.contains { $0.precip > 0 }

        if minutely.summary?.isEmpty == false || hasPrecip {
            WeatherCard(title: "分钟级降水", systemImage: "cloud.rain") {
                VStack(alignment: .leading, spacing: 8) {
                    if let summary = minutely.summary, !summary.isEmpty {
                        Label(summary, systemImage: hasPrecip ? "cloud.rain.fill" : "cloud.sun.fill")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                    if hasPrecip {
                        chart(points)
                    }
                }
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let isSnow = points.contains { $0.isSnow }
        let tint: Color = isSnow ? .cyan : .blue
        return Chart(points) { point in
            AreaMark(
                x: .value("时间", point.time),
                y: .value(isSnow ? "降雪" : "降水", point.precip)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(colors: [tint.opacity(0.55), tint.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value("时间", point.time),
                y: .value(isSnow ? "降雪" : "降水", point.precip)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
        }
        // 单位是「每 5 分钟毫米数」，数值很小，交给 Charts 自动定刻度
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.15))
                AxisValueLabel().foregroundStyle(.white.opacity(0.6))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .frame(height: 110)
    }
}

// MARK: - 生活指数

/// 生活指数（运动 / 洗车 / 穿衣 …，实测 16 项）。
/// 整个 grid 只包一个 NavigationLink，点任意卡片 push 一次到全部指数列表。
struct LifeIndicesSection: View {
    let indices: [LifeIndex]

    var body: some View {
        if !indices.isEmpty {
            WeatherCard(title: "生活指数", systemImage: "list.bullet.rectangle") {
                // 整个 grid 只包一个 NavigationLink，避免 16 个 Link 各 push 一次
                NavigationLink {
                    LifeIndicesFullView(indices: indices)
                } label: {
                    gridRows
                        // 每张小卡自带底色、点得动，但卡与卡之间的间距是透明的，
                        // 以及奇数项那个占位格 —— 点在那些地方没反应。
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 两列网格：用 VStack 包裹 HStack 分行，List 能正确计算完整高度
    private var gridRows: some View {
        let rows = stride(from: 0, to: indices.count, by: 2).map {
            Array(indices[$0..<min($0 + 2, indices.count)])
        }
        return VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    ForEach(rows[i]) { index in
                        card(index)
                    }
                    // 奇数项补空占位，保持对齐
                    if rows[i].count == 1 {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }

    private func card(_ index: LifeIndex) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: index.type))
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortName(type: index.type, name: index.name))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Text(index.category ?? "--")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // 定高：名称一行、等级一行，两列卡片才对得齐（否则长名换行会把整排顶歪）
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 卡片窄，「运动指数」去掉后缀只留「运动」，给 category 留出空间。
    /// 个别名称去掉后缀仍过长（如「空气污染扩散条件」），单独给短名，
    /// 否则只能截断成「空气污染扩散条…」。按 type 匹配，上游改文案也不影响。
    private static func shortName(type: String?, name: String?) -> String {
        if type == "10" { return "污染扩散" }
        guard let name else { return "--" }
        guard name.count > 2, name.hasSuffix("指数") else { return name }
        return String(name.dropLast(2))
    }

    /// 和风生活指数 type 编码 → SF Symbol。
    /// 用 type（稳定编码）而非 name 匹配，避免上游改文案就失效。
    static func symbol(for type: String?) -> String {
        switch type {
        case "1":  return "figure.run"                  // 运动
        case "2":  return "car.fill"                    // 洗车
        case "3":  return "tshirt.fill"                 // 穿衣
        case "4":  return "fish.fill"                   // 钓鱼
        case "5":  return "sun.max.fill"                // 紫外线
        case "6":  return "airplane"                    // 旅游
        case "7":  return "allergens"                   // 过敏
        case "8":  return "thermometer.medium"          // 舒适度
        case "9":  return "cross.case.fill"             // 感冒
        case "10": return "wind"                        // 空气污染扩散条件
        case "11": return "snowflake"                   // 空调开启
        case "12": return "sunglasses.fill"             // 太阳镜
        case "13": return "paintbrush.fill"             // 化妆
        case "14": return "sun.horizon.fill"            // 晾晒
        case "15": return "car.2.fill"                  // 交通
        case "16": return "umbrella.fill"               // 防晒
        default:   return "sparkles"
        }
    }
}

/// 全部生活指数列表页：点击任何生活指数卡片时 push 进入，展示所有指数及完整建议。
struct LifeIndicesFullView: View {
    let indices: [LifeIndex]

    var body: some View {
        List {
            ForEach(indices) { index in
                Section {
                    if let text = index.text, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .padding(.vertical, 2)
                    } else {
                        Text("暂无建议")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: LifeIndicesSection.symbol(for: index.type))
                            .foregroundStyle(.tint)
                        Text(index.name ?? "--")
                        Spacer()
                        Text(index.category ?? "--")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("生活指数")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 生活指数详情：完整建议文本（保留，供需要单独查看某一项的场合使用）
struct LifeIndexDetailView: View {
    let index: LifeIndex

    var body: some View {
        List {
            Section {
                HStack {
                    Text("等级")
                    Spacer()
                    Text(index.category ?? "--").foregroundStyle(.secondary)
                }
                if let date = index.date {
                    HStack {
                        Text("日期")
                        Spacer()
                        Text(date).foregroundStyle(.secondary)
                    }
                }
            }
            if let text = index.text, !text.isEmpty {
                Section("建议") {
                    Text(text)
                        .font(.callout)
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(index.name ?? "生活指数")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 逐小时空气质量

/// 未来 24 小时 AQI（WeatherKit 无此数据）。
/// 用柱状图而非列表：24 行读不出趋势，而 AQI 的价值就在趋势。
struct AirHourlyChart: View {
    let hours: [AirQuality]

    @Environment(\.colorScheme) private var colorScheme

    private struct Point: Identifiable {
        let time: Date
        let aqi: Double
        let color: Color
        let category: String
        var id: Date { time }
    }

    private var points: [Point] {
        let isDark = colorScheme == .dark
        return hours.compactMap { hour in
            guard let time = QWeatherFormat.date(hour.time),
                  let aqi = hour.aqi else { return nil }
            let color = QWeatherFormat.color(hour.color).map { QWeatherFormat.legible($0, isDark: isDark) }
            return Point(time: time,
                         aqi: aqi,
                         color: color ?? .secondary,
                         category: hour.category ?? "--")
        }
    }

    var body: some View {
        let points = points
        if !points.isEmpty {
            Chart(points) { point in
                BarMark(
                    x: .value("时间", point.time, unit: .hour),
                    y: .value("AQI", point.aqi)
                )
                // 用上游给的等级色：颜色与数值同源，不会出现「色和级对不上」
                .foregroundStyle(point.color)
                .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour())
                        }
                    }
                }
            }
            .frame(height: 110)
            .padding(.vertical, 6)
        }
    }
}
