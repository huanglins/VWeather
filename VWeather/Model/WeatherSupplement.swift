//
//  WeatherSupplement.swift
//  VWeather
//
//  天气补充数据（空气质量 / 生活指数 / 分钟降水 / 天气预警）。
//  数据源为 vapi 后台 /v1/weather/supplement（后台代理和风天气并归一化）。
//
//  与 `WeatherDisplay` 平级、不合并：`WeatherDisplay` 是 WeatherKit 的投影，
//  本模型来自另一个数据源。混在一起会让「哪个字段来自哪个源」不可知，
//  也会让「一方失败另一方仍可用」难以表达。
//
//  字段结构由后台归一化保证，与和风原始响应解耦——以后后台换源/加源，此处不用改。
//

import Foundation

/// 空气质量（中国标准 AQI，生态环境部）。实时与预报共用同一结构。
struct AirQuality: Codable, Identifiable {
    var standard: String?       // 采用的标准，正常为 cn-mee
    var aqi: Double?            // 数值，用于比较/上色
    var aqiDisplay: String?     // 展示用字符串（可能是 ">300" 这类非数值）
    var category: String?       // 优 / 良 / 轻度污染 ...
    var level: String?
    var color: String?          // "rgba(r,g,b,a)"
    var primary: String?        // 首要污染物名称，空气好时为 nil
    var primaryCode: String?
    var effect: String?         // 健康影响
    var advice: String?         // 一般人群建议
    var adviceSensitive: String?// 敏感人群建议

    // 各污染物浓度。CO 单位 mg/m³，其余 μg/m³。
    // 仅实时接口提供；预报接口不给浓度，这些为 nil。
    var pm2p5: Double?
    var pm10: Double?
    var o3: Double?
    var no2: Double?
    var so2: Double?
    var co: Double?

    // 预报专用时间字段（实时接口为 nil）
    var startTime: String?      // 逐日预报：该天起始
    var endTime: String?        // 逐日预报：该天结束
    var time: String?           // 逐小时预报：该小时

    var id: String { time ?? startTime ?? "current" }
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

/// 分钟级降水（未来 2 小时，5 分钟粒度）
struct MinutelyPrecip: Codable {
    /// 「95分钟后雨就停了」这类自然语言描述
    var summary: String?
    var updateTime: String?
    var items: [MinutelyItem]?

    struct MinutelyItem: Codable {
        var time: String?
        var precip: String?     // 毫米，注意上游是字符串
        var type: String?       // rain / snow
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
    var type: String?
    var typeCode: String?
    var severity: String?
    var severityColor: String?  // "blue" / "yellow" / "orange" / "red"
    var colorRGBA: String?
    var icon: String?
    var urgency: String?        // 中国数据源常为 nil
    var certainty: String?      // 中国数据源常为 nil
    var status: String?
    var startTime: String?
    var effectiveTime: String?
    var endTime: String?
    var text: String?           // 合规：预警正文原文，不得改写
    var instruction: String?    // 防御指引
    var sender: String?         // 合规：发布单位，必须展示
    var pubTime: String?        // 合规：发布时间，必须展示
}

/// 后台 /v1/weather/supplement 的响应
struct WeatherSupplement: Codable {
    var status: Int?
    var location: SupplementLocation?
    var air: AirQuality?            // 实时
    var airDaily: [AirQuality]?     // 未来 3 天（WeatherKit 无此数据）
    var airHourly: [AirQuality]?    // 未来 24 小时（WeatherKit 无此数据）
    var indices: [LifeIndex]?
    var minutely: MinutelyPrecip?
    var alerts: [WeatherAlertInfo]?
    /// 各项的失败原因。某项为 nil 表示该项成功。
    var errors: [String: String?]?
    var updateTime: String?

    struct SupplementLocation: Codable {
        var lng: Double?
        var lat: Double?
        var name: String?
    }

    /// 四项是否全部缺失（后台整体不可用时用于判断是否值得入库）
    var isEmpty: Bool {
        air == nil && minutely == nil
            && (indices?.isEmpty ?? true) && (alerts?.isEmpty ?? true)
    }
}
