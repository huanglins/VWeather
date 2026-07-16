//
//  CityListView.swift
//  VWeather
//
//  收藏地点：每个城市一张卡，卡的渐变取自该城市当前的天况。
//  点击切换首页城市、左滑删除、底部搜索栏添加。
//
//  仍用 List 而非 ScrollView：左滑删除是 List 自带的，换成 ScrollView 就得自己
//  实现手势与动画。把 List 的背景与分隔线关掉即可，代价比重写手势小得多。
//

import SwiftUI

struct CityListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cities: [CityModel] = []
    @State private var showCitySearch = false

    /// 各城市的快照，按 cityKey 索引。
    ///
    /// 单独存 state 而不是每次渲染都查库：一是查库在主线程，二是补数据要能
    /// 增量更新某一张卡。
    @State private var snapshots: [String: CityWeatherSnapshot] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cities.isEmpty {
                    ContentUnavailableView("还没有添加城市",
                                           systemImage: "location.slash",
                                           description: Text("点击下方搜索添加"))
                        .foregroundStyle(.white)
                } else {
                    List {
                        ForEach(cities, id: \.cityKey) { city in
                            Button { select(city) } label: {
                                CityCard(city: city,
                                         snapshot: city.cityKey.flatMap { snapshots[$0] })
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteRows)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom) {
                searchBar
            }
            .navigationTitle("收藏地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            .tint(.white)
            .sheet(isPresented: $showCitySearch) {
                CitySearchView(onAdd: { added in
                    cities = CityManager.manager.allCities()
                    // 新城立刻取数。不能指望 .task 里的 fillMissing ——
                    // 那个只在列表出现时跑一次，列表已经开着时添加的城市轮不到它，
                    // 卡片会一直空着直到关掉重开。
                    Task { await load(added, force: true) }
                })
            }
            .onAppear {
                cities = CityManager.manager.allCities()
                loadSnapshots()
            }
            .task { await fillMissing() }
        }
    }

    /// 底部搜索栏。只是个入口 —— 点了打开原本的搜索页，
    /// 不在这里做联想搜索，那是 CitySearchView 的事。
    private var searchBar: some View {
        Button {
            showCitySearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("搜索")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // 毛玻璃而非不透明底：卡片从栏下滚过时能透出模糊的色块，
            // 保留层次感。safeAreaInset 已经给列表留出了底部空间，
            // 最后一张卡仍能完整滚上来，不会被永久挡住。
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 数据

    private func loadSnapshots() {
        for city in cities {
            guard let key = city.cityKey else { continue }
            snapshots[key] = CityWeatherManager.manager.cachedSnapshot(for: city)
        }
    }

    /// 取一个城市的天气并落到 snapshots。
    ///
    /// 标 @MainActor 是必须的：下面 withTaskGroup 起的子任务不继承调用方的
    /// actor 上下文，不标就会在非主线程上改 @State。
    /// 不会因此串行化 —— 真正的网络请求在 refresh 内部，不受 MainActor 约束，
    /// 各城市仍是并发的。
    @MainActor
    private func load(_ city: CityModel, force: Bool = false) async {
        guard let key = city.cityKey else { return }
        if let snap = await CityWeatherManager.manager.refresh(for: city, force: force) {
            snapshots[key] = snap
        }
    }

    /// 给没有数据的城市补一次天气。
    ///
    /// 列表只读缓存的话，从没打开过的城市会永远显示一张空卡 —— 旧版列表只显示
    /// 一个小温度，看不出来；现在卡片这么大，空着就像坏了。
    ///
    /// 对所有城市都调 refresh 是安全的：它自带 30 分钟节流，有新鲜缓存时直接返回，
    /// 不会真的发请求。并发拉取，慢的城市不挡快的。
    private func fillMissing() async {
        await withTaskGroup(of: Void.self) { group in
            for city in cities {
                group.addTask { await load(city) }
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
            if let key = cities[index].cityKey { snapshots[key] = nil }
            _ = CityManager.manager.deleteCity(cities[index])
        }
        cities = CityManager.manager.allCities()
    }
}

// MARK: - 城市卡片

/// 一个城市的概览卡：地名 + 当前温度 + 天况高低温 + 迷你多天预报。
///
/// 卡片底色取自该城市**自己**的天况（与首页共用 WeatherPalette）——
/// 一眼扫过去，蓝的晴、灰的阴，不用逐个读文字。
private struct CityCard: View {
    let city: CityModel
    let snapshot: CityWeatherSnapshot?

    private var report: WeatherReport? { snapshot?.weather }
    private var now: WeatherNow? { report?.now }
    private var today: WeatherDay? { report?.daily?.first }
    private var condition: VWCondition { now?.condition ?? .unknown }
    private var isNight: Bool { snapshot?.sun?.isNight ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if city.isCurrentLocation == true {
                            Image(systemName: "location.fill").font(.caption2)
                        }
                        Text(city.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(now?.conditionText ?? "--")
                        if let hi = today?.tempMax, let lo = today?.tempMin {
                            Text("|").foregroundStyle(.white.opacity(0.35))
                            Text("▼ \(AppSettings.shared.tempText(lo))")
                            Text("▲ \(AppSettings.shared.tempText(hi))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                Text(AppSettings.shared.tempText(now?.temperature))
                    .font(.system(size: 40, weight: .semibold))
            }

            if let days = report?.daily, !days.isEmpty {
                miniForecast(Array(days.prefix(7)))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: WeatherPalette.colors(for: condition, isNight: isNight),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func miniForecast(_ days: [WeatherDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(Self.shortWeekday(day.date))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: (day.condition ?? .unknown).symbol())
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 16))
                        .frame(height: 20)
                    Text(AppSettings.shared.tempText(day.tempMax))
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// "2026-07-16" → "四"。今天也用星期，不用「今」——
    /// 一排七个字，混用会让对齐看着乱。
    private static func shortWeekday(_ raw: String?) -> String {
        guard let raw, let date = dayParser.date(from: raw) else { return "-" }
        let i = Calendar.current.component(.weekday, from: date)   // 1 = 周日
        return ["日", "一", "二", "三", "四", "五", "六"][i - 1]
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
