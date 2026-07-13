//
//  VHLSQLiteDatabase.swift
//  VHLSqlite
//
//  Created by Vincent on 2021/6/8.
//

import Foundation
import SQLite3

let SQLITE_DATE = SQLITE_NULL + 1
private let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class VHLSQLiteDataBase: NSObject {
    // 数据库地址类型
    public enum Location: CustomStringConvertible {
        case inMemory
        case temporary
        case uri(String)
        
        public var description: String {
            switch self {
            case .inMemory:
                return ":memory:"
            case .temporary:
                return ""
            case .uri(let URI):
                return URI
            }
        }
    }
    private static var _shared: VHLSQLiteDataBase?
    private static let sharedLock = NSLock()
    public static var shared: VHLSQLiteDataBase {
        get {
            sharedLock.lock()
            defer { sharedLock.unlock() }
            
            if let shared = _shared { return shared }
        
            guard let path = VHLSQLiteTool.dbPath(with: .documentDirectory, direcotry: "VHL", fileName: "VHLSQLite.sqlite"),
                  let db = try? VHLSQLiteDataBase(path: path) else {
                // 路径初始化失败（如 Widget Extension），安全回退到内存数据库
                guard let memDB = try? VHLSQLiteDataBase(location: .inMemory) else {
                    assertionFailure("[VHLSQLite] 内存数据库初始化失败，请检查 SQLite 库是否可用")
                    return VHLSQLiteDataBase()
                }
                _shared = memDB
                return memDB
            }
            _shared = db
            return db
        }

        set { _shared = newValue }
    }
    
    /// sqlite 数据库连接句柄
    private(set) var db: OpaquePointer? = nil
    /// 数据库连接地址
    private(set) var dbLocation: Location? = nil
    
    // 操作队列
    var queue: DispatchQueue = DispatchQueue(label: "cn.vincents.sqlite", attributes: [])

    fileprivate static let queueKey = DispatchSpecificKey<Int>()
    fileprivate lazy var queueContext: Int = unsafeBitCast(self, to: Int.self)
    
    // MARK: 记录数据的 表名/表结构信息
    fileprivate var tableInfos: [String: [String]] = [:]
    /// 本次会话中已为哪些表创建过索引（`CREATE INDEX IF NOT EXISTS` 是幂等的，但避免每次操作都执行）
    fileprivate var indexedTables: Set<String> = []
    
    /// 写操作遇到 SQLITE_BUSY / SQLITE_LOCKED 时的最大重试次数（跨进程写竞争用）。
    /// 每次重试退避 `busyRetryInterval`，默认 20 次 × 50ms ≈ 1s。可从外部按需调整。
    public var maxWriteRetry: Int = 20
    /// 每次重试的退避间隔（微秒），默认 50ms。
    public var busyRetryInterval: useconds_t = 50_000
    
    deinit {
        // 断开连接
        if db != nil {
            sqlite3_close(db)
            db = nil
            sync { tableInfos = [:]; indexedTables = [] }
        }
    }
    private override init() {
        super.init()
    }
    
    public init(location: Location = .inMemory,
                readOnly: Bool = false,
                busyTimeout: Double = 5.0) throws {
        super.init()

        dbLocation = location
        let cPath = location.description.cString(using: .utf8)
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        // 构建数据库连接
        // SQLITE_OPEN_NOMUTEX      并发模式
        // SQLITE_OPEN_FULLMUTEX    串行模式  **
        // sqlite3_config(<#T##Int32...#>)
        let resultCode = sqlite3_open_v2(cPath!, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
        
        if resultCode != SQLITE_OK {
            let errorMessge = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            VHLSQLitePrint("VHLSQLite - 数据库连接错误", errorMessge)
            throw NSError(domain: "cn.vincents.sqlite.error", code: Int(resultCode), userInfo: ["messge": errorMessge])
        } else {
            VHLSQLitePrint("VHLSQLite - 数据库连接成功:", location.description)
        }
        /// 设置超时时间
        sqlite3_busy_timeout(db, Int32(busyTimeout * 1_000))
        
        // 标记当前线程队列
        queue.setSpecific(key: VHLSQLiteDataBase.queueKey, value: queueContext)
    }
    
    public convenience init(path: String,
                            readOnly: Bool = false,
                            busyTimeout: Double = 5.0) throws {
        try self.init(location: .uri(path), readOnly: readOnly)
    }
    public convenience init(direcotryBase: FileManager.SearchPathDirectory = .documentDirectory,
                            direcotry: String,
                            fileName: String,
                            readOnly: Bool = false,
                            busyTimeout: Double = 5.0) throws {
        /// 数据库路径
        guard let path = VHLSQLiteTool.dbPath(with: direcotryBase, direcotry: direcotry, fileName: fileName) else {
            throw NSError(domain: "cn.vincents.sqlite", code: -10, userInfo: ["messge": "数据库地址错误"])
        }
        try self.init(path: path, readOnly: readOnly, busyTimeout: busyTimeout)
    }
}

// MARK: 队列方法
extension VHLSQLiteDataBase {
    func sync<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: VHLSQLiteDataBase.queueKey) == queueContext {
            return try block()
        } else {
            return try queue.sync(execute: block)
        }
    }
}

