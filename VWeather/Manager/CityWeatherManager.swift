//
//  CityWeatherManager.swift
//  VWeather
//
//  城市天气 + 日月快照：读缓存（秒显）与刷新入库。
//  复用 VHLAppleWeather（WeatherKit）与 VHLSunMoonManager（SunKit/MoonKit）。
//  补充数据（AQI / 生活指数 / 分钟降水 / 预警）走 VHLWeatherAPI（vapi 后台代理和风）。
//

import Foundation
import CoreLocation

/// 一次刷新的结果。
///
/// 天气（WeatherKit）与补充数据（vapi）来自两个独立数据源，成败互不影响：
/// 任一方失败，另一方仍照常入库并展示。故错误分开记录，而不是笼统给一个。
struct WeatherRefreshResult {
    var snapshot: CityWeatherSnapshot?
    /// WeatherKit 的失败原因，nil 表示成功
    var weatherError: Error?
    /// 补充数据的失败原因，nil 表示成功。补充数据失败不影响天气展示。
    var supplementError: Error?
}

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
    /// - Returns: 最新快照；失败时为上次的缓存（可能为 nil）。
    ///            需要知道失败原因时用 `refreshDetailed(for:force:)`。
    @discardableResult
    func refresh(for city: CityModel,
                 force: Bool = false,
                 includeSupplement: Bool = true) async -> CityWeatherSnapshot? {
        await refreshDetailed(for: city, force: force, includeSupplement: includeSupplement).snapshot
    }

    /// 同 `refresh`，但一并返回两个数据源各自的错误，供重试与 UI 提示使用。
    /// - Parameter includeSupplement: 是否拉取补充数据。Widget 只显示温度与天气现象，
    ///   传 false 可省掉一次网络请求与和风配额。
    @discardableResult
    func refreshDetailed(for city: CityModel,
                         force: Bool = false,
                         includeSupplement: Bool = true) async -> WeatherRefreshResult {
        guard let key = city.cityKey else { return WeatherRefreshResult() }

        let cached = cachedSnapshot(for: city)

        // 两个数据源各自独立节流。
        // 天气：缓存无天气数据时（如上次失败）不受节流，立即重试。
        let needWeather = force
            || cached?.weatherJSON == nil
            || Self.isStale(cached?.updateDate)
        // 补充数据：按 supplementDate 节流。失败也会写该时间，故后台故障时按 30 分钟退避。
        let needSupplement = includeSupplement
            && (force || Self.isStale(cached?.supplementDate))

        if !needWeather, !needSupplement, let cached {
            return WeatherRefreshResult(snapshot: cached)
        }

        let location = city.location

        // 两个数据源并发拉取：WeatherKit 走本地框架，补充数据走网络，互不阻塞。
        // 各自吞掉异常转成 Result，任一方失败不影响另一方入库。
        async let weatherTask = needWeather ? Self.fetchWeather(location) : nil
        async let supplementTask = needSupplement ? Self.fetchSupplement(location) : nil
        let (weatherResult, supplementResult) = await (weatherTask, supplementTask)

        // 组装与入库只做一次：两条链路各自 saveOrUpdate 会 last-write-wins 互相覆盖
        var snap = cached ?? CityWeatherSnapshot()
        snap.cityKey = key

        // 各模型整体 JSON 存储：新增展示字段时无需在此逐一赋值。
        // 失败时保留上次的值，好过把已有数据清成 nil。
        var weatherError: Error?
        if let weatherResult {
            switch weatherResult {
            case .success(let model):
                if let model {
                    snap.weatherJSON = CityWeatherSnapshot.encodeJSON(WeatherDisplay(from: model))
                }
            case .failure(let error):
                weatherError = error
                print("[CityWeatherManager] 天气请求失败 city=\(key): \(error.localizedDescription)")
            }

            // 日月（本地计算）。跟随天气一起更新
            let sun = VHLSunMoonManager.manager.sunInfo(location: location)
            let moon = VHLSunMoonManager.manager.moonInfo(location: location)
            snap.sunJSON = CityWeatherSnapshot.encodeJSON(sun)
            snap.moonJSON = CityWeatherSnapshot.encodeJSON(moon)
            snap.updateDate = Date()
        }

        var supplementError: Error?
        if let supplementResult {
            switch supplementResult {
            case .success(let model):
                snap.supplementJSON = CityWeatherSnapshot.encodeJSON(model)
            case .failure(let error):
                supplementError = error
                print("[CityWeatherManager] 补充数据请求失败 city=\(key): \(error.localizedDescription)")
            }
            // 成功失败都记，失败时用于退避
            snap.supplementDate = Date()
        }

        snap.saveOrUpdate()
        return WeatherRefreshResult(snapshot: snap,
                                    weatherError: weatherError,
                                    supplementError: supplementError)
    }

    /// 距上次更新是否已超过节流间隔（未更新过视为过期）
    private static func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= minRefreshInterval
    }

    // MARK: - 各数据源取数（异常转 Result，避免任一方抛出中断另一方）

    private static func fetchWeather(_ location: CLLocation) async -> Result<VHLWeatherModel?, Error> {
        do {
            return .success(try await VHLAppleWeather.shared.getWeather(for: location))
        } catch {
            return .failure(error)
        }
    }

    private static func fetchSupplement(_ location: CLLocation) async -> Result<WeatherSupplement, Error> {
        do {
            return .success(try await VHLWeatherAPI.shared.supplement(for: location))
        } catch {
            return .failure(error)
        }
    }
}
