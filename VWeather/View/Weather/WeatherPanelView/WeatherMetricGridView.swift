//  WeatherMetricGridView.swift
//  VWeather
//
//  首页天气指标网格。
//

import SwiftUI

struct WeatherMetricGridView: View {
    let now: WeatherNow?
    let today: WeatherDay?
    let sun: VHLSunInfo?
    let moon: VHLMoonInfo?
    let minutely: MinutelyPrecip?

    var body: some View {
        // 只有 8 张固定卡片，不需要懒加载。LazyVGrid 会把整组卡片的首次创建
        // 推迟到滚入视口时，恰好造成用户感知到的第一次滚动掉帧。
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                MetricCard(title: "日落", systemImage: "sunset", footnote: nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        MetricValue(value: VHLSunMoonManager.timeString(sun?.sunset))
                        SunArc(sun: sun)
                            .frame(height: 44)
                        HStack {
                            Text("日出")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(VHLSunMoonManager.timeString(sun?.sunrise))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                MetricCard(title: "云量", systemImage: "cloud",
                           footnote: cloudAdvice(now?.cloudCover)) {
                    MetricValue(value: now?.cloudCover.map { "\(Int($0))%" } ?? "--")
                }
            }

            GridRow {
                // 该值来自逐日预报的最高 UV，不是实时观测值。
                MetricCard(title: "今日紫外线最高", systemImage: "sun.max",
                           footnote: uvAdvice(today?.uvIndexMax)) {
                    MetricValue(
                        value: today?.uvIndexMax.map { String(format: "%.0f", $0) } ?? "--",
                        caption: uvLevel(today?.uvIndexMax)
                    )
                }

                MetricCard(title: "风", systemImage: "wind", footnote: nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        MetricValue(value: beaufort(now?.windSpeed).map { "\($0)" } ?? "--",
                                    unit: "级")

                        Spacer()

                        VStack(spacing: 3) {
                            metricLine("风速", now?.windSpeed.map {
                                String(format: "%.0f km/h", $0)
                            } ?? "--")
                            metricLine("风向", windText(now?.windDirectionText,
                                                        now?.windDirection))
                        }
                    }
                }
            }

            GridRow {
                MetricCard(title: "降水", systemImage: "drop", footnote: minutely?.summary) {
                    MetricValue(
                        value: now?.precipitation.map { String(format: "%g", $0) } ?? "0",
                        unit: "mm"
                    )
                }

                MetricCard(title: "能见度", systemImage: "eye",
                           footnote: visibilityAdvice(now?.visibility)) {
                    MetricValue(
                        value: now?.visibility.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "km"
                    )
                }
            }

            GridRow {
                MetricCard(title: "气压",
                           systemImage: "gauge.with.dots.needle.bottom.50percent",
                           footnote: nil) {
                    PressureGauge(value: now?.pressure)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                }

                MetricCard(title: "月相", systemImage: "moon.stars", footnote: moon?.phaseName) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(moon?.phaseEmoji ?? "--")
                            .font(.system(size: 30))
                        Text((moon?.illumination).map { "照度 \(Int($0))%" } ?? "--")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
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

    private func windText(_ text: String?, _ degrees: Double?) -> String {
        if let text, !text.isEmpty { return text }
        guard let degrees else { return "--" }
        let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[index] + "风"
    }

    private func beaufort(_ kmh: Double?) -> Int? {
        guard let kmh else { return nil }
        let upperBounds: [Double] = [1, 5, 11, 19, 28, 38, 49, 61, 74, 88, 102, 117]
        for (level, upperBound) in upperBounds.enumerated() where kmh < upperBound {
            return level
        }
        return 12
    }

    private func uvLevel(_ uv: Double?) -> String? {
        guard let uv else { return nil }
        switch uv {
        case ..<3:  return "低"
        case ..<6:  return "中等"
        case ..<8:  return "高"
        case ..<11: return "很高"
        default:    return "极高"
        }
    }

    private func uvAdvice(_ uv: Double?) -> String? {
        guard let uv else { return nil }
        switch uv {
        case ..<3: return "紫外线较弱，无需特别防护。"
        case ..<6: return "紫外线中等，建议防晒。"
        case ..<8: return "紫外线较强，注意遮阳。"
        default:   return "紫外线极强，尽量避免长时间户外活动。"
        }
    }

    private func cloudAdvice(_ cover: Double?) -> String? {
        guard let cover else { return nil }
        switch cover {
        case ..<10: return "天空晴朗，少有云彩。"
        case ..<40: return "少云，阳光充足。"
        case ..<70: return "多云，时有遮蔽。"
        default:    return "云层密布，阳光稀少。"
        }
    }

    private func visibilityAdvice(_ km: Double?) -> String? {
        guard let km else { return nil }
        switch km {
        case ..<1:  return "能见度很低，出行注意安全。"
        case ..<5:  return "能见度较低，视野受限。"
        case ..<15: return "能见度一般。"
        default:    return "天空通透，视野极为开阔。"
        }
    }
}

private struct SunArc: View {
    let sun: VHLSunInfo?

    private var progress: Double? {
        guard let sun else { return nil }
        let total = sun.sunset.timeIntervalSince(sun.sunrise)
        guard total > 0 else { return nil }
        let progress = Date().timeIntervalSince(sun.sunrise) / total
        return (0...1).contains(progress) ? progress : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 6
            let width = geometry.size.width - inset * 2
            let height = geometry.size.height - inset * 2

            ZStack(alignment: .topLeading) {
                ArcPath(upTo: 1)
                    .stroke(.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                if let progress {
                    ArcPath(upTo: progress)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.6), .white],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )

                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .shadow(color: .white.opacity(0.9), radius: 4)
                        .position(Self.point(progress, width, height))
                }
            }
            .frame(width: width, height: height)
            .offset(x: inset, y: inset)
        }
    }

    static func point(_ progress: Double, _ width: CGFloat, _ height: CGFloat) -> CGPoint {
        let controlX = width / 2
        let controlY = -height * 0.9
        let inverse = 1 - progress
        return CGPoint(
            x: 2 * inverse * progress * controlX + progress * progress * width,
            y: inverse * inverse * height
                + 2 * inverse * progress * controlY
                + progress * progress * height
        )
    }
}

