//  WeatherAirQualityView.swift
//  VWeather
//
//  首页空气质量实况、污染物和空气质量预报。
//

import SwiftUI
import Charts

struct WeatherAirQualityView: View {
    let city: CityModel
    let air: AirQuality
    let initialHourly: [AirQuality]
    let daily: [AirQuality]

    @State private var loadedHourly: [AirQuality]?
    @State private var isLoadingHourly = false

    private var hourly: [AirQuality] {
        loadedHourly ?? initialHourly
    }

    var body: some View {
        VStack(spacing: 14) {
            currentAirCard

            if !hourly.isEmpty || !daily.isEmpty {
                forecastCard
            }
        }
        .onAppear {
            restoreCachedHourlyIfNeeded()
        }
    }

    private var currentAirCard: some View {
        WeatherCard(title: "空气质量", systemImage: "aqi.medium") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(QWeatherFormat.color(air.color) ?? .secondary)
                            .frame(width: 46, height: 46)
                        Text(air.aqiText ?? "--")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.75))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(air.category ?? "--")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let effect = air.effect, !effect.isEmpty {
                            Text(effect)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }

                metricLine("首要污染物", air.primaryPollutant ?? "无")
                if let pollutants = air.pollutants {
                    if let value = pollutants.pm2p5 {
                        metricLine("PM2.5", concentrationText(value))
                    }
                    if let value = pollutants.pm10 {
                        metricLine("PM10", concentrationText(value))
                    }
                    if let value = pollutants.o3 {
                        metricLine("臭氧 O₃", concentrationText(value))
                    }
                    if let value = pollutants.no2 {
                        metricLine("二氧化氮 NO₂", concentrationText(value))
                    }
                    if let value = pollutants.so2 {
                        metricLine("二氧化硫 SO₂", concentrationText(value))
                    }
                    // CO 的单位是 mg/m³，与其他污染物不同。
                    if let value = pollutants.co {
                        metricLine("一氧化碳 CO", String(format: "%.1f mg/m³", value))
                    }
                }

                if let advice = air.advice, !advice.isEmpty {
                    Text(advice)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var forecastCard: some View {
        WeatherCard(title: "空气质量预报", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(daily) { item in
                    forecastRow(dayText(item.startTime), air: item)
                }

                if !hourly.isEmpty {
                    AirHourlyChart(hours: hourly)
                } else {
                    Button(action: loadHourly) {
                        HStack(spacing: 6) {
                            if isLoadingHourly {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                            }
                            Text(isLoadingHourly ? "加载中…" : "查看逐小时空气质量")
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingHourly)
                }
            }
        }
    }

    private func forecastRow(_ title: String, air: AirQuality) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(air.category ?? "--")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(air.aqiText ?? "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(minWidth: 34)
                .padding(.vertical, 3)
                .background(QWeatherFormat.color(air.color) ?? .secondary, in: Capsule())
        }
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(VWDesign.Typography.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(VWDesign.Typography.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func restoreCachedHourlyIfNeeded() {
        guard loadedHourly == nil, initialHourly.isEmpty,
              let cached = CityWeatherManager.manager.cachedAirHourly(for: city) else { return }
        loadedHourly = cached
    }

    private func loadHourly() {
        guard !isLoadingHourly else { return }
        isLoadingHourly = true

        Task {
            let result = await CityWeatherManager.manager.loadAirHourly(for: city)
            await MainActor.run {
                loadedHourly = result
                isLoadingHourly = false
            }
        }
    }

    private func concentrationText(_ value: Double) -> String {
        String(format: "%.0f μg/m³", value)
    }

    private func dayText(_ raw: String?) -> String {
        guard let date = QWeatherFormat.date(raw) else { return raw ?? "--" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.month(.abbreviated).day())
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
