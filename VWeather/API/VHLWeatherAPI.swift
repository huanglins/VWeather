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
    /// 常驻资源（每次刷新都取）。
    ///
    /// 两项**不在此列**、按需请求，以省上游：
    ///   · `minutely`（分钟降水）：5 分钟就过时、后端 TTL 短，仅在可能降水时才带上
    ///     （由 `CityWeatherManager` 据上一份报告判断）。
    ///   · `air-hourly`（逐小时空气质量）：只喂首页那张次要的小时 AQI 图，却是整整一条
    ///     60min 资源。改为用户点按「逐小时空气质量」时才单独取（见 `fetch(for:resources:)`）。
    private static let baseResources = ["now", "daily", "hourly",
                                        "air", "air-daily",
                                        "indices", "alerts"]

    /// 一次拉资源。
    ///
    /// 用聚合接口而非逐个资源请求：后者在移动网络下是多次往返，延迟与耗电都不划算。
    /// 后台会并发取各项，且各项独立成败 —— 某项失败不影响其余。
    ///
    /// - Parameter includeMinutely: 是否带上分钟降水。默认 false —— 只有判断可能降水时才传 true。
    ///
    /// 坐标系：`CLLocation` 给的是 WGS-84，而后台统一按 GCJ-02 处理（国内数据源的要求），
    /// 故必须显式带 `datum=wgs84` 让后台转换。漏掉不会报错，只会静默偏移约 550 米。
    func report(for location: CLLocation, includeMinutely: Bool = false) async throws -> WeatherReport {
        let coordinate = location.coordinate
        var resources = Self.baseResources
        if includeMinutely { resources.append("minutely") }
        return try await VHLHTTP.shared.get(baseURL.appendingPathComponent("weather"), query: [
            // 后台约定「经度,纬度」
            "location": String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude),
            "datum": "wgs84",
            "resources": resources.joined(separator: ","),
            // 资源专属参数用「<资源>.<参数>」前缀 —— daily 与 indices 的 days
            // 撞名且取值域不同（前者 3d/7d/…，后者只接受 1d/3d）
            "daily.days": "7d",
            // UI 首页只用 24 小时、组件只用 6 小时；72h 是更贵的档且载荷更大，无谓。
            "hourly.hours": "24h",
        ])
    }

    /// 按需取指定资源。用于用户点开某块（如「逐小时空气质量」→ air-hourly）时单独取，
    /// 避免把它塞进每次刷新的常驻请求里。后端仍按资源缓存，多是命中缓存。
    func fetch(for location: CLLocation, resources: [String]) async throws -> WeatherReport {
        let coordinate = location.coordinate
        return try await VHLHTTP.shared.get(baseURL.appendingPathComponent("weather"), query: [
            "location": String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude),
            "datum": "wgs84",
            "resources": resources.joined(separator: ","),
        ])
    }
}
