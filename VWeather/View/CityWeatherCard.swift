//
//  CityWeatherCard.swift
//  VWeather
//
//  城市天气概览卡的内容：地名 + 当前温度 + 天况高低温 + 迷你多天预报。
//
//  主 App 的城市列表与中号小组件共用它 —— 两处长得一样不是巧合，是同一份代码。
//  故本文件同时属于 VWeather 与 WeatherWidget 两个 target。
//
//  只画内容、不画背景：列表里要圆角卡片，小组件里要整屏铺满（圆角由系统给），
//  外壳交给各自的调用方。
//

import SwiftUI

struct CityWeatherCardContent: View {
    let title: String
    let isCurrentLocation: Bool
    let report: WeatherReport?
    /// 昼夜。列表用 SunKit 本地算的结果，小组件用报告里的日出日落 —— 都比按时段猜准。
    let isNight: Bool
    /// 迷你预报显示几天。中号小组件宽度有限，超过 7 天会挤。
    var dayCount: Int = 7

    private var now: WeatherNow? { report?.now }
    private var today: WeatherDay? { report?.daily?.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if isCurrentLocation {
                            Image(systemName: "location.fill").font(.caption2)
                        }
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(now?.conditionText ?? "--")
                        if let hi = today?.tempMax, let lo = today?.tempMin {
                            Text("|").foregroundStyle(.white.opacity(0.35))
                            Text("▼ \(AppSettings.shared.tempText(lo))")
                            Text("▲ \(AppSettings.shared.tempText(hi))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                Text(AppSettings.shared.tempText(now?.temperature))
                    .font(.system(size: 40, weight: .semibold))
            }

            if let days = report?.daily, !days.isEmpty {
                miniForecast(Array(days.prefix(dayCount)))
            }
        }
        .foregroundStyle(.white)
    }

    private func miniForecast(_ days: [WeatherDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                // 首末列贴边（与上方地名/大温度的左右边缘对齐），中间列居中。
                // 全部居中的话两端会各凹进半格，看着比整体窄一圈。
                let alignment: Alignment = index == 0 ? .leading
                    : index == days.count - 1 ? .trailing : .center
                VStack(spacing: 6) {
                    Text(Self.shortWeekday(day.date))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: (day.condition ?? .unknown).symbol())
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 16))
                        .frame(height: 20)
                    Text(AppSettings.shared.tempText(day.tempMax))
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }

    /// "2026-07-16" → "四"。今天也用星期，不用「今」——
    /// 一排七个字，混用会让对齐看着乱。
    static func shortWeekday(_ raw: String?) -> String {
        guard let raw, let date = dayParser.date(from: raw) else { return "-" }
        let i = Calendar.current.component(.weekday, from: date)   // 1 = 周日
        return ["日", "一", "二", "三", "四", "五", "六"][i - 1]
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
