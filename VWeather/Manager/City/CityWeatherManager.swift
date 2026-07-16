//
//  CityWeatherManager.swift
//  VWeather
//
//  城市天气 + 日月快照：读缓存（秒显）与刷新入库。
//
//  天气走 VHLWeatherAPI（vapi 后台），失败或没数据时由 VHLAppleWeather（WeatherKit）兜底。
//  日月走 VHLSunMoonManager（SunKit/MoonKit），本地算，不依赖网络。
//

import Foundation
import CoreLocation

/// 一次刷新的结果。
struct WeatherRefreshResult {
    var snapshot: CityWeatherSnapshot?
    /// 天气的失败原因，nil 表示成功。两个数据源都失败时才有值。
    var weatherError: Error?
    /// 是否用了兜底数据源。UI 可据此提示「数据可能不全」——
    /// WeatherKit 没有空气质量与生活指数，那几个 Section 会整块消失，
    /// 不说明的话看起来像 App 出了问题。
    var usedFallback: Bool = false
}

/// 选中城市 cityKey 的存储 key（App Group UserDefaults 共享；主 App 与小组件共用）
let UD_SelectedCityKey = "VW_selectedCityKey"

class CityWeatherManager {
    static let manager = CityWeatherManager()

    /// 「相近共享」半径：两地点相距在此距离内视为同一处天气，共用一条快照、只请求一次。
    /// 覆盖「同一个家」的当前定位（GPS 点）与手动城市（地理编码中心）常见的 1–3km 偏差，
    /// 又不至于把用户特意分开添加的相邻城区并成一份。
    static let shareRadius: CLLocationDistance = 3000   // 3km

    /// 读取城市的天气缓存快照（用于切换时秒显 / 离线）。
    /// 按「相近」取：返回半径内**最近**的一条快照，使当前定位与坐标相近的手动城市共用同一条。
    func cachedSnapshot(for city: CityModel) -> CityWeatherSnapshot? {
        guard let lat = city.latitude, let lng = city.longitude else { return nil }
        return nearestSnapshot(to: CLLocation(latitude: lat, longitude: lng))
    }

