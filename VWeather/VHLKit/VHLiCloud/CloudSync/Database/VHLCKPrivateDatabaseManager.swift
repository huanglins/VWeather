//
//  VHLCKPrivateDatabaseManager.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation

#if os(macOS)
import Cocoa
#else
import UIKit
#endif

import CloudKit

final class VHLCKPrivateDatabaseManager: VHLCKDatabaseManager {
    
    let container: CKContainer
    let database: CKDatabase
    
    let syncObjects: [VHLCKSyncable]

    var userDefaults: UserDefaults = .standard
    var canSync: Bool = true
    
    /// 保护 databaseChangeToken 的串行队列，防止 CloudKit 回调并发读写竞态
    private let tokenQueue = DispatchQueue(label: "cn.vincents.icloud.dbmanager.token")

    // MARK: - in-flight fetch 操作追踪（用于手动停止同步）
    // 只追踪 fetch 类操作（pull 流程）；push 操作（long-lived）不在此管理
    private let fetchOperationsLock = NSLock()
    private var _currentFetchDatabaseOperation: CKFetchDatabaseChangesOperation?
    private var _currentFetchZoneOperation: CKFetchRecordZoneChangesOperation?
    
    init(objects: [VHLCKSyncable],
         container: CKContainer,
         userDefaults: UserDefaults = .standard) {
        self.syncObjects = objects
        self.container = container
        self.database = container.privateCloudDatabase
        self.userDefaults = userDefaults
    }
    
    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?) {
        fetchChangesInDatabaseInternal(callback, retryCount: 0)
    }
    
    private func fetchChangesInDatabaseInternal(_ callback: ((Error?) -> Void)?, retryCount: Int) {
        VHLCKLogger.log("fetchChangesInDatabase start (retry=\(retryCount)), token=\(databaseChangeToken != nil ? "有" : "nil")")
        let changesOperation = CKFetchDatabaseChangesOperation(previousServerChangeToken: databaseChangeToken)
        changesOperation.fetchAllChanges = true
        
        // 设置超时，防止 CloudKit 操作无限挂起
        let config = CKOperation.Configuration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
//        config.qualityOfService = .userInitiated
        changesOperation.configuration = config

        fetchOperationsLock.lock()
        _currentFetchDatabaseOperation = changesOperation
        fetchOperationsLock.unlock()
        
        // Only update the changeToken when fetch process completes
        changesOperation.changeTokenUpdatedBlock = { [weak self](newToken) in
            self?.databaseChangeToken = newToken
        }
        
        changesOperation.fetchDatabaseChangesResultBlock = { [weak self] result in
            self?.fetchOperationsLock.lock()
            if self?._currentFetchDatabaseOperation === changesOperation {
                self?._currentFetchDatabaseOperation = nil
            }
            self?.fetchOperationsLock.unlock()

            guard let self else {
                VHLCKLogger.log("fetchDatabaseChangesResultBlock: self=nil, calling callback(nil)")
                // self 已释放，仍需保证 callback 触发，避免上层 pull() 永久阻塞
                callback?(nil)
                return
            }
            switch result {
            case .success((let serverChangeToken, let moreComing)):
                VHLCKLogger.log("fetchDatabaseChangesResultBlock success, moreComing=\(moreComing)")
                self.databaseChangeToken = serverChangeToken
                self.fetchChangesInZones(callback)
            case .failure(let error):
                VHLCKLogger.log("fetchDatabaseChangesResultBlock failure: \(error)")
                guard retryCount < 3 else {
                    VHLCKLogger.log("fetchDatabaseChangesResultBlock: 已达最大重试次数(\(retryCount))，放弃")
                    callback?(error)
                    return
                }
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .retry(let timeToWait, _):
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                        self.fetchChangesInDatabaseInternal(callback, retryCount: retryCount + 1)
                    }
                case .recoverableError(let reason, _):
                    switch reason {
                    case .changeTokenExpired:
                        /// The previousServerChangeToken value is too old and the client must re-sync from scratch
                        self.databaseChangeToken = nil
                        self.fetchChangesInDatabaseInternal(callback, retryCount: retryCount + 1)
                    case .userDeletedZone:
                        // 用户删除了整个数据库分区，触发自动恢复：重建 zone 并推送本地数据
                        self.recoverFromUserDeletedZone(callback)
                    default:
                        callback?(error)
                    }
                case .fail(_, _):
                    callback?(error)
                default:
                    callback?(error)
                }
            }
        }
        
        database.add(changesOperation)
    }
    
    /// 注册自定义的 zones
    func createCustomZonesIfAllowed() {
        let zonesToCreate = syncObjects.filter { !$0.isCustomZoneCreated }.map{ CKRecordZone(zoneID: $0.zoneID) }
        guard zonesToCreate.count > 0 else { return }
        
        let modifOperation = CKModifyRecordZonesOperation(recordZonesToSave: zonesToCreate, recordZoneIDsToDelete: nil)
        let zoneConfig = CKOperation.Configuration()
        zoneConfig.timeoutIntervalForRequest = 30
//        zoneConfig.qualityOfService = .userInitiated
        modifOperation.configuration = zoneConfig
        modifOperation.modifyRecordZonesResultBlock = { [weak self] result in
            guard let self else { return }
            
            switch result {
            case .success():
                self.syncObjects.forEach { object in
                    object.isCustomZoneCreated = true
                    
                    // As we register local database in the first step, we have to force push local objects which
                    // have not been caught to CloudKit to make data in sync
                    /// 第一次注册本地数据库时，必须强制 push 本地对象
                    DispatchQueue.main.async {
                        object.pushLocalObjectsToCloudKit(onPrepare: nil, onProgress: nil, completion: nil)
                    }
                }
            case .failure(let error):
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .retry(let timeToWait, _):
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                        self.createCustomZonesIfAllowed()
                    }
                default:
                    VHLCKLogger.log("createCustomZonesIfAllowed 失败（不可恢复）: \(error)")
                }
            }
        }
        
        database.add(modifOperation)
    }
    
    func createDatabaseSubscriptionIfHaveNot() {
        #if os(iOS) || os(tvOS) || os(macOS)
        guard !subscriptionIsLocallyCached else {
            return
        }
        let subscription = CKDatabaseSubscription(subscriptionID: VHLCKSubscription.cloudKitPrivateDatabaseSubscriptionID.id)
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push 静默推送
        subscription.notificationInfo = notificationInfo
        
        let createOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        createOperation.database = self.database
        createOperation.qualityOfService = .utility

        createOperation.modifySubscriptionsResultBlock = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success():
                self.subscriptionIsLocallyCached = true
                VHLCKLogger.log("createDatabaseSubscriptionIfHaveNot: 订阅创建成功")
            case .failure(let error):
                VHLCKLogger.log("createDatabaseSubscriptionIfHaveNot 失败: \(error)")
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .retry(let timeToWait, _):
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                        self.createDatabaseSubscriptionIfHaveNot()
                    }
                default:
                    // 非临时性失败（如权限不足），下次启动时重试（subscriptionIsLocallyCached 未置 true）
                    break
                }
            }
        }
        
        database.add(createOperation)
        #endif
    }
    
    func startObservingTermination() {
        // 先移除旧 observer，防止 repush() 重调 setup() 时重复注册，避免 cleanUp() 多次触发
        if let existing = terminationObserverToken {
            NotificationCenter.default.removeObserver(existing)
        }
        #if os(iOS) || os(tvOS)
        terminationObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.cleanUp() }
        #elseif os(macOS)
        terminationObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.cleanUp() }
        #endif
    }
    
    func registerLocalDatabase() {
        self.syncObjects.forEach { (object) in
            DispatchQueue.main.async {
                object.registerLocalDatabase()
            }
        }
    }
    
    @objc func cleanUp() {
        for syncObject in self.syncObjects {
            syncObject.cleanUp()
        }
    }
    
    // 清除所有 zones
    func deleteAllZones(_ callback: ((Error?) -> Void)?) {
        let group = DispatchGroup()
        var firstError: Error? = nil
        let errorLock = NSLock()
        
        for zoneId in zoneIds {
            group.enter()
            
            database.delete(withRecordZoneID: zoneId) { _, e in
                if let e {
                    errorLock.lock()
                    if firstError == nil { firstError = e }
                    errorLock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if firstError == nil {
                // 清除对象的同步缓存，重新获取
                self.syncObjects.forEach { object in
                    object.zoneChangesToken = nil
                    object.isCustomZoneCreated = false
                }
            }
            
            callback?(firstError)
        }
    }
}

extension VHLCKPrivateDatabaseManager {
    fileprivate func fetchChangesInZones(_ callback: ((Error?) -> Void)? = nil, retryCount: Int = 0) {
        // sync 已关闭：不拉取数据，但必须调用 callback 否则上层 pull() 的 completionHandler 永远不会被触发
        if !self.canSync {
            VHLCKLogger.log("fetchChangesInZones: canSync=false, skip")
            callback?(nil)
            return
        }

        let ids = zoneIds
        VHLCKLogger.log("fetchChangesInZones start (retry=\(retryCount)), zoneCount=\(ids.count), zones=\(ids.map(\.zoneName))")
        guard !ids.isEmpty else {
            VHLCKLogger.log("fetchChangesInZones: zoneIds 为空，无需拉取")
            callback?(nil)
            return
        }

        let changesOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: ids, configurationsByRecordZoneID: zoneIdConfigurations)
        changesOperation.fetchAllChanges = true
        
        // 设置超时，防止 CloudKit 操作无限挂起
        let config = CKOperation.Configuration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
//        config.qualityOfService = .userInitiated      // 不要设置优先级，可能导致线程反转回调永远不会执行
        changesOperation.configuration = config

        fetchOperationsLock.lock()
        _currentFetchZoneOperation = changesOperation
        fetchOperationsLock.unlock()

        // 原子计数器：统计本次 fetchChangesInZones 已处理的记录总数（更新+删除）
        let processedCount = VHLCKAtomicCounter()
        
        // 全量同步（所有 zone token 均为 nil）且本地有数据时，以本地记录数估算总量；
        // 增量同步或新设备首次同步（本地无数据）时无法预估，total = nil
        let isFullSync = syncObjects.allSatisfy { $0.zoneChangesToken == nil }
        let localTotal = syncObjects.reduce(0) { $0 + $1.localRecordCount }
        let estimatedTotal: Int? = isFullSync && localTotal > 0 ? localTotal : nil
        
        /// 增量更新时，CloudKit 会返回已修改的记录和删除的记录 ID；全量更新时，CloudKit 会返回所有记录，并且 recordWithIDWasDeletedBlock 不会被调用。
        changesOperation.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneId, token, _ in
            guard let self = self else { return }
            guard let syncObject = self.syncObjects.first(where: { $0.zoneID == zoneId }) else { return }
            syncObject.zoneChangesToken = token
        }
        /// 添加或者更新数据
        changesOperation.recordWasChangedBlock = { [weak self] (recordId, result) in
            guard let self = self else { return }
            
            if !self.canSync { return }
            
            switch result {
            case .success(let record):
                VHLCKLogger.log("recordWasChangedBlock: \(record.recordType) \(record.recordID.recordName)")
                if let syncObject = self.syncObjects.first(where: { $0.recordType == record.recordType }) {
                    syncObject.addOrUpdate(record: record)
                    let count = processedCount.increment()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .VHLiCloudSyncProgressNotification,
                            object: nil,
                            userInfo: [VHLiCloudSyncProgressKey: VHLCKSyncProgress(stage: .processingRecords(processed: count, total: estimatedTotal))]
                        )
                        NotificationCenter.default.post(
                            name: .VHLiCloudSyncDataChangedNotification,
                            object: nil,
                            userInfo: [
                                VHLiCloudSyncChangeRecordTypeKey: record.recordType,
                                VHLiCloudSyncChangeTypeKey: VHLiCloudSyncChangeType.addOrUpdate.rawValue
                            ]
                        )
                    }
                }
            case .failure(let error):
                VHLCKLogger.log("recordWasChangedBlock failure: \(error)")
                break
            }
        }
        /// 删除数据
        changesOperation.recordWithIDWasDeletedBlock = { [weak self] (recordId, recordType) in
            guard let self = self else { return }
            if !self.canSync { return }

            guard let syncObject = self.syncObjects.first(where: { $0.zoneID == recordId.zoneID}) else { return }
            syncObject.delete(recordID: recordId)
            let count = processedCount.increment()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .VHLiCloudSyncProgressNotification,
                    object: nil,
                    userInfo: [VHLiCloudSyncProgressKey: VHLCKSyncProgress(stage: .processingRecords(processed: count, total: estimatedTotal))]
                )
                NotificationCenter.default.post(
                    name: .VHLiCloudSyncDataChangedNotification,
                    object: nil,
                    userInfo: [
                        VHLiCloudSyncChangeRecordTypeKey: recordType,
                        VHLiCloudSyncChangeTypeKey: VHLiCloudSyncChangeType.delete.rawValue
                    ]
                )
            }
        }
        /// 获取完成回调（per-zone）
        // 注意：此 block 内 **不能** 调用 fetchChangesInZones(callback) 重试，否则和下方
        // fetchRecordZoneChangesResultBlock 发生竞争，导致 callback 被触发两次。
        // 所有重试逻辑统一由 fetchRecordZoneChangesResultBlock 处理。
        changesOperation.recordZoneFetchResultBlock = { [weak self] (zoneId, result) in
            guard let self = self else { return }
            switch result {
            case .success((let serverChangeToken, _, _)):
                guard let syncObject = self.syncObjects.first(where: { $0.zoneID == zoneId }) else {
                    VHLCKLogger.log("recordZoneFetchResultBlock: ⚠️ 未找到匹配 zone=\(zoneId.zoneName)/owner=\(zoneId.ownerName) 的 syncObject，token 未保存！syncObjects zones=\(self.syncObjects.map{ "\($0.zoneID.zoneName)/\($0.zoneID.ownerName)" })")
                    return
                }
                VHLCKLogger.log("recordZoneFetchResultBlock: zone=\(zoneId.zoneName), 保存新 token")
                syncObject.zoneChangesToken = serverChangeToken
                self.syncObjects.forEach { $0.resolvePendingRelationships() }
            case .failure(let error):
                VHLCKLogger.log("recordZoneFetchResultBlock failure zone=\(zoneId.zoneName): \(error)")
                // 仅在此清除本次 zone 对应的 token/flag，重试或恢复逻辑交给 fetchRecordZoneChangesResultBlock
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .recoverableError(let reason, _):
                    if let syncObject = self.syncObjects.first(where: { $0.zoneID == zoneId }) {
                        switch reason {
                        case .changeTokenExpired:
                            syncObject.zoneChangesToken = nil
                        case .userDeletedZone:
                            // zone 已被用户删除：清空该 zone 的所有本地状态，等待 resultBlock 统一恢复
                            syncObject.zoneChangesToken = nil
                            syncObject.isCustomZoneCreated = false
                        default:
                            break
                        }
                    }
                default:
                    break
                }
            }
        }
        changesOperation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            self?.fetchOperationsLock.lock()
            if self?._currentFetchZoneOperation === changesOperation {
                self?._currentFetchZoneOperation = nil
            }
            self?.fetchOperationsLock.unlock()

            guard let self = self else {
                VHLCKLogger.log("fetchRecordZoneChangesResultBlock: self=nil, calling callback(nil)")
                // self 已释放，仍需保证 callback 触发，避免上层 pull() 永久阻塞
                callback?(nil)
                return
            }

            switch result {
            case .success:
                VHLCKLogger.log("fetchRecordZoneChangesResultBlock success")
                self.syncObjects.forEach { $0.resolvePendingRelationships() }
                callback?(nil)
            case .failure(let error):
                VHLCKLogger.log("fetchRecordZoneChangesResultBlock failure: \(error)")
                guard retryCount < 3 else {
                    VHLCKLogger.log("fetchRecordZoneChangesResultBlock: 已达最大重试次数(\(retryCount))，放弃")
                    callback?(error)
                    return
                }
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .retry(let timeToWait, _):
                    // rate limit 等临时错误：延迟后整体重试
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) { [weak self] in
                        self?.fetchChangesInZones(callback, retryCount: retryCount + 1)
                    }
                case .recoverableError(let reason, _) where reason == .changeTokenExpired:
                    // token 过期：全部 zone token 已在 recordZoneFetchResultBlock 里清除，直接重试
                    self.fetchChangesInZones(callback, retryCount: retryCount + 1)
                case .recoverableError(let reason, _) where reason == .userDeletedZone:
                    // 用户删除了 zone：zone 状态已在 recordZoneFetchResultBlock 里清除，触发自动恢复
                    self.recoverFromUserDeletedZone(callback)
                default:
                    callback?(error)
                }
            }
        }
        
        VHLCKLogger.log("fetchChangesInZones: database.add(changesOperation)")
        database.add(changesOperation)
    }

    // MARK: - userDeletedZone 自动恢复

    func cancelInFlightCKOperations() {
        fetchOperationsLock.lock()
        let dbOp = _currentFetchDatabaseOperation
        let zoneOp = _currentFetchZoneOperation
        _currentFetchDatabaseOperation = nil
        _currentFetchZoneOperation = nil
        fetchOperationsLock.unlock()

        dbOp?.cancel()
        zoneOp?.cancel()
        VHLCKLogger.log("cancelInFlightCKOperations: 已取消 in-flight fetch 操作")
    }

    /// 用户在 iCloud 设置中删除了同步分区时的自动恢复流程：
    /// 1. 清空所有本地 zone token、isCustomZoneCreated 标志及数据库 changeToken
    /// 2. 调用 createCustomZonesIfAllowed() 重新创建分区；成功后框架会自动推送全量本地数据
    /// 3. 立即以"无错误"回调上层 pull()，不阻塞调用方（zone 重建与首次推送是后台异步操作）
    private func recoverFromUserDeletedZone(_ callback: ((Error?) -> Void)?) {
        VHLCKLogger.log("recoverFromUserDeletedZone: 用户删除了 iCloud zone，开始自动恢复")
        // 清空本地所有 zone 状态及数据库级别的 changeToken
        databaseChangeToken = nil
        syncObjects.forEach { object in
            object.zoneChangesToken = nil
            object.isCustomZoneCreated = false
        }
        // 异步重建 zone；createCustomZonesIfAllowed 内部成功后会调用 pushLocalObjectsToCloudKit
        createCustomZonesIfAllowed()
        // 本次 pull 以"成功"结束：zone 被删除意味着服务端无增量变更可拉取
        callback?(nil)
    }
}

