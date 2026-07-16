//
//  CityListView.swift
//  VWeather
//
//  城市管理页：右上角 "+" 添加城市、点击切换首页城市、左滑删除。
//

import SwiftUI

struct CityListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cities: [CityModel] = []
    @State private var showCitySearch = false

    var body: some View {
        NavigationStack {
            List {
                Section("我的城市") {
                    if cities.isEmpty {
                        Text("还没有添加城市")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cities, id: \.cityKey) { city in
                            Button {
                                select(city)
                            } label: {
                                HStack {
                                    if city.isCurrentLocation == true {
                                        Image(systemName: "location.fill")
                                            .foregroundStyle(.blue)
                                    }
                                    Text(city.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if let temp = CityWeatherManager.manager.cachedSnapshot(for: city)?.weather?.now?.temperature {
                                        Text(AppSettings.shared.tempText(temp)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteRows)
                    }
                }
            }
            .navigationTitle("城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCitySearch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCitySearch) {
                CitySearchView(onAdd: { _ in
                    cities = CityManager.manager.allCities()
                })
            }
            .onAppear {
                cities = CityManager.manager.allCities()
            }
        }
    }

    // MARK: - 操作

    private func select(_ city: CityModel) {
        CityManager.manager.setSelected(city)
        // 立即通知首页刷新，让首页在 sheet 关闭动画期间就更新，而非等动画结束
        NotificationCenter.default.post(name: .VWSelectedCityDidChange, object: nil)
        dismiss()

        // 「当前位置」项：请求一次定位；坐标变更则更新城市并强制刷新其天气，再次通知首页刷新
        guard city.isCurrentLocation == true else { return }
        CityManager.manager.refreshCurrentLocationCity { newCity, _ in
            guard let newCity = newCity else { return }
            let changed = newCity.cityKey != city.cityKey
            if changed { CityManager.manager.setSelected(newCity) }
            Task {
                await CityWeatherManager.manager.refresh(for: newCity, force: changed)
                NotificationCenter.default.post(name: .VWSelectedCityDidChange, object: nil)
            }
        }
    }

    private func deleteRows(_ offsets: IndexSet) {
        for index in offsets {
            _ = CityManager.manager.deleteCity(cities[index])
        }
        cities = CityManager.manager.allCities()
    }
}
