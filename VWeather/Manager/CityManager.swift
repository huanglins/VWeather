//
//  CityManager.swift
//  VWeather
//
//  城市管理：增删查、搜索（CLGeocoder）、当前定位城市维护、选中城市。
//

import Foundation
import CoreLocation

extension Notification.Name {
    /// 选中城市变更 / 当前位置更新后广播，首页据此**立即**刷新（无需等待 sheet 关闭动画）
    static let VWSelectedCityDidChange = Notification.Name("VWSelectedCityDidChange")
}

class CityManager {
    static let manager = CityManager()

    private let ud = UserDefaults(suiteName: "group.cn.vincents.dev") ?? .standard

    // MARK: - 查询

    /// 所有城市：「我的位置」置顶，其余按 sortOrder 升序（过滤已软删除项）
    func allCities() -> [CityModel] {
        let cities = CityModel.objects(order: .ASC("sortOrder")).filter { $0.isDeleted != true }
        let current = cities.filter { $0.isCurrentLocation == true }
        let others = cities.filter { $0.isCurrentLocation != true }
        return current + others
    }

    // MARK: - 增删

    /// 添加 / 更新一个城市（按 cityKey 去重）
    @discardableResult
    func addCity(_ city: CityModel) -> CityModel {
        var c = city
        if c.sortOrder == nil {
            let maxOrder = CityModel.objects().compactMap { $0.sortOrder }.max() ?? 0
            c.sortOrder = maxOrder + 1
        }
        if c.createDate == nil { c.createDate = Date() }
        c.isDeleted = false
        c.updateDate = Date()
        c.saveOrUpdate()
        return c
    }

    /// 删除城市（「我的位置」不可删）。
    /// 采用**软删除**（isDeleted=1）而非物理删除——否则该记录会被 iCloud 再次同步回来；
    /// 标记后由同步引擎把删除传播到云端，其它设备据此删除本地记录。
    @discardableResult
    func deleteCity(_ city: CityModel) -> Bool {
        if city.isCurrentLocation == true { return false }
        var c = city
        c.isDeleted = true
        c.updateDate = Date()
        let ok = c.update()
        SyncManager.manager.push()      // 尽快把删除推送到 iCloud（未开启同步时内部会跳过）
        if let key = city.cityKey {
            CityWeatherSnapshot.delete(whereSQL: "cityKey = '\(key)'")
            if selectedCityKey == key { setSelectedCityKey(nil) }
        }
        return ok
    }

    // MARK: - 搜索（CLGeocoder 正向地理编码）

    func searchCities(_ keyword: String) async -> [CityModel] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }

        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.geocodeAddressString(kw) else { return [] }

        // 去重（同坐标）
        var seen = Set<String>()
        return placemarks.compactMap { Self.city(from: $0) }.filter { c in
            guard let key = c.cityKey else { return false }
            return seen.insert(key).inserted
        }
    }

    /// CLPlacemark → CityModel
    static func city(from placemark: CLPlacemark) -> CityModel? {
        guard let loc = placemark.location else { return nil }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude

        var c = CityModel()
        c.latitude = lat
        c.longitude = lng
        c.cityKey = CityModel.makeKey(lat: lat, lng: lng)
        c.name = placemark.subLocality
            ?? placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
            ?? placemark.name
        c.province = placemark.administrativeArea
        c.country = placemark.country
        c.fullAddress = [placemark.country, placemark.administrativeArea, placemark.locality, placemark.subLocality]
            .compactMap { $0 }
            .joined()
        return c
    }

    // MARK: - 当前定位城市

    /// 定位并 upsert「我的位置」城市。首次时自动设为选中城市。
    func refreshCurrentLocationCity(_ completion: ((CityModel?, VHLLocationError?) -> Void)? = nil) {
        // 权限已被拒绝 / 受限：不再尝试，引导用户去「设置」开启
        let status = VHLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            DispatchQueue.main.async { completion?(nil, .denied) }
            return
        }
        VHLLocationManager.manager.aloneReGeocodeLocation { [weak self] model, _ in
            guard let self = self, let model = model else {
                // 反查此刻权限状态以区分失败原因（不再回退到任何默认位置）
                let status = VHLLocationManager.authorizationStatus()
                let failure: VHLLocationError = (status == .denied || status == .restricted) ? .denied : .failed
                DispatchQueue.main.async { completion?(nil, failure) }
                return
            }

            var c = CityModel()
            c.latitude = model.latitude
            c.longitude = model.longitude
            c.cityKey = CityModel.makeKey(lat: model.latitude, lng: model.longitude)
            c.name = model.area ?? model.city ?? "我的位置"
            c.province = model.province
            c.country = model.country
            c.fullAddress = model.address
            c.isCurrentLocation = true
            c.isDeleted = false
            c.sortOrder = 0
            c.createDate = Date()
            c.updateDate = Date()

            // 定位坐标可能变化：先移除旧的定位项，再写入新的
            CityModel.delete(whereSQL: "isCurrentLocation = 1")
            c.saveOrUpdate()

            if self.selectedCityKey == nil {
                self.setSelectedCityKey(c.cityKey)
            }
            DispatchQueue.main.async { completion?(c, nil) }
        }
    }

    // MARK: - 选中城市

    var selectedCityKey: String? {
        ud.string(forKey: UD_SelectedCityKey)
    }

    func setSelectedCityKey(_ key: String?) {
        if let key = key {
            ud.set(key, forKey: UD_SelectedCityKey)
        } else {
            ud.removeObject(forKey: UD_SelectedCityKey)
        }
    }

    func setSelected(_ city: CityModel) {
        setSelectedCityKey(city.cityKey)
    }

    /// 当前首页应显示的城市：优先选中项，否则列表首项
    var selectedCity: CityModel? {
        if let key = selectedCityKey,
           let city = CityModel.objects(whereSQL: "cityKey = ?", params: [key]).first {
            return city
        }
        return allCities().first
    }
}
