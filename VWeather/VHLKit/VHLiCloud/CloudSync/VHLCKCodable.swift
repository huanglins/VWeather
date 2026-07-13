//
//  VHLCKConvertible.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/21.
//

import Foundation
import CloudKit

/**
    用于对象转 CKRecord 的协议
 */

// MARK: - Encodable
// Model -> CKRecord
public protocol VHLCKRecordEncodable: Encodable {
    /// 存储表名
    static var recordType: String { get }
    /// 存储空间 ID
    static var zoneID: CKRecordZone.ID { get }
    /// 存储主键 ID （保持唯一性）
    var recordID: CKRecord.ID { get }
    
    /// 从 CloudKit 存储系统字段 CKRecord
    var cloudKitSystemFields: Data? { get set }
    
    /// 用于标记是否删除来处理 iCloud 同步，可用于延迟通知。 直接删除后，会被同步回来。
    var isDeleted: Bool? { get set }
    
    /// 本地最后修改时间，用于增量推送判断。
    /// 返回非 nil 且比 cloudKitLastModifiedDate 更新时，record 会被 push 到 CloudKit。
    /// 返回 nil 时，仅 cloudKitSystemFields == nil 的 record（从未同步过）会被 push。
    /// 模型应覆写此属性并返回其本地修改时间字段（如 updateDate）。
    var localModificationDate: Date? { get }
    
    /// 编码一个 CKRecord
    func encodeRecord() -> CKRecord?
}

extension VHLCKRecordEncodable {
    /// 表名（默认为类名）
    static var recordType: String { return String(describing: Self.self) }
    /// 自定义空间名称
    public static var zoneID: CKRecordZone.ID {
        return CKRecordZone.ID(zoneName: "\(recordType)sZone", ownerName: CKCurrentUserDefaultName)
    }
    
    /// 默认实现：返回 nil。模型应覆写此属性以启用增量推送。
    public var localModificationDate: Date? { return nil }
    
    /// 记录最后保存到 server 的时间（基础实现，每次访问均执行反序列化）
    public var cloudKitLastModifiedDate: Date? {
        guard let data = cloudKitSystemFields,
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record?.modificationDate
    }
}

// MARK: - class 类型缓存版本（避免重复执行 NSKeyedUnarchiver）

/// 关联对象 key：缓存上次解码时的 cloudKitSystemFields 数据快照
private var ckCachedDataKey: UInt8 = 0
/// 关联对象 key：缓存解码后的 modificationDate（NSNull 表示 nil）
private var ckCachedDateKey: UInt8 = 0

extension VHLCKRecordEncodable where Self: AnyObject {
    /// `cloudKitLastModifiedDate` 缓存版本（仅 class 类型生效）。
    ///
    /// 每次访问时对比当前 `cloudKitSystemFields` 与上次解码时的数据快照：
    /// - 数据未变 → 直接返回缓存 `Date`，跳过 NSKeyedUnarchiver
    /// - 数据已变 → 重新解码并更新缓存
    public var cloudKitLastModifiedDate: Date? {
        let currentData = cloudKitSystemFields
        
        // 与缓存快照比对；数据相同则直接返回缓存结果
        let cachedData = objc_getAssociatedObject(self, &ckCachedDataKey) as? Data
        if currentData == cachedData {
            let cached = objc_getAssociatedObject(self, &ckCachedDateKey)
            if let date = cached as? Date { return date }
            if cached is NSNull { return nil }
            // cached 为 nil 说明从未写入缓存，继续向下解码
        }
        
        // 解码 CKRecord
        let date: Date?
        if let data = currentData,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            let record = CKRecord(coder: coder)
            coder.finishDecoding()
            date = record?.modificationDate
        } else {
            date = nil
        }
        
        // 写缓存：data 快照 + date 结果（nil 用 NSNull 占位，以区分"未缓存"与"缓存为 nil"）
        objc_setAssociatedObject(self, &ckCachedDataKey,
                                 currentData, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        objc_setAssociatedObject(self, &ckCachedDateKey,
                                 date ?? NSNull(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return date
    }
}

// MARK: - Decodable
// CKRecord -> Model
public protocol VHLCKRecordDecodable: Decodable {
    // 解码一个 CKRecord
    static func decodeRecord(_ record: CKRecord) -> Self?
}

// MARK: - Codable
public protocol VHLCKRecordCodable: VHLCKRecordEncodable & VHLCKRecordDecodable {
    /// 处理冲突
    static func resolveConflict(clientModel: Self, serverModel: Self) -> Self?
}

// ---------------------------------------------------------------------------------------------
// MARK: - 默认 Codable 实现
extension VHLCKRecordCodable {
    public func encodeRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        return record
    }
    
    public static func decodeRecord<T>(_ record: CKRecord) -> T? where T : VHLCKRecordCodable {
        return nil
    }
}

/**
 1. cloudKitSystemFields 是什么

  每次记录成功推送到 CloudKit 后，服务端会返回一个完整的 CKRecord 对象（包含
  recordID、recordChangeTag、modificationDate 等系统字段
  ）。框架把这个 CKRecord 用 NSKeyedArchiver 序列化后存入本地数据库的 cloudKitSystemFields 字段：

   本地 Reminder.cloudKitSystemFields = NSKeyedArchiver(CKRecord)
                                                  ↑
                                 内含：recordID = "abc-123-rid"
                                       modificationDate = 服务端时间
                                       changeTag = 服务端版本标记

  2. 编码时 recordID 的优先级

  encodeRecord() 调用链：

   encodeRecord()
     └─ VHLCKRecordEncoder.encode(self)
          └─ value.encode(to: encoder)   // 会把 cloudKitSystemFields 写入 encoder.storage.record
          └─ encoder.buildRecord()
               └─ storage.record          ← ⚠️ 优先使用这里！
                  ?? CKRecord(recordName: self.recordID.recordName)  ← 才用 rid

  value.encode(to:) 过程中，遇到 key = "cloudKitSystemFields" 时，会把 Data 反序列化还原为 CKRecord
  存入 storage.record。
  因此 只要 cloudKitSystemFields != nil，最终 CKRecord 的 recordID 就来自里面，而不是当前对象的 rid。

 */
