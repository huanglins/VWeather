//
//  VHLCKRecordSingleValueEncoder.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/12.
//

import Foundation
import CloudKit

enum VHLCKRecordSingleValueEncodingError: Error {
  case unableToEncode
}

// MARK: - 用于编码单个值的编码器
struct VHLCKRecordSingleValueEncoder: Encoder {
    private var storage: _VHLCKRecordEncoder.Storage
    
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    init(storage: _VHLCKRecordEncoder.Storage, codingPath: [CodingKey]) {
        self.storage = storage
        self.codingPath = codingPath
    }
    
    /// 返回一个容器，用于存放多个由给定键索引的值。
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(DummyKeyedEncodingContainer())
    }
    
    /// 返回一个容器，用于存放多个没有键索引的值。
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return DummyUnkeyedCodingContainer()
    }
    
    /// 返回一个适合存放单一值的编码容器。
    func singleValueContainer() -> SingleValueEncodingContainer {
        var container = VHLCKRecordSingleValueEncodingContainer(storage: storage)
        container.codingPath = codingPath
        return container
    }
}

// MARK: - 编码容器
struct VHLCKRecordSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey] = []
    var storage: _VHLCKRecordEncoder.Storage
    
    mutating func encodeNil() throws {
        storage.encode(codingPath: codingPath, value: nil)
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        guard let value = value as? CKRecordValue else {
            throw VHLCKRecordSingleValueEncodingError.unableToEncode
        }
        storage.encode(codingPath: codingPath, value: value)
    }
}

struct DummyKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] = []
    
    mutating func encodeNil(forKey key: Key) throws {
        throw VHLCKRecordSingleValueEncodingError.unableToEncode
    }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        throw VHLCKRecordSingleValueEncodingError.unableToEncode
    }
    
    // 嵌套容器
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError("没有实现")
    }
    
    // 嵌套索引容器
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("没有实现嵌套容器")
    }
    
    // 父类容器
    mutating func superEncoder() -> Encoder {
        fatalError("没有实现")
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("没有实现")
    }
}

struct DummyUnkeyedCodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] = []
    
    var count: Int = 0
    
    mutating func encodeNil() throws {
        throw VHLCKRecordSingleValueEncodingError.unableToEncode
    }
    func encode<T>(_ value: T) throws where T : Encodable {
        throw VHLCKRecordSingleValueEncodingError.unableToEncode
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        fatalError("没有实现")
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("没有实现")
    }
    
    mutating func superEncoder() -> Encoder {
        fatalError("没有实现")
    }
}
