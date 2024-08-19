//
//  View+VHL.swift
//  EverListWidget
//
//  Created by Vincent on 2023/7/19.
//  Copyright © 2023 Darnel Studio. All rights reserved.
//

import Foundation
import SwiftUI

extension View {
    /// 适配 iOS 17 设置背景
    func adoptableWidgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            return containerBackground(for: .widget) { color }
        } else {
            return background(color)
        }
    }
    
    /// 使内容无效进行刷新
    func adoptableInvalidatableContent(_ invalidatable: Bool = true) -> some View {
        if #available(iOS 17.0, *) {
            return invalidatableContent(invalidatable)
        }
        return self
    }
}

// MARK: - Image 适配 iOS accentedRenderingMode
//extension Image {
//    func adoptableWidgetAccentedRenderingModeDesaturated() -> some View {
//        if #available(iOS 18.0, *) {
//            return widgetAccentedRenderingMode(.desaturated)
//        }
//        return self
//    }
//
//    func adoptableWidgetAccentedRenderingModeAccented() -> some View {
//        if #available(iOS 18.0, *) {
//            return widgetAccentedRenderingMode(.accented)
//        }
//        return self
//    }
//    
//    func adoptableWidgetAccentedRenderingModeAccentedDesaturated() -> some View {
//        if #available(iOS 18.0, *) {
//            return widgetAccentedRenderingMode(.accentedDesaturated)
//        }
//        return self
//    }
//    
//    func adoptableWidgetAccentedRenderingModeFullColor() -> some View {
//        if #available(iOS 18.0, *) {
//            return widgetAccentedRenderingMode(.fullColor)
//        }
//        return self
//    }
//}
