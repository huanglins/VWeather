//
//  WeatherReport.swift
//  VWeather
//
//  App 的天气模型 —— 与数据源无关。
//
//  两个来源都归一化到这里：
//    · vapi 后台（主）  GET /v1/weather?resources=...，本身就是中立 schema
//    · WeatherKit（兜底）后台不可用时端上直接取，由 VHLAppleWeather 映射进来
//
//  只有 `source` 记得住数据来自谁，其余字段一视同仁。UI 不该按来源分支，
//  归因除外 —— 那是法律要求，不是展示逻辑。
//
//  ⚠️ 曾经这里叫 WeatherSupplement，与「WeatherKit 的投影」WeatherDisplay 并存，
//     各存一列。那是双源时代的产物：后台只补 AQI 等四项，基础天气走 WeatherKit。
//     现在基础天气也走后台，「补充」的说法就名不副实了，两个模型也没有理由分开。
//

import Foundation

// MARK: - 单位约定
//
// 温度 ℃、风速 km/h、气压 hPa、能见度 km、降水 mm、
// 湿度与概率 0-100、风向 0-360 度、时间 ISO8601 带时区。
//
// 后台的中立 schema 就是按这套抹平的，直接对齐即可。
// WeatherKit 那条路要自己换算 —— 它给的是 Measurement，读 .value 拿到的单位
// 跟随 locale，在美区设备上会变成 °F / mph。必须显式 converted(to:)，
// 见 VHLAppleWeather 的映射。

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

    init() {}
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

    init() {}
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

    init() {}
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

    init() {}

    struct MinutelyItem: Codable {
        var time: String?
        var precipitation: Double?   // mm
        var type: String?            // rain / snow
        var chance: Double?          // 0-100

        init() {}
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

    init() {}
}

// MARK: - 报告

/// 数据来源。用于归因展示与排查，UI 的其它部分不该按它分支。
enum WeatherSource: String, Codable {
    case backend        // vapi 后台（当前由和风供数，可换）
    case weatherKit     // 端上 Apple WeatherKit（后台不可用时的兜底）
}

/// 一份天气报告。两个数据源都归一化成它。
///
/// 所有字段可选：数据源的能力不同（WeatherKit 没有 AQI 与生活指数，
/// 中国大陆也没有分钟降水），拿不到就是 nil，UI 按「有才显示」处理。
struct WeatherReport: Codable {
    var source: WeatherSource = .backend
    var updatedAt: String?
    var location: ReportLocation?
    var data: ResourceData?

    /// 各资源实际由谁供数（后台换源/降级时会变）。仅供排查，UI 不该依赖。
    var providers: [String: String?]?
    /// 各资源的失败原因。某项为 nil 表示成功。
    var errors: [String: String?]?

    struct ReportLocation: Codable {
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

        init() {}
    }

    init() {}

    init(source: WeatherSource, updatedAt: String? = nil, data: ResourceData) {
        self.source = source
        self.updatedAt = updatedAt
        self.data = data
    }

    /// 后台的响应里没有 `source` —— 那是本地概念，不是接口字段。
    /// 缺省即 .backend；WeatherKit 那条路由 VHLAppleWeather 显式构造。
    ///
    /// 不能用编译器合成的实现：合成的 init(from:) 会因为缺 `source` 键直接抛错，
    /// 属性上的默认值对它不生效。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(WeatherSource.self, forKey: .source) ?? .backend
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        location = try c.decodeIfPresent(ReportLocation.self, forKey: .location)
        data = try c.decodeIfPresent(ResourceData.self, forKey: .data)
        providers = try c.decodeIfPresent([String: String?].self, forKey: .providers)
        errors = try c.decodeIfPresent([String: String?].self, forKey: .errors)
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

    /// 是否一项数据都没有。
    ///
    /// 用途有二：
    ///   · 后台返回 200 但各项全空时，视同失败 —— 该降级到 WeatherKit，
    ///     而不是把一屏空白当成「成功」
    ///   · 旧版本的 weatherJSON 存的是 WeatherDisplay，字段名全不匹配，
    ///     解码会得到一个各项皆空的报告。它同样该被当作「没有数据」。
    var isEmpty: Bool {
        now == nil && air == nil && minutely == nil
            && (daily?.isEmpty ?? true) && (hourly?.isEmpty ?? true)
            && (indices?.isEmpty ?? true) && (alerts?.isEmpty ?? true)
    }
}

// MARK: - 时间与昼夜
//
// 放在模型层而非视图层：时间格式是数据的属性，Widget 与主 App 都要用，
// 而视图文件只在主 App target 里。

enum WeatherTime {
    /// 解析中立 schema 的时间。
    ///
    /// ⚠️ 上游的时间**不带秒**（`2026-07-16T04:59+08:00`），而
    /// `ISO8601DateFormatter` 的 `.withInternetDateTime` 要求有秒 —— 直接用它会解析失败。
    /// 这个坑踩过：解析失败被静默兜住，屏幕上显示的是原始机器格式，看着像「没渲染」。
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = noSeconds.date(from: raw) { return d }
        // 兜底：万一哪个数据源带上了秒
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return iso.date(from: raw)
    }

    private static let noSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmZZZZZ"
        return f
    }()
}

extension WeatherDay {
    /// 该时刻是否在本日的日落后 / 日出前。日出日落缺失时返回 nil，由调用方决定怎么办。
    func isNight(at t: Date) -> Bool? {
        guard let rise = WeatherTime.date(sunrise), let set = WeatherTime.date(sunset) else {
            return nil
        }
        return t < rise || t >= set
    }
}

extension WeatherReport {
    /// 该时刻是否为夜间，按当天的日出日落判断。
    ///
    /// 找不到对应日期的数据时回退到「18 点—6 点」—— 高纬度会不准，
    /// 但总好过让所有时刻共用同一个昼夜状态（那会让凌晨挂着太阳）。
    func isNight(at t: Date) -> Bool {
        let day = daily?.first { d in
            guard let s = WeatherTime.date(d.sunrise) else { return false }
            return Calendar.current.isDate(s, inSameDayAs: t)
        }
        if let night = day?.isNight(at: t) { return night }
        let h = Calendar.current.component(.hour, from: t)
        return h < 6 || h >= 18
    }
}
