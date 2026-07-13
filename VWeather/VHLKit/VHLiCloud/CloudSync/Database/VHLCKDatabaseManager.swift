//
//  VHLCKDatabaseManager.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation
import CloudKit

protocol VHLCKDatabaseManager: AnyObject {
    var database: CKDatabase { get }
    var container: CKContainer { get }
    var syncObjects: [VHLCKSyncable] { get }
    
    var userDefaults: UserDefaults { get set }
    var canSync: Bool { get set }
    
    init(objects: [VHLCKSyncable], container: CKContainer, userDefaults: UserDefaults)
    
    func prepare()
    
    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?)
    
    /// The CloudKit Best Practice is out of date, now use this:
    /// https://developer.apple.com/documentation/cloudkit/ckoperation
    /// Which problem does this func solve? E.g.:
    /// 1.(Offline) You make a local change, involve a operation
    /// 2. App exits or ejected by user
    /// 3. Back to app again
    /// The operation resumes! All works like a magic!
    func resumeLongLivedOperationIfPossible()
    
    /// 注册自定义的 zones (record 容器)
    func createCustomZonesIfAllowed()
    /// 订阅
    func createDatabaseSubscriptionIfHaveNot()
    /// 监听远程修改
    func startObservingRemoteChanges()
    func startObservingTermination()
    func registerLocalDatabase()
    
    func cleanUp()
    
    func deleteAllZones(_ callback: ((Error?) -> Void)?)
    
    /// 取消所有待处理的同步：防抖定时器 + 正在进行的 CKFetch 操作
    /// 已入队的 push（long-lived）操作不会被取消，以免丢失本地写入
    func cancelPendingOperations()
    
    /// 钩子：各子类取消自己持有的 in-flight CKOperation，由 cancelPendingOperations 默认实现调用
    func cancelInFlightCKOperations()
}

extension VHLCKDatabaseManager {
    func prepare() {
        syncObjects.forEach({ syncObject in
            syncObject.pipeToEngine = { [weak self] (recordsToSave, recordIDsToDelete, onProgress, pushCompletion) in
                guard let self = self else {
                    pushCompletion?()
                    return
                }
                if !self.canSync {
                    pushCompletion?()
                    return
                }
                
                self.syncRecordsToCloudKit(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete, onProgress: onProgress) { error in
                    pushCompletion?()
                }
            }
        })
    }
    
    func resumeLongLivedOperationIfPossible() {
        container.fetchAllLongLivedOperationIDs { [weak self](operationIDs, error) in
            guard let self = self, error == nil, let iDs = operationIDs else { return }
            
            for id in iDs {
                self.container.fetchLongLivedOperation(withID: id) { [weak self](ope, error) in
                    guard let self = self, error == nil else { return }
                    if let modifyOp = ope as? CKModifyRecordsOperation {
                        modifyOp.modifyRecordsResultBlock = { result in
                            
                        }
                        
                        // The Apple's example code in doc(https://developer.apple.com/documentation/cloudkit/ckoperation/#1666033)
                        // tells we add operation in container. But however it crashes on iOS 15 beta versions.
                        // And the crash log tells us to "CKDatabaseOperations must be submitted to a CKDatabase".
                        // So I guess there must be something changed in the daemon. We temperorily add this availabilty check.
                        if #available(iOS 15, *) {
                            self.database.add(modifyOp)
                        } else {
                            self.container.add(modifyOp)
                        }
                    }
                }
            }
        }
    }
    
    /// 监听 iCloud 远程变化。可安全多次调用——会先移除旧 observer 再重新注册。
    func startObservingRemoteChanges() {
        // 先移除旧 observer，防止 repush() 重复调用 setup() 时注册多个 observer
        if let existing = remoteChangeObserverToken {
            NotificationCenter.default.removeObserver(existing)
        }
        remoteChangeObserverToken = NotificationCenter.default.addObserver(
            forName: .VHLiCloudRemoteDataDidChangeRemotely, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.scheduleDebouncedFetch()
        }
    }
}