private struct ArcPath: Shape {
    let upTo: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: SunArc.point(0, rect.width, rect.height))
        let steps = 48
        for index in 1...steps {
            path.addLine(
                to: SunArc.point(Double(index) / Double(steps) * upTo,
                                 rect.width, rect.height)
            )
        }
        return path
    }
}

private struct PressureGauge: View {
    let value: Double?

    private static let sweep: Double = 260
    private static let lowerBound: Double = 950
    private static let upperBound: Double = 1050

    private var fraction: Double? {
        guard let value else { return nil }
        return min(max((value - Self.lowerBound) / (Self.upperBound - Self.lowerBound), 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                // 原实现用 41 个 Capsule + rotationEffect 组成刻度，首次出现会创建
                // 大量 SwiftUI 子视图。Canvas 将它们合并成一次绘制提交。
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0..<41 {
                        let progress = Double(index) / 40
                        let length: CGFloat = index % 10 == 0 ? 7 : 4
                        let opacity = index % 10 == 0 ? 0.7 : 0.28
                        drawTick(in: &context, center: center, side: side,
                                 progress: progress, length: length,
                                 width: 1.2, opacity: opacity)
                    }

                    if let fraction {
                        drawTick(in: &context, center: center, side: side,
                                 progress: fraction, length: 12,
                                 width: 2.5, opacity: 1)
                    }
                }
                .frame(width: side, height: side)

                VStack(spacing: 0) {
                    Text(value.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("hPa")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func drawTick(in context: inout GraphicsContext, center: CGPoint,
                          side: CGFloat, progress: Double, length: CGFloat,
                          width: CGFloat, opacity: Double) {
        let degrees = -Self.sweep / 2 + progress * Self.sweep
        let radians = degrees * .pi / 180
        let radius = side / 2 - 5
        let direction = CGVector(dx: sin(radians), dy: -cos(radians))
        let tickCenter = CGPoint(x: center.x + direction.dx * radius,
                                 y: center.y + direction.dy * radius)
        let halfLength = length / 2
        var path = Path()
        path.move(to: CGPoint(x: tickCenter.x - direction.dx * halfLength,
                              y: tickCenter.y - direction.dy * halfLength))
        path.addLine(to: CGPoint(x: tickCenter.x + direction.dx * halfLength,
                                 y: tickCenter.y + direction.dy * halfLength))
        context.stroke(path, with: .color(.white.opacity(opacity)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
