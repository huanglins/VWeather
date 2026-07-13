//
//  VHLSunMoonManager.swift
//  VWeather
//
//  日月信息工具类：封装 SunKit（日出日落 / 蓝调时刻 / 黄金时刻 / 曙暮光）
//  与 MoonKit（月相 / 月升月落 / 月亮星座 / 照度等）。
//
//  SunKit:  https://github.com/SunKit-Swift/SunKit
//  MoonKit: https://github.com/davideilmito/MoonKit
//
//  所有计算均在本地完成，无需联网。
//

import Foundation
import CoreLocation
import SunKit
import MoonKit

// MARK: - 太阳信息模型
/// 某一位置、某一天的太阳相关信息。字段均为纯值类型，便于缓存 / 跨 App Group 共享。
///
/// 所有属性均带默认值，可先 `VHLSunInfo()` 再逐字段赋值（避免大型初始化表达式导致的类型检查超时）。
struct VHLSunInfo: Codable {
    var date: Date = Date()                 // 计算所用日期
    var latitude: Double = 0                // 纬度
    var longitude: Double = 0               // 经度

    // 主要时刻
    var sunrise: Date = Date()              // 日出
    var sunset: Date = Date()               // 日落
    var solarNoon: Date = Date()            // 正午（太阳最高点）
    var solarMidnight: Date = Date()        // 子夜（太阳最低点）

    // 蓝调时刻（Blue Hour）——天空呈深蓝色，适合拍摄
    var morningBlueHourStart: Date = Date() // 晨间蓝调开始
    var morningBlueHourEnd: Date = Date()   // 晨间蓝调结束
    var eveningBlueHourStart: Date = Date() // 暮间蓝调开始
    var eveningBlueHourEnd: Date = Date()   // 暮间蓝调结束

    // 黄金时刻（Golden Hour）——光线柔和金黄，适合拍摄
    var morningGoldenHourStart: Date = Date()   // 晨间黄金时刻开始
    var morningGoldenHourEnd: Date = Date()     // 晨间黄金时刻结束
    var eveningGoldenHourStart: Date = Date()   // 暮间黄金时刻开始
    var eveningGoldenHourEnd: Date = Date()     // 暮间黄金时刻结束

    // 曙暮光
    var civilDawn: Date = Date()            // 民用晨光
    var civilDusk: Date = Date()            // 民用昏影
    var nauticalDawn: Date = Date()         // 航海晨光
    var nauticalDusk: Date = Date()         // 航海昏影
    var astronomicalDawn: Date = Date()     // 天文晨光
    var astronomicalDusk: Date = Date()     // 天文昏影

    // 方位角 / 高度角（单位：度）
    var azimuth: Double = 0                 // 当前太阳方位角
    var altitude: Double = 0                // 当前太阳高度角
    var sunriseAzimuth: Double = 0          // 日出方位角
    var sunsetAzimuth: Double = 0           // 日落方位角

    // 时长（单位：秒）
    var daylightDuration: TimeInterval = 0  // 白昼时长
    var nightDuration: TimeInterval = 0     // 夜晚时长

    // 当前状态
    var isNight: Bool = false               // 是否处于夜晚
    var isGoldenHour: Bool = false          // 是否处于黄金时刻
    var isBlueHour: Bool = false            // 是否处于蓝调时刻
}

// MARK: - 月亮信息模型
/// 某一位置、某一天的月亮相关信息。
struct VHLMoonInfo: Codable {
    var date: Date = Date()                 // 计算所用日期
    var latitude: Double = 0                // 纬度
    var longitude: Double = 0               // 经度

    // 月升月落（极昼 / 极夜等情况下可能为空）
    var moonrise: Date?                     // 月升时间
    var moonset: Date?                      // 月落时间
    var moonriseAzimuth: Double?            // 月升方位角（度）
    var moonsetAzimuth: Double?             // 月落方位角（度）

    // 月相
    var phase: String = ""                  // 月相英文原始值（MoonPhase.rawValue）
    var phaseName: String = ""              // 月相中文名，如 “满月”
    var phaseEmoji: String = ""             // 月相 Emoji，如 🌕
    var illumination: Double = 0            // 照亮百分比 0...100
    var ageInDays: Double = 0               // 月龄（天）

