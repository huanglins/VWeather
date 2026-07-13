//
//  VHLSQLitePropertyModel.swift
//  VideoEditor_Swift
//
//  Created by Vincent on 2020/5/25.
//  Copyright © 2020 Darnel Studio. All rights reserved.
//

import UIKit
import SQLite3

/** sqlite 数据库支持的类型 */
public enum VHLSQLiteType: String {
    case INTEGER = "INTEGER"    // 整形
    case REAL = "REAL"          // 浮点数类型
    case TEXT = "TEXT"          // 文本类型
    case BLOB = "BLOB"          // 数据类型
    case NULL = "NULL"          // 没有值
}
/// 查询排序
public enum VHLSQLiteOrderBy {
    case ASC(String)            // 升序排列
    case DESC(String)           // 降序排列
    
    var sql: String {
        switch self {
        case .ASC(let name):
            return "`\(name)` ASC"
        case .DESC(let name):
            return "`\(name)` DESC"
        }
    }
    
    var keyName: String {
        switch self {
        case .ASC(let name):
            return name
        case .DESC(let name):
            return name
        }
    }
}

/**
 保存单个属性的 Model
 */
public class VHLSQLiteProperty: NSObject {
    /// 类型
    public var type: Any.Type       // 属性的类型
    public var displayStyle: Mirror.DisplayStyle?
    
    public var key: String
    public var value: Any?
    
    /// 是否是主键
    public var isPrimaryKey: Bool = false
    /// 是否唯一键
    public var isUniqueKey: Bool = false
    /// 是否是索引
    public var isIndex: Bool = false
    
    public init(type: Any.Type, displayStyle: Mirror.DisplayStyle?,
                key: String, value: Any?,
                isPrimaryKey: Bool = false,
                isUniqueKey: Bool = false,
                isIndex: Bool = false) {
        self.type = type
        self.displayStyle = displayStyle
        
        self.key = key
        self.value = value
        
        self.isPrimaryKey = isPrimaryKey
        self.isUniqueKey = isUniqueKey
        self.isIndex = isIndex
    }
}

// MARK: - 扩展获取信息
extension VHLSQLiteProperty {
    /// sqlite 对应的类型
    public var sqlType: VHLSQLiteType {
        get {
            var sqlType: VHLSQLiteType = .NULL
            // 数字类型
            if type is Int.Type || type is Int?.Type {
                sqlType = .INTEGER
            }
            // Bool sqlite 没有单独的 Boolean
            else if type is Bool.Type || type is Bool?.Type {
                sqlType = .INTEGER
            }
            // 浮点数类型
            else if type is Float.Type || type is Float?.Type ||
                type is Double.Type || type is Double?.Type ||
                type is CGFloat.Type || type is CGFloat?.Type {
                sqlType = .REAL
            }
            else if type is NSNumber.Type || type is NSNumber?.Type {
                sqlType = .REAL
            }
            // 文本类型
            else if type is NSString.Type || type is NSString?.Type ||
                type is String.Type || type is String?.Type ||
                type is Character.Type || type is Character?.Type {
                sqlType = .TEXT
            }
            // data 类型
            else if type is Data.Type || type is Data?.Type {
                sqlType = .BLOB
            }
            // date 日期类型
            else if type is Date.Type || type is Date?.Type {
                sqlType = .TEXT
            }
            // 数组类型
            else if type is Array<String>.Type || type is Array<String>?.Type
                || (type is Array<NSString>.Type || type is Array<NSString>?.Type)
                || (type is Array<Int>.Type || type is Array<Int>?.Type)
                || (type is Array<Float>.Type || type is Array<Float>?.Type)
                || (type is Array<Double>.Type || type is Array<Double>?.Type)
                || (type is Array<Bool>.Type || type is Array<Bool>?.Type) {
                sqlType = .TEXT
            }
            // 字典类型
            else if type is Dictionary<String, String>.Type {
                sqlType = .TEXT
            }
            else {
                VHLSQLitePrint("VHLSQLite - SQL type 不支持的类型:", key, type)
                sqlType = .TEXT
            }
            
            return sqlType
        }
    }
    /// 存入数据库中的字段对应的值，数组字典等会被转换为字符串存入
    public var sqlValue: Any? {
        get {
            guard let value = value else { return nil }
            
            // 将 date 类型格式化存入数据库
            if (type is Date.Type || type is Date?.Type), let date = value as? Date {
                let dateString = VHLSQLiteTool.dateFormatter.string(from: date)
                return dateString as Any
            }
            
            // 值是否可以被 JSON 序列化，非值类型（int, bool）等
            if JSONSerialization.isValidJSONObject(value) {
                if let data = try? JSONSerialization.data(withJSONObject: value, options: []) {
                    return String(data: data, encoding: .utf8) ?? ""
                }
            }

            return value
        }
    }
}

