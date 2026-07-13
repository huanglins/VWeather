//
//  SyncManager.swift
//  VWeather
//
//  iCloud（CloudKit 私有数据库）同步：仅同步城市列表 CityModel。
//  精简自 TunTunFocus 的 SyncManager，去掉专注功能相关的后台保活逻辑。
//

import Foundation
import CloudKit
import UIKit

/// CloudKit 容器 identifier（需在 Apple Developer 后台创建该容器，并在 Signing & Capabilities 勾选 iCloud→CloudKit）
let iCloudIdentifier = "iCloud.cn.vincents.VWeather"
let UD_iCloudEnable = "VW_iCloudEnable"

class SyncManager {
    static let manager = SyncManager()

    private(set) var syncEngine: VHLCKSyncEngine?
    private var objects: [VHLCKSyncable] = []

    /// iCloud 同步开关（持久化）
    var syncIsOpen: Bool {
        get { UserDefaults.standard.bool(forKey: UD_iCloudEnable) }
        set {
            UserDefaults.standard.set(newValue, forKey: UD_iCloudEnable)
            if newValue {
                setupEngineIfNeeded()       // 首次开启同步时才创建引擎与 CKContainer
                syncEngine?.canSync = true
            } else {
                syncEngine?.canSync = false
            }
        }
    }
    var isSyncing: Bool { syncEngine?.isSyncing ?? false }
    var lastSyncDate: Date? { syncEngine?.lastSyncDate }

    init() {
        registerNotifications()
        // 仅在用户已开启同步时才初始化 CloudKit；未开启时不创建 CKContainer，
        // 避免在未配置 iCloud 容器 / 未签名（如模拟器）环境下启动即崩溃。
        if syncIsOpen {
            setupEngineIfNeeded()
        }
    }

    /// 懒初始化同步引擎（首次开启同步时才创建 CKContainer；需 app 具备 iCloud 容器 entitlement）
    private func setupEngineIfNeeded() {
        guard syncEngine == nil, let db = DBManager.manager.db else { return }

        let ud = UserDefaults(suiteName: APP_GROUP) ?? .standard
        // 仅注册城市列表参与同步；天气快照为本地缓存不同步
        objects = [
            VHLCKSQLiteSyncObject(type: CityModel.self, db: db, userDefaults: ud)
        ]

        let container = CKContainer(identifier: iCloudIdentifier)
        syncEngine = VHLCKSyncEngine(objects: objects,
                                     databaseScope: .private,
                                     container: container,
                                     userDefaults: ud,
                                     canSync: true)
        #if DEBUG
        syncEngine?.isLoggingEnabled = true
        #endif

        UIApplication.shared.registerForRemoteNotifications()   // 静默推送（用户不可见）
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func willEnterForeground() { sync() }
    @objc private func didEnterBackground() { sync() }
}

// MARK: - 同步操作
extension SyncManager {
    /// pull + push 一次
    func sync(_ completion: @escaping (Error?) -> Void = { _ in }) {
        guard syncIsOpen else { completion(nil); return }
        guard !isSyncing else { completion(nil); return }
        guard let engine = syncEngine else { completion(nil); return }

        engine.sync(completionHandler: { error in
            DispatchQueue.main.async { completion(error) }
        })
    }

    /// 仅推送本地变更（如删除后立即传播）
    func push(_ completion: @escaping () -> Void = {}) {
        guard syncIsOpen, let engine = syncEngine else { completion(); return }
        DispatchQueue.global().async { engine.push(completion: completion) }
    }

    /// 清空本地 token 后全量重新拉取
    func repull(_ completion: @escaping (Error?) -> Void = { _ in }) {
        guard let engine = syncEngine else { completion(nil); return }
        engine.repull(completion)
    }

    func stopSync() { syncEngine?.stopSync() }
}
