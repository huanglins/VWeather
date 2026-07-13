//
//  VHLCKSyncEngline.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation
import CloudKit

// ** 另外同步的方案：sqlite-data / GRDB SyncEngine **

/// iCloud 上次同步完成的时间
public let VHLCKLastSyncDate = "VHLCKLastSyncDate"

extension Notification.Name {
    // 同步完成通知
    public static let VHLiCloundSyncCompletionNotification = NSNotification.Name(rawValue: "VHLICloundSyncCompletionNotification")
    // 实时数据变化通知（每条记录变化时触发）
    // userInfo keys: VHLiCloudSyncChangeRecordTypeKey, VHLiCloudSyncChangeTypeKey
    public static let VHLiCloudSyncDataChangedNotification = NSNotification.Name(rawValue: "VHLiCloudSyncDataChangedNotification")
    // 同步进度通知（同步过程中实时触发）
    // userInfo key: VHLiCloudSyncProgressKey，值为 VHLCKSyncProgress
    public static let VHLiCloudSyncProgressNotification = NSNotification.Name(rawValue: "VHLiCloudSyncProgressNotification")
}

/// 实时数据变化通知的 userInfo key：对应 CloudKit recordType 字符串（如 "FocusModel"）
public let VHLiCloudSyncChangeRecordTypeKey = "VHLiCloudSyncChangeRecordTypeKey"
/// 实时数据变化通知的 userInfo key：值为 VHLiCloudSyncChangeType 原始值
public let VHLiCloudSyncChangeTypeKey = "VHLiCloudSyncChangeTypeKey"

/// 同步进度通知的 userInfo key：值为 VHLCKSyncProgress 实例
public let VHLiCloudSyncProgressKey = "VHLiCloudSyncProgressKey"

public enum VHLiCloudSyncChangeType: String {
    case addOrUpdate
    case delete
}

/// 同步进度信息，通过 VHLiCloudSyncProgressNotification 实时回传
public struct VHLCKSyncProgress: Sendable {
    public enum Stage: Sendable {
        /// 正在拉取云端变更列表
        case fetchingChanges
        /// 正在处理拉取到的记录
        /// - processed: 已处理的累计记录数（实时递增）
        /// - total: 预估总数；全量同步时为本地记录数，增量同步或新设备首次同步时为 nil
        case processingRecords(processed: Int, total: Int?)
        /// 正在推送本地变更到 iCloud
        /// - processed: 已推送的累计记录数（实时递增）
        /// - total: 本次需推送的精确总数
        case pushingChanges(processed: Int, total: Int)
    }
    public let stage: Stage
    public init(stage: Stage) { self.stage = stage }
}

public final class VHLCKSyncEngine {
    private(set) var databaseManager: VHLCKDatabaseManager

    /// 是否开启同步框架日志输出，默认关闭
    public var isLoggingEnabled: Bool {
        get { VHLCKLogger.isEnabled }
        set { VHLCKLogger.isEnabled = newValue }
    }
    
    /// 设置是否可以同步
    var canSync: Bool = true {
        didSet {
            databaseManager.canSync = canSync
            if !canSync {
                endSyncing()
            } else if oldValue == false, !_hasSetup {
                // sync 从关闭变为开启，且 setup 尚未执行过，执行初始化（创建 zone、拉取数据）
                setup()
            }
        }
    }

    /// 标记 setup() 是否已执行，防止重复初始化（注册观察者、创建订阅等）
    fileprivate var _hasSetup = false

    // MARK: isSyncing 线程安全实现
    // 用 NSLock 保护底层 _isSyncing，对外暴露只读的 isSyncing；
    // 通过 tryBeginSyncing() 原子地完成"检查 + 置位"，避免 TOCTOU 竞态。
    private let syncLock = NSLock()
    private var _isSyncing: Bool = false

    /// 是否同步中（线程安全只读）
    private(set) var isSyncing: Bool {
        get {
            syncLock.lock(); defer { syncLock.unlock() }
            return _isSyncing
        }
        set {
            syncLock.lock(); defer { syncLock.unlock() }
            _isSyncing = newValue
        }
    }

    /// 原子地尝试进入同步状态。已在同步中则返回 false，否则标记并返回 true。
    private func tryBeginSyncing() -> Bool {
        syncLock.lock(); defer { syncLock.unlock() }
        guard !_isSyncing else { return false }
        _isSyncing = true
        return true
    }

    private func endSyncing() {
        syncLock.lock(); defer { syncLock.unlock() }
        _isSyncing = false
    }

    /// pull 最长等待时间，超时后强制结束并回调（避免 CloudKit 无回调时长期占用 isSyncing）
    let pullTimeoutSeconds: TimeInterval = 60 * 6

