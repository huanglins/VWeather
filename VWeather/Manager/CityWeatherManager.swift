//
//  CityWeatherManager.swift
//  VWeather
//
//  城市天气 + 日月快照：读缓存（秒显）与刷新入库。
//  复用 VHLAppleWeather（WeatherKit）与 VHLSunMoonManager（SunKit/MoonKit）。
//

import Foundation
import CoreLocation

/// 选中城市 cityKey 的存储 key（App Group UserDefaults 共享；主 App 与小组件共用）
let UD_SelectedCityKey = "VW_selectedCityKey"

class CityWeatherManager {
    static let manager = CityWeatherManager()

    /// 读取城市的天气缓存快照（用于切换时秒显 / 离线）
    func cachedSnapshot(for city: CityModel) -> CityWeatherSnapshot? {
        guard let key = city.cityKey else { return nil }
        return CityWeatherSnapshot.objects(whereSQL: "cityKey = ?", params: [key]).first
    }

    /// 当前选中城市（App Group 共享；只读、不依赖 SyncManager，供小组件复用）。
    /// 优先取选中项，否则取排序首个未删除城市。
    func selectedCity() -> CityModel? {
        let ud = UserDefaults(suiteName: APP_GROUP) ?? .standard
        if let key = ud.string(forKey: UD_SelectedCityKey),
           let city = CityModel.objects(whereSQL: "cityKey = ?", params: [key]).first {
            return city
        }
        return CityModel.objects(whereSQL: "isDeleted != 1", order: .ASC("sortOrder")).first
    }

    /// 天气自动刷新的最小间隔。此间隔内的**自动**请求直接复用缓存，避免频繁请求 WeatherKit。
    /// 用户下拉刷新、当前位置坐标变更等场景传 `force: true` 可绕过。
    static let minRefreshInterval: TimeInterval = 30 * 60   // 30 分钟

    /// 请求最新天气 + 计算日月，组装快照并写入 SQLite。
    /// - Parameter force: 是否强制刷新（忽略频率限制）。默认 false，受 `minRefreshInterval` 节流。
    @discardableResult
    func refresh(for city: CityModel, force: Bool = false) async -> CityWeatherSnapshot? {
        guard let key = city.cityKey else { return nil }

        // 频率控制：非强制刷新时，若缓存仍在有效期内，直接复用缓存，不请求 WeatherKit。
        // 但如果缓存中没有天气数据（如之前的请求失败），则不受间隔限制，强制刷新。
        if !force,
           let cached = cachedSnapshot(for: city),
           cached.weatherJSON != nil,
           let updated = cached.updateDate,
           Date().timeIntervalSince(updated) < Self.minRefreshInterval {
            return cached
        }

        let location = city.location

        // 天气（WeatherKit，异步回调转 async）
        let weather: VHLWeatherModel? = await withCheckedContinuation { continuation in
            VHLAppleWeather.shared.getWeather(for: location) { model, _ in
                continuation.resume(returning: model)
            }
        }

        // 日月（本地计算）
        let sun = VHLSunMoonManager.manager.sunInfo(location: location)
        let moon = VHLSunMoonManager.manager.moonInfo(location: location)

        var snap = cachedSnapshot(for: city) ?? CityWeatherSnapshot()
        snap.cityKey = key

        // 各模型整体 JSON 存储：新增展示字段时无需在此逐一赋值
        if let w = weather {
            snap.weatherJSON = CityWeatherSnapshot.encodeJSON(WeatherDisplay(from: w))
        }
        snap.sunJSON = CityWeatherSnapshot.encodeJSON(sun)
        snap.moonJSON = CityWeatherSnapshot.encodeJSON(moon)

        snap.updateDate = Date()
        snap.saveOrUpdate()
        return snap
    }
}
