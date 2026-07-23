//
//  WeatherAstronomyDetailsView.swift
//  VWeather
//
//  可折叠的太阳与月亮详情。
//

import SwiftUI

struct WeatherAstronomyDetailsView: View {
    let sun: VHLSunInfo?
    let moon: VHLMoonInfo?

    var body: some View {
        VStack(spacing: 14) {
            AstronomyDetailCard(title: "太阳详情", systemImage: "sun.max") {
                metricLine("正午", VHLSunMoonManager.timeString(sun?.solarNoon))
                metricLine("子夜", VHLSunMoonManager.timeString(sun?.solarMidnight))
                metricLine("晨间蓝调", rangeText(sun?.morningBlueHourStart, sun?.morningBlueHourEnd))
                metricLine("暮间蓝调", rangeText(sun?.eveningBlueHourStart, sun?.eveningBlueHourEnd))
                metricLine("晨间黄金时刻", rangeText(sun?.morningGoldenHourStart, sun?.morningGoldenHourEnd))
                metricLine("暮间黄金时刻", rangeText(sun?.eveningGoldenHourStart, sun?.eveningGoldenHourEnd))
                metricLine("民用晨昏", rangeText(sun?.civilDawn, sun?.civilDusk))
                metricLine("航海晨昏", rangeText(sun?.nauticalDawn, sun?.nauticalDusk))
                metricLine("天文晨昏", rangeText(sun?.astronomicalDawn, sun?.astronomicalDusk))
                metricLine("白昼时长", durationText(sun?.daylightDuration))
                metricLine("夜晚时长", durationText(sun?.nightDuration))
                metricLine("太阳方位角", angleText(sun?.azimuth))
                metricLine("太阳高度角", angleText(sun?.altitude))
                metricLine("日出方位", angleText(sun?.sunriseAzimuth))
                metricLine("日落方位", angleText(sun?.sunsetAzimuth))
            }

            AstronomyDetailCard(title: "月亮详情", systemImage: "moon.stars") {
                metricLine("月龄", (moon?.ageInDays).map { String(format: "%.1f 天", $0) } ?? "--")
                metricLine("月亮星座", moon?.signName ?? "--")
                metricLine("月升", VHLSunMoonManager.timeString(moon?.moonrise))
                metricLine("月落", VHLSunMoonManager.timeString(moon?.moonset))
                metricLine("月升方位", angleText(moon?.moonriseAzimuth))
                metricLine("月落方位", angleText(moon?.moonsetAzimuth))
                metricLine("月亮方位角", angleText(moon?.azimuth))
                metricLine("月亮高度角", angleText(moon?.altitude))
                metricLine("距下次满月", daysText(moon?.daysToNextFullMoon))
                metricLine("距下次新月", daysText(moon?.daysToNextNewMoon))
            }
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

    private func rangeText(_ start: Date?, _ end: Date?) -> String {
        "\(VHLSunMoonManager.timeString(start)) - \(VHLSunMoonManager.timeString(end))"
    }

    private func angleText(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "--"
    }

    private func durationText(_ seconds: Double?) -> String {
        seconds.map { VHLSunMoonManager.durationString($0) } ?? "--"
    }

    private func daysText(_ value: Int?) -> String {
        value.map { "\($0) 天" } ?? "--"
    }
}

private struct AstronomyDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false
    @State private var expandedContentHeight: CGFloat = 0

    private let expansionAnimation = Animation.snappy(duration: 0.38, extraBounce: 0.08)

    var body: some View {
        WeatherCard {
            VStack(spacing: 0) {
                Button {
                    withAnimation(expansionAnimation) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label(title, systemImage: systemImage)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(VWDesign.Typography.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    content()
                }
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: AstronomyDetailHeightKey.self,
                                        value: proxy.size.height)
                    }
                }
                .onPreferenceChange(AstronomyDetailHeightKey.self) {
                    expandedContentHeight = $0
                }
                .frame(height: isExpanded ? expandedContentHeight : 0, alignment: .top)
                .opacity(isExpanded ? 1 : 0)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
            }
            .animation(expansionAnimation, value: isExpanded)
            .clipped()
        }
    }
}

private struct AstronomyDetailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
