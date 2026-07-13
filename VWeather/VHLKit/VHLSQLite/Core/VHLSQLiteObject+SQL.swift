//
//  VHLSQLiteObject+SQL.swift
//  VHLSqlite
//
//  Created by Vincent on 2021/6/7.
//

import Foundation

// MARK: - 表操作 SQL
extension VHLSQLiteObject {
    // MARK: 创建表的 sql 语句
    func createTableSQL() -> String {
        if tableName.isEmpty { return "" }
        
        var sql = "CREATE TABLE IF NOT EXISTS " + tableName
        
        let properties = getProperties()
        
        // 非主键字段
        let nonPrimaryProperties = properties.filter { $0.key != primaryKey() }
        let columsStr = nonPrimaryProperties.map { "'\($0.key)' \($0.sqlType)" }.joined(separator: ",")

        // 添加主键 + 非主键字段
        sql += "("
        if let primaryKeyProperty = primaryKeyProperty() {
            if primaryKeyProperty.sqlType == .INTEGER {
                sql += "'\(primaryKeyProperty.key)' INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE NOT NULL"
            } else {
                sql += "'\(primaryKeyProperty.key)' PRIMARY KEY UNIQUE NOT NULL"
            }
            if !columsStr.isEmpty { sql += "," }
        }
        sql += columsStr + ")"
        
        return sql
    }
    // MARK: 获取表信息的 sql 语句
    func tableInfoSQL() -> String {
        if tableName.isEmpty { return "" }
        
        // SELECT * FROM pragma_table_info(tableName)
        // PRAGMA table_info(tableName)
        return "PRAGMA table_info('\(tableName)')"
    }
    
    // MARK: 添加列的 sql
    func addColumnSQL(_ columnName: String, _ columnType: String) -> String {
        if tableName.isEmpty { return "" }
        return "ALTER TABLE " + tableName + " ADD COLUMN '\(columnName)' \(columnType)"
    }
}

// MARK: - 查询 SQL
extension VHLSQLiteObject {
    // MARK: 查询自己的条件 SQL，不带 WHERE
    func whereSelfSQL() -> String {
        var whereStr: String = ""
        
        let properties = getProperties()

        if let primary = properties.first(where: { $0.isPrimaryKey }) {
            if let value = primary.value, !VHLSQLiteTool.valueIsNil(value) {
                whereStr = "`\(primary.key)` = '\(value)'"
            }
        }
        
        if !whereStr.isEmpty { return whereStr }

        if let pk = pkid {                  // 主键
            whereStr = "pkid = \(pk)"
        } else if let uKeys = uniqueKeys(), uKeys.count > 0 {   // uniqueKey
            properties.filter({ uKeys.contains($0.key )}).forEach { (property) in
                let key = property.key
                let value = property.sqlValue
                
                if let value = value, !VHLSQLiteTool.valueIsNil(value) {
                    if whereStr.isEmpty {
                        whereStr += "`\(key)` = '\(value)'"
                    } else {
                        whereStr += " AND `\(key)` = '\(value)'"
                    }
                }
            }
        } else {
            for propertie in properties {
                let key = propertie.key
                let value = propertie.sqlValue
                
                if let value = value, !VHLSQLiteTool.valueIsNil(value) {
                    if whereStr.isEmpty {
                        whereStr += "`\(key)` = '\(value)'"
                    } else {
                        whereStr += " AND `\(key)` = '\(value)'"
                    }
                }
            }
        }
        
        return whereStr
    }
    
    // MARK: 查询该对象的条件 SQL (带参数)，不带 WHERE
    func whereSelfSQLParams() -> (whereSQL: String, params: [Any]) {
        var whereSQL = ""
        var params: [Any] = []
        
        let properties = getProperties()

        // 自定义主键
        if let primary = properties.first(where: { $0.isPrimaryKey }),
           let value = primary.value, !VHLSQLiteTool.valueIsNil(value) {
            whereSQL = "`\(primary.key)` = ?"
            params.append(value as Any)
        } else if let pk = pkid {                  // 主键
            whereSQL = "pkid = ?"
            params.append(pk as Any)
        } else if let uKeys = uniqueKeys(), uKeys.count > 0 {   // uniqueKey
            properties.filter({ uKeys.contains($0.key )}).forEach { (property) in
                let key = property.key
                let value = property.sqlValue
                
                if let value = value, !VHLSQLiteTool.valueIsNil(value) {
                    if whereSQL.isEmpty {
                        whereSQL += "`\(key)` = ?"
                    } else {
                        whereSQL += " AND `\(key)` = ?"
                    }
                    params.append(value as Any)
                }
            }
        } else {
            for property in properties {
                let key = property.key
                let value = property.sqlValue
                
                if let value = value, !VHLSQLiteTool.valueIsNil(value) {
                    if whereSQL.isEmpty {
                        whereSQL += "`\(key)` = ?"
                    } else {
                        whereSQL += " AND `\(key)` = ?"
                    }
                    params.append(value as Any)
                }
            }
        }
        
        return (whereSQL, params)
    }
    
