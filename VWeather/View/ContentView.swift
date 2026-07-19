//
//  ContentView.swift
//  VWeather
//
//  首页：整屏渐变背景（随天气变化）+ 浮在其上的毛玻璃卡片。
//
//  用 ScrollView 而非 List：设计里有 2 列的指标网格，List 的行模型套不进去；
//  且 List 自带的背景/分隔线在渐变上都要一一关掉，反而更绕。
//
//  文字固定白色系，不跟随浅色/深色模式 —— 背景恒为有色深底，
//  `.primary` 在浅色模式下是黑的，落在蓝色渐变上没法看。
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedCity: CityModel?
    @State private var snapshot: CityWeatherSnapshot?
    @State private var showCityList = false
    @State private var showSettings = false
    @State private var locationError: VHLLocationError?
    @State private var locating = false
    @Environment(\.scenePhase) private var scenePhase
    
    /// 当前天况与昼夜 —— 决定背景色调
    private var condition: VWCondition { snapshot?.weather?.now?.condition ?? .unknown }
    private var isNight: Bool { snapshot?.sun?.isNight ?? false }
    
    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackground(condition: condition, isNight: isNight)
                
                Group {
                    if let city = selectedCity {
                        WeatherMainView(city: city, snapshot: snapshot)
                    } else if locating {
                        ProgressView("定位中…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    } else if let error = locationError {
                        LocationErrorView(
                            error: error,
                            onOpenSettings: {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            },
                            onRetry: { firstLoad() }
                        )
                    } else {
                        ContentUnavailableView("暂无城市",
                                               systemImage: "location.slash",
                                               description: Text("点击左上角添加城市"))
                        .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle(selectedCity?.displayName ?? "天气")
            .navigationBarTitleDisplayMode(.inline)
            // 导航栏让位给渐变：留下按钮，去掉背景板
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCityList = true } label: {
                        Image(systemName: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tint(.white)
            .environment(\.colorScheme, .dark)
            .sheet(isPresented: $showCityList, onDismiss: reload) {
                CityListView()
            }
            .sheet(isPresented: $showSettings, onDismiss: reload) {
                SettingsView()
            }
        }
        .onAppear(perform: firstLoad)
        .onReceive(NotificationCenter.default.publisher(for: .VWSelectedCityDidChange)) { _ in
            reload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let city = selectedCity {
                Task { await refresh(city: city) }
            }
        }
    }
    
    // MARK: - 数据加载
    
    private func firstLoad() {
        // 已有城市则直接展示（不依赖定位）
        if !CityManager.manager.allCities().isEmpty {
            locationError = nil
            reload()
            return
        }
        // 首次进入且无城市：定位生成「我的位置」城市；失败则提示（不再回退任何默认位置）
        locating = true
        locationError = nil
        CityManager.manager.refreshCurrentLocationCity { city, error in
            locating = false
            if city != nil {
                reload()
            } else {
                locationError = error ?? .failed
            }
        }
    }
    
    private func reload() {
        let city = CityManager.manager.selectedCity
        selectedCity = city
        if city != nil { locationError = nil }   // 已有可显示城市，清除定位错误提示
        guard let city = city else {
            snapshot = nil
            return
        }
        // 先读缓存秒显，再后台刷新
        snapshot = CityWeatherManager.manager.cachedSnapshot(for: city)
        Task { await refresh(city: city) }
    }
    
    private func refresh(city: CityModel, force: Bool = false) async {
        let snap = await CityWeatherManager.manager.refresh(for: city, force: force)
        await MainActor.run {
            // 避免刷新期间用户已切换城市
            if city.cityKey == selectedCity?.cityKey {
                snapshot = snap
            }
        }
    }
}
