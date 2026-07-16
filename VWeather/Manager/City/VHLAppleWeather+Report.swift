//
//  VHLAppleWeather+Report.swift
//  VWeather
//
//  WeatherKit → WeatherReport 的映射。后台不可用时的兜底路径。
//
//  ⚠️ 这份映射必须与后台 app/services/weather/providers/apple.py 保持一致 ——
//     同一个 WeatherKit 天况经「端上兜底」和「后台以 Apple 为备选 provider」
//     两条路进来，得到的中立值必须相同，否则同一份上游数据会长出两种样子。
//
//  ⚠️ 单位：WeatherKit 给的是 Measurement，直接读 .value 拿到的单位跟随 locale
//     ——美区设备会得到 °F / mph，中立 schema 要的是 ℃ / km/h。
//     每一处都显式 converted(to:)，不能省。这类错不会崩，只会让数字悄悄偏掉。
//

import CoreLocation
import Foundation
import WeatherKit

extension VHLAppleWeather {

    /// 取天气并映射为中立报告。
    ///
    /// 一次请求把 current/daily/hourly/minute/alerts 全取回来 ——
    /// WeatherKit 是端上框架，没有配额顾虑，分开取反而多几次往返。
    func report(for location: CLLocation) async throws -> WeatherReport {
        let w = try await weatherService.weather(for: location)

        var data = WeatherReport.ResourceData()
        data.now = Self.mapNow(w.currentWeather)
        data.daily = w.dailyForecast.forecast.map(Self.mapDay)
        data.hourly = Self.futureHours(w.hourlyForecast.forecast).map(Self.mapHour)

        // 分钟降水：中国大陆不提供，海外才有。没有就是 nil，不是错误。
        if let minute = w.minuteForecast {
            data.minutely = Self.mapMinutely(minute)
        }
        // 预警：同样地区受限
        if let alerts = w.weatherAlerts, !alerts.isEmpty {
            data.alerts = alerts.map(Self.mapAlert)
        }
        // air / indices / air-daily / air-hourly：WeatherKit 框架层面就没有
        // （DataSet 枚举只有 5 个值，没有任何空气质量相关类型），留 nil。

        return WeatherReport(source: .weatherKit,
                             updatedAt: ISO8601DateFormatter().string(from: Date()),
                             data: data)
    }

    // MARK: - 各资源映射

    /// 逐小时预报的一天用不着 250 条。
    ///
    /// 实测 WeatherKit 的 hourlyForecast 从**昨天**某个整点开始、一直给到 10 天后
    /// （250 条，含十几条已经过去的小时）。而后台按 hours=24h 给未来 24 条。
    /// 两条路的字段和单位都一致，唯独**范围**不同 —— 兜底时首页会把
    /// 已经过去的小时排在最前，看着像是数据错乱。
    ///
    /// 在这里对齐后台的契约：当前整点起，24 条。
    private static func futureHours(_ hours: [HourWeather]) -> [HourWeather] {
        let start = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return Array(hours.filter { $0.date >= start }.prefix(24))
    }

    private static func mapNow(_ c: CurrentWeather) -> WeatherNow {
        var n = WeatherNow()
        n.observedAt = iso(c.date)
        n.temperature = c.temperature.converted(to: .celsius).value
        n.feelsLike = c.apparentTemperature.converted(to: .celsius).value
        n.condition = condition(c.condition)
        n.conditionText = c.condition.description
        n.rawCondition = "\(c.condition)"
        n.humidity = c.humidity * 100                    // WeatherKit 给 0-1
        n.pressure = c.pressure.converted(to: .hectopascals).value
        n.windSpeed = c.wind.speed.converted(to: .kilometersPerHour).value
        n.windDirection = c.wind.direction.converted(to: .degrees).value
        n.windDirectionText = "\(c.wind.compassDirection)"
        n.windGust = c.wind.gust?.converted(to: .kilometersPerHour).value
        n.uvIndex = Double(c.uvIndex.value)
        n.visibility = c.visibility.converted(to: .kilometers).value
        n.dewPoint = c.dewPoint.converted(to: .celsius).value
        n.cloudCover = c.cloudCover * 100
        return n
    }

    private static func mapDay(_ d: DayWeather) -> WeatherDay {
        var x = WeatherDay()
        // 中立 schema 的 date 是当地纯日期。DayWeather.date 是该日起点，
        // 按设备当前时区取日期 —— 与后台 apple provider 的做法对齐。
        x.date = dayFormatter.string(from: d.date)
        x.tempMax = d.highTemperature.converted(to: .celsius).value
        x.tempMin = d.lowTemperature.converted(to: .celsius).value
        x.condition = condition(d.condition)
        x.conditionText = d.condition.description
        x.rawCondition = "\(d.condition)"
        // WeatherKit 不区分白天/夜间天况 —— 保留键、置 nil，与后台一致
        x.conditionNight = nil
        x.precipitationChance = d.precipitationChance * 100
        x.precipitationAmount = d.rainfallAmount.converted(to: .millimeters).value
        x.precipitationType = "\(d.precipitation)"
        x.uvIndexMax = Double(d.uvIndex.value)
        x.sunrise = iso(d.sun.sunrise)
        x.sunset = iso(d.sun.sunset)
        x.moonrise = iso(d.moon.moonrise)
        x.moonset = iso(d.moon.moonset)
        x.moonPhase = "\(d.moon.phase)"
        return x
    }

