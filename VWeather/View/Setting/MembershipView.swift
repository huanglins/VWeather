//
//  MembershipView.swift
//  VWeather
//
//  云雾会员介绍、购买与恢复购买页面。
//

import SwiftUI

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iap = IAPManager.shared

    let showsCloseButton: Bool
    var onActivated: (() -> Void)?

    @State private var isProcessing = false
    @State private var statusMessage: String?

    init(showsCloseButton: Bool = false, onActivated: (() -> Void)? = nil) {
        self.showsCloseButton = showsCloseButton
        self.onActivated = onActivated
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: WeatherPalette.colors(for: .clear, isNight: false),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    benefits
                    purchaseCard
                    restoreButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("云雾会员")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            if iap.proStoreProduct == nil {
                _ = await iap.loadProducts()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 92, height: 92)
                Image(systemName: iap.isPro ? "checkmark.seal.fill" : "crown.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }

            Text(iap.isPro ? "会员已解锁" : "解锁更多收藏城市")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text(iap.isPro
                 ? "你已拥有云雾永久会员权益"
                 : "保留当前位置免费使用，会员可添加和管理更多收藏城市")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefitRow(icon: "plus.circle.fill",
                       title: "添加收藏城市",
                       subtitle: "搜索并保存你关心的多个城市")
            Divider().overlay(.white.opacity(0.14))
            benefitRow(icon: "icloud.fill",
                       title: "城市列表同步",
                       subtitle: "通过 iCloud 在你的设备间同步")
            Divider().overlay(.white.opacity(0.14))
            benefitRow(icon: "infinity",
                       title: "永久会员",
                       subtitle: "一次购买，永久解锁当前会员权益")
        }
        .padding(.horizontal, 16)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }

    private var purchaseCard: some View {
        VStack(spacing: 12) {
            if iap.isPro {
                Label("永久会员权益已生效", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Button(action: purchase) {
                    HStack {
                        if isProcessing {
                            ProgressView().tint(.blue)
                        }
                        Text(isProcessing ? "处理中…" : "永久解锁")
                        Spacer()
                        Text(iap.proPriceText ?? "获取价格中…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.08, green: 0.27, blue: 0.52))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }

            Text("购买由 App Store 处理，最终价格以系统购买确认页为准。")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    private var restoreButton: some View {
        Button {
            restore()
        } label: {
            Text("恢复购买")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    private func purchase() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = nil

        Task {
            let activated = await iap.purchasePro()
            await MainActor.run {
                isProcessing = false
                if activated {
                    statusMessage = "会员权益已成功解锁"
                    onActivated?()
                } else {
                    statusMessage = "未完成购买，请稍后重试"
                }
            }
        }
    }

    private func restore() {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = nil

        Task {
            let restored = await iap.restore()
            await MainActor.run {
                isProcessing = false
                if restored {
                    statusMessage = "会员权益已恢复"
                    onActivated?()
                } else {
                    statusMessage = "未找到可恢复的会员购买"
                }
            }
        }
    }
}

struct MembershipBannerView: View {
    let isPro: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isPro ? "checkmark.seal.fill" : "crown.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(isPro ? "云雾会员已开通" : "云雾会员")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(isPro ? "永久会员权益已生效" : "解锁添加和同步收藏城市")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 8)

            Text(isPro ? "查看" : "开通")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .padding(16)
        .background(
            LinearGradient(colors: WeatherPalette.colors(for: .clear, isNight: false),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}
