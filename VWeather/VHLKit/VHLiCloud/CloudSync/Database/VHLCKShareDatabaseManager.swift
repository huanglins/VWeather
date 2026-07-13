//
//  VHLCKShareDatabaseManager.swift
//  EverList
//
//  Created by Vincent on 2021/3/31.
//  Copyright © 2021 Darnel Studio. All rights reserved.
//

import Foundation
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

import CloudKit

final class VHLCKShareDatabaseManager: VHLCKDatabaseManager {
    
    var database: CKDatabase
    
    var container: CKContainer
    
    var syncObjects: [VHLCKSyncable]
    
    var userDefaults: UserDefaults = .standard
    var canSync: Bool = true
    
    init(objects: [VHLCKSyncable], container: CKContainer, userDefaults: UserDefaults) {
        self.syncObjects = objects
        self.container = container
        self.database = container.sharedCloudDatabase
        self.userDefaults = userDefaults
    }
    
    func fetchChangesInDatabase(_ callback: ((Error?) -> Void)?) {
        
    }
    
    func createCustomZonesIfAllowed() {
        
    }
    
    func createDatabaseSubscriptionIfHaveNot() {
        
    }
    
    func startObservingTermination() {
        
    }
    
    func registerLocalDatabase() {
        
    }
    
    func cleanUp() {
        
    }
    
    func deleteAllZones(_ callback: ((Error?) -> Void)?) {
    }
}

/**
 https://blog.csdn.net/cunjie3951/article/details/106905335
 */