// MARK: - 预处理 SQL 语句
fileprivate extension VHLSQLiteDataBase {
    // MARK: 预处理 SQL 语句
    private func prepare(_ sql: String, params: [Any]?) throws -> OpaquePointer? {
        guard let db = db else { return nil }
        
        var stmt: OpaquePointer?
        let cSQL = sql.cString(using: .utf8)
        
        // Prepare
        let result = sqlite3_prepare_v2(db, cSQL, -1, &stmt, nil)
        if result != SQLITE_OK {
            sqlite3_finalize(stmt)
            if let error = String(validatingUTF8: sqlite3_errmsg(self.db)) {
                let msg = "VHLSQLite - 无法预处理 SQL. SQL: \(sql), Error: \(error)"
                VHLSQLitePrint(msg)
                throw NSError(domain: "cn.vincents.sqlite", code: -101, userInfo: ["messge": msg])
            }
            return nil
        }
        // 绑定参数
        if let params = params, params.count > 0 {
            let cntParams = sqlite3_bind_parameter_count(stmt)
            let cnt = params.count
            // 如果 sql 中需要绑定的参数个数和数组中的个数不一致，那么直接返回错误
            if cntParams != CInt(cnt) {
                let msg = "VHLSQLite - 绑定参数个数不一致. SQL: \(sql), Parameters: \(params)"
                VHLSQLitePrint(msg)
                throw NSError(domain: "cn.vincents.sqlite", code: -102, userInfo: ["messge": msg])
            }
            
            var flag: CInt = 0
            for ndx in 1...cnt {
                let param = params[ndx - 1]
                // 整数类型：Int64 / Int 必须在 Bool 前，防止 NSNumber 整数被误判为 Bool
                if let value = param as? Int64 {
                    flag = sqlite3_bind_int64(stmt, CInt(ndx), sqlite3_int64(value))
                } else if let value = param as? Int {
                    // 兼容未经 AnyObject 桥接的原生 Swift Int
                    flag = sqlite3_bind_int64(stmt, CInt(ndx), Int64(value))
                } else if let value = param as? Bool {
                    flag = sqlite3_bind_int(stmt, CInt(ndx), value ? 1 : 0)
                // 浮点类型
                } else if let value = param as? Double {
                    flag = sqlite3_bind_double(stmt, CInt(ndx), value)
                } else if let value = param as? Float {
                    flag = sqlite3_bind_double(stmt, CInt(ndx), Double(value))
                // NSNumber 兜底：Int32 / Int16 / UInt 等经 AnyObject 桥接后落到此处
                } else if let value = param as? NSNumber {
                    flag = sqlite3_bind_int64(stmt, CInt(ndx), value.int64Value)
                // 文本
                } else if let string = param as? String {
                    flag = sqlite3_bind_text(stmt, CInt(ndx), string, -1, SQLITE_TRANSIENT)
                // 二进制：Swift Data 与 NSData toll-free bridged，as? NSData 一并处理
                } else if let data = param as? NSData {
                    flag = sqlite3_bind_blob(stmt, CInt(ndx), data.bytes, CInt(data.length), SQLITE_TRANSIENT)
                // 日期
                } else if let date = param as? Date {
                    let dateString = VHLSQLiteTool.dateFormatter.string(from: date)
                    flag = sqlite3_bind_text(stmt, CInt(ndx), dateString, -1, SQLITE_TRANSIENT)
                } else {
                    flag = sqlite3_bind_null(stmt, CInt(ndx))
                }
                
                if flag != SQLITE_OK {
                    sqlite3_finalize(stmt)
                    if let error = String(validatingUTF8: sqlite3_errmsg(self.db)) {
                        let msg = "VHLSQLite - 绑定错误 SQL: \(sql), Parameters: \(params), Index: \(ndx) Error: \(error)"
                        VHLSQLitePrint(msg)
                        throw NSError(domain: "cn.vincents.sqlite", code: -103, userInfo: ["messge": msg])
                    }
                    return nil
                }
            }
        }
        
        return stmt
    }
    
    // MARK: 执行 STMT
    private func execute(stmt: OpaquePointer, sql: String) throws -> Int {
        guard db != nil else { return -1 }

        defer { sqlite3_finalize(stmt) }

        // 执行 SQL。跨进程（主 App / Widget）共享同一个数据库文件时，
        // 写操作可能因锁竞争返回 SQLITE_BUSY / SQLITE_LOCKED。
        // busy_timeout 在「锁升级会死锁」等场景不会被调用，这里补一层显式重试，
        // 避免写入被静默丢弃（对应「小组件点完成要点两遍」问题）。
        var res = sqlite3_step(stmt)
        var retry = 0
        let maxRetry = max(0, maxWriteRetry)
        while (res == SQLITE_BUSY || res == SQLITE_LOCKED), retry < maxRetry {
            retry += 1
            NSLog("[LISTER-DB] 数据库繁忙(code=\(res))，第 \(retry)/\(maxRetry) 次重试. SQL: \(sql)")
            sqlite3_reset(stmt)             // 复位后可重新 step
            usleep(busyRetryInterval)       // 退避
            res = sqlite3_step(stmt)
        }
        if retry > 0 {
            if res == SQLITE_DONE || res == SQLITE_ROW || res == SQLITE_OK {
                NSLog("[LISTER-DB] 重试 \(retry) 次后写入成功. SQL: \(sql)")
            } else {
                let err = String(cString: sqlite3_errmsg(self.db))
                NSLog("[LISTER-DB] 重试 \(retry) 次后仍失败(code=\(res)): \(err). SQL: \(sql)")
            }
        }
        
        if res == SQLITE_ROW {
            let columnCount = sqlite3_column_count(stmt)
            if columnCount == 1 {
                let type = getColumnType(index: 0, stmt: stmt)
                if let value = getColumnValue(index: 0, type: type, stmt: stmt) as? Int {
                    return value
                }
            }
            
            VHLSQLitePrint("VHLSQLite - 这是一个查询，请使用 query 进行操作")
            return -1
        }
        if res != SQLITE_OK && res != SQLITE_DONE {
            if let error = String(validatingUTF8: sqlite3_errmsg(self.db)) {
                let msg = "VHLSQLite - failed to execute SQL: \(sql), Error: \(error)"
                VHLSQLitePrint(msg)
                NSLog("[LISTER-DB] 执行失败(code=\(res)): \(error). SQL: \(sql)")
                throw NSError(domain: "cn.vincents.sqlite", code: -201, userInfo: ["messge": error])
            }
            return -1
        }
        
        // Insert
        let upp = sql.uppercased()
        var result = 0
        if upp.hasPrefix("INSERT ") {       // 插入，返回最后一个插入的值
            let rid = sqlite3_last_insert_rowid(db)
            result = Int(rid)
        }
        // 修改或删除，返回受影响的行数
        else if upp.hasPrefix("DELETE") || upp.hasPrefix("UPDATE") {
            var cnt = sqlite3_changes(db)
            if cnt == 0 {
                cnt += 1
            }
            result = Int(cnt)
        } else {
            result = 1
        }
        
        return result
    }
    
    // MARK: 查询 STMT
    private func query(stmt: OpaquePointer, sql: String) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var fetchColumnInfo = true
        var columnCount: CInt = 0
        var columnNames: [String] = []
        var columnTypes: [CInt] = []
        
        var result = sqlite3_step(stmt)     // 执行 sql
        defer { sqlite3_finalize(stmt) }
        
        while result == SQLITE_ROW {
            // 获取表类型
            if fetchColumnInfo {
                columnCount = sqlite3_column_count(stmt)
                for index in 0..<columnCount {
                    let fallbackName = "column\(index)"
                    let name = sqlite3_column_name(stmt, index)
                        .flatMap { String(validatingUTF8: $0) } ?? fallbackName
                    columnNames.append(name)
                    columnTypes.append(getColumnType(index: index, stmt: stmt))
                }
                fetchColumnInfo = false
            }
            // 获取内容
            var row: [String: Any] = [:]
            for index in 0..<columnCount {
                let key = columnNames[Int(index)]
                let type = columnTypes[Int(index)]
                if let val = getColumnValue(index: index, type: type, stmt: stmt) {
                    row[key] = val
                }
            }
            
            rows.append(row)
            result = sqlite3_step(stmt)
        }

        if result != SQLITE_DONE, let error = String(validatingUTF8: sqlite3_errmsg(self.db)) {
            VHLSQLitePrint("VHLSQLite - failed to query SQL: \(sql), Error: \(error)")
        }
        
        return rows
    }
}

