//
//  SettingsView.swift
//  VWeather
//
//  设置页：iCloud 同步、温度单位、城市管理入口、关于。
//

import SwiftUI
import CloudKit
import StoreKit
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var iap = IAPManager.shared

    @State private var syncOn = SyncManager.manager.syncIsOpen
    @State private var unit = AppSettings.shared.temperatureUnit
    @State private var iCloudStatusText = "检查中…"
    @State private var syncing = false
    @State private var lastSync: Date? = SyncManager.manager.lastSyncDate
    @State private var showMembership = false
    @State private var supportErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showMembership = true
                    } label: {
                        MembershipBannerView(isPro: iap.isPro)
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // iCloud 同步
                Section {
                    Toggle("iCloud 同步", isOn: $syncOn)
                        .onChange(of: syncOn) { _, newValue in
                            SyncManager.manager.syncIsOpen = newValue
                            if newValue { triggerSync() }
                        }
                    LabeledContent("iCloud 账户", value: iCloudStatusText)
                    if syncOn {
                        LabeledContent("上次同步", value: lastSyncText)
                        Button(action: triggerSync) {
                            HStack {
                                Text("立即同步")
                                Spacer()
                                if syncing { ProgressView() }
                            }
                        }
                        .disabled(syncing)
                    }
                } header: {
                    Text("iCloud 同步")
                } footer: {
                    Text("开启后，添加/删除的城市会通过 iCloud 私有数据库在你的设备间同步。")
                }

                // 温度单位
                Section("温度单位") {
                    Picker("温度单位", selection: $unit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unit) { _, newValue in
                        AppSettings.shared.temperatureUnit = newValue
                    }
                }

                // 城市管理
                Section("城市") {
                    NavigationLink {
                        CityListView()
                    } label: {
                        Text("城市管理")
                    }
                }

                Section("支持与反馈") {
                    Button {
                        sendSupportEmail(kind: .featureWish)
                    } label: {
                        supportRow("功能许愿")
                    }
                    .buttonStyle(.plain)

                    Button {
                        openReviewPage()
                    } label: {
                        supportRow("给个好评")
                    }
                    .buttonStyle(.plain)

                    Button {
                        sendSupportEmail(kind: .feedback)
                    } label: {
                        supportRow("用户反馈")
                    }
                    .buttonStyle(.plain)
                }

                // 数据来源
                //
                // 合规：Apple 要求展示 Apple Weather 商标与「其他数据来源」链接，
                // 两者由 AppleWeatherAttribution 一并给出，不要拆开或只留其一。
                Section {
                    AppleWeatherAttribution()
                    LabeledContent("天气", value: "Apple 天气")
                    LabeledContent("空气质量 · 生活指数", value: "和风天气")
                    LabeledContent("分钟降水 · 气象预警", value: "和风天气")
                } header: {
                    Text("数据来源")
                } footer: {
                    Text("天气数据由 Apple 天气提供，空气质量、生活指数、分钟级降水与气象预警由和风天气提供。")
                }

                // 关于
                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMembership) {
                NavigationStack {
                    MembershipView(showsCloseButton: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("暂时无法打开", isPresented: supportErrorPresented) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(supportErrorMessage ?? "请稍后重试")
            }
            .onAppear(perform: refreshiCloudStatus)
        }
    }

    // MARK: - 辅助

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var lastSyncText: String {
        guard let date = lastSync else { return "从未" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private var supportErrorPresented: Binding<Bool> {
        Binding(
            get: { supportErrorMessage != nil },
            set: { if !$0 { supportErrorMessage = nil } }
        )
    }

    private func supportRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private enum SupportEmailKind {
        case featureWish
        case feedback

        var subject: String {
            switch self {
            case .featureWish: return "【云雾】功能许愿"
            case .feedback: return "【云雾】用户反馈"
            }
        }

        var prompt: String {
            switch self {
            case .featureWish: return "希望增加的功能：\n\n使用场景：\n\n"
            case .feedback: return "遇到的问题或建议：\n\n复现步骤：\n\n"
            }
        }
    }

    private func sendSupportEmail(kind: SupportEmailKind) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConfiguration.Support.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: kind.subject),
            URLQueryItem(name: "body", value: kind.prompt + diagnosticText),
        ]

        guard let url = components.url else {
            supportErrorMessage = "反馈邮箱配置无效"
            return
        }

        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                supportErrorMessage = "请先安装并配置邮件应用，或联系 \(AppConfiguration.Support.email)"
            }
        }
    }

    private func openReviewPage() {
        if let url = AppConfiguration.Store.writeReviewURL {
            UIApplication.shared.open(url, options: [:]) { opened in
                if !opened {
                    supportErrorMessage = "暂时无法打开 App Store"
                }
            }
        } else {
            requestReview()
        }
    }

    private var diagnosticText: String {
        "\n---\n应用版本：\(appVersion)\n系统版本：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n设备：\(UIDevice.current.model)"
    }

    private func triggerSync() {
        guard !syncing else { return }
        syncing = true
        SyncManager.manager.sync { _ in
            syncing = false
            lastSync = SyncManager.manager.lastSyncDate
        }
    }

    private func refreshiCloudStatus() {
        VHLiCloud.getSyncStatus { status in
            switch status {
            case .available:              iCloudStatusText = "可用"
            case .noAccount:              iCloudStatusText = "未登录"
            case .restricted:             iCloudStatusText = "受限"
            case .couldNotDetermine:      iCloudStatusText = "无法确定"
            case .temporarilyUnavailable: iCloudStatusText = "暂不可用"
            @unknown default:             iCloudStatusText = "未知"
            }
        }
    }
}

#Preview {
    SettingsView()
}
