//
//  CityListView.swift
//  VWeather
//
//  城市管理页：搜索添加城市、点击切换首页城市、左滑删除。
//

import SwiftUI

struct CityListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cities: [CityModel] = []
    @State private var keyword = ""
    @State private var searchResults: [CityModel] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                // 搜索结果
                if searching {
                    Section("搜索结果") {
                        HStack { ProgressView(); Text("搜索中…").foregroundStyle(.secondary) }
                    }
                } else if !searchResults.isEmpty {
                    Section("搜索结果") {
                        ForEach(searchResults, id: \.cityKey) { city in
                            Button {
                                add(city)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name ?? "未知")
                                        .foregroundStyle(.primary)
                                    if let addr = city.fullAddress, !addr.isEmpty {
                                        Text(addr).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // 我的城市
                Section("我的城市") {
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
                                if let temp = CityWeatherManager.manager.cachedSnapshot(for: city)?.weather?.temperature {
                                    Text(AppSettings.shared.tempText(temp)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
            .navigationTitle("城市")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $keyword, prompt: "搜索城市，如「北京」")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: keyword) { _, newValue in
                if newValue.isEmpty { searchResults = [] }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                cities = CityManager.manager.allCities()
            }
        }
    }

    // MARK: - 操作

    private func runSearch() async {
        searching = true
        let results = await CityManager.manager.searchCities(keyword)
        await MainActor.run {
            searchResults = results
            searching = false
        }
    }

    private func add(_ city: CityModel) {
        _ = CityManager.manager.addCity(city)
        cities = CityManager.manager.allCities()
        searchResults = []
        keyword = ""
        // 预取天气写入缓存（新添加城市强制请求一次）
        Task { await CityWeatherManager.manager.refresh(for: city, force: true) }
    }

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
