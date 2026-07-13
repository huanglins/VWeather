//
//  AppSettings.swift
//  VWeather
//
//  应用偏好设置（温度单位等），持久化到 UserDefaults。
//

import Foundation

/// 温度单位
enum TemperatureUnit: String, CaseIterable {
    case celsius
    case fahrenheit

    var symbol: String { self == .celsius ? "°C" : "°F" }
    var displayName: String { self == .celsius ? "摄氏 °C" : "华氏 °F" }
}

class AppSettings {
    static let shared = AppSettings()

    private let ud = UserDefaults.standard
    private let kUnit = "VW_temperatureUnit"

    var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: ud.string(forKey: kUnit) ?? "") ?? .celsius }
        set { ud.set(newValue.rawValue, forKey: kUnit) }
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
