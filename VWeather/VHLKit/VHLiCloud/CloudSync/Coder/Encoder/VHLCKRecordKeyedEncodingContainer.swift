//
//  VHLCKRecordKeyedEncodingContainer.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/15.
//

import Foundation
import CloudKit

// MARK: - VHLCKRecordKeyedEncodingContainer
final class VHLCKRecordKeyedEncodingContainer<Key: CodingKey> {
    var storage: _VHLCKRecordEncoder.Storage
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    lazy var jsonEncoder: JSONEncoder = {
        return JSONEncoder()
    }()
    
    init(storage: _VHLCKRecordEncoder.Storage) {
        self.storage = storage
    }
}

// MARK: - Protocol - KeyedEncodingContainerProtocol
// 实现编码转换
extension VHLCKRecordKeyedEncodingContainer: KeyedEncodingContainerProtocol {
    // 编码 nil
    func encodeNil(forKey key: Key) throws {
        storage.encode(codingPath: codingPath + [key], value: nil)
    }
    
    // 编码如果值不存在
    func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T : Encodable {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
    
    // 根据字段进行自定义解析
    func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        
        // 不支持嵌套对象 CKRecord.Reference
        guard !(value is VHLCKRecordEncodable) && !(value is [VHLCKRecordEncodable]) else {
            // throw VHLCKRecordEncodingError.referencesNotSupported((codingPath + [key]).map { $0.stringValue }.joined(separator: "-") )
            storage.encode(codingPath: codingPath + [key], value: nil)
            return
        }

        // cloudkit 系统字段 cloudKitSystemFields，里面包含 recordName、recordID、zoneID、ownerName、modificationDate 等信息，必须使用 Data 类型进行编码
        if key.stringValue == _VHLCloudKitSystemFieldsKeyName {
            guard let systemFieldsData = value as? Data else {
                throw VHLCKRecordEncodingError.systemFieldsDecode("\(_VHLCloudKitSystemFieldsKeyName) property must be of type Data.")
            }
            
            storage.set(record: VHLCKRecordEncoder.decodeSystemFields(with: systemFieldsData))
        } else if let value = value as? URL {               // url
            storage.encode(codingPath: codingPath + [key], value: VHLCKURLTransformer.encode(value))
        } else if let value = value as? [URL] {             // url 数组
            storage.encode(codingPath: codingPath + [key], value: value.map(VHLCKURLTransformer.encode) as CKRecordValue)
        } else if let value = value as? CKRecordValue {     // 可以直接转为 CKRecordValue 的值
            storage.encode(codingPath: codingPath + [key], value: value)
        } else {                                            // 自定义编码
            do {
                let encoder = VHLCKRecordSingleValueEncoder(storage: storage, codingPath: codingPath + [key])
                try value.encode(to: encoder)
            } catch {
                let value = try jsonEncoder.encode(value) as CKRecordValue
                storage.encode(codingPath: codingPath + [key], value: value)
            }
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError("Not implemented")
    }
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Not implemented")
    }
    func superEncoder() -> Encoder {
        fatalError("Not implemented")
    }
    func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Not implemented")
    }
}
