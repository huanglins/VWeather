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
import CoreLocation

struct CitySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iap = IAPManager.shared
    @State private var keyword = ""
    @State private var searchResults: [CityModel] = []
    @State private var searching = false
    @State private var searched = false
    /// 当前定位坐标（若有）——用于在结果里显示「距当前位置」。
    @State private var currentLocation: CLLocation?
    /// 已在列表里的城市 key。用于把结果标成「已添加」——
    /// addCity 是按 cityKey upsert 的，重复点不会加出两条，
    /// 但不标一下的话点了像没反应。
    @State private var existingKeys: Set<String> = []
    @State private var showMembership = false

    var onAdd: ((CityModel) -> Void)?

    init(onAdd: ((CityModel) -> Void)? = nil, previewResults: [CityModel]? = nil) {
        self.onAdd = onAdd
        if let previewResults {
            _searchResults = State(initialValue: previewResults)
            _searched = State(initialValue: true)
        }
    }

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
                let cities = CityManager.manager.allCities()
                existingKeys = Set(cities.compactMap { $0.cityKey })
                if let cur = cities.first(where: { $0.isCurrentLocation == true }),
                   let la = cur.latitude, let lo = cur.longitude {
                    currentLocation = CLLocation(latitude: la, longitude: lo)
                }
            }
            .sheet(isPresented: $showMembership) {
                NavigationStack {
                    MembershipView(showsCloseButton: true)
                }
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
                LazyVStack(spacing: 12) {
                    ForEach(searchResults, id: \.cityKey) { city in
                        row(city)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    private func row(_ city: CityModel) -> some View {
        let added = city.cityKey.map { existingKeys.contains($0) } ?? false
        let strong = added ? 0.45 : 1.0        // 已添加的整体压暗
        return Button {
            add(city)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(added ? 0.3 : 0.85))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    // 城市名 + 省份徽标
                    HStack(spacing: 6) {
                        Text(city.name ?? "未知")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(strong))
                            .lineLimit(1)
                        if let province = city.province, !province.isEmpty, province != city.name {
                            Text(province)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(added ? 0.35 : 0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(added ? 0.06 : 0.14)))
                        }
                    }

                    if let addr = city.fullAddress, !addr.isEmpty, addr != city.name {
                        Text(addr)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(added ? 0.3 : 0.6))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    // 元信息：经纬度 + 距当前位置
                    HStack(spacing: 12) {
                        if let coord = coordText(city) {
                            metaLabel("location.fill", coord)
                        }
                        if let dist = distanceText(city) {
                            metaLabel("arrow.left.and.right", dist)
                        }
                    }
                    .foregroundStyle(.white.opacity(added ? 0.28 : 0.5))
                    .padding(.top, 1)
                }

                Spacer(minLength: 8)

                if added {
                    Label("已添加", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(added ? 0.05 : 0.1)))
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    /// 一个「小图标 + 文字」的元信息标签。
    private func metaLabel(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(text).font(.caption2)
        }
    }

    /// 经纬度 → "22.54°N  114.06°E"。
    private func coordText(_ city: CityModel) -> String? {
        guard let la = city.latitude, let lo = city.longitude else { return nil }
        let ns = la >= 0 ? "N" : "S"
        let ew = lo >= 0 ? "E" : "W"
        return String(format: "%.2f°%@  %.2f°%@", abs(la), ns, abs(lo), ew)
    }

    /// 距当前定位的距离（无当前定位则不显示）。
    private func distanceText(_ city: CityModel) -> String? {
        guard let cur = currentLocation, let la = city.latitude, let lo = city.longitude else { return nil }
        let meters = cur.distance(from: CLLocation(latitude: la, longitude: lo))
        if meters < 1000 { return "距当前 \(Int(meters)) m" }
        return String(format: "距当前 %.0f km", meters / 1000)
    }

    private func runSearch() async {
        searching = true
        searched = true
        let results = await CityManager.manager.searchCities(keyword)
        let cur = currentLocation
        await MainActor.run {
            // 优先按距离排序：离当前定位近的排在前面，没有定位时保持 CLGeocoder 返回顺序
            if let cur {
                searchResults = results.sorted { a, b in
                    let da = cur.distance(from: a.location)
                    let db = cur.distance(from: b.location)
                    return da < db
                }
            } else {
                searchResults = results
            }
            searching = false
        }
    }

    private func add(_ city: CityModel) {
        guard iap.isPro else {
            showMembership = true
            return
        }

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
    func sample(_ name: String, _ prov: String, _ addr: String, _ la: Double, _ lo: Double) -> CityModel {
        var c = CityModel()
        c.name = name; c.province = prov; c.country = "中国"; c.fullAddress = addr
        c.latitude = la; c.longitude = lo
        c.cityKey = CityModel.makeKey(lat: la, lng: lo)
        return c
    }
    return CitySearchView(previewResults: [
        sample("朝阳区", "北京市", "中国北京市朝阳区", 39.9219, 116.4436),
        sample("南山区", "广东省", "中国广东省深圳市南山区", 22.5329, 113.9305),
        sample("西湖区", "浙江省", "中国浙江省杭州市西湖区", 30.2595, 120.1300),
    ])
}
