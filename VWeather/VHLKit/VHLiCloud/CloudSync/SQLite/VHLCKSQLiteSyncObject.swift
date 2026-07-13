//
//  VHLSQLiteSyncObject.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/6/4.
//

import Foundation
import CloudKit

public final class VHLCKSQLiteSyncObject<T> where T: VHLSQLiteObject & VHLCKRecordCodable {
    public var pipeToEngine: ((_ recordsToStore: [CKRecord], _ recordIDsToDelete: [CKRecord.ID], _ onProgress: (() -> Void)?, _ completion: (() -> Void)?) -> ())?
    
    public var db: VHLSQLiteDataBase = .shared
    public var userDefaults: UserDefaults = .standard
    
    /// 保护 zoneChangesToken 的串行队列，防止 CloudKit 回调并发读写竞态
    private let tokenQueue = DispatchQueue(label: "cn.vincents.icloud.syncobject.token")
    
    /**
     type: T.Type    传入用于确定 T(泛型的类型)
     */
    public init(type: T.Type,
                db: VHLSQLiteDataBase = .shared,
                userDefaults: UserDefaults = .standard) {
        self.db = db
        self.userDefaults = userDefaults
    }
}

// MARK: - 实现可同步协议
extension VHLCKSQLiteSyncObject: VHLCKSyncable {
    public var recordType: String { return T.recordType }
    public var zoneID: CKRecordZone.ID { return T.zoneID }
    
    public var zoneChangesToken: CKServerChangeToken? {
        get {
            tokenQueue.sync {
                let key = VHLCKKey.zoneChangesTokenKey.value + "." + T().tableName
                guard let tokenData = userDefaults.object(forKey: key) as? Data else { return nil }
                return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
            }
        }
        set {
            tokenQueue.sync {
                let key = VHLCKKey.zoneChangesTokenKey.value + "." + T().tableName
                guard let n = newValue else {
                    userDefaults.removeObject(forKey: key)
                    return
                }
                let data = try? NSKeyedArchiver.archivedData(withRootObject: n, requiringSecureCoding: false)
                userDefaults.set(data, forKey: key)
            }
        }
    }
    
    /// 自定义表空间是否已经创建
    public var isCustomZoneCreated: Bool {
        get {
            let key = VHLCKKey.hasCustomZoneCreatedKey.value + "." + T().tableName
            guard let flag = userDefaults.object(forKey: key) as? Bool else { return false }
            return flag
        }
        set {
            let key = VHLCKKey.hasCustomZoneCreatedKey.value + "." + T().tableName
            userDefaults.set(newValue, forKey: key)
        }
    }
    
    public func registerLocalDatabase() {
        
    }
    
    public func cleanUp() {
        // 使用 WHERE 子句直接删除已标记为软删除的记录，避免全量加载再过滤
        T.delete(self.db, whereSQL: "isDeleted = 1")
    }
    
    public func addOrUpdate(record: CKRecord) {
        guard var serverObject = T.decodeRecord(record) else {
            VHLCKLogger.log("addOrUpdate: 无法将 CloudKit record 转换为本地对象 (type=\(record.recordType))")
            return
        }

        // 提前将 cloudKitSystemFields 写入 serverObject。
        // 这样无论走哪条路径，serverObject 都已携带正确的 cloudKitSystemFields，
        // 无需在各分支重复编码；客户端胜出路径保留 localObject 的旧值即可。
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        serverObject.cloudKitSystemFields = archiver.encodedData

        let primaryKey = T.primaryKeyForRecordID(recordID: record.recordID) as Any
        guard let localObject = T.object(self.db, primaryKey: primaryKey) else {
            // ① 新记录：本地尚无此数据，直接写入。
            //    cloudKitSystemFields 已附加在 serverObject 上，避免被误判为"从未推送"的本地记录。
            serverObject.saveOrUpdate(self.db)
            return
        }

        // ② 本地已存在：由 resolveConflict 决定胜出方（可自定义合并策略）
        guard var resolved = T.resolveConflict(clientModel: localObject, serverModel: serverObject) else {
            return
        }

        // 通过比较 localModificationDate 判断胜出方：
        //   resolved 与 localObject 的 localModificationDate 相同 → 客户端版本胜出
        let clientWon = resolved.localModificationDate != nil
            && resolved.localModificationDate == localObject.localModificationDate

        if clientWon {
            // ③ 客户端版本胜出：写入合并后的本地版本。
            //    resolved 来自 localObject，保留旧 cloudKitSystemFields：
            //    cloudKitLastModifiedDate < localModificationDate，确保下次 push 仍能正确检测到本地改动。
            resolved.saveOrUpdate(self.db)
        } else {
            // ④ 服务端版本胜出：写入完整的服务端数据（含业务字段和 cloudKitSystemFields）。
            //    resolved 来自 serverObject，cloudKitSystemFields 已在方法开头更新，
            //    下次 push 时 cloudKitLastModifiedDate >= localModificationDate，不会重复推送。
            resolved.saveOrUpdate(self.db)
        }
    }
    