    /// 当前 iCloud 账户状态（由 ``refreshAccountStatus`` / ``setup`` 更新）
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    /// 上次同步时间
    var lastSyncDate: Date? {
        return userDefaults.value(forKey: VHLCKLastSyncDate) as? Date
    }
    var userDefaults: UserDefaults = .standard
    
    weak var delegate: VHLCKSyncEngineDelegate?
    
    public convenience init(objects: [VHLCKSyncable],
                            databaseScope: CKDatabase.Scope = .private,
                            container: CKContainer = .default(),
                            userDefaults: UserDefaults = .standard,
                            canSync: Bool = true) {
        switch databaseScope {
        case .private:
            let privateDatabaseManager = VHLCKPrivateDatabaseManager(objects: objects, container: container, userDefaults: userDefaults)
            privateDatabaseManager.canSync = canSync
            self.init(databaseManager: privateDatabaseManager, userDefaults: userDefaults, canSync: canSync)
        case .public:
            let publicDatabaseManager = VHLCKPublicDatabaseManager(objects: objects, container: container, userDefaults: userDefaults)
            publicDatabaseManager.canSync = canSync
            self.init(databaseManager: publicDatabaseManager, userDefaults: userDefaults, canSync: canSync)
        case .shared:
            let sharedDatabaseManager = VHLCKShareDatabaseManager(objects: objects, container: container, userDefaults: userDefaults)
            sharedDatabaseManager.canSync = canSync
            self.init(databaseManager: sharedDatabaseManager, userDefaults: userDefaults, canSync: canSync)
        default:
            fatalError("shared database scope is not suppoted yet")
        }
    }
    
    private init(databaseManager: VHLCKDatabaseManager,
                 userDefaults: UserDefaults = .standard,
                 canSync: Bool) {
        self.databaseManager = databaseManager
        self.userDefaults = userDefaults
        self.canSync = canSync
        // 仅在 sync 已开启时才执行初始化；若 sync 未开启，等到 canSync 变为 true 时再执行
        if canSync {
            setup()
        }
    }
    
    private func setup() {
        _hasSetup = true
        databaseManager.prepare()
        // 注入远程变化回调：远程通知触发时走 pull() 的 _isSyncing 锁，防止并发 fetch
        databaseManager.onRemoteChangeDetected = { [weak self] in
            self?.pull()
        }
        // 账号状态变更
        databaseManager.container.accountStatus { [weak self](status, error) in
            guard let self = self else { return }
            self.accountStatus = status
            switch status {
            case .available:
                self.databaseManager.registerLocalDatabase()
                self.databaseManager.createCustomZonesIfAllowed()
                // setup 不主动拉取数据，避免占用 _isSyncing 锁。
                // 数据拉取由 AppDelegate 的手动 sync() 以及 willEnterForeground 负责。
                self.databaseManager.resumeLongLivedOperationIfPossible()
                self.databaseManager.startObservingRemoteChanges()
                self.databaseManager.startObservingTermination()
                self.databaseManager.createDatabaseSubscriptionIfHaveNot()
            case .noAccount, .restricted:
                guard self.databaseManager is VHLCKPublicDatabaseManager else { break }
                
                self.databaseManager.resumeLongLivedOperationIfPossible()
                self.databaseManager.startObservingRemoteChanges()
                self.databaseManager.startObservingTermination()
                self.databaseManager.createDatabaseSubscriptionIfHaveNot()
            case .couldNotDetermine: break
            case .temporarilyUnavailable: break
            @unknown default: break
            }
            
            self.delegate?.handleEvent(.accountChange(status), syncEngine: self)
        }
    }
}

// MARK: - account status
extension VHLCKSyncEngine {
    /// 当前账户是否允许执行 pull（私有库需 `.available`；公共库在无账户时仍可拉公共数据）
    var allowsPull: Bool {
        switch accountStatus {
        case .available:
            return true
        case .noAccount, .restricted:
            return databaseManager is VHLCKPublicDatabaseManager
        case .couldNotDetermine, .temporarilyUnavailable:
            return false
        @unknown default:
            return false
        }
    }

    /// 查询 iCloud 账户状态并更新 ``accountStatus``。
    public func refreshAccountStatus(completionHandler: ((CKAccountStatus, Error?) -> Void)? = nil) {
        databaseManager.container.accountStatus { [weak self] status, error in
            self?.accountStatus = status
            completionHandler?(status, error)
        }
    }
}

