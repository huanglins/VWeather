//
//  VHLSQLiteObject.swift
//  VideoEditor_Swift
//
//  Created by Vincent on 2020/5/25.
//  Copyright © 2020 Darnel Studio. All rights reserved.
//

import UIKit

/**
 使用教程
 1. model 继承自 VHLSQLiteObject
 2. 自定义实现 codable 协议
 */

/**
 Tips
 实现 Codable 协议，用于 json to model
 日期格式存储自动转为 yyyy-MM-dd HH:mm:ss.SSS 格式
 
 
 新加字段必须声明为可选性，避免无法对不存在的字段进行 Codable。最好所有字段都加上可选型
 
 数组只支持 [string]
 字典只支出 [string: string]
 
 */

// MARK: - 属性描述符缓存（类型级元数据，每个类型只反射一次）

/// 单个属性的类型级元数据；与实例值无关，可在同类型所有实例间共享。
private struct VHLPropertyDescriptor {
    let key: String
    let type: Any.Type
    let displayStyle: Mirror.DisplayStyle?
    let isPrimaryKey: Bool
    let isUniqueKey: Bool
    let isIndex: Bool
}

/// 线程安全的属性描述符缓存，按 ObjectIdentifier 索引。
private final class VHLPropertyDescriptorCache {
    static let shared = VHLPropertyDescriptorCache()
    private var cache: [ObjectIdentifier: [VHLPropertyDescriptor]] = [:]
    private let lock = NSLock()

    func descriptors(for typeID: ObjectIdentifier) -> [VHLPropertyDescriptor]? {
        lock.lock(); defer { lock.unlock() }
        return cache[typeID]
    }

    func store(_ descriptors: [VHLPropertyDescriptor], for typeID: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        cache[typeID] = descriptors
    }
}

/// 数据库存储 ORM 对象。
///
/// 遵循此协议的类型可通过反射自动完成表创建、字段映射、增删改查。
/// 所有属性建议声明为可选型，以兼容字段新增时的 Codable 解码。
///
/// **使用步骤：**
/// 1. 定义 model 遵循 `VHLSQLiteObject`（同时遵循 `Codable`）
/// 2. 实现无参 `init()`
/// 3. 声明 `var pkid: Int?`（自增主键）
/// 4. 直接调用 `save()` / `saveOrUpdate()` / `delete()` 等方法
public protocol VHLSQLiteObject: Codable {
    var pkid: Int? { get set }
    var tableName: String { get }
    
    // ** 协议必须实现 init 方法，用于通过类对象获取属性 **
    init()
    
    /// 主键字段名，默认 "pkid"
    func primaryKey() -> String
    
    /// 唯一约束字段；当 pkid 为空时用于定位记录
    func uniqueKeys() -> [String]?
    
    /// 索引字段
    func indexKeys() -> [String]?
    
    /// 不持久化的字段
    func ignoreKeys() -> [String]?
    
    /// 将数据库查询结果字典还原为对象
    static func encodeObject(with result: [String: Any]) throws -> Self?
}

public extension VHLSQLiteObject {
    /// 获取类名
    var tableName: String {
        get {
            return String(describing: type(of: self))
        }
    }
    
    /// 主键
    func primaryKey() -> String { return "pkid" }
    func uniqueKeys() -> [String]? { return nil }
    func indexKeys() -> [String]? { return nil }
    func ignoreKeys() -> [String]? { return ["tableName"] }
}

// MARK: - 获取对象属性
public extension VHLSQLiteObject {
    var colums: [String] { get { return getProperties().map { $0.key } } }

