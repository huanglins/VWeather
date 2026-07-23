//
//  WeatherHourlyForecastView.swift
//  VWeather
//
//  首页逐小时天气预报。
//

import SwiftUI

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
        guard let time = WeatherTime.date(hour.time) else { return false }
        return report.isNight(at: time)
    }

    var body: some View {
        WeatherCard(title: "小时天气预报", systemImage: "clock", contentHorizontalPadding: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: VWDesign.Spacing.hourlyGap) {
                    ForEach(hours) { hour in
                        VStack(spacing: VWDesign.Spacing.hourlyStack) {
                            Text(QWeatherFormat.hourText(hour.time))
                                .font(.caption2)
                                .foregroundStyle(VWDesign.Palette.secondary)
                                .lineLimit(1)

                            Image(systemName: (hour.condition ?? .unknown).symbol(isNight: isNight(hour)))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                                .frame(height: 24)

                            // 只在有降水可能时显示概率，否则每格都挂个 0% 是纯噪音
//                            if let pop = hour.precipitationChance, pop > 0 {
//                                Text("\(Int(pop))%")
//                                    .font(.caption2)
//                                    .foregroundStyle(VWDesign.Palette.tertiary)
//                            } else {
//                                Text(" ").font(.caption2)
//                            }

                            Text(AppSettings.shared.tempText(hour.temperature))
                                .font(VWDesign.Typography.footnoteSemibold)
                                .foregroundStyle(VWDesign.Palette.primary)
                        }
                        //.frame(width: 44)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, VWDesign.Spacing.scrollV)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}