    // MARK: 查询该对象的 SQL
    func selectSelfSQL() -> String {
        if tableName.isEmpty { return "" }

        let whereSQL = whereSelfSQL()
        let sql = "SELECT * FROM \(tableName) WHERE \(whereSQL)"

        return sql
    }
}

// MARK: - Upsert SQL
extension VHLSQLiteObject {
    /// 生成 `INSERT ... ON CONFLICT(pk) DO UPDATE SET ...` upsert 语句。
    ///
    /// 适用条件：对象拥有值不为 nil 的非 INTEGER 主键，或声明了 `uniqueKeys()`。
    /// 不满足条件（如纯自增 INTEGER 主键）时返回 `nil`，调用方应降级到 SELECT + INSERT/UPDATE。
    func upsertSQLParams() -> (sql: String, params: [Any])? {
        let properties = getProperties()

        // 确定 ON CONFLICT 目标列
        var conflictKeys: [String] = []
        if let primaryProp = properties.first(where: { $0.isPrimaryKey }),
           primaryProp.sqlType != .INTEGER,
           let value = primaryProp.value, !VHLSQLiteTool.valueIsNil(value) {
            conflictKeys = [primaryProp.key]
        } else if let uKeys = uniqueKeys(), !uKeys.isEmpty {
            let matched = properties.filter { uKeys.contains($0.key) && !VHLSQLiteTool.valueIsNil($0.value) }
            if matched.count == uKeys.count {
                conflictKeys = matched.map { $0.key }
            }
        }
        guard !conflictKeys.isEmpty else { return nil }

        var insertCols: [String] = []
        var placeholders: [String] = []
        var params: [Any] = []
        var updateClauses: [String] = []

        for property in properties {
            let key = property.key
            guard let value = property.sqlValue else { continue }

            insertCols.append("`\(key)`")
            placeholders.append("?")
            params.append(value)

            // 冲突列本身不参与 UPDATE（主键不变）
            if !conflictKeys.contains(key) {
                updateClauses.append("`\(key)` = excluded.`\(key)`")
            }
        }

        guard !insertCols.isEmpty, !updateClauses.isEmpty else { return nil }

        let conflictTarget = conflictKeys.map { "`\($0)`" }.joined(separator: ", ")
        let sql = "INSERT INTO \(tableName)(\(insertCols.joined(separator: ", "))) "
            + "VALUES (\(placeholders.joined(separator: ", "))) "
            + "ON CONFLICT(\(conflictTarget)) DO UPDATE SET \(updateClauses.joined(separator: ", "))"

        return (sql, params)
    }
}

// MAKR: - 保存或修改的 SQL
extension VHLSQLiteObject {
    // MARK: 带参数的插入或修改 SQL
    func saveOrUpdateSQLParams(isInsert: Bool = true) -> (sql: String, params: [Any]) {
        var sql = ""
        var params: [Any] = []
        
        if isInsert {
            sql = "INSERT INTO \(tableName)("
        } else {
            sql = "UPDATE \(tableName) SET "
        }
        
        var valuesStr = ""
        var isFirst = true
        
        let properties = getProperties()
        for property in properties {
            let key = property.key
            guard let value = property.sqlValue else {
                continue
            }
            
//            if property.isPrimaryKey { continue }
            
            if isInsert {
                sql += isFirst ? "`\(key)`" : ", `\(key)`"
                valuesStr += isFirst ? " VALUES (?" : ", ?"
            } else {
                sql += isFirst ? "`\(key)` = ?" : ", `\(key)` = ?"
            }
            params.append(value as Any)
            isFirst = false
        }
        
        //
        if isInsert {
            sql += ")" + valuesStr + ")"
        } else { // 查询修改的 where 语句
            let whereSQLParams = whereSelfSQLParams()
            if !whereSQLParams.whereSQL.isEmpty {
                sql += " WHERE \(whereSQLParams.whereSQL)"
                params.append(contentsOf: whereSQLParams.params)
            }
        }
        
        return (sql, params)
    }
}

// MARK: - 单个修改
extension VHLSQLiteObject {
    func updateSQLPrames(parameters: [String: Any], whereSQL: String) -> (sql: String, params: [Any]) {
        let objectProperties = getProperties().filter({ parameters.keys.contains($0.key) })
        if objectProperties.count <= 0 { return ("", []) }

        for objectProperty in objectProperties {
            objectProperty.value = parameters[objectProperty.key]
        }
        
        var sql = "UPDATE \(tableName) SET "
        var params: [Any] = []

        var isFirst = true
        
        for property in objectProperties {
            let key = property.key
            let value = property.sqlValue       // 不能直接使用 parameters 的 value
            
            if VHLSQLiteTool.valueIsNil(value) { continue }
            
            sql += isFirst ? "`\(key)` = ?" : ", `\(key)` = ?"
            params.append(value as Any)
            
            isFirst = false
        }
        
        // WHERE
        if !whereSQL.isEmpty {
            sql += (whereSQL.contains("WHERE") ? " " : " WHERE ") + whereSQL
        }

        return (sql, params)
    }
}
