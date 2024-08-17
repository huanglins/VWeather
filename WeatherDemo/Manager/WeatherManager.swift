//
//  WeatherManager.swift
//  WeatherDemo
//
//  Created by Vincent on 2024/8/16.
//

import Foundation
import SwiftDate

let APP_GROUP = "group.cn.vincents.dev"
extension UserDefaults {
    static let group = UserDefaults(suiteName: APP_GROUP)
}

struct WeatherModel: Codable {
    var date: Date?
    var locationModel: VHLLocationModel?
    var weatherModel: VHLWeatherModel?
}

let UD_WeatherInfos = "UD_WeatherInfos"
let UD_CurrentLocation = "UD_CurrentLocation"
let UD_CurrentWeahter = "UD_CurrentWeahter"

class WeatherManager {
    static let manager = WeatherManager()
    
    func requestCurrentWeatherInfo(_ completion: @escaping (WeatherModel?, Error?) -> Void) {
        let lastCurrentWeatherInfo = getCurrentWeatherInfo()
        
        VHLLocationManager.manager.aloneReGeocodeLocation { locationModel, error in
            guard let locationModel = locationModel else {
                completion(lastCurrentWeatherInfo, nil)
                return
            }
            
            try? UserDefaults.group?.set(object: locationModel, forKey: UD_CurrentLocation)
            
            // 是否是同一个区，如果是同一个区，且刷新时间小于半小时，使用缓存
            if lastCurrentWeatherInfo?.locationModel?.city == locationModel.city
                && lastCurrentWeatherInfo?.locationModel?.area == locationModel.area {
                
                // 是否是同一天
                if let lastDate = lastCurrentWeatherInfo?.date, Date().compare(.isSameDay(lastDate)) {
                    let diffMinute = (Date()).difference(in: .minute, from: lastDate) ?? 31
                    // 刷新间隔大于 30 分钟
                    if diffMinute < 30 {
                        print("刷新间隔时间\(diffMinute)分钟，使用缓存")
                        completion(lastCurrentWeatherInfo, nil)
                        return
                    }
                }
            }
            
            VHLAppleWeather.shared.getWeather(for: locationModel.location) { weatherModel, error in
                guard let weatherModel else {
                    completion(lastCurrentWeatherInfo, nil)
                    return
                }
                
                var model = WeatherModel()
                model.locationModel = locationModel
                model.weatherModel = weatherModel
                model.date = Date()
                try? UserDefaults.group?.set(object: model, forKey: UD_CurrentWeahter)
                
                // 本地保存
                completion(model, nil)
            }
        }
    }
    
    func getCurrentWeatherInfo() -> WeatherModel? {
        let weatherInfo = try? UserDefaults.group?.get(objectType: WeatherModel.self, forKey: UD_CurrentWeahter)
        return weatherInfo
    }
}
