//
//  Tools.swift
//  WeatherDemo
//
//  Created by Vincent on 2024/8/17.
//

import SwiftUI

/// 像素字体
/// https://www.miao3.cn/detail?id=920
func FusionPixelRegular(_ size: CGFloat) -> Font {
    return Font(UIFont(name: "Fusion-Pixel-Regular", size: size) ?? .systemFont(ofSize: size))
}


extension Double {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
