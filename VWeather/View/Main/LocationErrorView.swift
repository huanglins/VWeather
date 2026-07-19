//
//  LocationErrorView.swift
//  VWeather
//
//  定位失败提示面板。
//

import SwiftUI

/// 定位失败时的提示视图，根据错误类型展示不同操作按钮。
struct LocationErrorView: View {
    let error: VHLLocationError
    let onOpenSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch error {
            case .denied:
                ContentUnavailableView {
                    Label("无法获取位置", systemImage: "location.slash")
                } description: {
                    Text("请点击同意位置权限")
                } actions: {
                    Button("前往设置开启") { onOpenSettings() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed:
                ContentUnavailableView {
                    Label("无法获取位置", systemImage: "location.slash")
                } description: {
                    Text("请检查定位服务后重试")
                } actions: {
                    Button("重试") { onRetry() }
                }
            }
        }
        .foregroundStyle(.white)
    }
}
