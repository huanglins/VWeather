//
//  WeatherLifeIndicesView.swift
//  VWeather
//
//  生活指数卡片、完整列表与单项详情。
//

import SwiftUI

// MARK: - 生活指数

/// 生活指数（运动 / 洗车 / 穿衣 …，实测 16 项）。
/// 整个 grid 只包一个 NavigationLink，点任意卡片 push 一次到全部指数列表。
struct LifeIndicesSection: View {
    let indices: [LifeIndex]

    var body: some View {
        if !indices.isEmpty {
            WeatherCard(title: "生活指数", systemImage: "list.bullet.rectangle") {
                // 整个 grid 只包一个 NavigationLink，避免 16 个 Link 各 push 一次
                NavigationLink {
                    LifeIndicesFullView(indices: indices)
                } label: {
                    gridRows
                        // 每张小卡自带底色、点得动，但卡与卡之间的间距是透明的，
                        // 以及奇数项那个占位格 —— 点在那些地方没反应。
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 两列网格：用 VStack 包裹 HStack 分行，List 能正确计算完整高度
    private var gridRows: some View {
        let rows = stride(from: 0, to: indices.count, by: 2).map {
            Array(indices[$0..<min($0 + 2, indices.count)])
        }
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(rows[i]) { index in
                        card(index)
                    }
                    // 奇数项补空占位，保持对齐
                    if rows[i].count == 1 {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }

    private func card(_ index: LifeIndex) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: index.type))
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortName(type: index.type, name: index.name))
                    .font(VWDesign.Typography.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                Text(index.category ?? "--")
                    .font(VWDesign.Typography.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // 定高：名称一行、等级一行，两列卡片才对得齐（否则长名换行会把整排顶歪）
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 卡片窄，「运动指数」去掉后缀只留「运动」，给 category 留出空间。
    /// 个别名称去掉后缀仍过长（如「空气污染扩散条件」），单独给短名，
    /// 否则只能截断成「空气污染扩散条…」。按 type 匹配，上游改文案也不影响。
    private static func shortName(type: String?, name: String?) -> String {
        if type == "10" { return "污染扩散" }
        guard let name else { return "--" }
        guard name.count > 2, name.hasSuffix("指数") else { return name }
        return String(name.dropLast(2))
    }

    /// 和风生活指数 type 编码 → SF Symbol。
    /// 用 type（稳定编码）而非 name 匹配，避免上游改文案就失效。
    static func symbol(for type: String?) -> String {
        switch type {
        case "1":  return "figure.run"                  // 运动
        case "2":  return "car.fill"                    // 洗车
        case "3":  return "tshirt.fill"                 // 穿衣
        case "4":  return "fish.fill"                   // 钓鱼
        case "5":  return "sun.max.fill"                // 紫外线
        case "6":  return "airplane"                    // 旅游
        case "7":  return "allergens"                   // 过敏
        case "8":  return "thermometer.medium"          // 舒适度
        case "9":  return "cross.case.fill"             // 感冒
        case "10": return "wind"                        // 空气污染扩散条件
        case "11": return "snowflake"                   // 空调开启
        case "12": return "sunglasses.fill"             // 太阳镜
        case "13": return "paintbrush.fill"             // 化妆
        case "14": return "sun.horizon.fill"            // 晾晒
        case "15": return "car.2.fill"                  // 交通
        case "16": return "umbrella.fill"               // 防晒
        default:   return "sparkles"
        }
    }
}

/// 全部生活指数列表页：点击任何生活指数卡片时 push 进入，展示所有指数及完整建议。
struct LifeIndicesFullView: View {
    let indices: [LifeIndex]

    var body: some View {
        List {
            ForEach(indices) { index in
                Section {
                    if let text = index.text, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .padding(.vertical, 2)
                    } else {
                        Text("暂无建议")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: LifeIndicesSection.symbol(for: index.type))
                            .foregroundStyle(.tint)
                        Text(index.name ?? "--")
                        Spacer()
                        Text(index.category ?? "--")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("生活指数")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 生活指数详情：完整建议文本（保留，供需要单独查看某一项的场合使用）
struct LifeIndexDetailView: View {
    let index: LifeIndex

    var body: some View {
        List {
            Section {
                HStack {
                    Text("等级")
                    Spacer()
                    Text(index.category ?? "--").foregroundStyle(.secondary)
                }
                if let date = index.date {
                    HStack {
                        Text("日期")
                        Spacer()
                        Text(date).foregroundStyle(.secondary)
                    }
                }
            }
            if let text = index.text, !text.isEmpty {
                Section("建议") {
                    Text(text)
                        .font(.callout)
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(index.name ?? "生活指数")
        .navigationBarTitleDisplayMode(.inline)
    }
}
