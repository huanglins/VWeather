//  WeatherSummaryChipsView.swift
//  VWeather
//
//  首页头部下方的三项摘要指标。
//

import SwiftUI

struct WeatherSummaryChipsView: View {
    let now: WeatherNow?
    let air: AirQuality?

    var body: some View {
        HStack(spacing: 10) {
            chip("体感温度", systemImage: "thermometer.medium", value: tempText(now?.feelsLike))

            // 空气质量只有部分数据源支持。缺失时保留占位，避免切换数据源后整行布局跳动。
            chip("空气质量", systemImage: "aqi.medium", value: air?.category ?? "--")
            chip("湿度", systemImage: "humidity",
                 value: now?.humidity.map { "\(Int($0))%" } ?? "--")
        }
    }

    private func chip(_ title: String, systemImage: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        )
    }

    private func tempText(_ value: Double?) -> String {
        AppSettings.shared.tempText(value)
    }
}
