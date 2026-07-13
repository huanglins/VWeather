//
//  VHLCKRecordEncoder.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/12.
//

import Foundation
import CloudKit

// 默认 key
let _VHLCloudKitSystemFieldsKeyName = "cloudKitSystemFields"

// MARK: - VHLCKRecordEncoder CKRecord 编码器
public final class VHLCKRecordEncoder {
    /// 单条记录允许的最大大小
    private let maximumAllowedRecordSizeInBytes: Int = 2 * 1024 * 1024
    
    public init() { }
    
    public func encode<T: VHLCKRecordCodable>(_ value: T) throws -> CKRecord {
        let recordType = T.recordType
        let recordName = value.recordID.recordName
        let zoneID = T.zoneID

        let encoder = _VHLCKRecordEncoder(recordType: recordType, recordName: recordName, zoneID: zoneID)
        
        try value.encode(to: encoder)
        
        let record = encoder.buildRecord()
        try validateSize(for: encoder.storage.keys)
        
        return record
    }
    
    /// 解码系统字段
    public static func decodeSystemFields(with systemFields: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) else { return nil }
        coder.requiresSecureCoding = true
        
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}

extension VHLCKRecordEncoder {
    /// 校验当前 record 是否超过大小限制
    fileprivate func validateSize(for recordKeyValue: [String: CKRecordValue?]) throws {
        guard let recordData = try? NSKeyedArchiver.archivedData(withRootObject: recordKeyValue,
                                                                 requiringSecureCoding: true) else {
            return
        }
        
        func formattedSize(ofDataCount dataCount: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .binary
            return formatter.string(fromByteCount: Int64(dataCount))
        }
        
        if recordData.count >= maximumAllowedRecordSizeInBytes {
            let context = EncodingError.Context(codingPath: [],
                                                debugDescription: "CKRecord is to large. Record is \(formattedSize(ofDataCount: recordData.count)), the maxmimum allowed size is \(formattedSize(ofDataCount: maximumAllowedRecordSizeInBytes)))"
                                                )
            
            throw EncodingError.invalidValue(Any.self, context)
        }
    }
}

// MARK: - _VHLCKRecordEncoder 实际实现的编码器
final class _VHLCKRecordEncoder {
    let recordType: CKRecord.RecordType
    let recordName: String
    let zoneID: CKRecordZone.ID
    let codingPath: [CodingKey] = []
    
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    var storage: Storage
    
    init(recordType: CKRecord.RecordType,
         recordName: String,
         zoneID: CKRecordZone.ID,
         storage: Storage = Storage()) {
        self.recordType = recordType
        self.recordName = recordName
        self.zoneID = zoneID
        self.storage = storage
    }
}

extension _VHLCKRecordEncoder {
    final class Storage {
        private(set) var record: CKRecord?
        private(set) var keys: [String: CKRecordValue?] = [:]
        
        func set(record: CKRecord?) {
            self.record = record
        }
        
        func encode(codingPath: [CodingKey], value: CKRecordValue?) {
            let key = codingPath.map { $0.stringValue }.joined(separator: "_")
            keys[key] = value
        }
    }
    
    /// ** 构建一个 CKRecord **
    func buildRecord() -> CKRecord {
        // 仅当 storage.record 的 recordID 与当前对象一致时才复用（保留系统字段）。
        // 若 recordName 不匹配，说明对象是从已同步记录复制而来且未清空
        // cloudKitSystemFields，此时必须以 value.recordID 重建，防止两条记录
        // 共享同一个 CKRecord.ID 导致原始记录被覆盖。
        let existingRecord: CKRecord? = storage.record.flatMap { record in
            guard record.recordID.recordName == recordName,
                  record.recordID.zoneID == zoneID else { return nil }
            return record
        }

        let output: CKRecord = existingRecord ?? CKRecord(recordType: recordType,
                                                          recordID: CKRecord.ID(recordName: recordName,
                                                                                zoneID: zoneID))
        
        guard output.recordType == recordType else {
            fatalError(
              """
              CloudKit记录类型不匹配:记录应该是类型 \(recordType) ，但它是
              类型 \(output.recordType)。这可能是损坏的cloudKitSystemData的结果，
              或者必须通过采用customcloudkitencoable在类型中纠正的记录/类型名称的更改。
              """
            )
        }
        
        // 将所有键值赋值
        storage.keys.forEach { (key, value) in
            output[key] = value
        }
        return output
    }
}

extension _VHLCKRecordEncoder: Encoder {
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let container = VHLCKRecordKeyedEncodingContainer<Key>(storage: storage)
        container.codingPath = codingPath
        return KeyedEncodingContainer(container)
    }
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Not implemented")
    }
    func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError("Not implemented")
    }
}

/**
 
 https://github.com/insidegui/CloudKitCodable
 */
