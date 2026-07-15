//
//  VHLWeatherAPI.swift
//  VWeather
//
//  vapi 后台天气接口。补齐 Apple WeatherKit 缺失的空气质量 / 生活指数 / 分钟降水 / 预警。
//  第三方 API（和风）的 key 与调用都在后台，客户端不持有任何密钥。
//

import CoreLocation
import Foundation

struct VHLWeatherAPI {
    static let shared = VHLWeatherAPI()

    private let baseURL = URL(string: "https://api.vincents.cn/v1")!

    /// 拉取补充数据。
    ///
    /// 坐标系：`CLLocation` 给的是 WGS-84，而和风在中国大陆要求 GCJ-02，
    /// 故必须显式带 `datum=wgs84` 让后台转换。漏掉不会报错，只会静默偏移数百米。
    func supplement(for location: CLLocation) async throws -> WeatherSupplement {
        let coordinate = location.coordinate
        let url = baseURL.appendingPathComponent("weather/supplement")
        return try await VHLHTTP.shared.get(url, query: [
            // 后台约定「经度,纬度」，与和风 v7 一致
            "location": String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude),
            "datum": "wgs84",
        ])
    }
}
