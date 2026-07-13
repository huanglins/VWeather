//
//  WeatherWidget.swift
//  WeatherWidget
//
//  Created by vincent on 2024/8/19.
//

import WidgetKit
import SwiftUI
import SwiftDate

let WeatherColors = [
    ["#888B8D","#000033",],
    ["#BDC3C7","#2C3E50",],
    ["#19547B","#FF7300",],
    ["#19547B","#FFA200",],
    ["#3A7FAD","#FFD79B",],
    ["#2CB929","#F9EB6D",],
    ["#D9F285","#FFA200",],
    ["#EBE9E5","#FF7300",],
    ["#544A7D","#FF4500",],
    ["#4E54C7","#F7DC8B",],
    ["#4E54C7","#FFFFEF",],
    ["#4E54C7","#8EFAFO",],
]

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        _ = DBManager.manager
        completion(cachedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        SwiftDate.defaultRegion = .current
        _ = DBManager.manager   // widget 进程初始化共享 DB

        // widget 也请求天气：拉取当前选中城市的最新数据（受 30 分钟节流，与主 App 共享缓存）
        Task {
            let base = await loadEntry()

            let interval = 30
            let startDate = Date()
            let entries: [SimpleEntry] = (0 ..< 48).map { offset in
                let entryDate = Calendar.current.date(byAdding: .minute, value: offset * interval, to: startDate)!
                return SimpleEntry(date: entryDate,
                                   cityName: base.cityName,
                                   temperature: base.temperature,
                                   conditionText: base.conditionText,
                                   symbol: base.symbol)
            }
            let afterDate = startDate + interval.minutes
            completion(Timeline(entries: entries, policy: .after(afterDate)))
        }
    }

    /// 请求并组装当前选中城市的天气 entry
    private func loadEntry() async -> SimpleEntry {
        guard let city = CityWeatherManager.manager.selectedCity() else {
            return SimpleEntry(date: Date())
        }
        let snap = await CityWeatherManager.manager.refresh(for: city)
        return entry(city: city, weather: snap?.weather)
    }

    /// 仅读缓存（用于快照占位）
    private func cachedEntry() -> SimpleEntry {
        guard let city = CityWeatherManager.manager.selectedCity() else {
            return SimpleEntry(date: Date())
        }
        return entry(city: city, weather: CityWeatherManager.manager.cachedSnapshot(for: city)?.weather)
    }

    private func entry(city: CityModel, weather: WeatherDisplay?) -> SimpleEntry {
        SimpleEntry(date: Date(),
                    cityName: city.displayName,
                    temperature: weather?.temperature,
                    conditionText: weather?.conditionText ?? "",
                    symbol: weather?.symbol ?? "")
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    var cityName: String = ""
    var temperature: Double? = nil
    var conditionText: String = ""
    var symbol: String = ""
}

struct WeatherWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        let date = Date()
        let hour = date.hour / 2
        let colors = WeatherColors[hour % WeatherColors.count].map{ Color(hex: $0) }
        // let gradient = Gradient(colors: colors)

        GeometryReader { geometry in
            ZStack {
                /**
                背景
                 Gradient Map
                 黑色遮罩过渡：70% +Hue
                 黑色遮罩过渡：15/30/45/60% Black Saturation
                 */
                ZStack {
                    Image("weather_bg")
                        .resizable().scaledToFill()
//                        .foregroundStyle(.linearGradient(gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(alignment: .topLeading) {
                            LinearGradient(colors: colors,
                                           startPoint: UnitPoint(x: 0.0, y: 0.0),
                                           endPoint: UnitPoint(x: 1, y: 1.0)
//                            LinearGradient(
//                                stops: [
//                                    Gradient.Stop(color: colors[0], location: 0),
//                                    Gradient.Stop(color: colors[1], location: 1),
//                                ],
//                                startPoint: UnitPoint(x: 0.0, y: 0.0),
//                                endPoint: UnitPoint(x: 1, y: 1.0)
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .opacity(0.7)
                        }
                        .hueRotation(.degrees(0.7)) // hue 应用色调旋转
                    
                    // colors.first.blendMode(.color)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                // 3. 黑色遮罩过渡 左亮右暗
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: .black.opacity(0.15), location: 0),
                            Gradient.Stop(color: .black.opacity(0.3), location: 0.3),
                            Gradient.Stop(color: .black.opacity(0.45), location: 0.6),
                            Gradient.Stop(color: .black.opacity(0.6), location: 1),
                        ],
                        startPoint: UnitPoint(x: 0, y: 0),
                        endPoint: UnitPoint(x: 1, y: 1)
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // 天气面板信息
                ZStack(alignment: .bottomLeading, content: {
                    VStack {
                        Spacer(minLength: 0)
                        #if DEBUG
                        HStack {
                            Text(Calendar.current.startOfDay(for: entry.date), style: .timer)
                                .font(FusionPixelRegular(14))
                                .multilineTextAlignment(.leading)
                                .foregroundColor(Color(hex: "#EEB0D8"))
                            Spacer()
                        }
                        #endif
                        WeatherInfoPanel(entry: entry)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct WeatherInfoPanel: View {
    var entry: SimpleEntry

    var body: some View {
        let date = Date()
        let shortWeekdaySymbols = Calendar.current.veryShortWeekdaySymbols
        let shortWeekdaySymbol = shortWeekdaySymbols[max(date.weekday - 1, 0) % 7]

        let area = entry.cityName
        let temperature = lroundf(Float(entry.temperature ?? 0.0))
        let condition = entry.conditionText
        
        // 天气信息
        let textColor = Color(hex: "#593F40")
        VStack(alignment: .leading, spacing: 4) {
            
            Text("\(date.month)月\(date.day)日 (\(shortWeekdaySymbol))")
                .foregroundColor(textColor)
                .font(FusionPixelRegular(13))
            HStack {
                Text("\(area) \(temperature)℃ \(condition)")
                    .foregroundColor(textColor)
                    .font(FusionPixelRegular(13))
                    .minimumScaleFactor(0.8)
                
                Spacer(minLength: 0)
            }
            
            let wDate = entry.date.formatted()
            Text("\(wDate)").foregroundColor(textColor)
                .font(FusionPixelRegular(10))
        }.padding(6).frame(height: 48, alignment: .leading).frame(maxWidth: 170).background(Color(hex: "#BDAD93"))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#423845").opacity(0.5), lineWidth: 2) // 边框
            )
            .shadow(color: Color(hex: "#413944").opacity(0.2), radius: 10, x: 0, y: 0) // 外阴影
            .padding(6) // 内边距，创建内阴影效果
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#A67A57")) // 内部填充颜色
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 0) // 内阴影
                    .clipShape(RoundedRectangle(cornerRadius: 14)) // 确保阴影不超出边界
            ).padding(1) // 内边距，创建内阴影效果
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color(hex: "#38434C").opacity(0.4)) // 内部填充颜色
                    .clipShape(RoundedRectangle(cornerRadius: 17)) // 确保阴影不超出边界
            )
    }
}

struct WeatherWidget: Widget {
    let kind: String = "WeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WeatherWidgetEntryView(entry: entry)
                .adoptableWidgetBackground(.clear)
        }
        .configurationDisplayName("天气组件")
        .description("我的天气组件")
        .adoptableWidgetContentMargin()
    }
}

#Preview(as: .systemSmall) {
    WeatherWidget()
} timeline: {
    SimpleEntry(date: .now)
    SimpleEntry(date: .now)
}
