//
//  VHLCKSyncEngine+Delegate.swift
//  VHLiCloud
//
//  Created by Vincent on 2023/7/13.
//

import Foundation
import CloudKit

extension VHLCKSyncEngine {
    public enum Event : Sendable {
        // 账户状态变更
        case accountChange(CKAccountStatus)
        // 数据库变更
        case fetchedDatabaseChanges
    }
}

protocol VHLCKSyncEngineDelegate: AnyObject {
    func handleEvent(_ event: VHLCKSyncEngine.Event, syncEngine: VHLCKSyncEngine)
}
