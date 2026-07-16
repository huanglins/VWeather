//
//  WeatherTheme.swift
//  VWeather
//
//  首页的视觉基调：随天气变化的渐变背景 + 浮在其上的毛玻璃卡片。
//
//  背景一律是有色深底，所以卡片内的文字**固定用白色系**，不跟随浅色/深色模式。
//  这不是偷懒：`.primary` 在浅色模式下是黑色，落在蓝色渐变上会糊成一团。
//

import SwiftUI

// MARK: - 调色板

enum WeatherPalette {

    /// 天况 + 昼夜 → 背景渐变色。
    ///
    /// 取色原则：贴合天况的直觉（晴用蓝、雨用灰蓝、沙尘用土黄），
    /// 同时保证**最浅的那一端也压得住白字** —— 卡片上的文字是白的，
    /// 背景一旦太亮就没法读了。夜间统一走深色系。
    static func colors(for condition: VWCondition, isNight: Bool) -> [Color] {
        if isNight { return night(condition) }
        return day(condition)
    }

    private static func day(_ c: VWCondition) -> [Color] {
        switch c {
        case .clear:
            return [hex(0x4EA8F5), hex(0x1E6FD9)]
        case .partlyCloudy:
            return [hex(0x6FB0E8), hex(0x3A7FC4)]
        case .cloudy:
            return [hex(0x8CA6BE), hex(0x556F8C)]
        case .overcast:
            return [hex(0x7E8B99), hex(0x4A5663)]
        case .fog, .haze:
            return [hex(0xA6ADB3), hex(0x6B737A)]
        case .drizzle, .rain:
            return [hex(0x5C86AC), hex(0x2C4A6B)]
        case .heavyRain, .thunderstorm:
            return [hex(0x40536E), hex(0x1C2636)]
        case .freezingRain, .sleet, .hail:
            return [hex(0x8FA8C0), hex(0x546E8A)]
        case .snow, .heavySnow:
            return [hex(0xA9C4DA), hex(0x6B89A6)]
        case .windy:
            return [hex(0x6FA8C8), hex(0x3A6E90)]
        case .sand:
            return [hex(0xC9A26B), hex(0x8A6A3C)]
        case .unknown:
            return [hex(0x8CA6BE), hex(0x556F8C)]
        }
    }

    private static func night(_ c: VWCondition) -> [Color] {
        switch c {
        case .clear, .partlyCloudy:
            return [hex(0x24365E), hex(0x0C1428)]
        case .cloudy, .overcast:
            return [hex(0x2C3648), hex(0x11161F)]
        case .fog, .haze:
            return [hex(0x3A3F45), hex(0x16191D)]
        case .drizzle, .rain, .heavyRain, .thunderstorm:
            return [hex(0x243448), hex(0x0B1119)]
        case .freezingRain, .sleet, .hail, .snow, .heavySnow:
            return [hex(0x3A4C60), hex(0x141D28)]
        case .windy:
            return [hex(0x27414F), hex(0x0D1820)]
        case .sand:
            return [hex(0x5A4830), hex(0x201A11)]
        case .unknown:
            return [hex(0x2C3648), hex(0x11161F)]
        }
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: 1)
    }
}

// MARK: - 背景

/// 随天气变化的渐变背景。
struct WeatherBackground: View {
    let condition: VWCondition
    let isNight: Bool

    @State private var drift = false

    /// 首帧过后才允许渐变过渡。
    ///
    /// 首帧时快照还没读出来，condition 是占位的 .unknown（灰）、isNight 是 false；
    /// 紧接着 ContentView 在自己的 onAppear 里**同步**读到缓存，两个值一起跳到真实值。
    /// 那是「数据到位」，不是「天气变了」—— 不该有 0.8 秒的过渡，
    /// 否则每次冷启动都会看到一次灰到蓝的爬色。
    @State private var settled = false

    var body: some View {
        ZStack {
            LinearGradient(colors: WeatherPalette.colors(for: condition, isNight: isNight),
                           startPoint: .top, endPoint: .bottom)

            // 缓慢漂移的高光，让纯渐变不至于太死板。
            //
            // 用 RadialGradient 而非粒子/动画图层：这是一层静态图形加一个
            // 位移动画，几乎不耗电。天气 App 常驻前台的时间不长，
            // 但没必要为一点装饰去烧 CPU。
            RadialGradient(colors: [.white.opacity(isNight ? 0.10 : 0.16), .clear],
                           center: .init(x: drift ? 0.78 : 0.42, y: drift ? 0.10 : 0.22),
                           startRadius: 4,
                           endRadius: 320)
                .blendMode(.softLight)
        }
        .ignoresSafeArea()
        // 天况变了要平滑过渡，不能硬切 —— 但首帧的占位值除外，见 settled
        .animation(settled ? .easeInOut(duration: 0.8) : nil, value: condition)
        .animation(settled ? .easeInOut(duration: 0.8) : nil, value: isNight)
        .onAppear {
            // 排到下一个主线程周期再开启过渡。
            // 首帧的 onAppear 里，ContentView 还要同步读缓存并改 condition ——
            // 那一跳必须落在 settled 仍为 false 的时候。用 Task 跳一拍即可，
            // 不必关心父子视图 onAppear 的先后（都在同一周期内）。
            Task { @MainActor in settled = true }

            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - 卡片

/// 浮在渐变上的毛玻璃卡片。
struct WeatherCard<Content: View>: View {
    var title: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.14))
        )
        .overlay(
            // 一道极淡的描边，把卡片从背景里"托"出来。
            // 只靠半透明填充的话，卡片落在渐变较亮的一段时边界会消失。
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        )
    }
}

/// 卡片里的一个小指标（网格用）。
struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    var footnote: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        WeatherCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                content()
                if let footnote {
                    Spacer(minLength: 0)
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        }
    }
}

/// 指标卡里的大数字 + 单位
struct MetricValue: View {
    let value: String
    var unit: String? = nil
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            if let unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if let caption {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

extension Color {
    /// 0xRRGGBB 字面量建色。视图里要固定颜色时用它，
    /// 免得在渐变背景上误用会跟随浅色/深色模式的语义色。
    init(hex4 value: UInt32) {
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}
