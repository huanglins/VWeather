//
//  VWCondition.swift
//  VWeather
//
//  天况枚举 → SF Symbol / 文案。
//
//  名字带 VW 前缀是为了避开 WeatherKit 自己的 `WeatherCondition` ——
//  同名会让 VHLAppleWeather 里的赋值撞类型。
//
//  后台返回的是与数据源无关的中立枚举（clear / partlyCloudy / overcast …），
//  由本文件映射成图标。此前用的是 WeatherKit 直接给的 `symbolName`，
//  改用后台数据源后那个字段没有了，需要自己映射。
//
//  枚举取值与后台 app/services/weather/schema.py 里的常量一一对应。
//

import Foundation

enum VWCondition: String, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case overcast
    case fog
    case haze
    case drizzle
    case rain
    case heavyRain
    case freezingRain
    case sleet
    case snow
    case heavySnow
    case hail
    case thunderstorm
    case windy
    case sand
    case unknown

    /// 后台可能加新枚举值，客户端不该因此解码失败 —— 未知一律落到 unknown。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VWCondition(rawValue: raw) ?? .unknown
    }

    /// SF Symbol 名。`isNight` 影响晴/少云的图标（夜间用月亮）。
    func symbol(isNight: Bool = false) -> String {
        switch self {
        case .clear:         return isNight ? "moon.stars.fill" : "sun.max.fill"
        case .partlyCloudy:  return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case .cloudy:        return "cloud.fill"
        case .overcast:      return "smoke.fill"
        case .fog:           return "cloud.fog.fill"
        case .haze:          return "sun.haze.fill"
        case .drizzle:       return "cloud.drizzle.fill"
        case .rain:          return "cloud.rain.fill"
        case .heavyRain:     return "cloud.heavyrain.fill"
        case .freezingRain:  return "cloud.sleet.fill"
        case .sleet:         return "cloud.sleet.fill"
        case .snow:          return "cloud.snow.fill"
        case .heavySnow:     return "snowflake"
        case .hail:          return "cloud.hail.fill"
        case .thunderstorm:  return "cloud.bolt.rain.fill"
        case .windy:         return "wind"
        case .sand:          return "sun.dust.fill"
        case .unknown:       return "questionmark.circle"
        }
    }

    /// 是否降水 —— 用于决定要不要在 UI 上强调
    var isPrecipitation: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .freezingRain,
             .sleet, .snow, .heavySnow, .hail, .thunderstorm:
            return true
        default:
            return false
        }
    }
}