// MARK: - GET
fileprivate extension VHLSQLiteDataBase {
    // MARK: 获取字段类型
    func getColumnType(index: CInt, stmt: OpaquePointer) -> CInt {
        // Column types - http://www.sqlite.org/datatype3.html (section 2.2 table column 1)
        let blobTypes = ["BINARY", "BLOB", "VARBINARY"]
        let charTypes = ["CHAR", "CHARACTER", "CLOB", "NATIONAL VARYING CHARACTER", "NATIVE CHARACTER", "NCHAR", "NVARCHAR", "TEXT", "VARCHAR", "VARIANT", "VARYING CHARACTER"]
        let dateTypes = ["DATE", "DATETIME", "TIME", "TIMESTAMP"]
        let intTypes = ["BIGINT", "BIT", "BOOL", "BOOLEAN", "INT", "INT2", "INT8", "INTEGER", "MEDIUMINT", "SMALLINT", "TINYINT"]
        let nullTypes = ["NULL"]
        let realTypes = ["DECIMAL", "DOUBLE", "DOUBLE PRECISION", "FLOAT", "NUMERIC", "REAL"]
        
        guard let buf = sqlite3_column_decltype(stmt, index) else {
            return sqlite3_column_type(stmt, index)
        }
        var tmp = String(validatingUTF8: buf)?.uppercased() ?? ""
        if let pos = tmp.range(of: "(") {
            tmp = String(tmp[..<pos.lowerBound])
        }

        if intTypes.contains(tmp) { return SQLITE_INTEGER }
        if realTypes.contains(tmp) { return SQLITE_FLOAT }
        if charTypes.contains(tmp) { return SQLITE_TEXT }
        if blobTypes.contains(tmp) { return SQLITE_BLOB }
        if nullTypes.contains(tmp) { return SQLITE_NULL }
        if dateTypes.contains(tmp) { return SQLITE_DATE }
        
        return SQLITE_TEXT
    }
    
    // MARK: 获取字段的值
    func getColumnValue(index: CInt, type: CInt, stmt: OpaquePointer) -> Any? {
        // Integer
        if type == SQLITE_INTEGER {
            return Int(sqlite3_column_int64(stmt, index))
        }
        // Float
        if type == SQLITE_FLOAT {
            return Double(sqlite3_column_double(stmt, index))
        }
        // Blob
        if type == SQLITE_BLOB {
            let data = sqlite3_column_blob(stmt, index)
            let size = sqlite3_column_bytes(stmt, index)
            guard size > 0, let data else { return Data() }
            let value = NSData(bytes: data, length: Int(size))
            return value
        }
        // Date
        if type == SQLITE_DATE {
            // 文字类型的时间
            if let ptr = UnsafeRawPointer(sqlite3_column_text(stmt, index)) {
                let uptr = ptr.bindMemory(to: CChar.self, capacity: 0)
                if var txt = String(validatingUTF8: uptr) {
                    // 仅含日期（10位），补全时间部分
                    if txt.count == 10 {
                        txt += " 00:00:00.000"
                    }
                    // 优先用毫秒格式解析；旧数据（秒精度，19位）回退到旧格式
                    if let date = VHLSQLiteTool.dateFormatter.date(from: txt)
                        ?? VHLSQLiteTool.legacyDateFormatter.date(from: txt) {
                        return date
                    } else {
                        NSLog("VHLSQLite : String value: \(txt) but could not be converted to date!")
                    }
                }
            }
            // 如果是时间戳类型的时间
            let val = sqlite3_column_double(stmt, index)
            let db = Date(timeIntervalSince1970: val)
            return db
        }
        // Ohter
        if let ptr = UnsafeRawPointer(sqlite3_column_text(stmt, index)) {
            let uptr = ptr.bindMemory(to: CChar.self, capacity: 0)
            let txt = String(validatingUTF8: uptr)
            return txt
        }
        // Null
        if type == SQLITE_NULL {
            return nil
        }
        return nil
    }
}

