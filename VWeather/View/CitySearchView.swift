//
//  CitySearchView.swift
//  VWeather
//
//  城市搜索添加页：输入地名 → CLGeocoder 搜索 → 点击添加城市。
//

import SwiftUI

struct CitySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var searchResults: [CityModel] = []
    @State private var searching = false
    @State private var searched = false
    var onAdd: ((CityModel) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if searching {
                    Section {
                        HStack { ProgressView(); Text("搜索中…").foregroundStyle(.secondary) }
                    }
                } else if searchResults.isEmpty && searched {
                    Section {
                        ContentUnavailableView("未找到结果",
                                               systemImage: "magnifyingglass",
                                               description: Text("请尝试其他关键词"))
                    }
                } else if !searchResults.isEmpty {
                    Section(searched ? "搜索结果" : "热门城市") {
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
            }
            .navigationTitle("添加城市")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $keyword, prompt: "搜索城市，如「北京」")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: keyword) { _, newValue in
                if newValue.isEmpty {
                    searchResults = []
                    searched = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                // 预展示一些示例城市
                searchResults = []
            }
        }
    }

    private func runSearch() async {
        searching = true
        searched = true
        let results = await CityManager.manager.searchCities(keyword)
        await MainActor.run {
            searchResults = results
            searching = false
        }
    }

    private func add(_ city: CityModel) {
        let added = CityManager.manager.addCity(city)
        onAdd?(added)
        // 预取天气（新添加城市强制请求一次）
        Task { await CityWeatherManager.manager.refresh(for: added, force: true) }
        dismiss()
    }
}

#Preview {
    CitySearchView()
}