    // MARK: 通过反射获取对应的属性列表
    func getProperties() -> [VHLSQLiteProperty] {
        let typeID = ObjectIdentifier(type(of: self))

        // ── 类型级元数据（首次调用时反射并缓存，后续直接读缓存）──
        let descriptors: [VHLPropertyDescriptor]
        if let cached = VHLPropertyDescriptorCache.shared.descriptors(for: typeID) {
            descriptors = cached
        } else {
            descriptors = Self.buildPropertyDescriptors(from: self)
            VHLPropertyDescriptorCache.shared.store(descriptors, for: typeID)
        }
        guard !descriptors.isEmpty else { return [] }

        // ── 实例级数据（每次读取当前属性值，仍需一次外部 Mirror）──
        let mirror = Mirror(reflecting: self)
        guard let displayStyle = mirror.displayStyle,
              displayStyle == .class || displayStyle == .struct else { return [] }

        // 将所有 children（含父类）建立 key → value 索引，O(n) 一次遍历
        var valueByKey: [String: Any] = [:]
        var currentMirror: Mirror? = mirror
        while let m = currentMirror {
            for child in m.children {
                if let label = child.label { valueByKey[label] = child.value }
            }
            currentMirror = m.superclassMirror
        }

        // 按缓存描述符顺序构建 VHLSQLiteProperty，跳过内层 Mirror 和过滤逻辑
        return descriptors.compactMap { desc in
            guard let value = valueByKey[desc.key] else { return nil }
            return VHLSQLiteProperty(type: desc.type, displayStyle: desc.displayStyle,
                                     key: desc.key, value: value,
                                     isPrimaryKey: desc.isPrimaryKey,
                                     isUniqueKey: desc.isUniqueKey,
                                     isIndex: desc.isIndex)
        }
    }

    /// 首次调用时通过完整反射构建类型的属性描述符列表（每个类型只执行一次）。
    private static func buildPropertyDescriptors(from instance: VHLSQLiteObject) -> [VHLPropertyDescriptor] {
        let mirror = Mirror(reflecting: instance)
        guard let displayStyle = mirror.displayStyle,
              displayStyle == .class || displayStyle == .struct else {
            VHLSQLitePrint("VHLSQLite - 只支持 class 或者 struct 作为 Model")
            return []
        }

        // 收集所有 children（含继承链）
        var allChildren: [(label: String?, value: Any)] = []
        var currentMirror: Mirror? = mirror
        while let m = currentMirror {
            allChildren.append(contentsOf: m.children)
            currentMirror = m.superclassMirror
        }
        guard !allChildren.isEmpty else { return [] }

        // 预计算过滤集合（只在缓存构建时执行一次）
        var ignoreSet: Set<String> = ["tableName"]
        if let extra = instance.ignoreKeys() { ignoreSet.formUnion(extra) }
        let primaryKeyName = instance.primaryKey()
        let uniqueKeySet   = Set(instance.uniqueKeys() ?? [])
        let indexKeySet    = Set(instance.indexKeys()  ?? [])

        var descriptors: [VHLPropertyDescriptor] = []
        for child in allChildren {
            guard let name = child.label else { continue }
            if name.hasPrefix("$__lazy_storage_$_") || name.hasSuffix(".storage") { continue }
            if ignoreSet.contains(name) { continue }

            // 内层 Mirror：仅在首次构建描述符时执行（不再每次调用 getProperties 都执行）
            let vMirror = Mirror(reflecting: child.value)
            descriptors.append(VHLPropertyDescriptor(
                key: name,
                type: vMirror.subjectType,
                displayStyle: vMirror.displayStyle,
                isPrimaryKey: name == primaryKeyName,
                isUniqueKey:  uniqueKeySet.contains(name),
                isIndex:      indexKeySet.contains(name)
            ))
        }
        return descriptors
    }
    
    /// 获取属性字典
    func getPropertyMaps() -> [String: Any] {
        var parameters: [String: Any] = [:]
        let properties = getProperties()
        for property in properties {
            if VHLSQLiteTool.valueIsNil(property.value) { continue }
            
            parameters[property.key] = property.value
        }
        return parameters
    }
    
    /// 获取主键
    func primaryKeyProperty() -> VHLSQLiteProperty? {
        return getProperties().first(where: { $0.isPrimaryKey })
    }
    /// 查找属性
    func property(with name: String) -> VHLSQLiteProperty? {
        return getProperties().first(where: { $0.key == name })
    }
}