// MARK: - 公开方法 执行 SQL
public extension VHLSQLiteDataBase {
    /// 执行 INSERT / UPDATE / DELETE 或 DDL 语句。
    /// - Parameters:
    ///   - sql: SQL 语句，支持 `?` 占位符。
    ///   - params: 与占位符一一对应的参数数组。
    /// - Returns: INSERT 返回最后一个 rowid；UPDATE/DELETE 返回受影响行数；其他返回 1。
    /// - Throws: SQL 语法错误或参数绑定错误时抛出。
    func execute(_ sql: String, params: [Any]? = nil) throws -> Int {
        var result = 0
        try sync {
            if let stmt = try self.prepare(sql, params: params) {
                result = try execute(stmt: stmt, sql: sql)
            }
        }
        
        return result
    }
    
    /// 执行 SELECT 查询，返回所有行。
    /// - Parameters:
    ///   - sql: SELECT 语句，支持 `?` 占位符。
    ///   - params: 与占位符一一对应的参数数组。
    /// - Returns: 结果行数组，每行为 `[列名: 值]` 字典。
    /// - Throws: SQL 语法错误或参数绑定错误时抛出。
    func query(_ sql: String, params: [Any]? = nil) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        try sync {
            if let stmt = try prepare(sql, params: params) {
                rows = self.query(stmt: stmt, sql: sql)
            }
        }
        return rows
    }
    
    /// 执行 SELECT 并返回第一行第一列的值，适合聚合查询（COUNT、MAX 等）。
    func scalar(_ sql: String, params: [Any]? = nil) throws -> Any? {
        let result = try query(sql, params: params)
        if result.count == 0 { return nil }
        
        return result[0].first?.value
    }
    
    /// 在事务中执行一组操作；任意步骤抛出异常时自动回滚。
    func transaction(_ block: () throws -> Void) throws {
        try sync {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            do {
                try block()
                sqlite3_exec(db, "COMMIT TRANSACTION;", nil, nil, nil)
            } catch {
                sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
                throw error
            }
        }
    }
}

