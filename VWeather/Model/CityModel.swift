//
//  CityModel.swift
//  VWeather
//
//  城市/地点数据模型（SQLite 表）。
//

import Foundation
import CoreLocation

/// 城市/地点。存入 SQLite（表名默认取类型名 "CityModel"）。
/// 所有字段声明为可选型，以兼容后续新增字段时的迁移与解码。
struct CityModel: VHLSQLiteObject {
    var pkid: Int?
    /// 唯一键：`"%.4f,%.4f"` 格式的经纬度，用于去重与关联天气缓存
    var cityKey: String?
    var latitude: Double?
    var longitude: Double?
    var name: String?           // 显示名（城市 / 区）
    var province: String?       // 省 / 州
    var country: String?        // 国家
    var fullAddress: String?    // 完整地址
    var isCurrentLocation: Bool? // 是否「我的位置」（自动定位项）
    var sortOrder: Int?         // 排序
    var createDate: Date?

    // MARK: iCloud 同步字段
    var updateDate: Date?               // 本地最后修改时间（增量推送判据）
    var isDeleted: Bool?                // 软删除标记（删除意图需同步传播）
    var cloudKitSystemFields: Data?     // CloudKit 回传的系统字段（recordID/changeTag/modificationDate）

    init() {}

    // 用 cityKey（稳定字符串）作主键：CloudKit recordName 取主键值、跨设备一致；
    // 不能用 pkid 自增（多设备数字会冲突）。主键自带 UNIQUE，saveOrUpdate 走主键 upsert。
    func primaryKey() -> String { "cityKey" }

    /// 坐标
    var location: CLLocation {
        CLLocation(latitude: latitude ?? 0, longitude: longitude ?? 0)
    }

    /// 首页 / 列表展示名
    var displayName: String {
        if isCurrentLocation == true {
            return name ?? "我的位置"
        }
        return name ?? province ?? country ?? "未知城市"
    }

    /// 由经纬度生成唯一键
    static func makeKey(lat: Double, lng: Double) -> String {
        String(format: "%.4f,%.4f", lat, lng)
    }
}
