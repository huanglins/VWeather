//
//  VHLCKPublicDatabaseManager.swift
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

final class VHLCKPublicDatabaseManager: VHLCKDatabaseManager {
    
    let container: CKContainer
    let database: CKDatabase
    
    let syncObjects: [VHLCKSyncable]
    
    var userDefaults: UserDefaults = .standard
    var canSync: Bool = true
    
    init(objects: [VHLCKSyncable], container: CKContainer, userDefaults: UserDefaults) {
        self.syncObjects = objects
        self.container = container
        self.database = container.publicCloudDatabase
        self.userDefaults = userDefaults
    }
    
    // MARK: - 实现基类方法
    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?) {
        let group = DispatchGroup()
        
        var fetchError: Error?
        syncObjects.forEach { [weak self](syncObject) in
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: syncObject.recordType, predicate: predicate)
            let queryOperation = CKQueryOperation(query: query)
            
            group.enter()
            self?.excuteQueryOperation(queryOperation: queryOperation, on: syncObject, callback: { error in
                if fetchError == nil { fetchError = error }
                group.leave()
            })
        }
        
        group.notify(queue: .main) {
            callback?(fetchError)
        }
    }
    
    /// 公共数据库不支持自定义 zone
    func createCustomZonesIfAllowed() {
        
    }
    
    func createDatabaseSubscriptionIfHaveNot() {
        syncObjects.forEach{ createSubscriptionInPublicDatabase(on: $0) }
    }
    
    func startObservingTermination() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(self.cleanUp), name: UIApplication.willTerminateNotification, object: nil)
        #elseif os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(self.cleanUp), name: NSApplication.willTerminateNotification, object: nil)
        #endif
    }
    
    func registerLocalDatabase() {
        syncObjects.forEach { (object) in
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
    
    func deleteAllZones(_ callback: ((Error?) -> Void)?) {
        callback?(nil)
    }
}

extension VHLCKPublicDatabaseManager {
    fileprivate func excuteQueryOperation(queryOperation: CKQueryOperation, on syncObject: VHLCKSyncable, callback: ((Error?) -> Void)? = nil) {
        // 废弃方法
//        queryOperation.recordFetchedBlock = { (record) in
//            if !self.canSync { return }
//            
//            syncObject.addOrUpdate(record: record)
//        }
//        
//        queryOperation.queryCompletionBlock = { [weak self](cursor, error) in
//            guard let self = self else { return }
//            if let cursor = cursor {
//                let subsequentQueryOperation = CKQueryOperation(cursor: cursor)
//                self.excuteQueryOperation(queryOperation: subsequentQueryOperation, on: syncObject, callback: callback)
//                return
//            }
//            
//            switch VHLCKErrorHandler.shared.resultType(with: error) {
//            case .success:
//                DispatchQueue.main.async {
//                    callback?(nil)
//                }
//            case .retry(let timeToWait, _):
//                VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
//                    self.excuteQueryOperation(queryOperation: queryOperation, on: syncObject, callback: callback)
//                }
//            default:
//                break
//            }
//        }
        
        queryOperation.recordMatchedBlock = { [weak self] (recordID, result) in
            guard let self else { return }
            
            if !self.canSync { return }
            
            switch result {
            case .success(let record):
                syncObject.addOrUpdate(record: record)
            case .failure(_):
                break
            }
        }
        queryOperation.queryResultBlock = { [weak self] (result) in
            guard let self else { return }
            
            switch result {
            case .success(let cursor):
                if let cursor = cursor {
                    let subsequentQueryOperation = CKQueryOperation(cursor: cursor)
                    self.excuteQueryOperation(queryOperation: subsequentQueryOperation, on: syncObject, callback: callback)
                    return
                }
            case .failure(let error):
                switch VHLCKErrorHandler.shared.resultType(with: error) {
                case .success:
                    DispatchQueue.main.async {
                        callback?(nil)
                    }
                case .retry(let timeToWait, _):
                    VHLCKErrorHandler.shared.retryOperationIfPossible(retryAfter: timeToWait) {
                        self.excuteQueryOperation(queryOperation: queryOperation, on: syncObject, callback: callback)
                    }
                default:
                    break
                }
            }
        }
        
        database.add(queryOperation)
    }
    
    fileprivate func createSubscriptionInPublicDatabase(on syncObject: VHLCKSyncable) {
        #if os(iOS) || os(tvOS) || os(macOS)
        let predict = NSPredicate(value: true)
        let subscription = CKQuerySubscription(recordType: syncObject.recordType, predicate: predict, subscriptionID: VHLCKSubscription.cloudKitPublicDatabaseSubscriptionID.id, options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push
        
        subscription.notificationInfo = notificationInfo
        
        let createOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        // 废弃
//        createOperation.modifySubscriptionsCompletionBlock = { (_, _, error) in
//            guard error == nil else { return }
//            self.subscriptionIsLocallyCached = true
//        }
        createOperation.modifySubscriptionsResultBlock = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success():
                self.subscriptionIsLocallyCached = true
            case .failure(_):
                break
            }
        }
        createOperation.qualityOfService = .utility
        database.add(createOperation)
        #endif
    }
}

// MARK: - get
extension VHLCKPublicDatabaseManager {
    var databaseChangeToken: CKServerChangeToken? {
        get {
            guard let tokenData = userDefaults.object(forKey: VHLCKKey.databaseChangesTokenKey.value) as? Data else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData)
        }
        set {
            guard let n = newValue else {
                userDefaults.removeObject(forKey: VHLCKKey.databaseChangesTokenKey.value)
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: n, requiringSecureCoding: false)
            userDefaults.setValue(data, forKey: VHLCKKey.databaseChangesTokenKey.value)
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
}
