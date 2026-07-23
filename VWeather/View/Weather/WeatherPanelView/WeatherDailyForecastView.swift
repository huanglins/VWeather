//
//  WeatherDailyForecastView.swift
//  VWeather
//
//  首页多天天气预报。
//

import SwiftUI

/// 未来数天。每行：星期 + 天况 + 降水概率 + 温度区间条。
struct DailyForecastSection: View {
    let days: [WeatherDay]

    /// 全部天数的温度跨度，用于把每天的区间条画在同一标尺上 ——
    /// 各自归一化的话，条形长度就失去了横向可比性。
    private var range: (min: Double, max: Double)? {
        let lows = days.compactMap { $0.tempMin }
        let highs = days.compactMap { $0.tempMax }
        guard let low = lows.min(), let high = highs.max(), high > low else { return nil }
        return (low, high)
    }

    var body: some View {
        WeatherCard(title: "\(days.count) 日天气预报", systemImage: "calendar") {
            VStack(spacing: 5) {
                ForEach(days) { day in
                    Color.clear
                        .frame(height: 26)
                        .overlay(
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    // 左：星期（30%）
                                    Text(Self.weekdayText(day.date))
                                        .font(VWDesign.Typography.footnoteSemibold)
                                        .foregroundStyle(VWDesign.Palette.primary)
                                        .frame(width: geometry.size.width * 0.3, alignment: .leading)

                                    // 中：天况图标 + 文案（40%）
                                    HStack(spacing: 8) {
                                        Image(systemName: (day.condition ?? .unknown).symbol())
                                            .symbolRenderingMode(.multicolor)
                                            .font(.system(size: 16, weight: .bold))
                                            .frame(width: 24)

                                        Text(day.conditionText ?? "--")
                                            .font(VWDesign.Typography.caption)
                                            .foregroundStyle(VWDesign.Palette.muted)
                                            .lineLimit(1)
                                    }
                                    .frame(width: geometry.size.width * 0.4, alignment: .leading)

                                    // 右：温度区间（30%）
                                    HStack(spacing: 4) {
                                        Text(AppSettings.shared.tempText(day.tempMin))
                                            .font(VWDesign.Typography.footnote)
                                            .foregroundStyle(VWDesign.Palette.dim)

                                        if let range, let low = day.tempMin, let high = day.tempMax {
                                            TempRangeBar(low: low,
                                                         high: high,
                                                         scaleMin: range.min,
                                                         scaleMax: range.max)
                                                .frame(height: 4)
                                        } else {
                                            Spacer()
                                        }

                                        Text(AppSettings.shared.tempText(day.tempMax))
                                            .font(VWDesign.Typography.footnoteSemibold)
                                            .foregroundStyle(VWDesign.Palette.primary)
                                    }
                                    .frame(width: geometry.size.width * 0.3, alignment: .trailing)
                                }
                            }
                        )
                }
            }
        }
    }

    static func weekdayText(_ raw: String?) -> String {
        guard let raw, let date = dayParser.date(from: raw) else { return raw ?? "--" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// 逐日预报的 date 是纯日期（无时区），按本地时区解析
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// 温度区间条。所有天共用一个标尺，故条形的位置与长度可横向对比。
private struct TempRangeBar: View {
    let low: Double
    let high: Double
    let scaleMin: Double
    let scaleMax: Double

    var body: some View {
        GeometryReader { geometry in
            let span = scaleMax - scaleMin
            let x = (low - scaleMin) / span * geometry.size.width
            let width = max((high - low) / span * geometry.size.width, 3)
            ZStack(alignment: .leading) {
                // 底槽用白色半透明：.quaternary 会跟随浅色/深色模式变灰，
                // 落在有色渐变上显脏
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex4: 0x6FC2FF), Color(hex4: 0xFF9A4D)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .offset(x: x)
            }
        }
    }
}
