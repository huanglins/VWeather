//  WeatherMainView.swift
//  VWeather
//
//  首页主要天气展示面板（已从 ContentView 抽离）。
//

import SwiftUI

// MARK: - 天气主视图

/// 首页天气详情主面板：包含逐小时、多天、空气质量、生活指数等全部 Section。
struct WeatherMainView: View {
    let city: CityModel
    let snapshot: CityWeatherSnapshot?

    private var isNight: Bool { snapshot?.sun?.isNight ?? false }

    private var report: WeatherReport? { snapshot?.weather }
    private var now: WeatherNow? { report?.now }
    private var today: WeatherDay? { report?.daily?.first }
    private var sun: VHLSunInfo? { snapshot?.sun }
    private var moon: VHLMoonInfo? { snapshot?.moon }

    var body: some View {

        ScrollView {
            VStack(spacing: 14) {
                header(now: now, today: today)

                // 气象预警：时效性最强，紧跟头部
                if let alerts = report?.alerts, !alerts.isEmpty {
                    WeatherAlertsView(alerts: alerts,
                                      condition: now?.condition ?? .unknown,
                                      isNight: isNight)
                }

                // 三连指标：一眼能看完的三个数
                WeatherSummaryChipsView(now: now, air: report?.air)

                // 小时天气
                if let hours = report?.hourly, !hours.isEmpty, let report {
                    HourlyForecastSection(hours: hours, report: report)
                }
                // 天气预报
                if let days = report?.daily, !days.isEmpty {
                    DailyForecastSection(days: days)
                }

                // 分钟级降水：两小时内要不要带伞
                if let minutely = report?.minutely {
                    MinutelyPrecipSection(minutely: minutely)
                }

                // 空气质量
                if let air = report?.air {
                    WeatherAirQualityView(city: city,
                                          air: air,
                                          initialHourly: report?.airHourly ?? [],
                                          daily: report?.airDaily ?? [])
                        .id(city.cityKey)
                }

                // 生活指数
                if let indices = report?.indices, !indices.isEmpty {
                    LifeIndicesSection(indices: indices)
                }

                // 天气指标网格
                WeatherMetricGridView(now: now, today: today, sun: sun, moon: moon,
                                      minutely: report?.minutely)

                WeatherAstronomyDetailsView(sun: sun, moon: moon)

                footer(report: report)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - 头部

    private func header(now: WeatherNow?, today: WeatherDay?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tempText(now?.temperature))
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(now?.conditionText ?? "--")
                        .font(VWDesign.Typography.subheadMedium)
                        .foregroundStyle(.white.opacity(0.9))
                    
                    if let high = today?.tempMax, let low = today?.tempMin {
                        Text("|")
                            .font(VWDesign.Typography.subheadMedium)
                            .foregroundStyle(.white.opacity(0.35))
                        Label(tempText(low), systemImage: "arrowtriangle.down.fill")
                            .font(VWDesign.Typography.subheadMedium)
                            .foregroundStyle(.white.opacity(0.8))
                        Label(tempText(high), systemImage: "arrowtriangle.up.fill")
                            .font(VWDesign.Typography.subheadMedium)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .font(.subheadline)
                .labelStyle(TightLabelStyle())
            }
            Spacer()
            Image(systemName: (now?.condition ?? .unknown).symbol(isNight: isNight))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 56))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.top, 6)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - 页脚

    @ViewBuilder
    private func footer(report: WeatherReport?) -> some View {
        VStack(spacing: 6) {
            if let date = snapshot?.updateDate {
                Text("更新时间：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(VWDesign.Typography.footnote)
            }
            // 后台是分项失败的：某项失败时对应卡片直接消失，
            // 不说一声用户无从判断是「没有这项数据」还是「拉取失败」。
            let failed = failedResourceNames(report)
            if !failed.isEmpty {
                Label("\(failed.joined(separator: "、"))暂时获取失败，请稍后重试",
                      systemImage: "exclamationmark.triangle")
                .font(VWDesign.Typography.footnote)
            }
            // 兜底数据源的能力比主数据源窄：空气质量与生活指数整块消失。
            // 同样要说一声，否则看起来像 App 坏了。
            if report?.source == .weatherKit {
                Label("Apple 天气",
                      systemImage: "arrow.triangle.2.circlepath")
                .font(VWDesign.Typography.footnote)
            }
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.55))
        .padding(.top, 4)
    }

    /// 后台 `errors` 里非 nil 的项即为失败项，映射成中文名用于提示。
    ///
    /// ⚠️ 键必须用后台的**资源名**（连字符形式）。此前这里写的是 airDaily /
    /// airHourly 的驼峰形式，而后台给的是 "air-daily" / "air-hourly" ——
    /// 永远匹配不上，那两项失败了也不会提示。驼峰只存在于 Swift 侧的
    /// CodingKeys 映射后，errors 字典是原样的 JSON 键。
    private func failedResourceNames(_ report: WeatherReport?) -> [String] {
        guard let errors = report?.errors else { return [] }
        let names = ["now": "实时天气",
                     "daily": "多天预报",
                     "hourly": "逐小时预报",
                     "air": "空气质量",
                     "air-daily": "空气质量预报",
                     "air-hourly": "逐小时空气质量",
                     "indices": "生活指数",
                     "minutely": "分钟级降水",
                     "alerts": "气象预警"]
        // 按固定顺序输出，避免字典顺序导致提示文案每次刷新都在跳
        return ["now", "daily", "hourly", "air", "air-daily", "air-hourly",
                "minutely", "indices", "alerts"]
            .filter { (errors[$0] ?? nil) != nil }
            .compactMap { names[$0] }
    }

    // MARK: - 格式化

    private func tempText(_ value: Double?) -> String {
        AppSettings.shared.tempText(value)   // 按当前温度单位（°C/°F）格式化
    }
}

// MARK: - 小组件

/// Label 默认的图标与文字间距在小字号下偏大，这里收紧
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}
