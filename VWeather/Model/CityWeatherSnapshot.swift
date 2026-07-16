//
//  CityWeatherSnapshot.swift
//  VWeather
//
//  城市天气 + 日月快照。
//  天气 / 太阳 / 月亮各以「整个模型的 JSON」存一列，避免与数据库字段一一对应赋值——
//  新增展示字段时只改对应模型（WeatherReport / VHLSunInfo / VHLMoonInfo），
//  快照存储、refresh、UI 会自动同步，不会遗漏。
//

import Foundation

/// 城市天气 + 日月快照。以 `cityKey` 与 `CityModel` 关联。
struct CityWeatherSnapshot: VHLSQLiteObject {
    var pkid: Int?
    var cityKey: String?        // 关联城市（唯一键）

    // 各模型整体 JSON（避免逐字段映射）
    var weatherJSON: String?    // WeatherReport（后台为主，WeatherKit 兜底）
    var sunJSON: String?        // VHLSunInfo
    var moonJSON: String?       // VHLMoonInfo

    /// 最后一次**尝试**刷新天气的时间（成功或失败都记）。
    /// 失败也记，是为了让数据源故障时按节流间隔退避，而不是每次刷新都重试。
    var updateDate: Date?

    init() {}

    func uniqueKeys() -> [String]? { ["cityKey"] }

    // MARK: - 便捷访问（惰性解码；计算属性不入库）

    /// 天气报告。空报告一律当作「没有数据」：
    ///   · 后台可能返回 200 但各项全空
    ///   · 旧版本这一列存的是 WeatherDisplay（WeatherKit 的 12 个标量投影），
    ///     字段名全不匹配，解码得到的是一个各项皆空的报告
    /// 两种情况都该触发重新取数，而不是把一屏空白当成有效缓存。
    var weather: WeatherReport? {
        guard let r: WeatherReport = Self.decodeJSON(weatherJSON), !r.isEmpty else { return nil }
        return r
    }
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

// 注：旧库里的 supplementJSON / supplementDate 两列会成为孤儿 —— VHLSQLite 只加列不删列。
// 无害，留着即可；强行清理要写迁移，不值当。
//
// 那两列是双源时代的产物：基础天气走 WeatherKit、补充数据走后台，各存一列、各自节流。
// 拆成两个节流是因为 Widget 每 30 分钟刷新会一直把 updateDate 顶新，
// 导致主 App 每次都命中节流、补充数据永远拉不到。
// 现在只有一个数据链路（后台为主、WeatherKit 兜底），一个 updateDate 就够了。
