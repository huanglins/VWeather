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

import CoreLocation
import SwiftUI
import UIKit

struct CityListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var iap = IAPManager.shared

    @State private var cities: [CityModel] = []
    @State private var showCitySearch = false
    @State private var showMembership = false

    /// 各城市的快照，按 cityKey 索引。
    ///
    /// 单独存 state 而不是每次渲染都查库：一是查库在主线程，二是补数据要能
    /// 增量更新某一张卡。
    @State private var snapshots: [String: CityWeatherSnapshot] = [:]

    /// 定位授权状态。存 state 而不是每次渲染都查 —— 从设置页回来要能刷新，
    /// 靠 scenePhase 变化重读。
    @State private var authStatus = VHLLocationManager.authorizationStatus()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cities.isEmpty && !showLocationPrompt {
                    ContentUnavailableView("还没有添加城市",
                                           systemImage: "location.slash",
                                           description: Text("点击下方搜索添加"))
                        .foregroundStyle(.white)
                } else {
                    List {
                        // 定位没开时，「当前位置」那张卡根本不会存在 ——
                        // 列表里只是少一行，用户无从知道为什么。放个提示占住它的位置。
                        if showLocationPrompt {
                            locationPrompt
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(cities, id: \.cityKey) { city in
                            Button { select(city) } label: {
                                CityCard(city: city,
                                         snapshot: city.cityKey.flatMap { snapshots[$0] })
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // 当前位置不可删（CityManager.deleteCity 本来就会拒绝）。
                            // 不禁掉的话左滑还是划得出删除按钮，点了却毫无反应 ——
                            // 有入口而无效，比没入口更让人困惑。
                            .deleteDisabled(city.isCurrentLocation == true)
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
            .sheet(isPresented: $showMembership) {
                NavigationStack {
                    MembershipView(showsCloseButton: true)
                }
            }
            .onAppear {
                cities = CityManager.manager.allCities()
                loadSnapshots()
                authStatus = VHLLocationManager.authorizationStatus()
                refreshCurrentLocationIfNeeded()
            }
            .task { await fillMissing() }
            // 用户可能去设置里改了权限再回来，或刚在系统弹框里点了允许。
            // 两种情况都不会自动重绘，得回前台时重读一次。
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                authStatus = VHLLocationManager.authorizationStatus()
                refreshCurrentLocationIfNeeded()
            }
        }
    }

    /// 定位不可用（拒绝 / 受限 / 还没问过）
    private var locationDenied: Bool {
        authStatus != .authorizedAlways && authStatus != .authorizedWhenInUse
    }

    /// 该不该显示定位提示。
    ///
    /// 判据是「有没有当前位置这张卡」，不是「权限给没给」——
    /// 权限被撤销时，之前定位出来的城市卡还在（数据只是不再更新），
    /// 光看权限的话会同时出现「定位权限未开启」和一张带定位图标的城市卡，
    /// 自相矛盾。有卡就显示卡，没卡才提示。
    private var showLocationPrompt: Bool {
        locationDenied && !cities.contains { $0.isCurrentLocation == true }
    }

    /// 「当前位置」缺位时的提示卡。放在列表最前，占住它本该在的位置。
    private var locationPrompt: some View {
        Button {
            if authStatus == .notDetermined {
                // 还没问过：弹系统授权框，别一上来就把人踢去设置
                VHLLocationManager.manager.locationManager.requestWhenInUseAuthorization()
            } else {
                // 明确拒绝过：系统不会再弹，只能去设置里改
                openAppSettings()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前位置")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(authStatus == .notDetermined
                         ? "点击开启定位，显示所在地天气"
                         : "定位权限未开启，点击前往设置")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 底部搜索栏。只是个入口 —— 点了打开原本的搜索页，
    /// 不在这里做联想搜索，那是 CitySearchView 的事。
    private var searchBar: some View {
        Button {
            if iap.isPro {
                showCitySearch = true
            } else {
                showMembership = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iap.isPro ? "magnifyingglass" : "crown.fill")
                Text(iap.isPro ? "搜索并添加城市" : "会员可添加收藏城市")
                Spacer()
                if !iap.isPro {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                }
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // 半透明底而非不透明：卡片从栏下滚过时能透出模糊色块，保留层次感。
            // iOS 26 用液态玻璃（随下方内容折射流动），更早回退毛玻璃。
            .modifier(SearchBarGlass())
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

    /// 有定位权限但「当前位置」城市不存在时，补建一个。
    ///
    /// 这个缺口不只是「刚点了允许」那一种：ContentView.firstLoad 只在
    /// **一个城市都没有**时才去定位，所以只要库里还有别的城市，
    /// 「当前位置」一旦缺失就永远不会重建 —— 用户首次拒绝定位、手动加了几个城市、
    /// 之后再去设置里开权限，就会一直看不到当前位置。
    ///
    /// 挂在 onAppear 而不只是 scenePhase：列表在已激活的场景里打开时
    /// scenePhase 不变，只靠它是不会触发的。
    private func refreshCurrentLocationIfNeeded() {
        guard !locationDenied else { return }
        guard !cities.contains(where: { $0.isCurrentLocation == true }) else { return }
        CityManager.manager.refreshCurrentLocationCity { city, _ in
            guard city != nil else { return }
            cities = CityManager.manager.allCities()
            Task { await fillMissing() }
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
            let city = cities[index]
            // 删成功了才清快照。deleteCity 对「当前位置」返回 false ——
            // 无条件清的话，行还在、快照没了，卡片会变成一张空白。
            guard CityManager.manager.deleteCity(city) else { continue }
            if let key = city.cityKey { snapshots[key] = nil }
        }
        cities = CityManager.manager.allCities()
    }
}

// MARK: - 城市卡片

/// 一个城市的概览卡。
///
/// 卡片底色取自该城市**自己**的天况（与首页、小组件共用 WeatherPalette）——
/// 一眼扫过去，蓝的晴、灰的阴，不用逐个读文字。
/// 内容部分抽在 CityWeatherCardContent，与中号小组件共用同一份代码。
private struct CityCard: View {
    let city: CityModel
    let snapshot: CityWeatherSnapshot?

    private var condition: VWCondition { snapshot?.weather?.now?.condition ?? .unknown }
    private var isNight: Bool { snapshot?.sun?.isNight ?? false }

    var body: some View {
        CityWeatherCardContent(title: city.displayName,
                               isCurrentLocation: city.isCurrentLocation == true,
                               report: snapshot?.weather,
                               isNight: isNight)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: WeatherPalette.colors(for: condition, isNight: isNight),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 底部搜索栏的半透明背景：iOS 26 用液态玻璃（可交互、随下方内容流动折射），
/// 更早系统回退毛玻璃 —— 两者都能透出下方滚过的卡片色块，保留层次。
private struct SearchBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