// MARK: - 转换数据类型，避免 Codable 错误
public extension VHLSQLiteProperty {
    // 转换值类型，比如数据库查出来是 Int，但是现在数据已经被改为 String，Codable 会错误。
    // 属性为数组和字典类型，数据库存储的都是字符串类型
    func transformValueType(_ value: Any) -> Any {
        if type is Int.Type || type is Int?.Type {
            if let value = value as? String {
                return (Int(value) ?? nil) as Any
            }
        }
        
        // 字符串类型。但数据库之前存储是数值类型
        if type is NSString.Type || type is NSString?.Type ||
            type is String.Type || type is String?.Type ||
            type is Character.Type || type is Character?.Type {
            
            if let value = value as? Int {
                return String(value)
            } else if let value = value as? Float {
                return String(value)
            } else if let value = value as? Double {
                return String(value)
            }
        }
        
        // Bool 类型
        if type is Bool.Type || type is Bool?.Type {
            if let value = value as? Int {
                return value == 1
            } else if let value = value as? String {
                return value == "1"
            }
        }
        
        // 数组类型
        if type is Array<String>.Type || type is Array<String>?.Type
            || (type is Array<NSString>.Type || type is Array<NSString>?.Type)
            || (type is Array<Int>.Type || type is Array<Int>?.Type)
            || (type is Array<Float>.Type || type is Array<Float>?.Type)
            || (type is Array<Double>.Type || type is Array<Double>?.Type)
            || (type is Array<Bool>.Type || type is Array<Bool>?.Type){
            if let value = value as? String, let data = value.data(using: .utf8) {
                let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any]
                return object ?? []
            }
        }
        
        // 字典类型
        if type is Dictionary<String, String>.Type || type is Dictionary<String, String>?.Type
            || (type is Dictionary<String, Any>.Type || type is Dictionary<String, Any>?.Type)
            || (type is Dictionary<String, Int>.Type || type is Dictionary<String, Int>?.Type)
            || (type is Dictionary<String, Float>.Type || type is Dictionary<String, Float>?.Type)
            || (type is Dictionary<String, Double>.Type || type is Dictionary<String, Double>?.Type) {
            if let value = value as? String, let data = value.data(using: .utf8) {
                let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                return object ?? [:]
            }
        }
        
        // 自定义协议类型
        if type is VHLSQLiteValueProtocol.Type || type is VHLSQLiteValueProtocol?.Type {
            if let value = value as? VHLSQLiteValueProtocol {
                return value.objectValue() as Any
            }
        }
        
        // Date 类型：数据库以 TEXT 存储，将字符串统一转换为当前格式
        // 旧数据为秒精度（"yyyy-MM-dd HH:mm:ss"），新数据为毫秒精度（"yyyy-MM-dd HH:mm:ss.SSS"）
        if type is Date.Type || type is Date?.Type {
            if let str = value as? String {
                let date = VHLSQLiteTool.dateFormatter.date(from: str)
                    ?? VHLSQLiteTool.legacyDateFormatter.date(from: str)
                if let date = date {
                    return VHLSQLiteTool.dateFormatter.string(from: date)
                }
            }
        }
        
        return value
    }
}

// 数据库字段值的协议
protocol VHLSQLiteValueProtocol {
    func objectValue() -> Any?
}
