//
//  ContentView.swift
//  VWeather
//
//  首页：展示所选城市的天气 + 太阳/月亮信息列表。
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

    var body: some View {
        NavigationStack {
            Group {
                if let city = selectedCity {
                    weatherList(city: city)
                } else if locating {
                    ProgressView("定位中…")
                } else if let error = locationError {
                    locationErrorView(error)
                } else {
                    ContentUnavailableView("暂无城市",
                                           systemImage: "location.slash",
                                           description: Text("点击左上角添加城市"))
                }
            }
            .navigationTitle(selectedCity?.displayName ?? "天气")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCityList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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

    // MARK: - 天气 + 日月列表

    @ViewBuilder
    private func weatherList(city: CityModel) -> some View {
        let w = snapshot?.weather
        let sun = snapshot?.sun
        let moon = snapshot?.moon
        let sup = snapshot?.supplement
        List {
            // 头部概览
            Section {
                VStack(spacing: 6) {
                    if let symbol = w?.symbol, !symbol.isEmpty {
                        Image(systemName: symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 44))
                    }
                    Text(tempText(w?.temperature))
                        .font(.system(size: 56, weight: .thin))
                    Text(w?.conditionText ?? "--")
                        .foregroundStyle(.secondary)
                    if let high = w?.highTemperature, let low = w?.lowTemperature {
                        Text("最高 \(intText(high)) · 最低 \(intText(low))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // 气象预警：时效性最强，放在最前
            if let alerts = sup?.alerts, !alerts.isEmpty {
                Section("气象预警") {
                    ForEach(alerts) { alert in
                        NavigationLink {
                            alertDetail(alert)
                        } label: {
                            alertRow(alert)
                        }
                    }
                }
            }

            // 分钟级降水：两小时内要不要带伞，比其它补充数据都急，故紧跟预警
            if let minutely = sup?.minutely {
                MinutelyPrecipSection(minutely: minutely)
            }

            // 空气质量
            if let air = sup?.air {
                Section("空气质量") {
                    airHeader(air)
                    infoRow("首要污染物", air.primary ?? "无")
                    if let v = air.pm2p5 { infoRow("PM2.5", concentrationText(v)) }
                    if let v = air.pm10 { infoRow("PM10", concentrationText(v)) }
                    if let v = air.o3 { infoRow("臭氧 O₃", concentrationText(v)) }
                    if let v = air.no2 { infoRow("二氧化氮 NO₂", concentrationText(v)) }
                    if let v = air.so2 { infoRow("二氧化硫 SO₂", concentrationText(v)) }
                    // CO 单位是 mg/m³，与其它污染物不同
                    if let v = air.co { infoRow("一氧化碳 CO", String(format: "%.1f mg/m³", v)) }
                    if let advice = air.advice, !advice.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("健康建议").font(.subheadline)
                            Text(advice)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // 未来 24 小时 / 3 天 AQI（WeatherKit 均无此数据）
                let hours = sup?.airHourly ?? []
                let days = sup?.airDaily ?? []
                if !hours.isEmpty || !days.isEmpty {
                    Section("空气质量预报") {
                        if !hours.isEmpty {
                            AirHourlyChart(hours: hours)
                        }
                        ForEach(days) { day in
                            airForecastRow(dayText(day.startTime), day)
                        }
                    }
                }
            }

            // 生活指数
            if let indices = sup?.indices {
                LifeIndicesSection(indices: indices)
            }

            // 天气详情
            Section("天气") {
                infoRow("体感温度", tempText(w?.apparentTemperature))
                infoRow("湿度", percentText(w?.humidity))
                infoRow("风速", w?.windSpeed.map { String(format: "%.1f m/s", $0) } ?? "--")
                infoRow("风向", w?.windDirection ?? "--")
                infoRow("气压", w?.pressure.map { String(format: "%.0f hPa", $0) } ?? "--")
                infoRow("降雨概率", w?.precipitationChance.map { "\(Int($0 * 100))%" } ?? "--")
                infoRow("紫外线", w?.uv.map { "\($0)" } ?? "--")
            }

            // 太阳
            Section("太阳") {
                infoRow("日出", VHLSunMoonManager.timeString(sun?.sunrise))
                infoRow("日落", VHLSunMoonManager.timeString(sun?.sunset))
                infoRow("正午", VHLSunMoonManager.timeString(sun?.solarNoon))
                infoRow("子夜", VHLSunMoonManager.timeString(sun?.solarMidnight))
                infoRow("晨间蓝调", rangeText(sun?.morningBlueHourStart, sun?.morningBlueHourEnd))
                infoRow("暮间蓝调", rangeText(sun?.eveningBlueHourStart, sun?.eveningBlueHourEnd))
                infoRow("晨间黄金时刻", rangeText(sun?.morningGoldenHourStart, sun?.morningGoldenHourEnd))
                infoRow("暮间黄金时刻", rangeText(sun?.eveningGoldenHourStart, sun?.eveningGoldenHourEnd))
                infoRow("民用晨昏", rangeText(sun?.civilDawn, sun?.civilDusk))
                infoRow("航海晨昏", rangeText(sun?.nauticalDawn, sun?.nauticalDusk))
                infoRow("天文晨昏", rangeText(sun?.astronomicalDawn, sun?.astronomicalDusk))
                infoRow("白昼时长", durationText(sun?.daylightDuration))
                infoRow("夜晚时长", durationText(sun?.nightDuration))
                infoRow("太阳方位角", angleText(sun?.azimuth))
                infoRow("太阳高度角", angleText(sun?.altitude))
                infoRow("日出方位", angleText(sun?.sunriseAzimuth))
                infoRow("日落方位", angleText(sun?.sunsetAzimuth))
            }

            // 月亮
            Section("月亮") {
                infoRow("月相", "\(moon?.phaseEmoji ?? "") \(moon?.phaseName ?? "--")")
                infoRow("照度", (moon?.illumination).map { "\(Int($0))%" } ?? "--")
                infoRow("月龄", (moon?.ageInDays).map { String(format: "%.1f 天", $0) } ?? "--")
                infoRow("月亮星座", moon?.signName ?? "--")
                infoRow("月升", VHLSunMoonManager.timeString(moon?.moonrise))
                infoRow("月落", VHLSunMoonManager.timeString(moon?.moonset))
                infoRow("月升方位", angleText(moon?.moonriseAzimuth))
                infoRow("月落方位", angleText(moon?.moonsetAzimuth))
                infoRow("月亮方位角", angleText(moon?.azimuth))
                infoRow("月亮高度角", angleText(moon?.altitude))
                infoRow("距下次满月", daysText(moon?.daysToNextFullMoon))
                infoRow("距下次新月", daysText(moon?.daysToNextNewMoon))
            }

            Section {
                if let date = snapshot?.updateDate {
                    Text("更新时间：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 后台是分项失败的：某项失败时对应 Section 直接消失，
                // 不说一声用户无从判断是「没有这项数据」还是「拉取失败」。
                let failed = failedSupplementNames(sup)
                if !failed.isEmpty {
                    Label("\(failed.joined(separator: "、"))暂时获取失败，下拉可重试",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await refresh(city: city, force: true) }   // 下拉刷新强制请求，绕过节流
    }

    /// 后台 `errors` 里非 nil 的项即为失败项，映射成中文名用于提示。
    /// 后台保证六个 key 都在，成功时值为 nil。
    private func failedSupplementNames(_ sup: WeatherSupplement?) -> [String] {
        guard let errors = sup?.errors else { return [] }
        let names = ["air": "空气质量",
                     "airDaily": "空气质量预报",
                     "airHourly": "逐小时空气质量",
                     "indices": "生活指数",
                     "minutely": "分钟级降水",
                     "alerts": "气象预警"]
        // 按固定顺序输出，避免字典顺序导致提示文案每次刷新都在跳
        return ["air", "airDaily", "airHourly", "minutely", "indices", "alerts"]
            .filter { (errors[$0] ?? nil) != nil }
            .compactMap { names[$0] }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    // MARK: - 空气质量

    /// AQI 数值 + 等级，用上游给的等级色
    private func airHeader(_ air: AirQuality) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(QWeatherFormat.color(air.color) ?? .secondary)
                    .frame(width: 46, height: 46)
                Text(air.aqiDisplay ?? "--")     // 展示用 aqiDisplay：可能是 ">300" 这类非数值
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(air.category ?? "--").font(.headline)
                if let effect = air.effect, !effect.isEmpty {
                    Text(effect)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func concentrationText(_ value: Double) -> String {
        String(format: "%.0f μg/m³", value)
    }

    /// AQI 预报行：日期 + 色块 AQI + 等级
    private func airForecastRow(_ title: String, _ air: AirQuality) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(air.category ?? "--")
                .foregroundStyle(.secondary)
            Text(air.aqiDisplay ?? "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(minWidth: 34)
                .padding(.vertical, 3)
                .background(QWeatherFormat.color(air.color) ?? .secondary, in: Capsule())
        }
    }

    /// 预报的 startTime 是该「当地日」零点对应的 UTC 时刻，
    /// 如 "2026-07-14T16:00Z" 即北京时间 07-15 00:00 —— 直接按本地时区取日期即可。
    private func dayText(_ raw: String?) -> String {
        guard let date = QWeatherFormat.date(raw) else { return raw ?? "--" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - 气象预警

    /// 预警列表行。
    /// 合规：《气象预报发布与传播管理办法》第九条要求注明发布单位与发布时间，
    /// 故 sender/pubTime 直接展示在行上，不必点进详情才能看到。
    private func alertRow(_ alert: WeatherAlertInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(alertColor(alert))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title ?? alert.type ?? "预警")
                    .font(.subheadline)
                    .lineLimit(2)
                if let sender = alert.sender {
                    Text("\(sender) · \(QWeatherFormat.timeText(alert.pubTime))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 预警详情。`text` 为上游原文，按合规要求原样展示，不得改写或摘要。
    private func alertDetail(_ alert: WeatherAlertInfo) -> some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(alertColor(alert))
                        .frame(width: 12, height: 12)
                    Text(alert.title ?? alert.type ?? "预警")
                        .font(.headline)
                }
                .padding(.vertical, 2)
            }

            Section("预警内容") {
                // 原文，不做任何加工
                Text(alert.text ?? "--")
                    .font(.callout)
                    .padding(.vertical, 2)
            }

            if let instruction = alert.instruction, !instruction.isEmpty {
                Section("防御指引") {
                    Text(instruction)
                        .font(.callout)
                        .padding(.vertical, 2)
                }
            }

            Section("发布信息") {
                // 合规必需：发布单位 + 发布时间
                infoRow("发布单位", alert.sender ?? "--")
                infoRow("发布时间", QWeatherFormat.timeText(alert.pubTime))
                infoRow("预警类型", alert.type ?? "--")
                if let start = alert.startTime {
                    infoRow("生效时间", QWeatherFormat.timeText(start))
                }
                if let end = alert.endTime {
                    infoRow("失效时间", QWeatherFormat.timeText(end))
                }
            }
        }
        .navigationTitle("气象预警")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func alertColor(_ alert: WeatherAlertInfo) -> Color {
        // 优先用上游给的精确颜色；取不到再按色名兜底
        if let color = QWeatherFormat.color(alert.colorRGBA) { return color }
        switch alert.severityColor?.lowercased() {
        case "blue":   return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        case "white":  return .gray
        default:       return .secondary
        }
    }

    // MARK: - 定位失败提示

    @ViewBuilder
    private func locationErrorView(_ error: VHLLocationError) -> some View {
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
    private func intText(_ value: Double) -> String {
        AppSettings.shared.tempText(value)
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
}

#Preview {
    ContentView()
}