    public func delete(recordID: CKRecord.ID) {
        guard let object = T.object(self.db, primaryKey: recordID.recordName) else { return }
        // CloudKit 删除通知是服务端权威指令，直接删除本地记录
        object.delete(self.db)
    }
    
    public func pushLocalObjectsToCloudKit(onPrepare: ((Int) -> Void)? = nil,
                                            onProgress: (() -> Void)? = nil,
                                            completion: (() -> Void)? = nil) {
        let allObjects = T.objects(self.db, whereSQL: "")

        // 增量推送：仅推送真正需要同步的记录，避免每次全量推送造成 CloudKit 循环触发变更通知
        // 推送条件（满足其一即推送）：
        //   1. cloudKitSystemFields == nil：从未推送到 CloudKit 的新记录
        //   2. localModificationDate > cloudKitLastModifiedDate：本地修改时间晚于上次服务端同步时间
        let recordsToStore: [CKRecord] = allObjects
            .filter { !($0.isDeleted ?? false) }
            .filter { obj in
                guard let cloudKitDate = obj.cloudKitLastModifiedDate else {
                    // cloudKitSystemFields 为 nil → 从未推送 → 需要推送
                    return true
                }
                guard let localDate = obj.localModificationDate else {
                    // 已同步但没有本地修改时间追踪 → 不重复推送（model 未实现 localModificationDate）
                    return false
                }
                return localDate > cloudKitDate
            }
            .compactMap { $0.encodeRecord() }

        // 软删除记录 → 需要推送到 CloudKit 执行删除
        let recordsToDeleted = allObjects
            .filter { $0.isDeleted ?? false }
            .filter { $0.cloudKitSystemFields != nil }
            .compactMap { $0.encodeRecord() }
        
        let totalCount = recordsToStore.count + recordsToDeleted.count
        onPrepare?(totalCount)

        VHLCKLogger.log("pushLocalObjectsToCloudKit [\(T.recordType)]: toStore=\(recordsToStore.count)/\(allObjects.filter{!($0.isDeleted ?? false)}.count), toDelete=\(recordsToDeleted.count)")

        guard !recordsToStore.isEmpty || !recordsToDeleted.isEmpty else {
            completion?()
            return
        }

        self.pipeToEngine?(recordsToStore, recordsToDeleted.map { $0.recordID }, onProgress, completion)
    }
    
    public func recordWasSavedToCloudKit(_ record: CKRecord) {
        guard var object = T.object(self.db, primaryKey: T.primaryKeyForRecordID(recordID: record.recordID) as Any) else { return }
        
        // 若在此次 push 进行期间本地又产生了新的修改（localModificationDate > record.modificationDate），
        // 则不更新 cloudKitSystemFields。保留旧值可确保 pushLocalObjectsToCloudKit 的过滤器
        // 在下次同步时仍能正确检测到该记录需要再次推送（旧 changeTag 引发的 serverRecordChanged 由冲突合并逻辑重试）。
        if let localDate = object.localModificationDate,
           let serverDate = record.modificationDate,
           localDate > serverDate {
            return
        }
        
        // 推送成功且无新本地修改：仅更新 cloudKitSystemFields 单列，
        // 使下次 push 时 localModificationDate <= cloudKitLastModifiedDate，避免重复推送。
        // 使用 update(parameters:) 而非 saveOrUpdate，防止全字段 upsert 覆盖
        // 在加载与写入之间并发写入的 updateDate 等业务字段（TOCTOU）。
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        object.cloudKitSystemFields = archiver.encodedData
        object.update(self.db, parameters: ["cloudKitSystemFields": archiver.encodedData])
    }
    
    public func resolvePendingRelationships() {
        
    }
    
    public var localRecordCount: Int {
        // SELECT COUNT(*) 比加载所有对象再取 .count 高效得多
        T.count(self.db, whereSQL: "")
    }
}

extension VHLSQLiteObject {
    /// 获取主键的值
    static func primaryKeyForRecordID(recordID: CKRecord.ID) -> Any? {
        return recordID.recordName
    }
}

// https://github.com/FahimF/SQLiteDB
