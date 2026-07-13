//
//  VHLCKDataType.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation

extension Notification.Name {
    public static let VHLiCloudRemoteDataDidChangeRemotely = NSNotification.Name("VHLiCloudRemoteDataDidChangeRemotely")
}

// MARK: - keys
public enum VHLCKKey: String {
    // tokens
    case databaseChangesTokenKey
    case zoneChangesTokenKey
    
    // Flags
    case subscriptionIsLocallyCachedKey
    case hasCustomZoneCreatedKey
    
    var value: String {
        return "vhlck.keys." + rawValue
    }
}

/// Dangerous part:
/// In most cases, you should not change the string value cause it is related to user settings.
/// e.g.: the cloudKitSubscriptionID, if you don't want to use "private_changes" and use another string. You should remove the old subsription first.
/// Or your user will not save the same subscription again. So you got trouble.
/// The right way is remove old subscription first and then save new subscription.
public enum VHLCKSubscription: String, CaseIterable {
    case cloudKitPrivateDatabaseSubscriptionID = "private_changes"
    case cloudKitPublicDatabaseSubscriptionID = "cloudKitPublicDatabaseSubcriptionID"
    
    var id: String {
        return rawValue
    }
    
    public static var allIDs: [String] {
        return VHLCKSubscription.allCases.map { $0.rawValue }
    }
}
