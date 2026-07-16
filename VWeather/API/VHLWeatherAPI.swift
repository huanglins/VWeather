//
//  VHLWeatherAPI.swift
//  VWeather
//
//  vapi 后台天气接口 —— App 的主数据源。
//  第三方 API 的 key 与调用都在后台，客户端不持有任何密钥。
//
//  后台是与数据源无关的抽象层：客户端只认「资源名」与中立结构，
//  不知道也不关心背后是和风还是别家。后台换源时这里零改动。
//
//  这条路失败时由 VHLAppleWeather 的 WeatherKit 兜底，见 CityWeatherManager。
//

import CoreLocation
import Foundation

struct VHLWeatherAPI {
    static let shared = VHLWeatherAPI()

    private let baseURL = URL(string: "https://api.vincents.cn/v1")!

    /// 本 App 需要的全部资源。
    ///
    /// 基础天气（now/daily/hourly）此前走端上 WeatherKit，2026-07 改为统一走后台：
    ///   · 多天预报其实 WeatherKit 也给了，但 `WeatherDisplay` 只落库 12 个标量，
    ///     数组取回来就扔了 —— 问题不在数据源。
    ///   · 分钟降水 WeatherKit 在中国大陆不提供。
    ///   · 继续双源意味着两套模型、两套合规义务（Apple 商标 + 数据源归因），
    ///     而后台抽象层里 Apple 仍是备选 provider，降级能力并未丢失。
    private static let resources = ["now", "daily", "hourly",
                                    "air", "air-daily", "air-hourly",
                                    "indices", "minutely", "alerts"]

    /// 一次拉全部资源。
    ///
    /// 用聚合接口而非逐个资源请求：后者在移动网络下是 9 次往返，延迟与耗电都不划算。
    /// 后台会并发取各项，且各项独立成败 —— 某项失败不影响其余。
    ///
    /// 坐标系：`CLLocation` 给的是 WGS-84，而后台统一按 GCJ-02 处理（国内数据源的要求），
    /// 故必须显式带 `datum=wgs84` 让后台转换。漏掉不会报错，只会静默偏移约 550 米。
    func report(for location: CLLocation) async throws -> WeatherReport {
        let coordinate = location.coordinate
        return try await VHLHTTP.shared.get(baseURL.appendingPathComponent("weather"), query: [
            // 后台约定「经度,纬度」
            "location": String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude),
            "datum": "wgs84",
            "resources": Self.resources.joined(separator: ","),
            // 资源专属参数用「<资源>.<参数>」前缀 —— daily 与 indices 的 days
            // 撞名且取值域不同（前者 3d/7d/…，后者只接受 1d/3d）
            "daily.days": "7d",
            "hourly.hours": "72h", // 24h、72h、168h
        ])
    }
}
