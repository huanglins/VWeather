//
//  WeatherSupplement.swift
//  VWeather
//
//  天气补充数据（空气质量 / 生活指数 / 分钟降水 / 气象预警）。
//  数据源为 vapi 后台 GET /v1/weather?resources=...
//
//  后台是与数据源无关的抽象层，本模型对齐的是它的**中立 schema**，
//  不含任何平台专有字段 —— 后台把和风换成别家时，这里零改动。
//
//  与 `WeatherDisplay` 平级、不合并：`WeatherDisplay` 是端上 WeatherKit 的投影，
//  本模型来自后台。混在一起会让「哪个字段来自哪个源」不可知，
//  也会让「一方失败另一方仍可用」难以表达。
//

import Foundation

// MARK: - 基础天气
//
// 单位由后台的中立 schema 保证：温度 ℃、风速 km/h、气压 hPa、能见度 km、
// 湿度与概率 0-100、风向 0-360 度、时间 ISO8601 带时区。
// 各数据源的原始表示差异极大（有的给字符串、有的湿度是小数），后台已抹平。

/// 实时天气
struct WeatherNow: Codable {
    var observedAt: String?
    var temperature: Double?
    var feelsLike: Double?
    var condition: VWCondition?
    var conditionText: String?      // 人读文案（如「阴」）
    var rawCondition: String?       // 上游原始码，仅供排查
    var humidity: Double?           // 0-100
    var pressure: Double?
    var windSpeed: Double?
    var windDirection: Double?      // 0-360 度
    var windDirectionText: String?  // 如「东北风」，某些源没有
    var windGust: Double?
    var uvIndex: Double?
    var visibility: Double?         // km
    var dewPoint: Double?
    var cloudCover: Double?         // 0-100
    var precipitation: Double?      // mm
}

/// 逐日预报的一天
struct WeatherDay: Codable, Identifiable {
    var date: String?
    var tempMax: Double?
    var tempMin: Double?
    var condition: VWCondition?
    var conditionText: String?
    var rawCondition: String?
    /// 夜间天况。某些源不区分白天/夜间，此时为 nil。
    var conditionNight: VWCondition?
    var conditionTextNight: String?
    var precipitationChance: Double?    // 0-100
    var precipitationAmount: Double?    // mm
    var precipitationType: String?
    var windSpeed: Double?
    var windDirection: Double?
    var windDirectionText: String?
    var humidity: Double?
    var pressure: Double?
    var uvIndexMax: Double?
    var sunrise: String?
    var sunset: String?
    var moonrise: String?
    var moonset: String?
    var moonPhase: String?

    var id: String { date ?? UUID().uuidString }
}

/// 逐小时预报的一小时
struct WeatherHour: Codable, Identifiable {
    var time: String?
    var temperature: Double?
    var feelsLike: Double?
    var condition: VWCondition?
    var conditionText: String?
    var rawCondition: String?
    var precipitationChance: Double?
    var precipitationAmount: Double?
    var precipitationType: String?
    var humidity: Double?
    var pressure: Double?
    var windSpeed: Double?
    var windDirection: Double?
    var windDirectionText: String?
    var uvIndex: Double?
    var cloudCover: Double?
    var dewPoint: Double?
    var visibility: Double?

    var id: String { time ?? UUID().uuidString }
}

// MARK: - 补充数据

/// 空气质量。实时与预报共用同一结构（后台 schema 如此设计）。
struct AirQuality: Codable, Identifiable {
    /// 采用的 AQI 标准，如 cn-mee。**不假定是中国标准**——
    /// 后台不绑定单一标准（和风同时返回多套，别家可能只给一套）。
    var standard: String?
    var aqi: Double?            // 数值，用于比较/上色
    var aqiText: String?        // 展示用；某些标准会给 ">300" 这类非数值
    var category: String?       // 优 / 良 / 轻度污染 ...
    var level: String?
    var color: String?          // "rgba(r,g,b,a)"
    var primaryPollutant: String?   // 首要污染物，空气好时为 nil
    var effect: String?         // 健康影响
    var advice: String?         // 一般人群建议
    var adviceSensitive: String?// 敏感人群建议
    var pollutants: Pollutants?

    // 预报专用时间字段（实时为 nil）
    var time: String?           // 逐小时预报
    var startTime: String?      // 逐日预报
    var endTime: String?

    /// 其它 AQI 标准，如 {"us-epa": {...}}。一般用不上，保留以备。
    var otherStandards: [String: OtherStandard]?

