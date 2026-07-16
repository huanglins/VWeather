//
//  DBManager.swift
//  VWeather
//
//  SQLite 数据库管理器：配置数据库连接、建表、版本迁移。
//  数据库文件建在 App Group 容器下，便于将来小组件读取。
//

import Foundation

class DBManager {
    static let manager = DBManager()

    /// 数据库版本，**变更表字段后需 +1**，并在 handleDBUpgrade 中调用对应 model 的 migration
    /// v2: CityModel 主键由 pkid 改为 cityKey 并新增 iCloud 同步列
    let dbVersion: Int = 2
    private(set) var db: VHLSQLiteDataBase?

    private let lock = NSLock()

    let DB_GROUP = "group.cn.vincents.weather"
    let DBFolder = "VWeather"
    let DBName = "weather.sqlite"

    init() {
        configSharedDB()
    }

    func configSharedDB() {
        if db != nil { return }

        lock.lock()
        defer { lock.unlock() }

        if let database = createDB() {
            db = database
            VHLSQLiteDataBase.shared = database
            createTablesIfNeeded()
            handleDBUpgrade()
        } else {
            // createDB 失败（如 App Group 未配置、沙盒限制等），回退内存数据库，避免崩溃
            print("[DBManager] ⚠️ createDB 失败，回退到内存数据库，数据不会持久化")
            if let memDB = try? VHLSQLiteDataBase(location: .inMemory) {
                db = memDB
                VHLSQLiteDataBase.shared = memDB
                createTablesIfNeeded()
            }
        }
    }

    // MARK: 建表
    private func createTablesIfNeeded() {
        _ = try? CityModel().createTable()
        _ = try? CityWeatherSnapshot().createTable()
    }

    // MARK: 处理升级迁移
    func handleDBUpgrade() {
        guard let db = db else { return }

        let version = db.getVersion()
        print("[DBManager] 当前数据库版本:", version)

        if dbVersion > version {
            // v2：CityModel 主键从 pkid 改为 cityKey 属结构变更，
            // 直接使用 createTable 让 ORM 自动补齐新列（addColumnIfNoExist）。
            // 不再 dropTable + 重建，避免丢失数据。
            createTablesIfNeeded()
            _ = db.setVersion(dbVersion)
            print("[DBManager] 数据库升级到版本", dbVersion)
        }
    }
}

// MARK: - 数据库路径
extension DBManager {
    /// App Group 容器中的数据库地址（不可用时回退到 Documents/VWeather）
    private func dbURL() -> URL? {
        if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DB_GROUP) {
            return sharedURL.appendingPathComponent(DBName, isDirectory: false)
        }

        guard let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return nil
        }
        let dbDir = (documentPath as NSString).appendingPathComponent(DBFolder)
        if FileManager.default.fileExists(atPath: dbDir) == false {
            try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        }
        return URL(fileURLWithPath: (dbDir as NSString).appendingPathComponent(DBName))
    }

    func createDB() -> VHLSQLiteDataBase? {
        guard let dbURL = dbURL() else { return nil }
        guard let database = try? VHLSQLiteDataBase(path: dbURL.path) else { return nil }
        return database
    }
}