    // 月亮星座
    var sign: String = ""                   // 星座英文原始值（AstrologicalSign.rawValue）
    var signName: String = ""               // 星座中文名，如 “金牛座”
    var signSymbol: String = ""             // 星座符号，如 ♉

    // 距离下一次
    var daysToNextFullMoon: Int = 0         // 距下一次满月的天数
    var daysToNextNewMoon: Int = 0          // 距下一次新月的天数

    // 方位角 / 高度角（单位：度）
    var azimuth: Double = 0                 // 当前月亮方位角
    var altitude: Double = 0                // 当前月亮高度角
}

// MARK: - 日月信息管理器
/// 便捷的日月信息计算入口。
///
/// 用法示例：
/// ```swift
/// let location = CLLocation(latitude: 22.54, longitude: 114.06)
/// let sun = VHLSunMoonManager.manager.sunInfo(location: location)
/// print("日出 \(VHLSunMoonManager.timeString(sun.sunrise))，日落 \(VHLSunMoonManager.timeString(sun.sunset))")
///
/// let moon = VHLSunMoonManager.manager.moonInfo(location: location)
/// print("今日月相：\(moon.phaseEmoji) \(moon.phaseName)，照度 \(Int(moon.illumination))%")
///
/// // 或直接使用当前定位（需已定位成功）
/// let curSun = VHLSunMoonManager.manager.currentSunInfo()
/// ```
class VHLSunMoonManager {
    static let manager = VHLSunMoonManager()

    // MARK: 指定位置查询

    /// 计算指定位置、指定日期的太阳信息。
    /// - Parameters:
    ///   - location: 地理位置
    ///   - timeZone: 时区，默认当前设备时区
    ///   - date: 日期，默认当前时间
    func sunInfo(location: CLLocation,
                 timeZone: TimeZone = .current,
                 date: Date = Date()) -> VHLSunInfo {
        var sun = Sun(location: location, timeZone: timeZone, date: date)
        sun.setDate(date)

        // 逐字段赋值，避免超大初始化表达式导致编译器类型检查超时
        var info = VHLSunInfo()
        info.date = date
        info.latitude = location.coordinate.latitude
        info.longitude = location.coordinate.longitude

        info.sunrise = sun.sunrise
        info.sunset = sun.sunset
        info.solarNoon = sun.solarNoon
        info.solarMidnight = sun.solarMidnight

        info.morningBlueHourStart = sun.morningBlueHourStart
        info.morningBlueHourEnd = sun.morningBlueHourEnd
        info.eveningBlueHourStart = sun.eveningBlueHourStart
        info.eveningBlueHourEnd = sun.eveningBlueHourEnd

        info.morningGoldenHourStart = sun.morningGoldenHourStart
        info.morningGoldenHourEnd = sun.morningGoldenHourEnd
        info.eveningGoldenHourStart = sun.eveningGoldenHourStart
        info.eveningGoldenHourEnd = sun.eveningGoldenHourEnd

        info.civilDawn = sun.civilDawn
        info.civilDusk = sun.civilDusk
        info.nauticalDawn = sun.nauticalDawn
        info.nauticalDusk = sun.nauticalDusk
        info.astronomicalDawn = sun.astronomicalDawn
        info.astronomicalDusk = sun.astronomicalDusk

        info.azimuth = sun.azimuth.degrees
        info.altitude = sun.altitude.degrees
        info.sunriseAzimuth = sun.sunriseAzimuth
        info.sunsetAzimuth = sun.sunsetAzimuth

        info.daylightDuration = TimeInterval(sun.totalDayLightTime)
        info.nightDuration = TimeInterval(sun.totalNightTime)

        info.isNight = sun.isNight
        info.isGoldenHour = sun.isGoldenHour
        info.isBlueHour = sun.isBlueHour

        return info
    }

