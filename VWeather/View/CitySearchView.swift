//
//  CitySearchView.swift
//  VWeather
//
//  城市搜索添加页：输入地名 → CLGeocoder 搜索 → 点击添加。
//
//  与 CityListView 同一套视觉：黑底 + 半透明行。
//
//  搜索由回车触发，不做边打边搜 —— CLGeocoder 明确要求「每次用户操作最多一次
//  请求」，逐字符触发会被限流并开始返回错误。真要做联想，得换 MKLocalSearchCompleter
//  （那是专为 as-you-type 设计的），不是加个防抖就能糊过去的。
//

import SwiftUI

struct CitySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var searchResults: [CityModel] = []
    @State private var searching = false
    @State private var searched = false
    /// 已在列表里的城市 key。用于把结果标成「已添加」——
    /// addCity 是按 cityKey upsert 的，重复点不会加出两条，
    /// 但不标一下的话点了像没反应。
    @State private var existingKeys: Set<String> = []

    var onAdd: ((CityModel) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("添加城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .tint(.white)
            .onAppear {
                existingKeys = Set(CityManager.manager.allCities().compactMap { $0.cityKey })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if searching {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("搜索中…").font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        } else if !searched {
            // 还没搜过：说清楚要做什么，别给一片空白
            ContentUnavailableView {
                Label("搜索城市", systemImage: "magnifyingglass")
            } description: {
                Text("输入城市或地区名，按回车搜索")
            }
            .foregroundStyle(.white)
        } else if searchResults.isEmpty {
            ContentUnavailableView {
                Label("未找到结果", systemImage: "mappin.slash")
            } description: {
                Text("换个关键词试试，或输入更完整的地名")
            }
            .foregroundStyle(.white)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(searchResults, id: \.cityKey) { city in
                        row(city)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    private func row(_ city: CityModel) -> some View {
        let added = city.cityKey.map { existingKeys.contains($0) } ?? false
        return Button {
            add(city)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(added ? 0.3 : 0.75))

                VStack(alignment: .leading, spacing: 3) {
                    Text(city.name ?? "未知")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(added ? 0.45 : 1))
                    if let addr = city.fullAddress, !addr.isEmpty, addr != city.name {
                        Text(addr)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(added ? 0.3 : 0.55))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if added {
                    Text("已添加")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(added ? 0.05 : 0.1)))
        }
        .buttonStyle(.plain)
        .disabled(added)
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
        // 取数交给 onAdd 的接收方（CityListView）。
        //
        // 这里原本自己起一个 Task 预取，结果没人接：数据落了库，但列表的
        // snapshots 不会更新，新城的卡片一直空着，直到关掉列表重开。
        // 让需要结果的人去取，别发一个没人接的请求。
        onAdd?(added)
        dismiss()
    }
}

#Preview {
    CitySearchView()
}
