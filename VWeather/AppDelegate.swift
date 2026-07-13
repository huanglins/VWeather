//
//  AppDelegate.swift
//  VWeather
//
//  Created by Vincent on 2024/8/17.
//

import Foundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions
                     launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 初始化 iCloud 同步（此处 UIApplication 已就绪，可注册静默推送）
        _ = SyncManager.manager
        // 初始化内购：触发 StoreKit 交易监听，并加载产品与权益
        Task { await IAPManager.shared.loadProducts() }
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        
        let sceneConfig : UISceneConfiguration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig

    }
}

// MARK: - 远程静默推送（CloudKit 订阅变更）
extension AppDelegate {
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard SyncManager.manager.syncIsOpen else {
            completionHandler(.noData)
            return
        }
        // 通知同步引擎有远程变更（引擎会防抖后自动 pull）
        NotificationCenter.default.post(name: .VHLiCloudRemoteDataDidChangeRemotely, object: nil)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("注册远程通知失败:", error.localizedDescription)
    }
}
