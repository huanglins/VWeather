//
//  VHLCKSQLiteConvertible.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/6/9.
//

import Foundation
import CloudKit

// ** 注意：不要使用 pkid 自增来设置为主键，当多设备的同步的时候，数字 pkid 会重复

extension VHLCKRecordCodable where Self: VHLSQLiteObject {
    
    public static var zoneID: CKRecordZone.ID {
        return CKRecordZone.ID(zoneName: "\(recordType)sZone", ownerName: CKCurrentUserDefaultName)
    }
    
    public var recordID: CKRecord.ID {
        guard let primaryProerty = self.primaryKeyProperty() else {
            fatalError("需要设置 SQLite Object 的主键")
        }
        let primaryKeyValue = "\(primaryProerty.value ?? 0)"
        
        return CKRecord.ID(recordName: primaryKeyValue, zoneID: Self.zoneID)
    }
    
    func encodeRecord() -> CKRecord? {
        // 使用 codable 的方式进行转换
        // ** 一个致命的问题 JSONEncoder ，一旦为可选属性设置了一个值并且该值已同步到 iCloud，则无法将其设置回 nil 并再次同步到 iCloud。它始终会与 iCloud 值同步。
        do {
            let record = try VHLCKRecordEncoder().encode(self)
            // 若模型实现了 VHLCKAttachmentSyncable，将附件字段的本地路径替换为 CKAsset
            (self as? any VHLCKAttachmentSyncable)?.applyAssetPatching(to: record)
            return record
        } catch {
            VHLCKLogger.log("VHLCKRecord 编码错误: \(error)")
        }

        return nil
        
//        // 自定义转换
//        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
//        let properties = getProperties()
//
//        for prop in properties {
//            if prop.key == "cloudKitSystemFields" { continue }
//
//            guard let value = prop.value else { continue }
//            // 空数组无法推断类型，会报错
//            /// annot use an empty list to initialize a new field (field 'repeatDays' in record type 'Reminder' should be more precise)\
//            if let value = value as? [Any], value.count <= 0 { continue }
//
//            record[prop.key] = value as? CKRecordValue
//        }
//
//        return record
    }
    
    public static func decodeRecord(_ record: CKRecord) -> Self? {
        /// 遍历所有属性。 CKRecord -> Object
        var result: [String: Any] = [:]
        
        // 若模型实现了 VHLCKAttachmentSyncable，预先取得附件字段名集合
        let assetKeys: Set<String>
        if let attachType = Self.self as? any VHLCKAttachmentSyncable.Type {
            assetKeys = Set(attachType.assetFieldKeys)
        } else {
            assetKeys = []
        }
        
        for prop in Self().getProperties() {
            let key = prop.key
            guard let value = record.value(forKey: key) else { continue }
            
            // 附件字段：CKAsset → 保存到本地永久路径 → 存储 absoluteString
            // 若 fileURL 为 nil（文件尚未下载），跳过此字段以保留本地现有值
            if !assetKeys.isEmpty, assetKeys.contains(key), let asset = value as? CKAsset,
               let localAsset = VHLCKAsset.parse(from: key, record: record, asset: asset) {
                result[key] = localAsset.filePath.absoluteString
            } else {
                result[key] = value
            }
        }

        let object = try? Self.encodeObject(with: result)

        return object
    }
}

extension VHLCKRecordCodable where Self: VHLSQLiteObject {
    public static func resolveConflict(clientModel: Self, serverModel: Self) -> Self? {
        // 本地已标记软删除（等待 push 到 CloudKit），删除意图优先于对端任何更新
        if clientModel.isDeleted ?? false {
            return clientModel
        }
        if let clientDate = clientModel.cloudKitLastModifiedDate,
           let serverDate = serverModel.cloudKitLastModifiedDate {
            return clientDate > serverDate ? clientModel : serverModel
        }
        return serverModel
    }
}