// MARK: - public method
extension VHLCKSyncEngine {
    // MARK: 手动停止当前同步
    /// 手动停止当前进行中的同步。
    ///
    /// 调用后：
    /// - 取消防抖定时器，阻止尚未触发的远程变化拉取
    /// - 取消正在进行的 CKFetch 操作（pull 流程），触发其 completion block（携带 operationCancelled 错误）
    /// - `isSyncing` 会在被取消操作的 completion block 回调后自动重置为 false
    ///
    /// 已入队的 push（long-lived）操作不受影响，以确保本地写入不丢失。
    /// 停止后可正常调用 `sync()` / `pull()` 重新开始同步。
    public func stopSync() {
        VHLCKLogger.log("stopSync: 手动停止同步")
        databaseManager.cancelPendingOperations()
    }

    // MARK: 清空本地同步缓存，重新从 iCloud 拉取所有数据
    /// 清空本地同步缓存，重新从 iCloud 拉取所有数据
    public func repull(_ completionHandler: ((Error?) -> Void)? = nil) {
        // 使用 databaseManager 的 userDefaults（App Group）清除 databaseChangeToken
        databaseManager.userDefaults.removeObject(forKey: VHLCKKey.databaseChangesTokenKey.value)
        // 清除对象的同步缓存，重新获取
        databaseManager.syncObjects.forEach { object in
            object.zoneChangesToken = nil
        }
        pull(completionHandler: completionHandler)
    }
    
    /// 从 iCloud 拉取数据与本地合并
    public func pull(completionHandler: ((Error?) -> Void)? = nil) {
        guard canSync else {
            completionHandler?(NSError(domain: "cn.vincents.icloud.notSync", code: -11))
            return
        }

        refreshAccountStatus { [weak self] status, error in
            guard let self else {
                DispatchQueue.main.async { completionHandler?(error) }
                return
            }

            guard self.allowsPull else {
                VHLCKLogger.log("iCloud 账户不可用，跳过 pull：\(status.rawValue)")
                let accountError = error ?? NSError(
                    domain: "cn.vincents.icloud.accountUnavailable",
                    code: -12,
                    userInfo: [NSLocalizedDescriptionKey: "iCloud account unavailable"]
                )
                DispatchQueue.main.async { completionHandler?(accountError) }
                return
            }

            guard self.tryBeginSyncing() else {
                DispatchQueue.main.async {
                    completionHandler?(NSError(domain: "cn.vincents.icloud.syncing", code: -9))
                }
                return
            }

            self.performPull(completionHandler: completionHandler)
        }
    }