    /// 与 location 相近（半径内）的现有快照中**最近**的一条；没有则 nil。
    private func nearestSnapshot(to location: CLLocation) -> CityWeatherSnapshot? {
        var best: (snap: CityWeatherSnapshot, dist: CLLocationDistance)?
        for snap in CityWeatherSnapshot.objects() {
            guard let loc = snap.location else { continue }
            let d = location.distance(from: loc)
            guard d <= Self.shareRadius else { continue }
            if best == nil || d < best!.dist { best = (snap, d) }
        }
        return best?.snap
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

    /// 天气自动刷新的最小间隔。此间隔内的**自动**请求直接复用缓存。
    /// 用户下拉刷新、当前位置坐标变更等场景传 `force: true` 可绕过。
    static let minRefreshInterval: TimeInterval = 30 * 60   // 30 分钟

    /// 请求最新天气 + 计算日月，组装快照并写入 SQLite。
    /// - Parameter force: 是否强制刷新（忽略频率限制）。默认 false，受 `minRefreshInterval` 节流。
    /// - Returns: 最新快照；失败时为上次的缓存（可能为 nil）。
    ///            需要知道失败原因时用 `refreshDetailed(for:force:)`。
    @discardableResult
    func refresh(for city: CityModel, force: Bool = false) async -> CityWeatherSnapshot? {
        await refreshDetailed(for: city, force: force).snapshot
    }

    /// 同 `refresh`，但一并返回失败原因与是否降级，供重试与 UI 提示使用。
    @discardableResult
    func refreshDetailed(for city: CityModel, force: Bool = false) async -> WeatherRefreshResult {
        guard let lat = city.latitude, let lng = city.longitude else { return WeatherRefreshResult() }
        let location = CLLocation(latitude: lat, longitude: lng)

        // 半径内已有可复用的快照：在它上面更新（多城共用一条）；没有才新建、锚在本城坐标。
        let cached = nearestSnapshot(to: location)

        // 缓存里没有天气时（上次失败，或旧版本遗留的 WeatherDisplay 解不出来）
        // 不受节流，立即重试。
        let needWeather = force || cached?.weather == nil || Self.isStale(cached?.updateDate)
        if !needWeather, let cached {
            return WeatherRefreshResult(snapshot: cached)   // 相近且新鲜 → 直接复用，不请求
        }

        let (report, error) = await Self.fetchReport(location)

        var snap = cached ?? CityWeatherSnapshot()
        if snap.weatherKey == nil {
            // 新建快照：以本城坐标作代表点（后续相近城市据此共用）
            snap.weatherKey = CityModel.makeKey(lat: lat, lng: lng)
            snap.latitude = lat
            snap.longitude = lng
        }

        // 失败时保留上次的值，好过把已有数据清成 nil ——
        // 离线时展示「30 分钟前的天气」远好过展示空白。
        if let report {
            snap.weatherJSON = CityWeatherSnapshot.encodeJSON(report)
        }

        // 日月本地算，不依赖网络，故天气失败它也照常更新。
        // 按快照的代表坐标算，与快照锚点一致（复用他城快照时也不串位）。
        let snapLoc = snap.location ?? location
        let sun = VHLSunMoonManager.manager.sunInfo(location: snapLoc)
        let moon = VHLSunMoonManager.manager.moonInfo(location: snapLoc)
        snap.sunJSON = CityWeatherSnapshot.encodeJSON(sun)
        snap.moonJSON = CityWeatherSnapshot.encodeJSON(moon)
        // 成功失败都记，失败时用于退避
        snap.updateDate = Date()

        snap.saveOrUpdate()
        return WeatherRefreshResult(snapshot: snap,
                                    weatherError: error,
                                    usedFallback: report?.source == .weatherKit)
    }

    /// 清理无人引用的孤儿快照：半径内没有任何在用（未软删）城市的快照即删除。
    /// 快照按「相近」共享、不再与城市一一对应，故城市增删 / 当前位置移动后调用它做 GC，
    /// 而非在删除单个城市时直接删其快照（那样会误删仍被邻近城市共用的一条）。
    func pruneOrphanSnapshots() {
        let cityLocations: [CLLocation] = CityModel.objects(whereSQL: "isDeleted != 1").compactMap {
            guard let la = $0.latitude, let lo = $0.longitude else { return nil }
            return CLLocation(latitude: la, longitude: lo)
        }
        for snap in CityWeatherSnapshot.objects() {
            guard let key = snap.weatherKey else { continue }
            let referenced = snap.location.map { loc in
                cityLocations.contains { $0.distance(from: loc) <= Self.shareRadius }
            } ?? false      // 无坐标的老快照视作孤儿
            if !referenced {
                CityWeatherSnapshot.delete(whereSQL: "weatherKey = '\(key)'")
            }
        }
    }

    /// 距上次更新是否已超过节流间隔（未更新过视为过期）
    private static func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) >= minRefreshInterval
    }

    // MARK: - 取数：后台为主，WeatherKit 兜底

    /// 返回 (报告, 错误)。两者不会同时为 nil：
    /// 拿到任一数据源的数据就返回它，全都失败才返回错误。
    private static func fetchReport(_ location: CLLocation) async -> (WeatherReport?, Error?) {
        var primaryError: Error?
        do {
            let report = try await VHLWeatherAPI.shared.report(for: location)
            // 后台返回 200 但各项全空 —— 视同失败。把一屏空白当成「成功」
            // 会让兜底路径永远走不到，而用户看到的就是个坏掉的 App。
            if !report.isEmpty {
                return (report, nil)
            }
            primaryError = WeatherFetchError.emptyResponse
            print("[CityWeatherManager] 后台返回空报告，转 WeatherKit 兜底")
        } catch {
            primaryError = error
            print("[CityWeatherManager] 后台天气失败，转 WeatherKit 兜底：\(error.localizedDescription)")
        }

        // 兜底：WeatherKit 是端上框架，没有网络也可能有缓存数据。
        // 它没有空气质量/生活指数，中国大陆也没有分钟降水 —— 那几项会缺，
        // 但基础天气能显示，比整屏空白强。
        do {
            let report = try await VHLAppleWeather.shared.report(for: location)
            if !report.isEmpty {
                return (report, nil)
            }
            return (nil, primaryError)
        } catch {
            print("[CityWeatherManager] WeatherKit 兜底也失败：\(error.localizedDescription)")
            // 报主数据源的错：兜底是实现细节，用户要知道的是「天气没取到」，
            // 而主数据源的失败原因通常更能说明问题。
            return (nil, primaryError ?? error)
        }
    }
}

enum WeatherFetchError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "天气数据为空"
        }
    }
}