// MARK: - 远程通知 Debounce
// protocol extension 无法直接定义存储属性，借助 associated object 保存 DispatchWorkItem 和 observer token

private var fetchDebounceWorkItemKey: UInt8 = 0
private var remoteChangeObserverTokenKey: UInt8 = 0
private var terminationObserverTokenKey: UInt8 = 0
private var onRemoteChangeDetectedKey: UInt8 = 0

extension VHLCKDatabaseManager {
    /// NC observer token，用于 startObservingRemoteChanges 防重复注册
    private var remoteChangeObserverToken: NSObjectProtocol? {
        get { objc_getAssociatedObject(self, &remoteChangeObserverTokenKey) as? NSObjectProtocol }
        set { objc_setAssociatedObject(self, &remoteChangeObserverTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// NC observer token，用于 startObservingTermination 防重复注册
    var terminationObserverToken: NSObjectProtocol? {
        get { objc_getAssociatedObject(self, &terminationObserverTokenKey) as? NSObjectProtocol }
        set { objc_setAssociatedObject(self, &terminationObserverTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// 远程变化回调，由 VHLCKSyncEngine 注入，走完整的 _isSyncing 检查
    var onRemoteChangeDetected: (() -> Void)? {
        get { objc_getAssociatedObject(self, &onRemoteChangeDetectedKey) as? (() -> Void) }
        set { objc_setAssociatedObject(self, &onRemoteChangeDetectedKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    fileprivate var fetchDebounceWorkItem: DispatchWorkItem? {
        get { objc_getAssociatedObject(self, &fetchDebounceWorkItemKey) as? DispatchWorkItem }
        set { objc_setAssociatedObject(self, &fetchDebounceWorkItemKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    // MARK: - 停止同步

    func cancelPendingOperations() {
        fetchDebounceWorkItem?.cancel()
        fetchDebounceWorkItem = nil
        cancelInFlightCKOperations()
    }

    /// 默认空实现；VHLCKPrivateDatabaseManager 重写以取消 in-flight CKFetchOperation
    func cancelInFlightCKOperations() { }

    /// 防抖：同一时间窗口内多条远程通知只触发一次，通过 onRemoteChangeDetected 走 _isSyncing 锁
    fileprivate func scheduleDebouncedFetch(delay: TimeInterval = 0.5) {
        fetchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let handler = self.onRemoteChangeDetected {
                handler()
            } else {
                // 未注入 handler 时的降级：直接拉取（兼容不经 engine 独立使用的场景）
                self.fetchChangesInDatabase(nil)
            }
        }
        fetchDebounceWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - ** 同步数据 *
extension VHLCKDatabaseManager {
    /// Sync local data to CloudKit . 推送本地变化数据到 CloudKit
    /// For more about the savePolicy: https://developer.apple.com/documentation/cloudkit/ckrecordsavepolicy
    public func syncRecordsToCloudKit(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID], onProgress: (() -> Void)? = nil, completion: ((Error?) -> ())? = nil) {
        if !self.canSync {
            completion?(nil)
            return
        }
        guard recordsToSave.count > 0 || recordIDsToDelete.count > 0 else {
            completion?(nil)
            return
        }
        
        // CloudKit 不允许同一个 CKRecord.ID 在 recordsToSave 中出现两次（返回 invalidArguments）。
        // 在提交前去重并记录日志，帮助排查上游数据问题（如 cloudKitSystemFields 与主键碰撞、
        // SQLite 主键为 nil 等），同时防止操作因此错误而整体失败。
        var seenSaveIDs = Set<CKRecord.ID>()
        let uniqueRecordsToSave = recordsToSave.filter { seenSaveIDs.insert($0.recordID).inserted }
        if uniqueRecordsToSave.count < recordsToSave.count {
            VHLCKLogger.log("syncRecordsToCloudKit: ⚠️ 发现 \(recordsToSave.count - uniqueRecordsToSave.count) 个重复 CKRecord.ID，已去重（原始数量=\(recordsToSave.count)）")
        }
        
        // 同样去重删除列表，避免重复删除同一个 recordID
        let uniqueRecordIDsToDelete = Array(Set(recordIDsToDelete))
        
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: uniqueRecordsToSave, recordIDsToDelete: uniqueRecordIDsToDelete)

        let config = CKOperation.Configuration()
        config.isLongLived = true
        config.timeoutIntervalForRequest = 60
//        config.qualityOfService = .userInitiated
        modifyOperation.configuration = config
        
        modifyOperation.savePolicy = .changedKeys
        modifyOperation.isAtomic = true
        
        // 推送成功后更新本地 cloudKitSystemFields，使增量推送逻辑能正确识别已同步状态
        modifyOperation.perRecordSaveBlock = { [weak self] (recordID, result) in
            guard let self = self else { return }
            if case .success(let savedRecord) = result,
               let syncObject = self.syncObjects.first(where: { $0.recordType == savedRecord.recordType }) {
                syncObject.recordWasSavedToCloudKit(savedRecord)
            }
            onProgress?()
        }
        
        // 删除
        modifyOperation.perRecordDeleteBlock = { (recordID, result) in
            onProgress?()
        }
        
        modifyOperation.modifyRecordsResultBlock = { [weak self] result in
            guard let self else {
                completion?(nil)
                return
            }
            switch result {
            case .success():
                DispatchQueue.main.async { completion?(nil) }
            case .failure(let error):
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .success:
                    DispatchQueue.main.async { completion?(nil) }
                case .recoverableError(let reason, _): //let message):
                    switch reason {
                        // 服务器记录版本与本地不一致，导致保存失败（serverRecordChanged / serverRejectedRequest / serverResponseLost）
                    case .serverRecordChanged:
                        // CKError.serverRecordChanged 携带了服务端最新 record（含正确的 changeTag）
                        // 和客户端尝试保存的 record（含本地 changedKeys）。
                        // 以服务端 record 为基础，将本地变更字段覆盖上去，再重试，
                        // 避免因 changeTag 过期导致本次推送静默丢失。
                        guard let ckError = error as? CKError,
                              let serverRecord = ckError.serverRecord,
                              let clientRecord = ckError.clientRecord else {
                            DispatchQueue.main.async { completion?(error) }
                            break
                        }
                        for key in clientRecord.changedKeys() {
                            serverRecord[key] = clientRecord[key]
                        }
                        let mergedRecords = recordsToSave.map { record -> CKRecord in
                            record.recordID == serverRecord.recordID ? serverRecord : record
                        }
                        self.syncRecordsToCloudKit(recordsToSave: mergedRecords, recordIDsToDelete: recordIDsToDelete, onProgress: onProgress, completion: completion)
                    default:
                        // 其他错误也要调用 completion，否则上层 DispatchGroup 永久阻塞
                        DispatchQueue.main.async { completion?(error) }
                    }
                case .retry(let timeToWait, _):
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                        self.syncRecordsToCloudKit(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete, onProgress: onProgress, completion: completion)
                    }
                case .chunk:
                    // 超过限制时分片：
                    // - 删除 ID 只放进第一片，避免 CloudKit 对重复删除操作报错
                    // - firstError 用 NSLock 保护，防止并发 completion handler 竞争写入
                    let chunks = recordsToSave.chunkItUp(by: 300)
                    let chunkGroup = DispatchGroup()
                    var firstError: Error? = nil
                    let errorLock = NSLock()
                    for (index, chunk) in chunks.enumerated() {
                        chunkGroup.enter()
                        let deleteIDs = index == 0 ? recordIDsToDelete : []
                        self.syncRecordsToCloudKit(recordsToSave: chunk, recordIDsToDelete: deleteIDs, onProgress: onProgress) { err in
                            if let err = err {
                                errorLock.lock()
                                if firstError == nil { firstError = err }
                                errorLock.unlock()
                            }
                            chunkGroup.leave()
                        }
                    }
                    chunkGroup.notify(queue: .global()) {
                        completion?(firstError)
                    }
                default:
                    // 其他错误也要调用 completion，否则上层 DispatchGroup 永久阻塞
                    DispatchQueue.main.async { completion?(error) }
                }
            }
        }
        
        database.add(modifyOperation)
    }
}