// MARK: - Codable 编解码
extension VHLSQLiteObject {
    static func encodeObject(with result: [String: Any]) throws -> Self? {
        let object = Self.init()
        let properties = object.getProperties()
        let colums = object.colums

        // 过滤仅保留模型字段，并通过 transformValueType 正规化基础类型
        var keyValues = result.filter { colums.contains($0.key) }
        for (key, value) in keyValues {
            if let property = properties.first(where: { $0.key == key }) {
                keyValues[key] = property.transformValueType(value)
            }
        }

        // 直接从字典解码，无需 JSONSerialization 往返序列化
        // VHLDictionaryDecoder 内部处理类型转换，Optional 字段不匹配时记录日志并跳过
        do {
            return try VHLDictionaryDecoder().decode(Self.self, from: keyValues)
        } catch {
            VHLSQLitePrint("VHLSQLite - 字典转对象错误: ", error)
            throw error
        }
    }
    
    static func encodeObjects(with results: [[String: Any]]) throws -> [Self] {
        var objects: [Self] = []
        
        for result in results {
            if let object = try Self.encodeObject(with: result) {
                objects.append(object)
            }
        }
        
        return objects
    }
}

// MARK: - 扩展 表操作 方法
public extension VHLSQLiteObject {
    // MARK: 表是否存在
    func isTableExists(_ db: VHLSQLiteDataBase = .shared) -> Bool {
        return db.tableExists(tableName: self.tableName)
    }
    
    // MARK: 当前对象是否存在
    func isExists(_ db: VHLSQLiteDataBase = .shared) -> Bool {
        return db.objectExists(self)
    }
    
    // MARK: 创建表
    @discardableResult
    func createTable(_ db: VHLSQLiteDataBase = .shared) throws -> Bool {
        guard self.tableName != "" else {
            VHLSQLitePrint("VHLSQLite - ", String(describing: type(of: self)), "表名不存在")
            return false
        }
        return try db.createTable(object: self)
    }
    
    // MARK: 清空表
    @discardableResult
    func cleanTable(_ db: VHLSQLiteDataBase = .shared) throws -> Bool {
        return try db.cleanTable(self.tableName)
    }
    
    // MARK: 删除表
    @discardableResult
    func dropTable(_ db: VHLSQLiteDataBase = .shared) throws -> Bool {
        return try db.dropTable(self.tableName)
    }
}

// MARK: - 扩展 增删改查 方法
public extension VHLSQLiteObject {
    /// 只保存（不检查是否已存在，减少一次 SELECT 查询）。
    /// - Returns: 插入行的 rowid（自增主键值），失败返回 0。
    @discardableResult
    mutating func save(_ db: VHLSQLiteDataBase = .shared) -> Int {
        let lastRowID = (try? db.save(self)) ?? 0
        if self.pkid == nil, lastRowID > 0 {
            self.pkid = lastRowID
            self.update(parameters: ["pkid": lastRowID])
        }
        
        return lastRowID
    }
    /// 更新当前对象对应的数据库记录。对象须已存在于数据库中（通过主键或唯一键定位）。
    /// - Returns: 更新成功返回 `true`，对象不存在或更新失败返回 `false`。
    @discardableResult
    func update(_ db: VHLSQLiteDataBase = .shared) -> Bool {
        return (try? db.update(self)) ?? false
    }
    
    /// 如果对象已存在则更新，否则插入。
    /// - Returns: 操作成功返回 `true`。
    @discardableResult
    mutating func saveOrUpdate(_ db: VHLSQLiteDataBase = .shared) -> Bool {
        return (try? db.saveOrUpdate(self)) ?? false
    }
    
    /// 从数据库中删除当前对象对应的记录。
    /// - Returns: 删除成功返回 `true`。
    @discardableResult
    func delete(_ db: VHLSQLiteDataBase = .shared) -> Bool {
        return (try? db.delete(self)) ?? false
    }
    
    // MARK: 修改指定属性
    /// 仅更新指定字段，通过主键或唯一键定位记录。
    /// - Parameters:
    ///   - parameters: 要更新的字段字典，key 为属性名。
    /// - Returns: 受影响的行数，失败或无匹配字段时返回 -1。
    @discardableResult
    func update(_ db: VHLSQLiteDataBase = .shared, parameters: [String: Any]) -> Int {
        let whereSQL = whereSelfSQL()
        let (sql, params) = updateSQLPrames(parameters: parameters, whereSQL: whereSQL)
        if sql.isEmpty { return -1 }

        _ = try? createTable(db)
        return (try? db.execute(sql, params: params)) ?? -1
    }
    
