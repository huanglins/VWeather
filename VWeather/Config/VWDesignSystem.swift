//
//  VWDesignSystem.swift
//  VWeather
//
//  设计系统：集中管理字体、颜色、间距、圆角等视觉 token。
//

import SwiftUI

// MARK: - 设计 Token

enum VWDesign {

    // MARK: 颜色

    enum Palette {
        // 文字层级
        static let primary = Color.white                           // 重要数字、主标题
        static let secondary = Color.white.opacity(0.65)           // 卡片标题、次要标签
        static let tertiary = Color.white.opacity(0.75)            // 补充信息、降水概率
        static let quaternary = Color.white.opacity(0.6)           // 脚注、次要描述
        static let strong = Color.white.opacity(0.9)               // 强调文字、高亮信息
        static let muted = Color.white.opacity(0.8)                // 天况文案、一般信息
        static let dim = Color.white.opacity(0.7)                  // 次要温度、辅助数字
        static let disabled = Color.white.opacity(0.55)            // 页脚、失效提示

        // 卡片组件
        static let cardFill = Color.white.opacity(0.14)            // 卡片底色
        static let cardStroke = Color.white.opacity(0.16)          // 卡片描边
        static let chipFill = Color.white.opacity(0.14)            // 指标块底色
        static let itemFill = Color.white.opacity(0.12)            // 生活指数卡片底色
        static let trackFill = Color.white.opacity(0.22)           // 温度条轨道
        static let labelIcon = Color.white.opacity(0.9)            // 图标强调色

        // 图表
        static let gridLine = Color.white.opacity(0.15)            // 网格线
        static let axisLabel = Color.white.opacity(0.6)            // 坐标轴标签
        static let shadow = Color.black.opacity(0.15)              // 阴影
        static let aqiText = Color.black.opacity(0.75)             // AQI 数值（色块上）

        // 天气图标：系统 SF Symbol 用 .multicolor 渲染模式，
        // 无需额外设色。以下供自定义图标使用。
        static let weatherIcon = Color.white
    }

    // MARK: 间距

    enum Spacing {
        /// 卡片水平内边距（标准）
        static let cardH: CGFloat = 14
        /// 卡片垂直内边距
        static let cardV: CGFloat = 14
        /// 卡片内部 VStack 元素间距
        static let cardStack: CGFloat = 12
        /// Section（卡片）之间的间距
        static let section: CGFloat = 14
        /// 网格列间距
        static let grid: CGFloat = 14
        /// 行内常规水平间距
        static let row: CGFloat = 10
        /// 行内紧凑水平间距
        static let rowTight: CGFloat = 5
        /// 卡片内垂直元素紧凑间距
        static let stack: CGFloat = 8
        /// 垂直元素密集间距（逐小时内部）
        static let stackDense: CGFloat = 6
        /// 极紧凑间距（MetricValue 等）
        static let stackTight: CGFloat = 4
        /// 内容左右外边距（ContentView 级别）
        static let contentMargin: CGFloat = 16
        /// 横向滚动内容顶端/底端内边距
        static let scrollV: CGFloat = 2
        /// 逐小时列表列间距
        static let hourlyGap: CGFloat = 5
        /// 逐小时列表列内垂直间距
        static let hourlyStack: CGFloat = 8
    }

    // MARK: 圆角

    enum CornerRadius {
        /// 卡片
        static let card: CGFloat = 20
        /// 指标块
        static let chip: CGFloat = 16
        /// 生活指数内部卡片
        static let item: CGFloat = 12
        /// AQI 柱状
        static let bar: CGFloat = 2
    }

    // MARK: 字体

    enum Typography {
        // 大标题 / 主要数字
        static let mainTemperature = Font.system(size: 72, weight: .semibold, design: .rounded)
        static let largeMetric = Font.system(size: 30, weight: .semibold, design: .rounded)
        static let gaugeValue = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let aqiBadge = Font.system(size: 16, weight: .semibold)
        static let aqiNumber = Font.system(size: 13, weight: .semibold)

        // 正文层级
        static let headline = Font.system(size: 17, weight: .semibold)
        static let subheadline = Font.system(size: 14, weight: .medium)
        static let subheadMedium = Font.system(size: 15, weight: .medium)
        static let callout = Font.system(size: 16, weight: .regular)
        static let calloutSemibold = Font.system(size: 16, weight: .semibold)

        // 小字
        static let footnote = Font.system(size: 13, weight: .medium)
        static let footnoteSemibold = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 12, weight: .medium)
        static let caption2 = Font.system(size: 11, weight: .regular)
    }

    // MARK: 卡片的公用修饰

    /// 卡片背景（圆角矩形 + 半透明填充）
    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
            .fill(Palette.cardFill)
    }

    /// 卡片描边
    static func cardStroke() -> some View {
        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
            .stroke(Palette.cardStroke, lineWidth: 0.5)
    }
}

// MARK: - 便捷修饰器

extension View {

    /// 卡片标题样式
    func vwCardTitle() -> some View {
        self.font(VWDesign.Typography.footnote)
            .foregroundStyle(VWDesign.Palette.secondary)
    }

    /// 主温度数字样式
    func vwMainTemperature() -> some View {
        self.font(VWDesign.Typography.mainTemperature)
            .foregroundStyle(VWDesign.Palette.primary)
    }

    /// 次要正文（subheadline 级）
    func vwSubheadline() -> some View {
        self.font(VWDesign.Typography.subheadline)
            .foregroundStyle(VWDesign.Palette.primary)
    }

    /// 强调小字（footnote semibold，如温度值）
    func vwStrongFootnote() -> some View {
        self.font(VWDesign.Typography.footnoteSemibold)
            .foregroundStyle(VWDesign.Palette.primary)
    }

    /// 辅助说明（tertiary 色，如降水概率）
    func vwSupplementary() -> some View {
        self.font(VWDesign.Typography.caption2)
            .foregroundStyle(VWDesign.Palette.tertiary)
    }

    /// 半透明指标块背景
    func vwChipBackground() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: VWDesign.CornerRadius.chip, style: .continuous)
                .fill(VWDesign.Palette.chipFill)
        )
    }
}


