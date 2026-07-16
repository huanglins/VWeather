//
//  AppSettings.swift
//  VWeather
//
//  应用偏好设置（温度单位等），持久化到 App Group 的 UserDefaults。
//

import Foundation
import Observation
import WidgetKit

/// 温度单位
enum TemperatureUnit: String, CaseIterable {
    case celsius
    case fahrenheit

    var symbol: String { self == .celsius ? "°C" : "°F" }
    var displayName: String { self == .celsius ? "摄氏 °C" : "华氏 °F" }
}

/// ⚠️ `temperatureUnit` 必须是**存储属性**。
///
/// 它原本是个计算属性、每次读写直通 UserDefaults —— 看着更"无状态"，但
/// @Observable 只追踪存储属性，计算属性改了不会触发任何视图重绘。
/// 症状就是：设置页把单位改成华氏，首页还是摄氏，得杀掉重进才生效。
/// 改成存储属性 + didSet 落盘，读的人（首页、城市列表、卡片）自动跟着变。
@Observable
class AppSettings {
    static let shared = AppSettings()

    /// 存 App Group 而非 UserDefaults.standard —— 小组件要读同一份设置。
    /// 用 standard 的话两个进程各存各的：主 App 设成华氏，小组件还是摄氏。
    @ObservationIgnored private let ud = UserDefaults(suiteName: APP_GROUP) ?? .standard

    var temperatureUnit: TemperatureUnit {
        didSet {
            guard temperatureUnit != oldValue else { return }
            ud.set(temperatureUnit.rawValue, forKey: Self.kUnit)
            // 小组件是独立进程，不会因为 App 改了设置就自己重画
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static let kUnit = "VW_temperatureUnit"

    init() {
        let group = UserDefaults(suiteName: APP_GROUP) ?? .standard
        // 迁移：老版本存在 standard 里。group 里没有时回退读一次，
        // 免得升级后用户的单位设置被悄悄重置成摄氏。
        let raw = group.string(forKey: Self.kUnit)
            ?? UserDefaults.standard.string(forKey: Self.kUnit)
            ?? ""
        temperatureUnit = TemperatureUnit(rawValue: raw) ?? .celsius
    }

    /// 摄氏原值 → 按当前单位格式化（不带单位符号），如 "23°"
    func tempText(_ celsius: Double?) -> String {
        guard let c = celsius else { return "--" }
        return "\(Int(round(convert(c))))°"
    }

    /// 摄氏原值 → 按当前单位格式化（带单位符号），如 "23°C" / "73°F"
    func tempTextWithUnit(_ celsius: Double?) -> String {
        guard let c = celsius else { return "--" }
        return "\(Int(round(convert(c))))\(temperatureUnit.symbol)"
    }

    private func convert(_ celsius: Double) -> Double {
        temperatureUnit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }
}