// MARK: - 数据库版本
public extension VHLSQLiteDataBase {
    // MARK: 获取数据库版本
    func getVersion() -> Int {
        return (try? scalar("PRAGMA user_version") as? Int) ?? 0
    }
    
    // MARK: 设置数据库版本
    @discardableResult
    func setVersion(_ dbVersion: Int) -> Int {
        let sql = "PRAGMA user_version=\(dbVersion)"
        let result = try? execute(sql)
        return result ?? 0
    }
}

// ---------------------------------------------------------------------------------------
// MARK: - 数据库 / 表操作
public extension VHLSQLiteDataBase {
    /// 数据库 表是否存在
    func tableExists(tableName: String) -> Bool {
        let isExist = sync { tableInfos.keys.contains(tableName) }
        if isExist { return true }
        
        let sql = "SELECT EXISTS (SELECT * FROM sqlite_master WHERE type = 'table' AND name = ?) AS 'EXISTS'"
        // 查询返回结果为
        if let isExist = try? scalar(sql, params: [tableName]) as? Int, isExist == 1 {
            sync { tableInfos[tableName] = [] }
            return true
        }
        
        return false
    }
    
    /// 单个对象是否存在
    func objectExists(_ object: VHLSQLiteObject) -> Bool {
        let (whereSQL, params) = object.whereSelfSQLParams()
        guard !whereSQL.isEmpty else { return false }
        let sql = "SELECT 1 FROM \(object.tableName) WHERE \(whereSQL) LIMIT 1"
        guard let results = try? query(sql, params: params) else { return false }
        return results.count > 0
    }
}

