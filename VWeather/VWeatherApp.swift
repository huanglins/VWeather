//
//  VWeatherApp.swift
//  VWeather
//
//  Created by vincent on 2024/8/19.
//

import SwiftUI
import SwiftDate

@main
struct VWeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appdelegate

    init() {
        configInit()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension VWeatherApp {
    func configInit() {
        // 设置默认时区
        SwiftDate.defaultRegion = .current

        // 初始化数据库（建表 / 迁移）
        _ = DBManager.manager

        print("第一次初始化")
    }
}
