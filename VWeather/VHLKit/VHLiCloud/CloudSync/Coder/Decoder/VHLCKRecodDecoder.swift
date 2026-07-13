//
//  VHLCKRecodDecoder.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/11.
//

import Foundation
import CloudKit

// MARK: - CKRecod 解码器
public final class VHLCKRecordDecoder {
    public init() {}
    
    public func decode<T: Decodable>(_ type: T.Type, from record: CKRecord) throws -> T {
        let decoder = _VHLCKRecordDecoder(record: record)
        return try T(from: decoder)
    }
}

// MARK: - _VHLCKRecordDecoder 实际实现的解码器
final class _VHLCKRecordDecoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    private var record: CKRecord
    
    init(record: CKRecord) {
        self.record = record
    }
}

// MARK: - 实现解码
extension _VHLCKRecordDecoder: Decoder {
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        let container = VHLCKRecordKeyedDecodingContainer<Key>(record: record)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        fatalError("Not implemented")
    }
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        fatalError("No implemented")
    }
}

/**
 
 https://github.com/insidegui/CloudKitCodable
 */
