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

            if let date = snapshot?.updateDate {
                Section {
                    Text("更新时间：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await refresh(city: city, force: true) }   // 下拉刷新强制请求，绕过节流
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
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
