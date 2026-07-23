//  WeatherAlertsView.swift
//  VWeather
//
//  首页气象预警列表及预警详情。
//

import SwiftUI

struct WeatherAlertsView: View {
    let alerts: [WeatherAlertInfo]
    let condition: VWCondition
    let isNight: Bool

    @State private var isExpanded = false

    private var visibleAlerts: [WeatherAlertInfo] {
        isExpanded ? alerts : Array(alerts.prefix(3))
    }

    var body: some View {
        WeatherCard {
            VStack(spacing: 10) {
                ForEach(visibleAlerts) { alert in
                    NavigationLink {
                        alertDetail(alert)
                    } label: {
                        alertRow(alert)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                    )

                    if alert.id != visibleAlerts.last?.id || alerts.count > 3 {
                        Divider()
                            .overlay(.white.opacity(0.15))
                            .transition(.opacity)
                    }
                }

                if alerts.count > 3 {
                    expandButton
                }
            }
            .animation(.snappy(duration: 0.38, extraBounce: 0.08), value: isExpanded)
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.38, extraBounce: 0.08)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? "收起" : "展开其余 \(alerts.count - 3) 条")
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 合规要求预警传播时必须注明发布单位与发布时间，故直接展示在列表行中。
    private func alertRow(_ alert: WeatherAlertInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(alertColor(alert))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title ?? alert.type ?? "预警")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let sender = alert.sender {
                    Text("\(sender) · \(QWeatherFormat.timeText(alert.pubTime))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// `text` 为上游预警原文，按合规要求原样展示，不做改写或摘要。
    private func alertDetail(_ alert: WeatherAlertInfo) -> some View {
        ZStack {
            WeatherBackground(condition: condition, isNight: isNight)

            ScrollView {
                VStack(spacing: 14) {
                    WeatherCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(alertColor(alert))
                            Text(alert.title ?? alert.type ?? "预警")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                    }

                    WeatherCard(title: "预警内容", systemImage: "doc.text") {
                        Text(alert.text ?? "--")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let instruction = alert.instruction, !instruction.isEmpty {
                        WeatherCard(title: "防御指引", systemImage: "shield") {
                            Text(instruction)
                                .font(.callout)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WeatherCard(title: "发布信息", systemImage: "info.circle") {
                        VStack(spacing: 4) {
                            metricLine("发布单位", alert.sender ?? "--")
                            metricLine("发布时间", QWeatherFormat.timeText(alert.pubTime))
                            metricLine("预警类型", alert.type ?? "--")
                            if let start = alert.startTime {
                                metricLine("生效时间", QWeatherFormat.timeText(start))
                            }
                            if let end = alert.endTime {
                                metricLine("失效时间", QWeatherFormat.timeText(end))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("气象预警")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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

    private func alertColor(_ alert: WeatherAlertInfo) -> Color {
        switch alert.color?.lowercased() {
        case "blue":   return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        case "white":  return .gray
        default:        return .white
        }
    }
}
