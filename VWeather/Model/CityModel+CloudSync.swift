//
//  CityModel+CloudSync.swift
//  VWeather
//
//  CityModel 的 iCloud 同步接入。**仅主 App target**——依赖 VHLiCloud，
//  小组件不参与同步，故从 CityModel.swift 拆分到此文件，避免 widget 被迫引入 VHLiCloud。
//

import Foundation

// VHLCKSQLiteCodable 已为 (VHLSQLiteObject & VHLCKRecordCodable) 提供
// recordID / encodeRecord / decodeRecord / resolveConflict 的默认实现，
// 这里只需覆写 localModificationDate 供增量推送判断。
extension CityModel: VHLCKRecordCodable {
    var localModificationDate: Date? { updateDate }
}
