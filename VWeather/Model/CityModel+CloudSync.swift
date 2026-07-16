//
//  CityModel+CloudSync.swift
//  VWeather
//
//  CityModel 的 iCloud 同步接入。**仅主 App target**——依赖 VHLiCloud，
//  小组件不参与同步，故从 CityModel.swift 拆分到此文件，避免 widget 被迫引入 VHLiCloud。
//

import Foundation
import CloudKit

// VHLCKSQLiteCodable 已为 (VHLSQLiteObject & VHLCKRecordCodable) 提供
// recordID / encodeRecord / decodeRecord / resolveConflict 的默认实现，
// 这里覆写 localModificationDate 供增量推送判断，并覆写 encodeRecord 把
// 「当前位置」挡在同步之外。
extension CityModel: VHLCKRecordCodable {
    var localModificationDate: Date? { updateDate }

    /// 「当前位置」是**设备本地状态**、随移动而变，不参与 iCloud 同步。
    ///
    /// 返回 nil 即把它挡在 push 之外（store 与 delete 两条推送路径都走 encodeRecord，
    /// 见 VHLCKSQLiteSyncObject.pushLocalObjectsToCloudKit 的 `.compactMap { $0.encodeRecord() }`）。
    /// 否则它会作为一条「城市」同步到其它设备（每台设备各在不同位置，纯属噪音），
    /// 且用固定主键会让多设备在同一 recordName 上互相覆盖。
    ///
    /// encodeRecord 是协议要求（VHLCKRecordEncodable）、动态派发，这里的覆写会被通用同步层调用到。
    func encodeRecord() -> CKRecord? {
        guard isCurrentLocation != true else { return nil }
        return try? VHLCKRecordEncoder().encode(self)
    }
}