    private static func mapHour(_ h: HourWeather) -> WeatherHour {
        var x = WeatherHour()
        x.time = iso(h.date)
        x.temperature = h.temperature.converted(to: .celsius).value
        x.feelsLike = h.apparentTemperature.converted(to: .celsius).value
        x.condition = condition(h.condition)
        x.conditionText = h.condition.description
        x.rawCondition = "\(h.condition)"
        x.precipitationChance = h.precipitationChance * 100
        x.precipitationAmount = h.precipitationAmount.converted(to: .millimeters).value
        x.precipitationType = "\(h.precipitation)"
        x.humidity = h.humidity * 100
        x.pressure = h.pressure.converted(to: .hectopascals).value
        x.windSpeed = h.wind.speed.converted(to: .kilometersPerHour).value
        x.windDirection = h.wind.direction.converted(to: .degrees).value
        x.windDirectionText = "\(h.wind.compassDirection)"
        x.uvIndex = Double(h.uvIndex.value)
        x.cloudCover = h.cloudCover * 100
        x.dewPoint = h.dewPoint.converted(to: .celsius).value
        x.visibility = h.visibility.converted(to: .kilometers).value
        return x
    }

    private static func mapMinutely(_ m: Forecast<MinuteWeather>) -> MinutelyPrecip {
        var out = MinutelyPrecip()
        out.summary = m.summary                           // 「一小时内有小雨」这类描述
        out.interval = 1                                  // WeatherKit 逐分钟
        out.items = m.forecast.map { x in
            var i = MinutelyPrecip.MinutelyItem()
            i.time = iso(x.date)
            // ⚠️ precipitationIntensity 的类型是 Measurement<UnitSpeed>，但 Apple
            //    文档说它的单位是 mm/hr —— 是拿 UnitSpeed 装了个非速度的量。
            //    所以这里**不能** converted(to:)：转成 km/h 之类只会得到一个
            //    看着正常的错数。直接读 .value，它就是 mm/hr。
            //    除以 60 得到这一分钟的毫米数，与中立 schema 的 mm 对齐。
            i.precipitation = x.precipitationIntensity.value / 60
            i.type = "\(x.precipitation)"
            i.chance = x.precipitationChance * 100
            return i
        }
        return out
    }

    /// ⚠️ 合规缺口：《气象预报发布与传播管理办法》第九条要求传播气象预警必须
    ///    注明发布单位**与发布时间**，而 WeatherKit 的 WeatherAlert 压根没有
    ///    发布时间字段（只有 detailsURL / source / summary / region / severity）。
    ///
    ///    没拿 metadata.date 顶替 —— 那是报文的读取时间，不是预警的发布时间，
    ///    填上去是编造一个合规字段，比留空更糟。
    ///
    ///    实测 Apple 在中国大陆不返回任何预警，故这条路只在境外触发，
    ///    该法规的属地范围之外。但若哪天 Apple 开始在境内给预警，这里就是个雷。
    private static func mapAlert(_ a: WeatherAlert) -> WeatherAlertInfo {
        var x = WeatherAlertInfo()
        x.id = a.detailsURL.absoluteString          // 没有 id 字段，用详情链接代替
        x.title = a.summary
        x.text = a.summary                          // 只给摘要，没有正文全文
        x.severity = severity(a.severity)
        x.severityText = "\(a.severity)"
        x.sender = a.source                         // 发布单位
        x.pubTime = nil                             // 见上：上游没有，不编
        return x
    }

    // MARK: - 值映射

    /// WeatherKit 天况 → 中立枚举。
    /// 与后台 apple.py 的 _CONDITION 表一一对应，改这里就要同步改那边。
    private static func condition(_ c: WeatherKit.WeatherCondition) -> VWCondition {
        switch c {
        case .clear, .mostlyClear, .hot, .frigid:            return .clear
        case .partlyCloudy:                                  return .partlyCloudy
        case .mostlyCloudy, .cloudy:                         return .cloudy
        case .smoky, .haze:                                  return .haze
        case .foggy:                                         return .fog
        case .drizzle:                                       return .drizzle
        case .rain, .sunShowers:                             return .rain
        case .heavyRain:                                     return .heavyRain
        case .freezingDrizzle, .freezingRain:                return .freezingRain
        case .sleet, .wintryMix, .sunFlurries:               return .sleet
        case .snow, .flurries:                               return .snow
        case .heavySnow, .blizzard, .blowingSnow:            return .heavySnow
        case .hail:                                          return .hail
        case .thunderstorms, .scatteredThunderstorms,
             .isolatedThunderstorms, .strongStorms:          return .thunderstorm
        case .windy, .breezy:                                return .windy
        case .blowingDust:                                   return .sand
        case .hurricane, .tropicalStorm:                     return .heavyRain
        @unknown default:                                    return .unknown
        }
    }

    /// WeatherKit 分级 → 中立分级（与后台 schema 的取值域一致）
    private static func severity(_ s: WeatherSeverity) -> String {
        switch s {
        case .minor:    return "minor"
        case .moderate: return "moderate"
        case .severe:   return "severe"
        case .extreme:  return "extreme"
        case .unknown:  return "minor"
        @unknown default: return "minor"
        }
    }

    // MARK: - 时间

    /// 中立 schema 的时间是 ISO8601 带时区
    private static func iso(_ d: Date?) -> String? {
        guard let d else { return nil }
        return isoFormatter.string(from: d)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
