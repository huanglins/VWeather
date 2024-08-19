//
//  DateTimerDisplayView.swift
//  QuickLauncher
//
//  Created by vincent on 2023/11/24.
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - 用于显示时间的视图
/**
 示例：
 Text(Calendar.current.startOfDay(for: Date()), style: .timer)
     .timerDisplay(style: .second, font: f)
 */
public struct TextTimerDisplayModifier: ViewModifier {
    public enum Style {
        case timer, hour, minute, second, hourMinute, minuteSecond
    }
    
    var style: Style = .timer
    /// 根据显示的字体才裁剪
    var font: UIFont = .monospacedSystemFont(ofSize: 20, weight: .medium)
    
    init(style: Style, font: UIFont) {
        self.style = style
        self.font = font
    }
    
    public func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            content.font(Font(font))
                .multilineTextAlignment(.trailing)
                .frame(width: textWidth("00:00:00", font: font))
                .offset(x: timerOffsetX())

//            HStack(spacing: 0) {
//                content.font(Font(font))
//                    .frame(width: textWidth("00:00:00", font: font))
//                    .multilineTextAlignment(.trailing)
//                    .offset(x: timerOffsetX())
//            }.frame(width: textWidth("00:00:00", font: font), alignment: .trailing)
        }.frame(width: styleTextWidth(with: style), height: font.lineHeight + 1, alignment: .leading).clipped()
    }
    
    fileprivate func styleTextWidth(with style: Style) -> CGFloat {
        switch style {
        case .timer: return textWidth("00:00:00", font: font)
        case .hour, .minute, .second: return textWidth("00", font: font)
        case .hourMinute, .minuteSecond: return textWidth("00:00", font: font)
        }
    }
    fileprivate func timerOffsetX() -> CGFloat {
        switch style {
        case .timer: return 0
        case .hour, .hourMinute: return 0
        case .minute, .minuteSecond:
            return -textWidth("00:", font: font)
        case .second:
            return -textWidth("00:00:", font: font)
        }
    }
    fileprivate func textWidth(_ text: String, font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = text.size(withAttributes: fontAttributes)
        return size.width
    }
}
public extension View {
    func timerDisplay(style: TextTimerDisplayModifier.Style, font: UIFont) -> some View {
        modifier(TextTimerDisplayModifier(style: style, font: font))
    }
}
