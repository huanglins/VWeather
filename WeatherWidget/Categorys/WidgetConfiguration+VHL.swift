//
//  WidgetConfiguration+VHL.swift
//  EverListWidget
//
//  Created by Vincent on 2023/8/22.
//  Copyright © 2023 Darnel Studio. All rights reserved.
//

import Foundation
import WidgetKit
import SwiftUI

extension WidgetConfiguration {
    /// 组件的编辑
    func adoptableWidgetContentMargin() -> some WidgetConfiguration {
//        if #available(iOSApplicationExtension 15.0, *) {
        if #available(iOS 17.0, *) {
            return contentMarginsDisabled()
        }
        
        return self
    }
    
    /// 可移除背景 (false 表示不支持可移除背景，比如照片组件)
    func adoptableContainerBackgroundRemovable(_ b: Bool) -> some WidgetConfiguration {
        if #available(iOS 17.0, *) {
            return containerBackgroundRemovable(b)
        }
        
        return self
    }
}