// MARK: - get
extension VHLCKPrivateDatabaseManager {
    var databaseChangeToken: CKServerChangeToken? {
        get {
            tokenQueue.sync {
                guard let tokenData = userDefaults.object(forKey: VHLCKKey.databaseChangesTokenKey.value) as? Data else { return nil }
                return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
            }
        }
        set {
            tokenQueue.sync {
                guard let n = newValue else {
                    userDefaults.removeObject(forKey: VHLCKKey.databaseChangesTokenKey.value)
                    return
                }
                let data = try? NSKeyedArchiver.archivedData(withRootObject: n, requiringSecureCoding: false)
                userDefaults.setValue(data, forKey: VHLCKKey.databaseChangesTokenKey.value)
            }
        }
    }
    
    var subscriptionIsLocallyCached: Bool {
        get {
            guard let flag = userDefaults.object(forKey: VHLCKKey.subscriptionIsLocallyCachedKey.value) as? Bool else {
                return false
            }
            return flag
        }
        set {
            userDefaults.set(newValue, forKey: VHLCKKey.subscriptionIsLocallyCachedKey.value)
        }
    }
    
    /// 所有分区 zone id
    fileprivate var zoneIds: [CKRecordZone.ID] {
        return syncObjects.map { $0.zoneID }
    }
    
    @available(iOS 12.0, *)
    private var zoneIdConfigurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] {
        return syncObjects.reduce([CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration]()) { (dict, syncObject) -> [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] in
            var dict = dict
            let zoneConfiguration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let token = syncObject.zoneChangesToken
            // 日志追踪：记录实际传给 CloudKit 的 zone token，nil 表示会触发全量拉取
            VHLCKLogger.log("zoneIdConfigurations: zone=\(syncObject.zoneID.zoneName), token=\(token != nil ? "有 (增量)" : "nil (全量)")")
            zoneConfiguration.previousServerChangeToken = token
            dict[syncObject.zoneID] = zoneConfiguration
            return dict
        }
    }
}

// MARK: - 原子计数器（用于记录处理进度统计）
final class VHLCKAtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    /// 递增并返回递增后的值
    @discardableResult
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    /// 增加指定数量并返回新值
    @discardableResult
    func add(_ amount: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        value += amount
        return value
    }
    /// 当前值（只读快照）
    var currentValue: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
