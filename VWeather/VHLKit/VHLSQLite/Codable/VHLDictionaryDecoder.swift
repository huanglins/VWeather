//
//  VHLDictionaryDecoder.swift
//  VHLSQLite
//
//  将 [String: Any] 字典直接解码为 Codable 对象，避免 JSONSerialization 往返。
//
//  特性：
//  - 支持类型自动转换（Int→Bool, String→Int, NSData→Data 等）
//  - Date 兼容毫秒格式与旧秒精度格式
//  - 数组/字典以 JSON 字符串存储时自动解析
//  - Optional 字段类型不匹配时记录日志并返回 nil，不中断整体解码
//

import Foundation

// MARK: - 公共入口

/// 将 `[String: Any]` 字典直接解码为 `Codable` 对象。
///
/// 替代 `JSONSerialization.data() + JSONDecoder.decode()` 的双重序列化路径，
/// 直接在字典上运行 Codable 的 `init(from:)`。
public final class VHLDictionaryDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let dec = _DictDecoder(storage: .keyed(dictionary), codingPath: [])
        return try T(from: dec)
    }
}

// MARK: - 内部 Storage

private enum _DictStorage {
    case keyed([String: Any])
    case unkeyed([Any])
    case single(Any)
}

// MARK: - Decoder

private final class _DictDecoder: Decoder {
    let storage: _DictStorage
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(storage: _DictStorage, codingPath: [CodingKey]) {
        self.storage = storage
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .keyed(let dict) = storage else {
            throw _typeMismatch([String: Any].self, "Expected keyed container", codingPath)
        }
        return KeyedDecodingContainer(_KeyedContainer<Key>(dict: dict, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch storage {
        case .unkeyed(let arr):
            return _UnkeyedContainer(array: arr, codingPath: codingPath)
        case .single(let v):
            if let arr = v as? [Any] {
                return _UnkeyedContainer(array: arr, codingPath: codingPath)
            }
            throw _typeMismatch([Any].self, "Expected unkeyed container", codingPath)
        case .keyed:
            throw _typeMismatch([Any].self, "Expected unkeyed container", codingPath)
        }
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        switch storage {
        case .single(let v): return _SingleValueContainer(value: v, codingPath: codingPath)
        case .keyed(let d):  return _SingleValueContainer(value: d, codingPath: codingPath)
        case .unkeyed(let a): return _SingleValueContainer(value: a, codingPath: codingPath)
        }
    }
}

// MARK: - KeyedDecodingContainerProtocol

private struct _KeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    let dict: [String: Any]
    var codingPath: [CodingKey]

    var allKeys: [K] { dict.keys.compactMap { K(stringValue: $0) } }

    func contains(_ key: K) -> Bool {
        guard let v = dict[key.stringValue] else { return false }
        return !VHLSQLiteTool.valueIsNil(v)
    }

    func decodeNil(forKey key: K) throws -> Bool {
        guard let v = dict[key.stringValue] else { return true }
        return VHLSQLiteTool.valueIsNil(v)
    }

    // ── 标量 decode ─────────────────────────────────────────────────────────

    func decode(_ type: Bool.Type,   forKey key: K) throws -> Bool   { try _coerceBool(_raw(key), key: key) }
    func decode(_ type: String.Type, forKey key: K) throws -> String { try _coerceString(_raw(key), key: key) }
    func decode(_ type: Double.Type, forKey key: K) throws -> Double { try _coerceDouble(_raw(key), key: key) }
    func decode(_ type: Float.Type,  forKey key: K) throws -> Float  { Float(try _coerceDouble(_raw(key), key: key)) }
    func decode(_ type: Int.Type,    forKey key: K) throws -> Int    { try _coerceInt(_raw(key), key: key) }
    func decode(_ type: Int8.Type,   forKey key: K) throws -> Int8   { Int8(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: Int16.Type,  forKey key: K) throws -> Int16  { Int16(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: Int32.Type,  forKey key: K) throws -> Int32  { Int32(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: Int64.Type,  forKey key: K) throws -> Int64  { Int64(try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: UInt.Type,   forKey key: K) throws -> UInt   { UInt(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: UInt8.Type,  forKey key: K) throws -> UInt8  { UInt8(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 { UInt16(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 { UInt32(clamping: try _coerceInt(_raw(key), key: key)) }
    func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 { UInt64(clamping: try _coerceInt(_raw(key), key: key)) }

    // ── 标量 decodeIfPresent（Optional 字段：类型不匹配时记录日志并返回 nil）──

    func decodeIfPresent(_ type: Bool.Type,   forKey key: K) throws -> Bool?   { _safeOptional(key) { try _coerceBool(_raw(key), key: key) } }
    func decodeIfPresent(_ type: String.Type, forKey key: K) throws -> String? { _safeOptional(key) { try _coerceString(_raw(key), key: key) } }
    func decodeIfPresent(_ type: Double.Type, forKey key: K) throws -> Double? { _safeOptional(key) { try _coerceDouble(_raw(key), key: key) } }
    func decodeIfPresent(_ type: Float.Type,  forKey key: K) throws -> Float?  { _safeOptional(key) { Float(try _coerceDouble(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: Int.Type,    forKey key: K) throws -> Int?    { _safeOptional(key) { try _coerceInt(_raw(key), key: key) } }
    func decodeIfPresent(_ type: Int8.Type,   forKey key: K) throws -> Int8?   { _safeOptional(key) { Int8(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: Int16.Type,  forKey key: K) throws -> Int16?  { _safeOptional(key) { Int16(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: Int32.Type,  forKey key: K) throws -> Int32?  { _safeOptional(key) { Int32(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: Int64.Type,  forKey key: K) throws -> Int64?  { _safeOptional(key) { Int64(try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: UInt.Type,   forKey key: K) throws -> UInt?   { _safeOptional(key) { UInt(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: UInt8.Type,  forKey key: K) throws -> UInt8?  { _safeOptional(key) { UInt8(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: K) throws -> UInt16? { _safeOptional(key) { UInt16(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: K) throws -> UInt32? { _safeOptional(key) { UInt32(clamping: try _coerceInt(_raw(key), key: key)) } }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: K) throws -> UInt64? { _safeOptional(key) { UInt64(clamping: try _coerceInt(_raw(key), key: key)) } }

    // ── 泛型 decode / decodeIfPresent ───────────────────────────────────────

    func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {
        try _decodeValue(type, from: _raw(key), key: key)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
        _safeOptional(key) { try _decodeValue(type, from: _raw(key), key: key) }
    }

    // ── 嵌套容器 ────────────────────────────────────────────────────────────

    func nestedContainer<NK: CodingKey>(keyedBy type: NK.Type, forKey key: K) throws -> KeyedDecodingContainer<NK> {
        let raw = try _raw(key)
        let d: [String: Any]
        if let dict = raw as? [String: Any] { d = dict }
        else if let s = raw as? String, let parsed = _parseJSONDict(s) { d = parsed }
        else { throw _typeMismatch([String: Any].self, "Expected dict for '\(key.stringValue)'", codingPath + [key]) }
        return KeyedDecodingContainer(_KeyedContainer<NK>(dict: d, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        let raw = try _raw(key)
        let a: [Any]
        if let arr = raw as? [Any] { a = arr }
        else if let s = raw as? String, let parsed = _parseJSONArray(s) { a = parsed }
        else { throw _typeMismatch([Any].self, "Expected array for '\(key.stringValue)'", codingPath + [key]) }
        return _UnkeyedContainer(array: a, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> Decoder {
        _DictDecoder(storage: .keyed(dict), codingPath: codingPath)
    }

    func superDecoder(forKey key: K) throws -> Decoder {
        let d = (try? nestedContainer(keyedBy: _AnyKey.self, forKey: key))
            .map { _ in dict } ?? [:]
        let sub = dict[key.stringValue] as? [String: Any] ?? [:]
        return _DictDecoder(storage: .keyed(sub), codingPath: codingPath + [key])
    }

    // ── 内部工具 ─────────────────────────────────────────────────────────────

    /// 取原始值；key 不存在时抛出 keyNotFound
    @discardableResult
    private func _raw(_ key: K) throws -> Any {
        guard let v = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
                debugDescription: "Key '\(key.stringValue)' not found"))
        }
        return v
    }

    /// Optional 字段安全解码：key 不存在/nil → nil；类型不匹配 → 日志 + nil
    private func _safeOptional<T>(_ key: K, decode: () throws -> T) -> T? {
        guard let raw = dict[key.stringValue], !VHLSQLiteTool.valueIsNil(raw) else { return nil }
        do { return try decode() }
        catch {
            VHLSQLitePrint("VHLDictionaryDecoder ⚠️ key='\(key.stringValue)' \(error.localizedDescription)")
            return nil
        }
    }

    /// 泛型解码分派（Date / Data / 数组 / 字典 / 嵌套 Decodable）
    private func _decodeValue<T: Decodable>(_ type: T.Type, from raw: Any, key: CodingKey) throws -> T {
        if type == Date.self { return try _coerceDate(raw, key: key) as! T }
        if type == Data.self { return try _coerceData(raw, key: key) as! T }

        // 数组 JSON 字符串
        if let str = raw as? String, let arr = _parseJSONArray(str) {
            return try T(from: _DictDecoder(storage: .unkeyed(arr), codingPath: codingPath + [key]))
        }
        // 字典 JSON 字符串
        if let str = raw as? String, let dict = _parseJSONDict(str) {
            return try T(from: _DictDecoder(storage: .keyed(dict), codingPath: codingPath + [key]))
        }
        // 已解析数组
        if let arr = raw as? [Any] {
            return try T(from: _DictDecoder(storage: .unkeyed(arr), codingPath: codingPath + [key]))
        }
        // 已解析字典
        if let d = raw as? [String: Any] {
            return try T(from: _DictDecoder(storage: .keyed(d), codingPath: codingPath + [key]))
        }
        // 单值（枚举 RawRepresentable、自定义 Codable 等）
        return try T(from: _DictDecoder(storage: .single(raw), codingPath: codingPath + [key]))
    }
}

// MARK: - UnkeyedDecodingContainer

private struct _UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [Any]
    var codingPath: [CodingKey]
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    private(set) var currentIndex: Int = 0

    private mutating func _next() throws -> Any {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self,
                .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end"))
        }
        let v = array[currentIndex]; currentIndex += 1; return v
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return true }
        if VHLSQLiteTool.valueIsNil(array[currentIndex]) { currentIndex += 1; return true }
        return false
    }

    mutating func decode(_ type: Bool.Type)   throws -> Bool   { let v = try _next(); return try _coerceBool(v, key: _idxKey(currentIndex - 1)) }
    mutating func decode(_ type: String.Type) throws -> String { let v = try _next(); return try _coerceString(v, key: _idxKey(currentIndex - 1)) }
    mutating func decode(_ type: Double.Type) throws -> Double { let v = try _next(); return try _coerceDouble(v, key: _idxKey(currentIndex - 1)) }
    mutating func decode(_ type: Float.Type)  throws -> Float  { let v = try _next(); return Float(try _coerceDouble(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: Int.Type)    throws -> Int    { let v = try _next(); return try _coerceInt(v, key: _idxKey(currentIndex - 1)) }
    mutating func decode(_ type: Int8.Type)   throws -> Int8   { let v = try _next(); return Int8(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: Int16.Type)  throws -> Int16  { let v = try _next(); return Int16(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: Int32.Type)  throws -> Int32  { let v = try _next(); return Int32(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: Int64.Type)  throws -> Int64  { let v = try _next(); return Int64(try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: UInt.Type)   throws -> UInt   { let v = try _next(); return UInt(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: UInt8.Type)  throws -> UInt8  { let v = try _next(); return UInt8(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { let v = try _next(); return UInt16(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { let v = try _next(); return UInt32(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { let v = try _next(); return UInt64(clamping: try _coerceInt(v, key: _idxKey(currentIndex - 1))) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let v = try _next()
        let key = _idxKey(currentIndex - 1)
        if type == Date.self { return try _coerceDate(v, key: key) as! T }
        if type == Data.self { return try _coerceData(v, key: key) as! T }
        return try T(from: _DictDecoder(storage: .single(v), codingPath: codingPath + [key]))
    }

    mutating func nestedContainer<NK: CodingKey>(keyedBy type: NK.Type) throws -> KeyedDecodingContainer<NK> {
        let v = try _next()
        guard let d = v as? [String: Any] else {
            throw _typeMismatch([String: Any].self, "Expected dict in array at index \(currentIndex - 1)", codingPath)
        }
        return KeyedDecodingContainer(_KeyedContainer<NK>(dict: d, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let v = try _next()
        guard let a = v as? [Any] else {
            throw _typeMismatch([Any].self, "Expected array in array at index \(currentIndex - 1)", codingPath)
        }
        return _UnkeyedContainer(array: a, codingPath: codingPath)
    }

    mutating func superDecoder() throws -> Decoder {
        let v = try _next()
        return _DictDecoder(storage: .single(v), codingPath: codingPath)
    }
}

// MARK: - SingleValueDecodingContainer

private struct _SingleValueContainer: SingleValueDecodingContainer {
    let value: Any
    var codingPath: [CodingKey]

    func decodeNil() -> Bool { VHLSQLiteTool.valueIsNil(value) }
    func decode(_ type: Bool.Type)   throws -> Bool   { try _coerceBool(value, key: _idxKey(0)) }
    func decode(_ type: String.Type) throws -> String { try _coerceString(value, key: _idxKey(0)) }
    func decode(_ type: Double.Type) throws -> Double { try _coerceDouble(value, key: _idxKey(0)) }
    func decode(_ type: Float.Type)  throws -> Float  { Float(try _coerceDouble(value, key: _idxKey(0))) }
    func decode(_ type: Int.Type)    throws -> Int    { try _coerceInt(value, key: _idxKey(0)) }
    func decode(_ type: Int8.Type)   throws -> Int8   { Int8(clamping:  try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: Int16.Type)  throws -> Int16  { Int16(clamping: try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: Int32.Type)  throws -> Int32  { Int32(clamping: try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: Int64.Type)  throws -> Int64  { Int64(try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: UInt.Type)   throws -> UInt   { UInt(clamping:   try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { UInt8(clamping:  try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { UInt16(clamping: try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { UInt32(clamping: try _coerceInt(value, key: _idxKey(0))) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { UInt64(clamping: try _coerceInt(value, key: _idxKey(0))) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Date.self { return try _coerceDate(value, key: _idxKey(0)) as! T }
        if type == Data.self { return try _coerceData(value, key: _idxKey(0)) as! T }
        if let v = value as? T { return v }
        // RawRepresentable（如 String-backed enum）
        return try T(from: _DictDecoder(storage: .single(value), codingPath: codingPath))
    }
}

// MARK: - 类型转换工具（文件私有）

private func _coerceBool(_ v: Any, key: CodingKey) throws -> Bool {
    if let b = v as? Bool   { return b }
    if let i = v as? Int    { return i != 0 }
    if let s = v as? String {
        let l = s.lowercased()
        if l == "1" || l == "true"  { return true }
        if l == "0" || l == "false" { return false }
    }
    throw _typeMismatch(Bool.self, "Cannot coerce \(type(of: v)) '\(v)' to Bool", [key])
}

private func _coerceString(_ v: Any, key: CodingKey) throws -> String {
    if let s = v as? String { return s }
    if let i = v as? Int    { return String(i) }
    if let d = v as? Double { return String(d) }
    if let b = v as? Bool   { return b ? "1" : "0" }
    throw _typeMismatch(String.self, "Cannot coerce \(type(of: v)) to String", [key])
}

private func _coerceInt(_ v: Any, key: CodingKey) throws -> Int {
    if let i = v as? Int    { return i }
    if let d = v as? Double { return Int(d) }
    if let b = v as? Bool   { return b ? 1 : 0 }
    if let s = v as? String, let i = Int(s)    { return i }
    if let s = v as? String, let d = Double(s) { return Int(d) }
    throw _typeMismatch(Int.self, "Cannot coerce \(type(of: v)) '\(v)' to Int", [key])
}

private func _coerceDouble(_ v: Any, key: CodingKey) throws -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int    { return Double(i) }
    if let b = v as? Bool   { return b ? 1.0 : 0.0 }
    if let s = v as? String, let d = Double(s) { return d }
    throw _typeMismatch(Double.self, "Cannot coerce \(type(of: v)) to Double", [key])
}

private func _coerceDate(_ v: Any, key: CodingKey) throws -> Date {
    if let d = v as? Date   { return d }
    if let s = v as? String,
       let d = VHLSQLiteTool.dateFormatter.date(from: s)
            ?? VHLSQLiteTool.legacyDateFormatter.date(from: s) { return d }
    if let ts = v as? Double { return Date(timeIntervalSince1970: ts) }
    if let ts = v as? Int    { return Date(timeIntervalSince1970: Double(ts)) }
    throw _typeMismatch(Date.self, "Cannot coerce \(type(of: v)) '\(v)' to Date", [key])
}

private func _coerceData(_ v: Any, key: CodingKey) throws -> Data {
    if let d = v as? Data   { return d }
    if let d = v as? NSData { return d as Data }
    if let s = v as? String, let d = Data(base64Encoded: s) { return d }
    throw _typeMismatch(Data.self, "Cannot coerce \(type(of: v)) to Data", [key])
}

// MARK: - JSON 工具

private func _parseJSONArray(_ s: String) -> [Any]? {
    guard s.hasPrefix("[") else { return nil }
    guard let data = s.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [Any]
}

private func _parseJSONDict(_ s: String) -> [String: Any]? {
    guard s.hasPrefix("{") else { return nil }
    guard let data = s.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

// MARK: - 错误 / Key 工具

private func _typeMismatch<T>(_ type: T.Type, _ msg: String, _ path: [CodingKey]) -> DecodingError {
    .typeMismatch(type, DecodingError.Context(codingPath: path, debugDescription: msg))
}

private struct _AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

private func _idxKey(_ i: Int) -> CodingKey { _AnyKey(intValue: i) }