public extension VHLSQLiteDataBase {
    /// 创建表
    @discardableResult
    func createTable(object: VHLSQLiteObject) throws -> Bool {
        let tableName = object.tableName
        if tableName == "" { return false }
        
        // 表是否存在
        var createResult = true
        if !tableExists(tableName: tableName) {
            let createTableSQL = object.createTableSQL()
            createResult = try execute(createTableSQL) > 0
            
            if createResult { sync { tableInfos[tableName] = [] } }
        }
        
        // 更新表字段
        for property in object.getProperties() {
            try addColumnIfNoExist(object, column: property)
        }

        // 创建索引（每个表每次会话只执行一次）
        let alreadyIndexed = sync { indexedTables.contains(tableName) }
        if !alreadyIndexed {
            try createIndexesIfNeeded(object: object)
            _ = sync { indexedTables.insert(tableName) }
        }

        return createResult
    }
    
    /// 清空表
    @discardableResult
    func cleanTable(_ tableName: String) throws -> Bool {
        let cleanSQL = "DELETE FROM \(tableName)"
        let result = try execute(cleanSQL) > 0
        return result
    }
    
    /// 删除表
    @discardableResult
    func dropTable(_ tableName: String) throws -> Bool {
        let dropSQL = "DROP TABLE IF EXISTS \(tableName)"
        let result = try execute(dropSQL)
        if result > 0 { sync { tableInfos[tableName] = nil } }
        return result > 0
    }
}

// MARK: - 字段操作
public extension VHLSQLiteDataBase {
    //MARK: 添加不存在的字段
    @discardableResult
    func addColumnIfNoExist(_ object: VHLSQLiteObject, column: VHLSQLiteProperty) throws -> Bool {
        // 字段已存在
        let tableName = object.tableName
        let columns = sync { tableInfos[tableName] } ?? []
        
        if let _ = columns.firstIndex(where: { (existColumn) -> Bool in
            return existColumn == column.key
        }) {
            return false
        }

        // 查询表信息
        let tableInfoSQL = object.tableInfoSQL()
        let existsColumnNames = try query(tableInfoSQL).map({ (dic:[String : Any]) -> String in
            (dic["name"] as? String) ?? ""
        })
        sync { tableInfos[tableName] = existsColumnNames }
        
        // 判断是否存在，不存在则添加
        if existsColumnNames.firstIndex(where: { (existColumn) -> Bool in
            return existColumn == column.key
        }) == nil {
            let addColumnSQL = object.addColumnSQL(column.key, column.sqlType.rawValue)
            return try execute(addColumnSQL) > 0
        }
        
        return false
    }

