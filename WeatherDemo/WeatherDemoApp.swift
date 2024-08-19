//
//  WeatherDemoApp.swift
//  WeatherDemo
//
//  Created by vincent on 2024/8/19.
//

import SwiftUI
import SwiftDate

@main
struct WeatherDemoApp: App {
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

extension WeatherDemoApp {
    func configInit() {
        // 设置默认时区
        SwiftDate.defaultRegion = .current
        
        print("第一次初始化")
    }
}
