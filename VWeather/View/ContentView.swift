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
    /// 逐小时空气质量：不在常驻请求里，用户点开才按需取（省上游）。
    @State private var airHourly: [AirQuality]?
    @State private var airHourlyLoading = false

    /// 当前天况与昼夜 —— 决定背景色调
    private var condition: VWCondition { snapshot?.weather?.now?.condition ?? .unknown }
    private var isNight: Bool { snapshot?.sun?.isNight ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackground(condition: condition, isNight: isNight)

                Group {
                    if let city = selectedCity {
                        weatherScroll(city: city)
                    } else if locating {
                        ProgressView("定位中…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    } else if let error = locationError {
                        locationErrorView(error)
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
    }

    // MARK: - 主体

    @ViewBuilder
    private func weatherScroll(city: CityModel) -> some View {
        let sun = snapshot?.sun
        let moon = snapshot?.moon
        let report = snapshot?.weather
        let now = report?.now
        let today = report?.daily?.first

        ScrollView {
            VStack(spacing: 14) {
                header(now: now, today: today)

                // 气象预警：时效性最强，紧跟头部
                if let alerts = report?.alerts, !alerts.isEmpty {
                    alertsCard(alerts)
                }

                // 三连指标：一眼能看完的三个数
                summaryChips(now: now, air: report?.air)

                if let hours = report?.hourly, !hours.isEmpty, let report {
                    HourlyForecastSection(hours: hours, report: report)
                }

                if let days = report?.daily, !days.isEmpty {
                    DailyForecastSection(days: days)
                }

                // 分钟级降水：两小时内要不要带伞
                if let minutely = report?.minutely {
                    MinutelyPrecipSection(minutely: minutely)
                }

                if let air = report?.air {
                    airCard(air)
                    // 逐小时优先用按需加载到的；report 里默认不含 air-hourly（已移出常驻请求）
                    let airHours = airHourly ?? report?.airHourly ?? []
                    let airDays = report?.airDaily ?? []
                    if !airHours.isEmpty || !airDays.isEmpty {
                        airForecastCard(hours: airHours, days: airDays)
                    }
                }

                if let indices = report?.indices, !indices.isEmpty {
                    LifeIndicesSection(indices: indices)
                }

                metricGrid(now: now, today: today, sun: sun, moon: moon,
                           minutely: report?.minutely)

                astronomyCards(sun: sun, moon: moon)

                footer(report: report)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await refresh(city: city, force: true) }   // 下拉刷新强制请求，绕过节流
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
                        .foregroundStyle(.white.opacity(0.9))
                    if let high = today?.tempMax, let low = today?.tempMin {
                        Text("|").foregroundStyle(.white.opacity(0.35))
                        Label(tempText(low), systemImage: "arrowtriangle.down.fill")
                            .foregroundStyle(.white.opacity(0.8))
                        Label(tempText(high), systemImage: "arrowtriangle.up.fill")
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

    // MARK: - 三连指标

    private func summaryChips(now: WeatherNow?, air: AirQuality?) -> some View {
        HStack(spacing: 10) {
            chip("体感温度", "thermometer.medium", tempText(now?.feelsLike))
            // 空气质量只有主数据源有 —— WeatherKit 兜底时这格会显示 "--"，
            // 而不是让整行塌掉，避免布局在两个数据源之间跳来跳去
            chip("空气质量", "aqi.medium", air?.category ?? "--")
            chip("湿度", "humidity", now?.humidity.map { "\(Int($0))%" } ?? "--")
        }
    }

    private func chip(_ title: String, _ icon: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(0.16), lineWidth: 0.5))
    }

    // MARK: - 指标网格

    @ViewBuilder
    private func metricGrid(now: WeatherNow?, today: WeatherDay?,
                            sun: VHLSunInfo?, moon: VHLMoonInfo?,
                            minutely: MinutelyPrecip?) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)], spacing: 14) {
            // 日落 + 日出（日月是本地算的，天气源挂了也有）
            MetricCard(title: "日落", systemImage: "sunset",
                       footnote: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    MetricValue(value: VHLSunMoonManager.timeString(sun?.sunset))
                    SunArc(sun: sun)
                        .frame(height: 44)
                    HStack {
                        Text("日出").font(.caption).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(VHLSunMoonManager.timeString(sun?.sunrise))
                            .font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }

            MetricCard(title: "云量", systemImage: "cloud",
                       footnote: cloudAdvice(now?.cloudCover)) {
                MetricValue(value: now?.cloudCover.map { "\(Int($0))%" } ?? "--")
            }

            // 标题写「今日最高」而不是「紫外线」：这个值来自逐日预报的 uvIndexMax，
            // 不是此刻的实测 —— 主数据源的实时天气压根不含 UV。
            // 叫「紫外线」会让人以为是当前值，晚上看到「极高」就很莫名。
            MetricCard(title: "今日紫外线最高", systemImage: "sun.max",
                       footnote: uvAdvice(today?.uvIndexMax)) {
                MetricValue(value: today?.uvIndexMax.map { String(format: "%.0f", $0) } ?? "--",
                            caption: uvLevel(today?.uvIndexMax))
            }

            MetricCard(title: "风", systemImage: "wind", footnote: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    MetricValue(value: beaufort(now?.windSpeed).map { "\($0)" } ?? "--",
                                unit: "级")
                    VStack(spacing: 3) {
                        metricLine("风速", now?.windSpeed.map { String(format: "%.0f km/h", $0) } ?? "--")
                        metricLine("风向", windText(now?.windDirectionText, now?.windDirection))
                    }
                }
            }

            MetricCard(title: "降水", systemImage: "drop",
                       footnote: minutely?.summary) {
                MetricValue(value: now?.precipitation.map { String(format: "%g", $0) } ?? "0",
                            unit: "mm")
            }

            MetricCard(title: "能见度", systemImage: "eye",
                       footnote: visibilityAdvice(now?.visibility)) {
                MetricValue(value: now?.visibility.map { String(format: "%.0f", $0) } ?? "--",
                            unit: "km")
            }

            MetricCard(title: "气压", systemImage: "gauge.with.dots.needle.bottom.50percent",
                       footnote: nil) {
                PressureGauge(value: now?.pressure)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
            }

            MetricCard(title: "月相", systemImage: "moon.stars",
                       footnote: moon?.phaseName) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(moon?.phaseEmoji ?? "--").font(.system(size: 30))
                    Text((moon?.illumination).map { "照度 \(Int($0))%" } ?? "--")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).font(.caption).foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - 预警

    private func alertsCard(_ alerts: [WeatherAlertInfo]) -> some View {
        WeatherCard {
            VStack(spacing: 10) {
                ForEach(alerts) { alert in
                    NavigationLink { alertDetail(alert) } label: {
                        alertRow(alert)
                            // 行里有 Spacer，那段是透明的、默认不参与 hit-test ——
                            // 只有文字和箭头点得动，中间一大片空白点不动。
                            // 以前首页是 List，行自带整行命中区；改成 ScrollView
                            // 之后这份"白送"就没了，得自己补。
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if alert.id != alerts.last?.id {
                        Divider().overlay(.white.opacity(0.15))
                    }
                }
            }
        }
    }

    /// 预警行。
    /// 合规：《气象预报发布与传播管理办法》第九条要求注明发布单位与发布时间，
    /// 故 sender/pubTime 直接展示在行上，不必点进详情才能看到。
    private func alertRow(_ alert: WeatherAlertInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(alertColor(alert))
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title ?? alert.type ?? "预警")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let sender = alert.sender {
                    Text("\(sender) · \(QWeatherFormat.timeText(alert.pubTime))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - 空气质量

    private func airCard(_ air: AirQuality) -> some View {
        WeatherCard(title: "空气质量", systemImage: "aqi.medium") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(QWeatherFormat.color(air.color) ?? .secondary)
                            .frame(width: 46, height: 46)
                        Text(air.aqiText ?? "--")   // 展示用 aqiText：可能是 ">300" 这类非数值
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.75))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(air.category ?? "--")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let effect = air.effect, !effect.isEmpty {
                            Text(effect)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }

                metricLine("首要污染物", air.primaryPollutant ?? "无")
                if let p = air.pollutants {
                    if let v = p.pm2p5 { metricLine("PM2.5", concentrationText(v)) }
                    if let v = p.pm10 { metricLine("PM10", concentrationText(v)) }
                    if let v = p.o3 { metricLine("臭氧 O₃", concentrationText(v)) }
                    if let v = p.no2 { metricLine("二氧化氮 NO₂", concentrationText(v)) }
                    if let v = p.so2 { metricLine("二氧化硫 SO₂", concentrationText(v)) }
                    // CO 单位是 mg/m³，与其它污染物不同
                    if let v = p.co { metricLine("一氧化碳 CO", String(format: "%.1f mg/m³", v)) }
                }
                if let advice = air.advice, !advice.isEmpty {
                    Text(advice)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func airForecastCard(hours: [AirQuality], days: [AirQuality]) -> some View {
        WeatherCard(title: "空气质量预报", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 10) {
                if !hours.isEmpty {
                    AirHourlyChart(hours: hours)
                } else {
                    // 逐小时 AQI 按需加载：不塞进每次刷新的常驻请求，点开才取
                    Button(action: loadAirHourly) {
                        HStack(spacing: 6) {
                            if airHourlyLoading {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                            }
                            Text(airHourlyLoading ? "加载中…" : "查看逐小时空气质量")
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(airHourlyLoading)
                }
                ForEach(days) { day in
                    airForecastRow(dayText(day.startTime), day)
                }
            }
        }
    }

    private func loadAirHourly() {
        guard let city = selectedCity, !airHourlyLoading else { return }
        airHourlyLoading = true
        Task {
            let hours = await CityWeatherManager.manager.loadAirHourly(for: city)
            await MainActor.run {
                airHourly = hours
                airHourlyLoading = false
            }
        }
    }

    /// AQI 预报行：日期 + 等级 + 色块 AQI
    private func airForecastRow(_ title: String, _ air: AirQuality) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(air.category ?? "--")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(air.aqiText ?? "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(minWidth: 34)
                .padding(.vertical, 3)
                .background(QWeatherFormat.color(air.color) ?? .secondary, in: Capsule())
        }
    }

    // MARK: - 日月详情
    //
    // 设计稿里没有这两块，但它们是已有功能（SunKit/MoonKit 算出来的天文数据）。
    // 收进可折叠卡片：默认不占地方，要看的时候点开。

    private func astronomyCards(sun: VHLSunInfo?, moon: VHLMoonInfo?) -> some View {
        VStack(spacing: 14) {
            WeatherCard {
                DisclosureGroup {
                    VStack(spacing: 4) {
                        metricLine("正午", VHLSunMoonManager.timeString(sun?.solarNoon))
                        metricLine("子夜", VHLSunMoonManager.timeString(sun?.solarMidnight))
                        metricLine("晨间蓝调", rangeText(sun?.morningBlueHourStart, sun?.morningBlueHourEnd))
                        metricLine("暮间蓝调", rangeText(sun?.eveningBlueHourStart, sun?.eveningBlueHourEnd))
                        metricLine("晨间黄金时刻", rangeText(sun?.morningGoldenHourStart, sun?.morningGoldenHourEnd))
                        metricLine("暮间黄金时刻", rangeText(sun?.eveningGoldenHourStart, sun?.eveningGoldenHourEnd))
                        metricLine("民用晨昏", rangeText(sun?.civilDawn, sun?.civilDusk))
                        metricLine("航海晨昏", rangeText(sun?.nauticalDawn, sun?.nauticalDusk))
                        metricLine("天文晨昏", rangeText(sun?.astronomicalDawn, sun?.astronomicalDusk))
                        metricLine("白昼时长", durationText(sun?.daylightDuration))
                        metricLine("夜晚时长", durationText(sun?.nightDuration))
                        metricLine("太阳方位角", angleText(sun?.azimuth))
                        metricLine("太阳高度角", angleText(sun?.altitude))
                        metricLine("日出方位", angleText(sun?.sunriseAzimuth))
                        metricLine("日落方位", angleText(sun?.sunsetAzimuth))
                    }
                    .padding(.top, 8)
                } label: {
                    Label("太阳详情", systemImage: "sun.max")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        // 标题与展开箭头之间是 Spacer，那段默认点不动。
                        // 撑满再给个 contentShape，整条标题栏才都能点。
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(.white.opacity(0.6))
            }

            WeatherCard {
                DisclosureGroup {
                    VStack(spacing: 4) {
                        metricLine("月龄", (moon?.ageInDays).map { String(format: "%.1f 天", $0) } ?? "--")
                        metricLine("月亮星座", moon?.signName ?? "--")
                        metricLine("月升", VHLSunMoonManager.timeString(moon?.moonrise))
                        metricLine("月落", VHLSunMoonManager.timeString(moon?.moonset))
                        metricLine("月升方位", angleText(moon?.moonriseAzimuth))
                        metricLine("月落方位", angleText(moon?.moonsetAzimuth))
                        metricLine("月亮方位角", angleText(moon?.azimuth))
                        metricLine("月亮高度角", angleText(moon?.altitude))
                        metricLine("距下次满月", daysText(moon?.daysToNextFullMoon))
                        metricLine("距下次新月", daysText(moon?.daysToNextNewMoon))
                    }
                    .padding(.top, 8)
                } label: {
                    Label("月亮详情", systemImage: "moon.stars")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        // 标题与展开箭头之间是 Spacer，那段默认点不动。
                        // 撑满再给个 contentShape，整条标题栏才都能点。
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .tint(.white.opacity(0.6))
            }
        }
    }

    // MARK: - 页脚

    @ViewBuilder
    private func footer(report: WeatherReport?) -> some View {
        VStack(spacing: 6) {
            if let date = snapshot?.updateDate {
                Text("更新时间：\(date.formatted(date: .abbreviated, time: .shortened))")
            }
            // 后台是分项失败的：某项失败时对应卡片直接消失，
            // 不说一声用户无从判断是「没有这项数据」还是「拉取失败」。
            let failed = failedResourceNames(report)
            if !failed.isEmpty {
                Label("\(failed.joined(separator: "、"))暂时获取失败，下拉可重试",
                      systemImage: "exclamationmark.triangle")
            }
            // 兜底数据源的能力比主数据源窄：空气质量与生活指数整块消失。
            // 同样要说一声，否则看起来像 App 坏了。
            if report?.source == .weatherKit {
                Label("主数据源不可用，当前为 Apple 天气兜底，部分数据缺失",
                      systemImage: "arrow.triangle.2.circlepath")
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

    // MARK: - 预警详情

    /// 预警详情。`text` 为上游原文，按合规要求原样展示，不得改写或摘要。
    private func alertDetail(_ alert: WeatherAlertInfo) -> some View {
        ZStack {
            WeatherBackground(condition: condition, isNight: isNight)
            ScrollView {
                VStack(spacing: 14) {
                    WeatherCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(alertColor(alert))
                            Text(alert.title ?? alert.type ?? "预警")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                    }

                    WeatherCard(title: "预警内容", systemImage: "doc.text") {
                        // 原文，不做任何加工
                        Text(alert.text ?? "--")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let instruction = alert.instruction, !instruction.isEmpty {
                        WeatherCard(title: "防御指引", systemImage: "shield") {
                            Text(instruction)
                                .font(.callout)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    WeatherCard(title: "发布信息", systemImage: "info.circle") {
                        VStack(spacing: 4) {
                            // 合规必需：发布单位 + 发布时间
                            metricLine("发布单位", alert.sender ?? "--")
                            metricLine("发布时间", QWeatherFormat.timeText(alert.pubTime))
                            metricLine("预警类型", alert.type ?? "--")
                            if let start = alert.startTime {
                                metricLine("生效时间", QWeatherFormat.timeText(start))
                            }
                            if let end = alert.endTime {
                                metricLine("失效时间", QWeatherFormat.timeText(end))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("气象预警")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func alertColor(_ alert: WeatherAlertInfo) -> Color {
        // 后台的中立 schema 只给色名（blue/yellow/orange/red），不给 rgba ——
        // 那是某一家数据源的专有表示，不属于中立层。
        switch alert.color?.lowercased() {
        case "blue":   return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        case "white":  return .gray
        default:       return .white
        }
    }

    // MARK: - 定位失败提示

    @ViewBuilder
    private func locationErrorView(_ error: VHLLocationError) -> some View {
        Group {
            switch error {
            case .denied:
                // 权限被拒绝：引导去「设置」开启
                ContentUnavailableView {
                    Label("无法获取位置", systemImage: "location.slash")
                } description: {
                    Text("请点击同意位置权限")
                } actions: {
                    Button("前往设置开启") { openAppSettings() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed:
                // 其它失败：可重试
                ContentUnavailableView {
                    Label("无法获取位置", systemImage: "location.slash")
                } description: {
                    Text("请检查定位服务后重试")
                } actions: {
                    Button("重试") { firstLoad() }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
        airHourly = nil        // 换城市：逐小时 AQI 需为新城重新按需加载
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

    // MARK: - 格式化

    private func tempText(_ value: Double?) -> String {
        AppSettings.shared.tempText(value)   // 按当前温度单位（°C/°F）格式化
    }
    private func percentText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "--"
    }
    /// 时间区间 "HH:mm - HH:mm"
    private func rangeText(_ start: Date?, _ end: Date?) -> String {
        "\(VHLSunMoonManager.timeString(start)) - \(VHLSunMoonManager.timeString(end))"
    }
    /// 角度 "N°"
    private func angleText(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "--"
    }
    /// 时长（秒）"x小时y分钟"
    private func durationText(_ seconds: Double?) -> String {
        seconds.map { VHLSunMoonManager.durationString($0) } ?? "--"
    }
    /// 天数 "N 天"
    private func daysText(_ value: Int?) -> String {
        value.map { "\($0) 天" } ?? "--"
    }
    private func concentrationText(_ value: Double) -> String {
        String(format: "%.0f μg/m³", value)
    }

    /// 风向。中立 schema 保证有角度，方位文字则未必——某些数据源只给角度
    /// （如 Apple），此时用角度换算出方位。
    private func windText(_ text: String?, _ degrees: Double?) -> String {
        if let text, !text.isEmpty { return text }
        guard let d = degrees else { return "--" }
        let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let i = Int((d.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i] + "风"
    }

    /// 预报的 startTime 是该「当地日」零点对应的 UTC 时刻，
    /// 如 "2026-07-14T16:00Z" 即北京时间 07-15 00:00 —— 直接按本地时区取日期即可。
    private func dayText(_ raw: String?) -> String {
        guard let date = QWeatherFormat.date(raw) else { return raw ?? "--" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - 派生指标
    //
    // 上游只给数值，等级与建议是本地按公开标准算的。
    // 没有把它们当成"数据源给的"来展示 —— 那会让人以为是气象台的结论。

    /// 蒲福风级。中立 schema 给的是 km/h，按标准风速区间换算。
    private func beaufort(_ kmh: Double?) -> Int? {
        guard let v = kmh else { return nil }
        let upper: [Double] = [1, 5, 11, 19, 28, 38, 49, 61, 74, 88, 102, 117]
        for (i, u) in upper.enumerated() where v < u { return i }
        return 12
    }

    private func uvLevel(_ uv: Double?) -> String? {
        guard let uv else { return nil }
        switch uv {
        case ..<3:  return "低"
        case ..<6:  return "中等"
        case ..<8:  return "高"
        case ..<11: return "很高"
        default:    return "极高"
        }
    }

    private func uvAdvice(_ uv: Double?) -> String? {
        guard let uv else { return nil }
        switch uv {
        case ..<3:  return "紫外线较弱，无需特别防护。"
        case ..<6:  return "紫外线中等，建议防晒。"
        case ..<8:  return "紫外线较强，注意遮阳。"
        default:    return "紫外线极强，尽量避免长时间户外活动。"
        }
    }

    private func cloudAdvice(_ cover: Double?) -> String? {
        guard let c = cover else { return nil }
        switch c {
        case ..<10: return "天空晴朗，少有云彩。"
        case ..<40: return "少云，阳光充足。"
        case ..<70: return "多云，时有遮蔽。"
        default:    return "云层密布，阳光稀少。"
        }
    }

    private func visibilityAdvice(_ km: Double?) -> String? {
        guard let v = km else { return nil }
        switch v {
        case ..<1:  return "能见度很低，出行注意安全。"
        case ..<5:  return "能见度较低，视野受限。"
        case ..<15: return "能见度一般。"
        default:    return "天空通透，视野极为开阔。"
        }
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

/// 日出到日落的弧线 + 当前太阳位置。
struct SunArc: View {
    let sun: VHLSunInfo?

    /// 太阳在「日出→日落」这段里走到哪了。
    ///
    /// **夜间返回 nil，而不是夹到 0 或 1。**
    /// 夹紧的话，23 点会把圆点停在弧线右端 —— 看着像「太阳正在落」，
    /// 其实早落了两三个小时。宁可不画点，也别画一个错的位置。
    private var progress: Double? {
        guard let sun else { return nil }
        let total = sun.sunset.timeIntervalSince(sun.sunrise)
        guard total > 0 else { return nil }
        let p = Date().timeIntervalSince(sun.sunrise) / total
        return (0...1).contains(p) ? p : nil
    }

    var body: some View {
        GeometryReader { geo in
            // 留出圆点半径 + 光晕，否则弧顶的点会被卡片裁掉
            let inset: CGFloat = 6
            let w = geo.size.width - inset * 2
            let h = geo.size.height - inset * 2

            ZStack(alignment: .topLeading) {
                // 整条弧：淡。夜里只剩它，本身就说明「今天这段已经走完」
                ArcPath(upTo: 1)
                    .stroke(.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                if let t = progress {
                    // 已走过的一段：亮。让「过了多少」一眼可见，
                    // 而不用去对比圆点和两端的距离
                    ArcPath(upTo: t)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.6), .white],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )

                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .shadow(color: .white.opacity(0.9), radius: 4)
                        .position(Self.point(t, w, h))
                }
            }
            .frame(width: w, height: h)
            .offset(x: inset, y: inset)
        }
    }

    /// 二次贝塞尔上 t 处的点。P0=(0,h) P2=(w,h)，控制点在正上方。
    ///
    /// 弧线与圆点都由它算，所以两者必然重合。
    /// 用 Shape 的 `.trim` 就不行 —— trim 按**弧长**取参，而圆点按 t 取参，
    /// 二次贝塞尔上这两者不是一回事，圆点会从亮段末端飘开。
    static func point(_ t: Double, _ w: CGFloat, _ h: CGFloat) -> CGPoint {
        let cx = w / 2, cy = -h * 0.9        // 控制点抬高，弧顶落在 ~0.05h
        let mt = 1 - t
        return CGPoint(x: 2 * mt * t * cx + t * t * w,
                       y: mt * mt * h + 2 * mt * t * cy + t * t * h)
    }
}

/// 弧线的前 `upTo` 段（按贝塞尔参数，不是弧长）。
private struct ArcPath: Shape {
    let upTo: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: SunArc.point(0, w, h))
        // 采样成折线：段数够多，视觉上与真曲线无异，
        // 却能和圆点共用同一套参数
        let steps = 48
        for i in 1...steps {
            path.addLine(to: SunArc.point(Double(i) / Double(steps) * upTo, w, h))
        }
        return path
    }
}

/// 气压表盘：刻度环 + 指针 + 中心读数。
///
/// 刻度是装饰，**指针角度才是数据**。区间取常见海平面气压 950–1050 hPa，
/// 超出就顶到两端 —— 台风天的极端低压不该让指针转到盘外去。
struct PressureGauge: View {
    let value: Double?

    private static let sweep: Double = 260        // 表盘张角
    private static let lo: Double = 950
    private static let hi: Double = 1050

    private var fraction: Double? {
        guard let v = value else { return nil }
        return min(max((v - Self.lo) / (Self.hi - Self.lo), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // 刻度：40 根短线沿盘面排开
                ForEach(0..<41, id: \.self) { i in
                    let t = Double(i) / 40
                    Capsule()
                        .fill(.white.opacity(i % 10 == 0 ? 0.7 : 0.28))
                        .frame(width: 1.2, height: i % 10 == 0 ? 7 : 4)
                        .offset(y: -side / 2 + 5)
                        .rotationEffect(.degrees(-Self.sweep / 2 + t * Self.sweep))
                }
                if let f = fraction {
                    // 读数标记落在**刻度环上**，不用从圆心出发的指针 ——
                    // 指针会横穿中心的数字，两者叠在一起谁也看不清。
                    Capsule()
                        .fill(.white)
                        .frame(width: 2.5, height: 12)
                        .offset(y: -side / 2 + 6)
                        .rotationEffect(.degrees(-Self.sweep / 2 + f * Self.sweep))
                }
                VStack(spacing: 0) {
                    Text(value.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("hPa")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
}