    /// 为 `indexKeys()` 声明的字段创建索引（`CREATE INDEX IF NOT EXISTS`，幂等）。
    func createIndexesIfNeeded(object: VHLSQLiteObject) throws {
        let indexProperties = object.getProperties().filter { $0.isIndex }
        for property in indexProperties {
            let sql = "CREATE INDEX IF NOT EXISTS " +
                      "idx_\(object.tableName)_\(property.key) " +
                      "ON \(object.tableName)(`\(property.key)`)"
            _ = try execute(sql)
        }

        // 为 `uniqueKeys()` 声明的字段创建复合唯一索引（`CREATE UNIQUE INDEX IF NOT EXISTS`，幂等），
        // 使 saveOrUpdate 的 `INSERT ... ON CONFLICT(uniqueKeys) DO UPDATE` upsert 有匹配的 UNIQUE 约束。
        if let uniqueKeys = object.uniqueKeys(), !uniqueKeys.isEmpty {
            let cols = uniqueKeys.map { "`\($0)`" }.joined(separator: ", ")
            let indexName = "uidx_\(object.tableName)_\(uniqueKeys.joined(separator: "_"))"
            let sql = "CREATE UNIQUE INDEX IF NOT EXISTS \(indexName) ON \(object.tableName)(\(cols))"
            _ = try execute(sql)
        }
    }
}

// MARK: - 增删改查
public extension VHLSQLiteDataBase {
    /// 保存
    func save(_ object: VHLSQLiteObject) throws -> Int {
        // 建表
        try createTable(object: object)
        
        let (sql, params) = object.saveOrUpdateSQLParams(isInsert: true)
        return try execute(sql, params: params)
    }
    
    /// 删除
    func delete(_ object: VHLSQLiteObject) throws -> Bool {
        let tableName = object.tableName
        var sql = "DELETE FROM \(tableName)"

        let (whereSQL, params) = object.whereSelfSQLParams()
        if !whereSQL.isEmpty {
            sql += " WHERE \(whereSQL)"
        }
        
        return try execute(sql, params: params) > 0
    }
    
    /// 修改
    func update(_ object: VHLSQLiteObject) throws -> Bool {
        // 建表
        try createTable(object: object)
        
        let isExists = objectExists(object)
        if !isExists { return false }
        
        let (sql, params) = object.saveOrUpdateSQLParams(isInsert: false)
        
        return try execute(sql, params: params) > 0
    }
    
    /// 保存修改
    func saveOrUpdate(_ object: VHLSQLiteObject) throws -> Bool {
        // 建表
        try createTable(object: object)

        // 优先走 upsert（0 SELECT），适用于有非 INTEGER 主键或 uniqueKeys 的模型
        if let (sql, params) = object.upsertSQLParams() {
            return try execute(sql, params: params) > 0
        }

        // 降级：1 SELECT + INSERT/UPDATE，适用于纯自增 INTEGER 主键模型
        let isExists = objectExists(object)
        let (sql, params) = object.saveOrUpdateSQLParams(isInsert: !isExists)
        return try execute(sql, params: params) > 0
    }
}

/**
 Tips：
 多线程多字典进行读写时，当多线程同时操作同一个 key 会发生野指针闪退  EXC_BAD_ACCESS
 修复方法为：
 1. 加锁。性能不高
 2. GCD 线程管理
 
 测试例子
 var tableInfos: [String: [String]] = [:]
 let queue = DispatchQueue(label: "cn.vincents.queue")
 for i in 0..<1000 {
     DispatchQueue.global().async {
         let a = ["\(i)"]
         queue.async {
             print(tableInfos.keys.contains("test"))
         }
         queue.async {
             tableInfos["test"] = a
         }
     }
 }
 */

/**
 
 数据迁移
 https://gitee.com/dhar/YTBaseDBManager
 
 SQLite 多线程
 https://blog.csdn.net/lijinqi1987/article/details/51781535
 https://www.jianshu.com/p/f036a947853b
 
 */
