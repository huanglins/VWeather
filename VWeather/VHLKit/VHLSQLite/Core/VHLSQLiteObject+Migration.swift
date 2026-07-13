//
//  VHLSQLiteObject+Migration.swift
//  Lister
//
//  Created by Vincent on 2023/8/8.
//

import Foundation

// MARK: - 数据迁移
// 将当前表备份，重新创建新表，再将表数据迁移过去
extension VHLSQLiteObject {
    static func migration(_ db: VHLSQLiteDataBase = .shared, handleData: (_ data: [String: Any]) -> [String: Any]) throws {
        try db.transaction {
            let object = Self.init()
            let tableName = object.tableName
            let bakTableName = tableName + "_bak"
            
            // 表是否存在
            if !object.isTableExists(db) {
                VHLSQLitePrint("VHLSQLite - 数据迁移，\(tableName) 表不存在")
                throw NSError(domain: "cn.vincents.sqlite.error", code: Int(-999), userInfo: ["messge": "表不存在"])
            }
            
            // 将当前表备份
            let bakSQL = "ALTER TABLE \(tableName) RENAME TO \(bakTableName)"
            let bakResult = try db.execute(bakSQL)
            VHLSQLitePrint("VHLSQLite - 备份表: \(tableName), 结果:", bakResult == 1 ? "成功" : "错误")
            
            // 删除表
            try object.dropTable(db)
            // 重新创建新表
            try object.createTable(db)
            
            // 查询旧表的数据并写入
            let selectBakSQL = "SELECT * FROM \(bakTableName)"
            let datas = try db.query(selectBakSQL)
            
            // 处理数据
            var objects: [Self] = []
            for data in datas {
                /// -- 这里可以自定义处理数据
                let data = handleData(data)
                
                if let object = try Self.encodeObject(with: data) {
                    objects.append(object)
                }
            }
            
            try objects.saveOrUpdate(db)
            VHLSQLitePrint("VHLSQLite - 迁移数据: \(tableName) 完成")
            
            // 删除临时表
            try db.dropTable(bakTableName)
        }
    }
}
