//
//  SceneDelegate.swift
//  VWeather
//
//  Created by Vincent on 2024/8/17.
//

import Foundation
import UIKit
import WidgetKit

class SceneDelegate: NSObject, UIWindowSceneDelegate {

    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo
               session: UISceneSession, options
               connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = scene as? UIWindowScene else {return}

        // 冷启动：从小组件点进来时，URL 随 connectionOptions 一起送达
        handleWidgetDeepLink(connectionOptions.urlContexts.first?.url)
    }

    /// 热启动：App 已在运行时从小组件点进来
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleWidgetDeepLink(URLContexts.first?.url)
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        WidgetCenter.shared.reloadAllTimelines()
        print("刷新小组件")
    }
}

// MARK: - 小组件深链：点卡片 → 首页切到对应城市
extension SceneDelegate {

    /// 解析 `vweather://city?key=<cityKey>`，把首页选中城市切到该城市。
    /// ⚠️ scheme/host/key 与小组件 `WidgetDeepLink` 保持一致（跨 target，两处各存一份字面量）。
    func handleWidgetDeepLink(_ url: URL?) {
        guard let url,
              url.scheme == "vweather", url.host == "city",
              let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "key" })?.value
        else { return }

        _ = DBManager.manager   // 冷启动路径确保共享库已就绪

        // 指向的城市已被删就不切，免得把选中项落到一个不存在的 key 上。
        guard CityModel.objects(whereSQL: "cityKey = ?", params: [key])
            .contains(where: { $0.isDeleted != true }) else { return }

        CityManager.manager.setSelectedCityKey(key)
        // 热启动：ContentView 监听此通知即时 reload 首页。
        // 冷启动：选中项已落盘，ContentView.firstLoad 也会读到，通知只是兜底。
        NotificationCenter.default.post(name: .VWSelectedCityDidChange, object: nil)
    }
}
