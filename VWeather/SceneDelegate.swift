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