    private func performPull(completionHandler: ((Error?) -> Void)?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .VHLiCloudSyncProgressNotification,
                object: nil,
                userInfo: [VHLiCloudSyncProgressKey: VHLCKSyncProgress(stage: .fetchingChanges)]
            )
        }

        var timedOut = false
        DispatchQueue.main.asyncAfter(deadline: .now() + pullTimeoutSeconds) { [weak self] in
            guard let self, self.isSyncing, !timedOut else { return }
            timedOut = true
            self.endSyncing()
            VHLCKLogger.log("pull 同步超时 (\(self.pullTimeoutSeconds)s)，强制结束")
            NotificationCenter.default.post(name: .VHLiCloundSyncCompletionNotification, object: nil)
            completionHandler?(NSError(
                domain: "cn.vincents.icloud.syncTimeout",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Sync timed out"]
            ))
        }

        databaseManager.fetchChangesInDatabase { [weak self] error in
            guard !timedOut else { return }
            timedOut = true

            if let error {
                VHLCKLogger.log("pull 同步错误: \(error.localizedDescription)")
            } else {
                VHLCKLogger.log("pull 同步成功")
                self?.userDefaults.setValue(Date(), forKey: VHLCKLastSyncDate)
            }

            self?.endSyncing()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .VHLiCloundSyncCompletionNotification, object: nil)
                completionHandler?(error)
            }
        }
    }
    
    // MARK: 清空云端数据，重新将本地数据推送到云端
    /// 清空云端数据，重新将本地数据推送到云端
    public func repush(progressHandler: ((VHLCKSyncProgress) -> Void)? = nil, completion: ((Error?) -> Void)? = nil) {
        guard canSync else {
            completion?(NSError(domain: "VHLiCloud", code: -999, userInfo: [NSLocalizedDescriptionKey: "Sync not enabled"]))
            return
        }
        guard !isSyncing else {
            completion?(NSError(domain: "VHLiCloud", code: -2, userInfo: [NSLocalizedDescriptionKey: "isSyncing"]))
            return
        }
        
        // 使用 databaseManager 的 userDefaults，确保与 App Group 等自定义 UserDefaults 一致
        databaseManager.userDefaults.removeObject(forKey: VHLCKKey.databaseChangesTokenKey.value)
        
        databaseManager.cleanUp()
        databaseManager.deleteAllZones { [weak self] error in
            guard let self else { return }

            if error == nil {
                self._hasSetup = false
                self.setup()
            }

            if error != nil {
                completion?(error)
                return
            }

            self.push(progressHandler: progressHandler) {
                completion?(nil)
            }
        }
    }
    /// 推送本地修改到 iCloud (不要太频繁调用)
    /// - progressHandler: 每条 record 保存成功后回调（主线程）
    /// - completion: 所有 syncObject 均推送成功后回调
    public func push(progressHandler: ((VHLCKSyncProgress) -> Void)? = nil, completion: (() -> Void)? = nil) {
        if !self.canSync { return }
        guard !databaseManager.syncObjects.isEmpty else {
            completion?()
            return
        }
        let actualTotal = VHLCKAtomicCounter()
        let processedCount = VHLCKAtomicCounter()

        let onProgress: (() -> Void) = {
            let processed = processedCount.increment()
            let total = actualTotal.currentValue
            VHLCKLogger.log("push: 进度 \(processed)/\(total)")

            let progress = VHLCKSyncProgress(stage: .pushingChanges(processed: processed, total: total))
            DispatchQueue.main.async {
                progressHandler?(progress)
                NotificationCenter.default.post(
                    name: .VHLiCloudSyncProgressNotification,
                    object: nil,
                    userInfo: [VHLiCloudSyncProgressKey: progress]
                )
            }
        }

        let onPrepare: (Int) -> Void = { saveCount in
            actualTotal.add(saveCount)
        }

        let group = DispatchGroup()
        databaseManager.syncObjects.forEach { syncObject in
            group.enter()
            syncObject.pushLocalObjectsToCloudKit(onPrepare: onPrepare, onProgress: onProgress) {
                group.leave()
            }
        }

        // onPrepare 在所有 syncObject 的 pushLocalObjectsToCloudKit 中同步触发完毕，
        // actualTotal 此时已是精准值；在此发送初始进度 (0/total)
        let total = actualTotal.currentValue
        VHLCKLogger.log("push: 开始推送, actualTotal=\(total)")
        if total > 0 {
            DispatchQueue.main.async {
                let progress = VHLCKSyncProgress(stage: .pushingChanges(processed: 0, total: total))
                progressHandler?(progress)
                NotificationCenter.default.post(
                    name: .VHLiCloudSyncProgressNotification,
                    object: nil,
                    userInfo: [VHLiCloudSyncProgressKey: progress]
                )
            }
        }

        group.notify(queue: .main) {
            VHLCKLogger.log("push: 推送完成, actualTotal=\(total)")
            completion?()
        }
    }
    
    // MARK: 同步数据。推送本地更新，拉取云端数据
    /// 同步数据。先拉取云端变更，再推送本地修改
    /// - progressHandler: 进度回调（主线程），pull 阶段转发 NotificationCenter 进度，push 阶段直接回调
    /// - onPullCompletion: pull 完成时回调（主线程）
    /// - onPushCompletion: push 完成时回调（主线程）
    /// - completionHandler: pull 阶段结束时回调（早于 push 完成）
    public func sync(progressHandler: ((VHLCKSyncProgress) -> Void)? = nil,
                     onPullCompletion: ((Error?) -> Void)? = nil,
                     onPushCompletion: (() -> Void)? = nil,
                     completionHandler: ((Error?) -> Void)? = nil) {
        var pullObserver: NSObjectProtocol?
        if let progressHandler {
            pullObserver = NotificationCenter.default.addObserver(
                forName: .VHLiCloudSyncProgressNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let progress = notification.userInfo?[VHLiCloudSyncProgressKey] as? VHLCKSyncProgress else { return }
                // pull 阶段的进度由 observer 转发；push 阶段由 push(progressHandler:) 直接回调
                if case .pushingChanges = progress.stage { return }
                if Thread.isMainThread {
                    progressHandler(progress)
                } else {
                    DispatchQueue.main.async { progressHandler(progress) }
                }
            }
        }

        pull { [weak self] error in
            if let pullObserver { NotificationCenter.default.removeObserver(pullObserver) }

            guard let self = self else {
                completionHandler?(error)
                return
            }

            // pull 的 completionHandler 已在主线程回调，在此同步 post 通知，
            // 确保 observer 在被 SyncManager.sync 的 completion 移除前就能收到
            NotificationCenter.default.post(
                name: .VHLiCloudSyncProgressNotification,
                object: nil,
                userInfo: [VHLiCloudSyncProgressKey: VHLCKSyncProgress(stage: .pushingChanges(processed: 0, total: 0))]
            )

            onPullCompletion?(error)
            completionHandler?(error)

            // 拉取完成后推送本地修改；cleanUp 必须等 push 成功后才能删除软删除记录
            DispatchQueue.global().async {
                self.push(progressHandler: progressHandler, completion: {
                    onPushCompletion?()
                    self.databaseManager.cleanUp()     // 清空本地标记删除的对象 isDeleted
                })
            }
        }
    }
}
