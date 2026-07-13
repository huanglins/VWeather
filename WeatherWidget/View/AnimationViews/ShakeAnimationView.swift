//
//  ShakeAnimationView.swift
//

import SwiftUI
import UIKit
import SwiftUI
import ClockHandRotationKit
// https://github.com/TopWidgets/SwingAnimation
// https://github.com/tangtiancheng/DouYinComment

// MARK: - 摇摇乐
fileprivate struct ArcView: Shape {
    var arcStartAngle: Double
    var arcEndAngle: Double
    var arcRadius: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: arcRadius,
                    startAngle: .degrees(arcStartAngle),
                    endAngle: .degrees(arcEndAngle),
                    clockwise: false)
        return path
    }
}

struct ShakeAnimationView<Content: View>: View {
    var count: Int = 7                                  // 摇摇的帧数
    var duration: TimeInterval  = 1.4                   // 摇摇的总时长
    var shakeAngle: CGFloat = 15.0                      // 摇摇的角度
    var anchor: UnitPoint = UnitPoint(x: 0.5, y: 1)     // 摇摇运动的锚点
    @ViewBuilder
    var content: (Int) -> Content
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            
            //每帧距离多少度
            let transFAngele = shakeAngle / Double(max(count - 1, 1))
            
            //https://max2d.com/archives/897   计算原理.   如果要方便,那就是lineWidth设置为imageWH.然后arcRadius设置为一个非常非常大的数即可不用做以下运算. 下面的只是为了说清楚算法
            //多少度
            let angle = 360.0 / (Double(max(2 * count - 2, 1)))
            //正方形宽高
            let imageWH = max(width, height)
            //一半宽高（显式转为 Double，统一在 Double 下计算，避免 CGFloat/Double 混合推断导致类型检查超时）
            let halfWH = Double(imageWH / 2)
            //一半弧度
            let halfRadian = (angle / 2) / 180.0 * Double.pi
            let tanHalf = tan(halfRadian)
            // 半径
            let halfWHSq = halfWH * halfWH
            let term1 = 5.0 * halfWHSq
            let term2 = halfWHSq / (tanHalf * tanHalf)
            let term3 = 4.0 * halfWHSq / tanHalf
            let radiu = sqrt(term1 + term2 + term3)
            let b = halfWH / tanHalf
            let lineWidth = radiu - b
            //这里其实不乘以300才是完完全全正确的结果,每个大小都是刚刚好的.但是这样转起来之后重叠部分会留阴影, 所以加以放大后.半径变大了,但是重叠部分还是那么大.相应的周长绝对速度就变大了. 这样阴影就会快速略过,肉眼便无法感知了.越放大效果越好.应该是这个理
            let arcRadius = (radiu - (lineWidth / 2)) * 400
            
            ZStack {
                ForEach(1...(2 * count - 2), id: \.self) { index in
                    ZStack {
                        let contentAngle = getAngle(index: index, imageFrame: count, transFAngele: transFAngele)
                        content(count - index % count)
                            .rotationEffect(.degrees(contentAngle), anchor: anchor)
                            .frame(width: width * 0.85, height: height * 0.85)
                    }
                    .frame(width: width, height: height, alignment: .center)
                    .mask(
                        ArcView(arcStartAngle: angle * Double(index - 1),
                                arcEndAngle: angle * Double(index),
                                arcRadius: arcRadius)
                        .stroke(style: .init(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
                        .frame(width: width, height: height)
                        .clockHandRotationEffect(period: .custom(duration))
                        .offset(y: arcRadius)
                    )
                }
            }
            .frame(width: width, height: height)
        }
    }
    
    func getAngle(index:NSInteger, imageFrame:NSInteger, transFAngele:CGFloat) -> CGFloat {
        if index < imageFrame {
            let result1 = Double(index) * transFAngele - Double(imageFrame - 1) * transFAngele / 2
            return result1
        } else {
            let result1 = Double(imageFrame - 1) * transFAngele / 2 - Double(index + 1 - imageFrame) * transFAngele
            return result1
        }
    }
}
