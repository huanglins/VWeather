//
//  VHLCKURLTransformer.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/13.
//

import Foundation
import CloudKit

enum VHLCKURLTransformer {
    static func encode(_ value: URL) -> CKRecordValue {
        // 如果是本地路径，那么编码为 CKAsset value
        if value.isFileURL {
            return CKAsset(fileURL: value)
        }
        
        return value.absoluteString as CKRecordValue
    }
    
    static func decodeMany(record: CKRecord, key: CodingKey, codingPath: [CodingKey]) throws -> [URL] {
        if let array = record[key.stringValue] as? [Any] {
            return try array.map { try decodeValue(value: $0, codingPath: codingPath) }
        }
        return []
    }
    
    static func decodeSingle(record: CKRecord, key: CodingKey, codingPath: [CodingKey]) throws -> URL {
        return try decodeValue(value: record[key.stringValue] as Any, codingPath: codingPath)
    }
    
    private static func decodeValue(value: Any, codingPath: [CodingKey]) throws -> URL {
        // CKAsset
        if let asset = value as? CKAsset {
            guard let url = asset.fileURL else {
                let context = DecodingError.Context(
                  codingPath: codingPath, debugDescription: "CKAsset URL was nil.")
                throw DecodingError.valueNotFound(URL.self, context)
            }
            
            return url
        }
        
        // String
        guard let str = value as? String else {
            let context = DecodingError.Context(
              codingPath: codingPath,
              debugDescription: "URL should have been encoded as String in CKRecord."
            )
            throw DecodingError.typeMismatch(URL.self, context)
        }
        
        // URL
        guard let url = URL(string: str) else {
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "The string \(str) is not a valid url.")
            throw DecodingError.typeMismatch(URL.self, context)
        }
        
        return url
    }
}
