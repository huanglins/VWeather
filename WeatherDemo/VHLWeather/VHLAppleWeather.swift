//
//  VHLWeather.swift
//  WeatherDemo
//
//  Created by vincent on 2024/8/15.
//

import Foundation
import WeatherKit
import CoreLocation

// 1. 需要在 Targets -> Signing & Capabilities -> 添加 WeatherKit
// 2. 需要再苹果后台 https://developer.apple.com/ Certificates - Identifiers - App Services 中勾选 WeatherKit

class VHLAppleWeather {
    static let shared = VHLAppleWeather()
    
    let weatherService = WeatherService.shared
    
    // 归因信息
    func getAttribution() async throws -> WeatherAttribution {
        let attribution = try await weatherService.attribution
        return attribution
    }
}

// MARK: - 获取天气信息
extension VHLAppleWeather {
    func getWeather(for location: CLLocation, completion: @escaping (VHLWeatherModel?, Error?) -> Void) {
        Task {
            do {
                let model = try await getWeather(for: location)
                completion(model, nil)
            } catch {
                completion(nil, error)
                print(String(describing: error.localizedDescription))
            }
        }
    }
    
    func getWeather(for location: CLLocation) async throws -> VHLWeatherModel? {
        // 1. 请求天气信息
//        let calendar = Calendar.current
//        guard let endDate = calendar.date(byAdding: .hour, value: 12, to: Date.now) else {
//            return nil
//        }
//        let result = try await weatherService.weather(for: location, including: .current, .hourly(startDate: Date.now, endDate: endDate), .daily)
        // let result = try await weatherService.weather(for: location, including: .current, .hourly, .daily, .alerts, .availability)
        
        let result = try await weatherService.weather(for: location)
        let currentWeather = result.currentWeather
        let minuteForecast = result.minuteForecast
        let hourlyForecast = result.hourlyForecast
        let dailyForecast = result.dailyForecast
        let weatherAlerts = result.weatherAlerts
        let availability = result.availability
        
        // --------------------------------------------------------------------------------
        
        // 2. 解析天气数据
        var dataModel = VHLWeatherModel()
        // 当前天气
        dataModel.currentWeather = currentWeather
        // 分钟天气
        dataModel.minuteForecast = minuteForecast?.forecast ?? []
        // 小时天气数据
        dataModel.hourlyForecast = hourlyForecast.forecast
        // 每天天气
        dataModel.dailyForecast = dailyForecast.forecast
        // 天气预警
        dataModel.weatherAlerts = weatherAlerts ?? []
        // 可用服务
        dataModel.availability = availability
        
        
        dataModel.date = currentWeather.date                                            // 天气的日期
        // weather.temperature.formatted(.measurement(width: .wide, usage: .weather))
        dataModel.temperature = currentWeather.temperature.value                        // 温度
        dataModel.apparentTemperature = currentWeather.apparentTemperature.value        // 体感温度
        dataModel.symbol = currentWeather.symbolName                                    // 天气图标 symbol
        dataModel.condition = currentWeather.condition                                  // 天气信息
        dataModel.uv = currentWeather.uvIndex.value                                     // 紫外线
        dataModel.windSpeed = currentWeather.wind.speed.value                           // 风速
        dataModel.windDirection = "\(currentWeather.wind.compassDirection)"             // 风向
        dataModel.pressure = currentWeather.pressure.value                              // 气压
        dataModel.humidity = Int(100 * currentWeather.humidity)                         // 湿度
        
        // 当天天气，天气预报
        if let dailyWeather = dailyForecast.first {
            let highTemperature = dailyWeather.highTemperature
            dataModel.highTemperature = highTemperature.value                           // 最高气温
            
            let lowTemperature = dailyWeather.lowTemperature
            dataModel.lowTemperature = lowTemperature.value                             // 最低气温
            
            dataModel.localSunrise = dailyWeather.sun.sunrise                           // 日出 时间
            dataModel.localSunset = dailyWeather.sun.sunset                             // 日落 时间
            dataModel.solarNoon = dailyWeather.sun.solarNoon                            // 正午 时间
            dataModel.astronomicalDawn = dailyWeather.sun.astronomicalDawn              // 黄昏 时间
            dataModel.astronomicalDusk = dailyWeather.sun.astronomicalDusk              // 黎明 时间
            
            dataModel.precipitationChance = dailyWeather.precipitationChance            // 降雨概率
        }
        
        return dataModel
    }
}

// ---------------------------------------------------------------------------------------------------
struct VHLWeatherModel: Codable {
    // 当前天气数据
    var currentWeather: CurrentWeather?
    // 分钟天气
    var minuteForecast: [MinuteWeather] = []
    // 小时天气预报
    var hourlyForecast: [HourWeather] = []
    // 每天天气预报
    var dailyForecast: [DayWeather] = []
    // 天气预警
    var weatherAlerts: [WeatherAlert] = []
    // 可用服务
    var availability: WeatherAvailability?
    
    var date: Date?
    
    var temperature: Double = 0.0
    var highTemperature: Double?
    var lowTemperature: Double?
    var symbol = ""
    var condition: WeatherCondition?        // 天气信息
    var apparentTemperature: Double?        // 体感温度
    
    var localSunrise: Date?         // 日出
    var localSunset: Date?          // 日落
    var solarNoon: Date?            // 正午
    var astronomicalDawn: Date?     // 黎明
    var astronomicalDusk: Date?     // 黄昏
    
    var uv = 0
    var windSpeed: Double = 0.0     // 风速
    var windDirection = ""          // 风向
    
    var humidity = 0                // 湿度

    var pressure: Double = 0.0      // 气压
    var precipitationChance: Double = 0.0   // 降雨概率
}

/**
 https://github.com/Sendeky/weatherkit-weather-app
 
 https://www.kodeco.com/41376031-weatherkit-tutorial-getting-started/page/2?page=1#toc-anchor-001
 
 https://medium.com/@giulio.caggegi/getting-started-with-ios-16-weatherkit-21abf6fb38ab
 */