    /// 计算指定位置、指定日期的月亮信息。
    /// - Parameters:
    ///   - location: 地理位置
    ///   - timeZone: 时区，默认当前设备时区
    ///   - date: 日期，默认当前时间
    func moonInfo(location: CLLocation,
                  timeZone: TimeZone = .current,
                  date: Date = Date()) -> VHLMoonInfo {
        let moon = Moon(location: location, timeZone: timeZone)
        moon.setDate(date)

        let phase = moon.currentMoonPhase
        let sign = moon.moonSign

        // 逐字段赋值，避免超大初始化表达式导致编译器类型检查超时
        var info = VHLMoonInfo()
        info.date = date
        info.latitude = location.coordinate.latitude
        info.longitude = location.coordinate.longitude

        info.moonrise = moon.moonRise
        info.moonset = moon.moonSet
        info.moonriseAzimuth = moon.moonriseAzimuth
        info.moonsetAzimuth = moon.moonsetAzimuth

        info.phase = phase.rawValue
        info.phaseName = phase.vhl_chineseName
        info.phaseEmoji = phase.vhl_emoji
        info.illumination = moon.moonPercentage
        info.ageInDays = moon.ageOfTheMoonInDays

        info.sign = sign.rawValue
        info.signName = sign.vhl_chineseName
        info.signSymbol = sign.vhl_symbol

        info.daysToNextFullMoon = moon.nextFullMoon
        info.daysToNextNewMoon = moon.nextNewMoon

        info.azimuth = moon.azimuth
        info.altitude = moon.altitude

        return info
    }

    // MARK: 使用当前定位的便捷方法

    /// 使用当前定位（`VHLLocationManager`）计算太阳信息，未定位成功时返回 nil。
    func currentSunInfo(date: Date = Date()) -> VHLSunInfo? {
        guard let model = VHLLocationManager.manager.currentLocationModel else { return nil }
        return sunInfo(location: model.location, date: date)
    }

    /// 使用当前定位（`VHLLocationManager`）计算月亮信息，未定位成功时返回 nil。
    func currentMoonInfo(date: Date = Date()) -> VHLMoonInfo? {
        guard let model = VHLLocationManager.manager.currentLocationModel else { return nil }
        return moonInfo(location: model.location, date: date)
    }
}

// MARK: - 格式化辅助
extension VHLSunMoonManager {
    /// 将时间格式化为 “HH:mm”。
    static func timeString(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date = date else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone
        return f.string(from: date)
    }

    /// 将时长（秒）格式化为 “x小时y分钟”。
    static func durationString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)小时\(minutes)分钟" }
        return "\(minutes)分钟"
    }
}

// MARK: - MoonPhase 中文本地化
extension MoonPhase {
    /// 月相中文名称。
    var vhl_chineseName: String {
        switch self {
        case .newMoon:          return "新月"
        case .waxingCrescent:   return "娥眉月"
        case .firstQuarter:     return "上弦月"
        case .waxingGibbous:    return "盈凸月"
        case .fullMoon:         return "满月"
        case .waningGibbous:    return "亏凸月"
        case .lastQuarter:      return "下弦月"
        case .waningCrescent:   return "残月"
        case .error:            return "未知"
        }
    }

    /// 月相对应的 Emoji。
    var vhl_emoji: String {
        switch self {
        case .newMoon:          return "🌑"
        case .waxingCrescent:   return "🌒"
        case .firstQuarter:     return "🌓"
        case .waxingGibbous:    return "🌔"
        case .fullMoon:         return "🌕"
        case .waningGibbous:    return "🌖"
        case .lastQuarter:      return "🌗"
        case .waningCrescent:   return "🌘"
        case .error:            return "❓"
        }
    }
}

// MARK: - AstrologicalSign 中文本地化
extension AstrologicalSign {
    /// 星座中文名称。
    var vhl_chineseName: String {
        switch self {
        case .aries:        return "白羊座"
        case .taurus:       return "金牛座"
        case .gemini:       return "双子座"
        case .cancer:       return "巨蟹座"
        case .leo:          return "狮子座"
        case .virgo:        return "处女座"
        case .libra:        return "天秤座"
        case .scorpio:      return "天蝎座"
        case .sagittarius:  return "射手座"
        case .capricorn:    return "摩羯座"
        case .aquarius:     return "水瓶座"
        case .pisces:       return "双鱼座"
        case .error:        return "未知"
        }
    }

    /// 星座符号。
    var vhl_symbol: String {
        switch self {
        case .aries:        return "♈"
        case .taurus:       return "♉"
        case .gemini:       return "♊"
        case .cancer:       return "♋"
        case .leo:          return "♌"
        case .virgo:        return "♍"
        case .libra:        return "♎"
        case .scorpio:      return "♏"
        case .sagittarius:  return "♐"
        case .capricorn:    return "♑"
        case .aquarius:     return "♒"
        case .pisces:       return "♓"
        case .error:        return "❓"
        }
    }
}