    @discardableResult
    func update(_ db: VHLSQLiteDataBase = .shared, propertyNames: [String]) -> Int {
        var parameters: [String: Any] = [:]
        let properties = getProperties()
        for property in properties {
            if !propertyNames.contains(property.key) { continue }
            if VHLSQLiteTool.valueIsNil(property.value) { continue }
            
            parameters[property.key] = property.value
        }
        if parameters.count <= 0 { return -1 }
        return update(parameters: parameters)
    }
}

// MARK: - 类对象操作 增删改查
public extension VHLSQLiteObject {
    /// 安全参数化查询。`whereSQL` 中用 `?` 占位，`params` 按位置绑定，防止 SQL 注入。
    static func objects(_ db: VHLSQLiteDataBase = .shared,
                        whereSQL: String = "",
                        params: [Any] = [],
                        order: VHLSQLiteOrderBy? = nil,
                        limit: Int = 0,
                        offset: Int = 0) -> [Self] {
        let object = Self.init()
        var sql = "SELECT * FROM \(object.tableName)"
        if !whereSQL.isEmpty { sql += " WHERE \(whereSQL)" }
        if let order = order, object.colums.contains(order.keyName) {
            sql += " ORDER BY \(order.sql)"
        }
        if limit > 0 { sql += " LIMIT \(limit) OFFSET \(offset)" }
        return objects(db, for: sql, params: params)
    }

