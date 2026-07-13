//
//  CityWeatherSnapshot.swift
//  VWeather
//
//  城市天气 + 日月快照。
//  天气 / 太阳 / 月亮各以「整个模型的 JSON」存一列，避免与数据库字段一一对应赋值——
//  新增展示字段时只改对应模型（WeatherDisplay / VHLSunInfo / VHLMoonInfo），
//  快照存储、refresh、UI 会自动同步，不会遗漏。
//

import Foundation

/// 天气展示模型（纯值 Codable）。从 WeatherKit 的 `VHLWeatherModel` 提取展示所需字段，
/// 以便整体 JSON 序列化。（`VHLWeatherModel` 含 WeatherKit 复杂类型，不适合直接入库/展示。）
struct WeatherDisplay: Codable {
    var temperature: Double?
    var apparentTemperature: Double?
    var highTemperature: Double?
    var lowTemperature: Double?
    var symbol: String?
    var conditionText: String?
    var uv: Int?
    var windSpeed: Double?
    var windDirection: String?
    var pressure: Double?
    var humidity: Int?
    var precipitationChance: Double?

    init() {}

    init(from w: VHLWeatherModel) {
        temperature = w.temperature
        apparentTemperature = w.apparentTemperature
        highTemperature = w.highTemperature
        lowTemperature = w.lowTemperature
        symbol = w.symbol
        conditionText = w.condition.map { "\($0)" }
        uv = w.uv
        windSpeed = w.windSpeed
        windDirection = w.windDirection
        pressure = w.pressure
        humidity = w.humidity
        precipitationChance = w.precipitationChance
    }
}

/// 城市天气 + 日月快照。以 `cityKey` 与 `CityModel` 关联。
struct CityWeatherSnapshot: VHLSQLiteObject {
    var pkid: Int?
    var cityKey: String?        // 关联城市（唯一键）

    // 各模型整体 JSON（避免逐字段映射）
    var weatherJSON: String?    // WeatherDisplay
    var sunJSON: String?        // VHLSunInfo
    var moonJSON: String?       // VHLMoonInfo

    var updateDate: Date?       // 快照更新时间

    init() {}

    func uniqueKeys() -> [String]? { ["cityKey"] }

    // MARK: - 便捷访问（惰性解码；计算属性不入库）
    var weather: WeatherDisplay? { Self.decodeJSON(weatherJSON) }
    var sun: VHLSunInfo? { Self.decodeJSON(sunJSON) }
    var moon: VHLMoonInfo? { Self.decodeJSON(moonJSON) }

    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func decodeJSON<T: Decodable>(_ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
