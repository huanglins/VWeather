//
//  VHLiCloud.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation
import CloudKit

public class VHLiCloud {
    static var status: CKAccountStatus = .couldNotDetermine
    
    /// iCloud 是否可用
    static func isAvailable(completionHandler: @escaping (Bool, CKAccountStatus, Error?) -> Void) {
        CKContainer.default().accountStatus { (status, error) in
            switch status {
            case .available:
                completionHandler(true, status, error)
            case .couldNotDetermine, .noAccount, .restricted:
                completionHandler(false, status, error)
            case .temporarilyUnavailable:
                completionHandler(false, status, error)
            @unknown default:
                completionHandler(false, status, error)
                VHLCKLogger.log("accountStatus: unknown default case")
            }
        }
    }
    
    // MARK: iCloud 同步描述
    static func getSyncStatus(_ block:@escaping (CKAccountStatus) -> Void) {
        // 检测 iCloud 使用状态
        CKContainer.default().accountStatus { status, error in
            if error != nil {
                // some error occurred (probably a failed connection, try again)
            } else {
                VHLiCloud.status = status
            }
            DispatchQueue.main.async {
                block(VHLiCloud.status)
            }
        }
    }
}
/**
 1.  项目设置 -> Signing & Capabilities 中打开 iCloud
 
 Key-value storage: 以键值对的方式缓存数据，可存储的类型与UserDefaults一致，API也几乎一样。
 Document storage: 用来存储用户可见的文件，这种方式被很多App使用，如 XMind、MWeb等，在iCloud Drive下可以直接看到文件。
 Core Data storage: 以CoreData的方式存储数据，其实就是数据库，当需要存储大量数据又不需要考虑跨平台（如Android）时会是不错的选择。
 
 ** 注意开发完成后，需要在 iCloud 后台部署数据库到生产环境
 */

/**

 IceCream
 https://github.com/caiyue1993/IceCream
 Listify 的iCloud云同步功能开发笔记
 https://zhuanlan.zhihu.com/p/106223913
 Listify 云同步模块的改进
 https://yigang.life/listify-cloud-improve
 
 CloudKit实践
 https://www.foolishtalk.org/2018/12/15/CloudKit%E5%AE%9E%E8%B7%B5/
 
 
 ** 支持 iCloud 同步的 sqlite 数据库 **
 https://github.com/pointfreeco/sqlite-data
 
 */

/**
 同步使用
 
 
 // MARK: 收到远程通知
 func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
     
 // VHLiCloud Sync 接收通知
 if let dict = userInfo as? [String: NSObject], let notification = CKNotification(fromRemoteNotificationDictionary: dict), let subscriptionID = notification.subscriptionID, VHLCKSubscription.allIDs.contains(subscriptionID) {
     NotificationCenter.default.post(name: VHLCKNotifications.cloudKitDataDidChangeRemotely.name, object: nil, userInfo: userInfo)
     completionHandler(.newData)
 }
 }
 
 
 */