    // MARK: 查询（原始 SQL 拼接，已废弃）
    // "直接拼接 SQL 字符串存在注入风险，请改用 objects(_:whereSQL:params:order:limit:offset:)"
    static func objects2(_ db: VHLSQLiteDataBase = .shared,
                        wheres: String = "",
                        order: VHLSQLiteOrderBy? = nil,
                        limit: Int = 0,
                        offset: Int = 0) -> [Self] {
        let object = Self.init()
        let tableName = object.tableName
        
        var sql = "SELECT * FROM \(tableName)"
        
        // WHERE
        if !wheres.isEmpty {
            sql += " WHERE \(wheres)"
        }
        
        // Order
        if let order = order {
            if object.colums.contains(order.keyName) {
                sql += " ORDER BY \(order.sql)"
            }
        }
        
        // Limit / Offset
        if limit > 0 {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        return objects(db, for: sql)
    }
    
    /// 查询。可以通过参数的形式指定查询条件
    static func objects(_ db: VHLSQLiteDataBase = .shared,
                        filter parameters: [String: Any],
                        order: VHLSQLiteOrderBy? = nil,
                        limit: Int = 0) -> [Self] {
        let object = Self.init()
        let tableName = object.tableName
        var sql = "SELECT * FROM \(tableName)"
        
        // WHERE
        let objectProperties = object.getProperties()
        let objectPropertyKeys = objectProperties.map({ $0.key })
        let parameters = parameters.filter({ objectPropertyKeys.contains($0.key) })

        var whereSQL = ""
        var params: [Any] = []
        var isFirst = true
        
        for parameter in parameters {
            let key = parameter.key
            let value = parameter.value
            
            if VHLSQLiteTool.valueIsNil(value) { continue }
            
            whereSQL += isFirst ? "`\(key)` = ?" : ", `\(key)` = ?"
            params.append(value as Any)

            isFirst = false
        }
        
        if params.count > 0 {
            sql += " WHERE \(whereSQL)"
        }
        
        // Order
        if let order = order {
            if object.colums.contains(order.keyName) {
                sql += " ORDER BY \(order.sql)"
            }
        }
        
        // Limit
        if limit > 0 {
            sql += " LIMIT 0, \(limit)"
        }
        
        return objects(db, for: sql, params: params)
    }
    
    static func objects(_ db: VHLSQLiteDataBase = .shared, for sql: String, params: [Any]? = nil) -> [Self] {
        let object = Self.init()
        
        _ = try? object.createTable(db)
        guard let results = try? db.query(sql, params: params) else { return [] }
        
        let objects = try? encodeObjects(with: results)
        return objects ?? []
    }
    
    /// 通过主键查找
    static func object(_ db: VHLSQLiteDataBase = .shared,
                       primaryKey: Any) -> Self? {
        let pk = Self().primaryKey()
        return objects(db, filter: [pk: primaryKey]).first
    }
    
    /// 修改指定属性
    static func update(_ db: VHLSQLiteDataBase = .shared, parameters: [String: Any], whereSQL: String) -> Int {
        let object = Self.init()
        let (sql, params) = object.updateSQLPrames(parameters: parameters, whereSQL: whereSQL)
        if sql.isEmpty { return -1 }
        
        do {
            let result = try db.execute(sql, params: params)
            return result
        } catch {
            VHLSQLitePrint("VHLSQLite - 修改失败", error.localizedDescription)
        }
        
        return -1
    }
    
    /// 根据条件删除
    @discardableResult
    static func delete(_ db: VHLSQLiteDataBase = .shared, whereSQL: String) -> Bool {
        let object = Self.init()
        let tableName = object.tableName
        var sql = "DELETE FROM \(tableName)"

        if !whereSQL.isEmpty {
            sql += (whereSQL.contains("WHERE") ? " " : " WHERE ") + whereSQL
        }
        return (try? db.execute(sql)) ?? 0 > 0
    }
    
    /// 获取插入数据的自增长主键ID
    static func maxPKID(_ db: VHLSQLiteDataBase = .shared) -> Int {
        let object = Self.init()
        let sql = "SELECT max(pkid) FROM \(object.tableName)"
        return (try? db.scalar(sql) as? Int) ?? -1
    }

    /// 统计满足条件的记录数（参数化安全版本）。比 `objects(whereSQL:params:).count` 更高效，不加载任何行数据。
    /// - Parameters:
    ///   - whereSQL: 可选 WHERE 子句（不含 "WHERE" 关键字），使用 `?` 占位，例如 `"isDeleted = ?"`
    ///   - params: 与 `whereSQL` 中 `?` 一一对应的绑定值
    static func count(_ db: VHLSQLiteDataBase = .shared, whereSQL: String = "", params: [Any] = []) -> Int {
        let tableName = Self.init().tableName
        var sql = "SELECT COUNT(*) FROM \(tableName)"
        if !whereSQL.isEmpty { sql += " WHERE \(whereSQL)" }
        return (try? db.scalar(sql, params: params) as? Int) ?? 0
    }

    // "直接拼接 SQL 字符串存在注入风险，请改用 count(_:whereSQL:params:)"
    static func count2(_ db: VHLSQLiteDataBase = .shared, wheres: String = "") -> Int {
        let tableName = Self.init().tableName
        var sql = "SELECT COUNT(*) FROM \(tableName)"
        if !wheres.isEmpty {
            sql += " WHERE \(wheres)"
        }
        return (try? db.scalar(sql) as? Int) ?? 0
    }
}

public extension Array where Element: VHLSQLiteObject {
    mutating func saveOrUpdate(_ db: VHLSQLiteDataBase = .shared) throws {
        try db.transaction {
            self = map({
                var object = $0
                _ = object.saveOrUpdate(db)
                return object
            })
        }
    }
}

// MARK: - 序列化
public extension VHLSQLiteObject {
    func toDict() throws -> [String: Any] {
        if !JSONSerialization.isValidJSONObject(self) { return [:] }
        
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError()
        }
        return dictionary
    }
    
    func toJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func copy() throws -> Self? {
        let data = try JSONEncoder().encode(self)
        let copy = try JSONDecoder().decode(Self.self, from: data)
        return copy
    }
}

// MARK: 扩展数组操作
public extension Array where Element: VHLSQLiteObject {
    func toDict() -> [String: Any] {
        if !JSONSerialization.isValidJSONObject(self) { return [:] }
        
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        guard let dictionary = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
    
    func toJson() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Equatable 相等
extension VHLSQLiteObject { // Equatable
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let lhsPKValue = lhs.primaryKeyProperty()?.value, let rhsPKValue = rhs.primaryKeyProperty()?.value else {
            return false
        }
        if let lhsPKValue = lhsPKValue as? Int, let rhsPKValue = rhsPKValue as? Int {
            return lhsPKValue == rhsPKValue
        }
        if let lhsPKValue = lhsPKValue as? String, let rhsPKValue = rhsPKValue as? String {
            return lhsPKValue == rhsPKValue
        }
        
        return lhs.pkid == rhs.pkid
    }
}
