//
//  WeatherDisplayFormat.swift
//  VWeather
//
//  天气面板共用的时间与颜色格式化工具。
//

import SwiftUI
import UIKit

/// 后台归一化后仍保留了和风的两个原始约定：颜色是 "rgba(...)" 字符串、时间不带秒。
/// 这两处解析在预警 / 空气质量 / 分钟降水里都要用，故集中在此。
enum QWeatherFormat {
    /// 解析后台给的 "rgba(r,g,b,a)" 字符串
    static func color(_ raw: String?) -> Color? {
        guard let raw,
              raw.hasPrefix("rgba("), raw.hasSuffix(")") else { return nil }
        let body = raw.dropFirst(5).dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return Color(.sRGB,
                     red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255,
                     opacity: parts[3])
    }

    /// 和风的时间**不带秒**，且两种时区写法都出现过（实测同一响应里两种都有）：
    ///   - UTC：`2026-07-15T10:00Z`（airHourly / 预警）
    ///   - 东八区：`2026-07-15T17:00+08:00`（minutely）
    /// 故不能用 ISO8601DateFormatter（其 withInternetDateTime 要求有秒，会解析失败）。
    /// `ZZZZZ` 两种写法都能吃。

    /// 上游等级色是给「大色块 + 黑字」设计的，如「良」是纯黄 rgba(255,255,0)。
    /// 这种色画成细柱放在浅色卡片上几乎看不见（实测）。
    /// 故保留色相与饱和度、只在亮度过高时压暗：色仍与 AQI 等级严格同源，
    /// 不会出现「色和级对不上」，只是把对比度补回来。深色模式下卡片是深底，无需处理。
    static func legible(_ color: Color, isDark: Bool) -> Color {
        guard !isDark else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        // sRGB 相对亮度，阈值 0.55 约等于「在白底上还看得清」的下限
        while b > 0.25, luminance(hue: h, saturation: s, brightness: b) > 0.55 {
            b *= 0.92
        }
        return Color(UIColor(hue: h, saturation: s, brightness: b, alpha: a))
    }

    private static func luminance(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
            .getRed(&r, green: &g, blue: &bl, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * bl
    }

    /// 解析实现在模型层（WeatherTime）—— Widget 也要用，而视图文件只在主 App target。
    static func date(_ raw: String?) -> Date? { WeatherTime.date(raw) }

    /// 日期 + 时间。解析失败时原样返回，好过显示 "--"
    /// （预警的发布时间是合规必需项，宁可显示原始串也不能吞掉）。
    static func timeText(_ raw: String?) -> String {
        guard let raw else { return "--" }
        guard let date = date(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// 只要小时，给逐小时预报用。当前这一小时显示「现在」。
    ///
    /// 不能用 `timeText`：它带完整日期，24 格横排会把每格撑到 200pt 宽，
    /// 布局直接失控。逐小时的语境里日期是冗余的。
    static func hourText(_ raw: String?) -> String {
        guard let raw, let date = date(raw) else { return "--" }
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .hour) { return "现在" }
        return date.formatted(.dateTime.hour())
    }
}
