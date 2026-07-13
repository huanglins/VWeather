//
//  VHLCKRecordKeyedDecodingContainer.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/26.
//

import Foundation
import CloudKit

 final class VHLCKRecordKeyedDecodingContainer<Key: CodingKey> {
    var record: CKRecord
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    lazy var jsonDecoder: JSONDecoder = {
        return JSONDecoder()
    }()
    
    init(record: CKRecord) {
        self.record = record
    }
    
    private lazy var systemFieldsData: Data = {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }()
    
    func nestedCodingPath(forKey key: CodingKey) -> [CodingKey] {
        return self.codingPath + [key]
    }
}

// MARK: - Protocol - KeyedDecodingContainerProtocol 实现解码容器协议
extension VHLCKRecordKeyedDecodingContainer: KeyedDecodingContainerProtocol {
    var allKeys: [Key] {
        return self.record.allKeys().compactMap { Key(stringValue: $0) }
    }
    
    func contains(_ key: Key) -> Bool {
        // CKRecord 不包含表示系统字段信息的键。系统字段数据
        // 必须单独提取。这里返回 true 告诉解码器我们可以提取这个值。
        guard key.stringValue != _VHLCloudKitSystemFieldsKeyName else { return true }
        
        // 所有其他键必须存在于 CKRecord 中才能被解码。
        return allKeys.contains(where: { $0.stringValue == key.stringValue })
    }
    
    /// 解码 nil 值
    func decodeNil(forKey key: Key) throws -> Bool {
        if key.stringValue == _VHLCloudKitSystemFieldsKeyName {
            return systemFieldsData.count == 0
        }
        return record[key.stringValue] == nil
    }
    
    /// 解码值
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        // 从 CKRecord 中提取系统字段数据。
        if key.stringValue == _VHLCloudKitSystemFieldsKeyName {
            return systemFieldsData as! T
        } else if type == URL.self {
            return try VHLCKURLTransformer.decodeSingle(record: record, key: key, codingPath: codingPath) as! T
        } else if type == [URL].self {
            return try VHLCKURLTransformer.decodeMany(record: record, key: key, codingPath: codingPath) as! T
        } else if let value = record[key.stringValue] as? T {
            return value
        } else if let value = record[key.stringValue] as? Data,
                  let decodedValue = try? jsonDecoder.decode(type, from: value) {
            return decodedValue
        }
        
        // 自定义单值解码
        let decoder = VHLCKRecordSingleValueDecoder(record: record, codingPath: codingPath + [key])
        guard let decodedValue = try? type.init(from: decoder) else {
            let context = DecodingError.Context(
              codingPath: codingPath,
              debugDescription: "Value could not be decoded for key \(key)."
            )
            throw DecodingError.typeMismatch(type, context)
        }
        
        return decodedValue
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError("Not implemented")
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        fatalError("Not implemented")
    }
    
    func superDecoder() throws -> Decoder {
        return _VHLCKRecordDecoder(record: record)
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        let decoder = _VHLCKRecordDecoder(record: record)
        decoder.codingPath = [key]
        return decoder
    }
}
