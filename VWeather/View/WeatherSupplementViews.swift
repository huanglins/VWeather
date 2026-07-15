//
//  WeatherSupplementViews.swift
//  VWeather
//
//  补充数据（vapi 后台代理和风）的展示：分钟级降水 / 生活指数 / 逐小时空气质量。
//  与 ContentView 拆开：这三块自成一体，且 ContentView 已承担首页骨架与日月展示。
//
//  各 Section 都按「有数据才出现」组织——后台任一项失败只会让对应 Section 消失，
//  不影响其它项（后台是分项失败的，见 WeatherSupplement.errors）。
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
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmZZZZZ"
        return f
    }()

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

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = parser.date(from: raw) { return date }
        // 兜底：万一上游哪天带上了秒
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return iso.date(from: raw)
    }

    /// 日期 + 时间。解析失败时原样返回，好过显示 "--"
    /// （预警的发布时间是合规必需项，宁可显示原始串也不能吞掉）。
    static func timeText(_ raw: String?) -> String {
        guard let raw else { return "--" }
        guard let date = date(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
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
            guard let time = QWeatherFormat.date(item.time),
                  // 上游把毫米给成字符串
                  let precip = Double(item.precip ?? "") else { return nil }
            return Point(time: time, precip: precip, isSnow: item.type == "snow")
        }
    }

    var body: some View {
        let points = points
        // 无降水时全是 0，画出来是条贴底的直线，纯噪音——此时只留 summary 那句话。
        let hasPrecip = points.contains { $0.precip > 0 }

        if minutely.summary?.isEmpty == false || hasPrecip {
            Section("分钟级降水") {
                if let summary = minutely.summary, !summary.isEmpty {
                    Label(summary, systemImage: hasPrecip ? "cloud.rain.fill" : "cloud.sun.fill")
                        .font(.callout)
                        .padding(.vertical, 2)
                }
                if hasPrecip {
                    chart(points)
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
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                    }
                }
            }
        }
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}

// MARK: - 生活指数

/// 生活指数（运动 / 洗车 / 穿衣 …，实测 16 项）。
/// 整个 grid 只包一个 NavigationLink，点任意卡片 push 一次到全部指数列表。
struct LifeIndicesSection: View {
    let indices: [LifeIndex]

    var body: some View {
        if !indices.isEmpty {
            Section("生活指数") {
                // 整个 grid 只包一个 NavigationLink，避免 16 个 Link 各 push 一次。
                // 不用 LazyVGrid（在 List 内算不出固有高度导致被截断），改用 VStack 分行。
                NavigationLink {
                    LifeIndicesFullView(indices: indices)
                } label: {
                    gridRows
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            // 卡片自带背景，去掉 List 行的默认留白与背景
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
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
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortName(type: index.type, name: index.name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(index.category ?? "--")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // 定高：名称一行、等级一行，两列卡片才对得齐（否则长名换行会把整排顶歪）
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
