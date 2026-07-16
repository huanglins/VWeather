//
//  WeatherManager.swift
//  VWeather
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
    var lastUseDate: Date? = Date()
    
    var locationModel: VHLLocationModel?
    var weatherModel: VHLWeatherModel?
    
    var state: Int?
}

let UD_WeatherInfos = "UD_WeatherInfos"
let UD_CurrentLocation = "UD_CurrentLocation"
let UD_CurrentWeahter = "UD_CurrentWeahter"

class WeatherManager {
    static let manager = WeatherManager()
    
    let refreshInterval: TimeInterval = 30      // 刷新间隔（分钟）
    
    func requestCurrentWeatherInfo(focusRefresh: Bool = false, _ completion: @escaping (WeatherModel?, Error?) -> Void) {
        var lastCurrentWeatherInfo = getCurrentWeatherInfo()
        
        VHLLocationManager.manager.singificantLocationChanges { [weak self] locationModel, error in
            guard let self else { return }
            
            // 没有获取到位置
            guard let locationModel = locationModel else {
                lastCurrentWeatherInfo?.state = -1
                lastCurrentWeatherInfo?.lastUseDate = Date()
                setCurrentWeatherInfo(lastCurrentWeatherInfo)
                completion(lastCurrentWeatherInfo, nil)
                return
            }
            
            try? UserDefaults.group?.set(object: locationModel, forKey: UD_CurrentLocation)
            
            if !focusRefresh {
                // 是否是同一个区，如果是同一个区，且刷新时间小于半小时，使用缓存
                if lastCurrentWeatherInfo?.locationModel?.city == locationModel.city
                    && lastCurrentWeatherInfo?.locationModel?.area == locationModel.area {
                    
                    // 是否是同一天
                    if let lastDate = lastCurrentWeatherInfo?.date, Date().compare(.isSameDay(lastDate)) {
                        let diffMinute = (Date()).difference(in: .minute, from: lastDate) ?? 31
                        // 检查刷新间隔时间
                        if diffMinute < Int(self.refreshInterval) {
                            print("刷新间隔时间\(diffMinute)分钟，使用缓存")
                            
                            lastCurrentWeatherInfo?.lastUseDate = Date()
                            lastCurrentWeatherInfo?.state = 1
                            setCurrentWeatherInfo(lastCurrentWeatherInfo)
                            
                            completion(lastCurrentWeatherInfo, nil)
                            return
                        }
                    }
                }
            }
            
            VHLAppleWeather.shared.getWeather(for: locationModel.location) { weatherModel, error in
                guard let weatherModel else {
                    lastCurrentWeatherInfo?.lastUseDate = Date()
                    lastCurrentWeatherInfo?.state = -2
                    self.setCurrentWeatherInfo(lastCurrentWeatherInfo)
                    completion(lastCurrentWeatherInfo, nil)
                    return
                }
                
                var model = WeatherModel()
                model.date = Date()
                model.lastUseDate = Date()
                model.locationModel = locationModel
                model.weatherModel = weatherModel
                self.setCurrentWeatherInfo(model)
                
                // 本地保存
                completion(model, nil)
            }
        }
    }
    
    func getCurrentWeatherInfo() -> WeatherModel? {
        let weatherInfo = try? UserDefaults.group?.get(objectType: WeatherModel.self, forKey: UD_CurrentWeahter)
        return weatherInfo
    }
    
    func setCurrentWeatherInfo(_ weatherModel: WeatherModel?) {
        try? UserDefaults.group?.set(object: weatherModel, forKey: UD_CurrentWeahter)
        UserDefaults.group?.synchronize()
    }
}
