//
//  SelectCityIntent.swift
//  WeatherWidget
//
//  中号小组件的配置：长按小组件 → 编辑 → 选城市。
//
//  ⚠️ 用 String 参数 + DynamicOptionsProvider，**不用 AppEntity + EntityQuery**。
//
//  原本用的是 AppEntity(CityEntity)。实测（NSLog + 抓小组件进程日志）：
//  用户在配置界面选中城市后，configuration.city 恒为 nil，EntityQuery.entities(for:)
//  从**未**被调用 —— 系统压根没把选择存下来。排除过 id 格式（改 hex 无效）、
//  脏状态（删了重加无效）、metadata 分布（补主 App target 无效）。
//  最后加了个 Bool 探针参数对照：Bool 改了能存住，同一个 intent 里的 AppEntity 存不住。
//  结论：这套环境下 AppEntity 的 widget 配置持久化就是坏的。
//
//  String 是系统原生可持久化类型（探针已证），配 IntentItem 就能既存 cityKey
//  又显示中文名。城市列表来自共享数据库（App Group group.cn.vincents.weather）。
//

import AppIntents
import WidgetKit

/// 「当前位置」的哨兵值。
///
/// ⚠️ 不能存当前位置那一刻的坐标 cityKey。当前位置城市的 cityKey **就是坐标串**，
/// 用户一移动，CityManager.refreshCurrentLocationCity 会删掉旧记录、按新坐标建新的
/// （新 cityKey）。存了旧坐标的话，移动后那条记录没了 → 小组件查不到 → 显示暂无，
/// 完全不跟随当前位置。存哨兵，resolveCity 每次查「当下的当前位置城市」，坐标随便变。
///
/// 前后缀加下划线，避免和真实 cityKey（纯坐标）撞。
let kWidgetCurrentLocation = "__current_location__"

/// 配置界面的城市候选。value 存 cityKey（当前位置存哨兵），title 显示中文名。
struct CityOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        _ = DBManager.manager          // 小组件进程里初始化共享库
        // isDeleted 为 NULL 时 "isDeleted != 1" 在 SQL 里求值为 NULL（不是 true），
        // 那行会被静默漏掉 —— 与 CityManager.allCities 一致，改在 Swift 侧过滤。
        let cities = CityModel.objects(order: .ASC("sortOrder"))
            .filter { $0.isDeleted != true }
        let items = cities.compactMap { city -> IntentItem<String>? in
            guard let key = city.cityKey else { return nil }
            let isCurrent = city.isCurrentLocation == true
            return IntentItem(isCurrent ? kWidgetCurrentLocation : key,
                              title: "\(city.displayName)",
                              subtitle: isCurrent ? "当前位置" : nil)
        }
        // 带 IntentItem（value + 显示名）的路径必须走 section；
        // init(items:) 那个重载收的是 [String]，直接显示 raw string
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择城市"
    static var description = IntentDescription("选择小组件要显示的城市")

    /// 存 cityKey（坐标串）；「当前位置」存 kWidgetCurrentLocation 哨兵。
    /// 为空表示「未配置」，由 provider 回退到当前位置。
    @Parameter(title: "城市", optionsProvider: CityOptionsProvider())
    var cityKey: String?

    init() {}

    init(cityKey: String?) {
        self.cityKey = cityKey
    }
}