    var id: String { time ?? startTime ?? "current" }

    struct Pollutants: Codable {
        var pm2p5: Double?      // 注意是 pm2p5 不是 pm25
        var pm10: Double?
        var o3: Double?
        var no2: Double?
        var so2: Double?
        var co: Double?         // 单位 mg/m³，其余为 μg/m³
    }

    struct OtherStandard: Codable {
        var aqi: Double?
        var aqiText: String?
        var category: String?
    }
}

/// 生活指数（运动 / 洗车 / 穿衣 / 紫外线 ...）
struct LifeIndex: Codable, Identifiable {
    var type: String?
    var name: String?
    var level: String?
    var category: String?
    var text: String?
    var date: String?

    var id: String { (date ?? "") + "-" + (type ?? "") }
}

/// 分钟级降水
struct MinutelyPrecip: Codable {
    /// 「95分钟后雨就停了」这类自然语言描述
    var summary: String?
    /// 采样间隔分钟数（各源不同）
    var interval: Double?
    var items: [MinutelyItem]?

    struct MinutelyItem: Codable {
        var time: String?
        var precipitation: Double?   // mm
        var type: String?            // rain / snow
        var chance: Double?          // 0-100
    }
}

/// 气象预警
///
/// ⚠️ 合规：《气象预报发布与传播管理办法》第九条要求传播气象预警必须注明
/// 发布单位（`sender`）与发布时间（`pubTime`），且不得更改内容（`text` 须原样展示）。
/// 展示预警的 UI 必须带上这三项，不要省略或改写。
struct WeatherAlertInfo: Codable, Identifiable {
    var id: String?
    var title: String?
    var type: String?           // 预警类型（如「大风」）
    var severity: String?       // 中立分级：minor/moderate/severe/extreme
    var severityText: String?   // 上游原文
    var color: String?          // 色名：blue/yellow/orange/red
    var urgency: String?        // 中国数据源常为 nil
    var certainty: String?      // 中国数据源常为 nil
    var status: String?
    var startTime: String?
    var endTime: String?
    var text: String?           // 合规：预警正文原文，不得改写
    var instruction: String?    // 防御指引
    var sender: String?         // 合规：发布单位，必须展示
    var pubTime: String?        // 合规：发布时间，必须展示
}

/// 后台聚合接口 GET /v1/weather?resources=... 的响应
struct WeatherSupplement: Codable {
    var status: Int?
    var location: SupplementLocation?
    var updatedAt: String?
    var data: ResourceData?
    /// 各资源实际由谁供数（后台换源/降级时会变）。仅供排查，UI 不该依赖。
    var providers: [String: String?]?
    /// 各资源的失败原因。某项为 nil 表示成功。
    var errors: [String: String?]?

    struct SupplementLocation: Codable {
        var lng: Double?
        var lat: Double?
        var name: String?
    }

    /// 资源数据。键名与后台的资源名一致，含连字符的需 CodingKeys 映射。
    struct ResourceData: Codable {
        var now: WeatherNow?
        var daily: [WeatherDay]?
        var hourly: [WeatherHour]?
        var air: AirQuality?
        var airDaily: [AirQuality]?
        var airHourly: [AirQuality]?
        var indices: [LifeIndex]?
        var minutely: MinutelyPrecip?
        var alerts: [WeatherAlertInfo]?

        enum CodingKeys: String, CodingKey {
            case now, daily, hourly
            case air
            case airDaily = "air-daily"     // 后台资源名带连字符
            case airHourly = "air-hourly"
            case indices, minutely, alerts
        }
    }

    // MARK: - 便捷访问（让调用方不必层层解包）

    var now: WeatherNow? { data?.now }
    var daily: [WeatherDay]? { data?.daily }
    var hourly: [WeatherHour]? { data?.hourly }
    var air: AirQuality? { data?.air }
    var airDaily: [AirQuality]? { data?.airDaily }
    var airHourly: [AirQuality]? { data?.airHourly }
    var indices: [LifeIndex]? { data?.indices }
    var minutely: MinutelyPrecip? { data?.minutely }
    var alerts: [WeatherAlertInfo]? { data?.alerts }

    /// 是否一项数据都没有（后台整体不可用时用于判断是否值得入库）
    var isEmpty: Bool {
        now == nil && air == nil && minutely == nil
            && (daily?.isEmpty ?? true) && (hourly?.isEmpty ?? true)
            && (indices?.isEmpty ?? true) && (alerts?.isEmpty ?? true)
    }
}
