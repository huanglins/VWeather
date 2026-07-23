//
//  WeatherMinutelyPrecipView.swift
//  VWeather
//
//  首页分钟级降水预报。
//

import Charts
import SwiftUI

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
