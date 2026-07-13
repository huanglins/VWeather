//
//  VHLSQLiteTool.swift
//  VideoEditor_Swift
//
//  Created by Vincent on 2020/5/25.
//  Copyright © 2020 Darnel Studio. All rights reserved.
//

import UIKit

public class VHLSQLiteTool: NSObject {
    #if DEBUG
    static var isDEBUG: Bool = true
    #else
    static var isDEBUG: Bool = false
    #endif
    
    /// 日期格式化对象（毫秒精度，避免重复创建）
    /// 格式：yyyy-MM-dd HH:mm:ss.SSS，精度 1ms，避免与 CloudKit 服务端时间戳比较时因秒级截断导致的推送漏检
    static var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    /// 旧格式解析器（秒精度），仅用于读取升级前写入的历史数据
    static let legacyDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    
    /// 构建数据库地址
    static func dbPath(with direcotryBase: FileManager.SearchPathDirectory = .documentDirectory,
                           direcotry: String, fileName: String) -> String? {
        guard let directoryPath = NSSearchPathForDirectoriesInDomains(direcotryBase, .userDomainMask, true).first else {
            return nil
        }
        let directoryPathNS = (directoryPath as NSString).appendingPathComponent(direcotry)
        checkAndCreateDirectory(directory: directoryPathNS)
        
        /// 去除空格 / 判断是否有文件后缀
        var fName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                
        let subffixs = ["sqlite3", "sqlite", "db"]
        if subffixs.first(where: { fName.lowercased().hasSuffix($0)}) == nil {
            fName += ".sqlite3"
        }
        
        let filePath = (directoryPathNS as NSString).appendingPathComponent(fName)
        return filePath
    }
    
    /// 检查并创建目录
    static func checkAndCreateDirectory(directory: String) {
        var isDirecotry : ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory, isDirectory:&isDirecotry) {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

// MARK: - 字符串处理
extension VHLSQLiteTool {
    /// 删除空格
    static func removeBlankSpace(_ name: String) -> String {
        var databaseName = name
        
        //包含空格的情况，去掉空格
        let blankSpaceStr = " "
        if name.contains(blankSpaceStr) {
            databaseName = databaseName.replacingOccurrences(of:blankSpaceStr, with:"")
        }
        
        return databaseName
    }
    
    /// 判断一个值是否为空（nil 或 NSNull）。
    /// - Note: 整数 `0`、布尔 `false`、空字符串均视为有效值，不会被判定为 nil。
    static func valueIsNil(_ value: Any?) -> Bool {
        guard let value = value else { return true }
        return value is NSNull
    }
}

// MARK: - base64
extension VHLSQLiteTool {
    static func base64String(with data: Data?) -> String? {
        return data?.base64EncodedString()
    }
    static func dataWith(base64String: String?) -> Data? {
        return Data(base64Encoded: base64String ?? "")
    }
}

func VHLSQLitePrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if !VHLSQLiteTool.isDEBUG { return }
    
    #if DEBUG
    print(items, separator: separator, terminator: terminator)
    #endif
}
