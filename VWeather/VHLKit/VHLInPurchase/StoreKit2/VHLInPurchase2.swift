////
////  VHLInPurchase.swift
////  EverList
////
////  Created by Vincent on 2022/9/6.
////  Copyright © 2022 Darnel Studio. All rights reserved.
////

import Foundation
import StoreKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

// 定义一个简单的错误枚举
enum StoreError: Error {
    case failedVerification                         // 验证错误
}

// 统一的购买/恢复结果，便于 UI 显示 Toast
enum FlowResult {
    case success(Transaction)
    case failure(Error?)
    case cancelled(String)
    case pending(String)

    var message: String {
        switch self {
        case .success(let trans):
            return "购买成功，交易 ID: \(trans.id)"
        case .failure(let error):
            return "购买失败: \(error?.localizedDescription ?? "未知错误")"
        case .cancelled(let msg), .pending(let msg):
            return msg
        }
    }
}

// 定义商品 ID，必须和 .storekit 文件里的一致
enum ProductID: String, CaseIterable {
    case lifetime = "cn.vincents.lifetime"    // 非消耗型
    /*
     注意下面两个订阅方式：月付和年付，它们属于同一个订阅组，必须将 Subscription Level 设置为不同的值
     Subscription Level（订阅等级）的数字越小，优先级越高。
     如果用户 从 Level 2（月付）转去 Level 1（年付），这在 Apple 的定义中属于 升级（Upgrade）。
     
     这种情况下订阅会发生什么变化呢？
     当用户在 同一个订阅组 内，从低等级（Level 2）切换到高等级（Level 1）时，会发生以下行为：
     1.立即生效：用户的“按月订阅”会立即停止，用户的“按年订阅”会立即开始。
     2.按比例退款：Apple 会自动计算“按月订阅”中剩余未使用的天数，并将这部分的钱退还给用户（通常是原路退回）。
     3.全额扣款：用户会被立即扣除“按年订阅”的全额费用。
     4.周期重置：订阅的续期日期（Renewal Date）会更新。比如今天是 11月29日，用户操作了升级，那么新的到期日就是明年的 11月29日。
     总结：用户现在的状态是“按年订阅”生效中，“按月订阅”已失效。用户获得了无缝的权益升级体验。
     
     开发过程总要如何处理这种情况：
     - 当用户在 App 内或系统设置里完成购买后，你的 Transaction.updates 监听器会收到一个新的 Transaction。
     - 你需要调用 Transaction.currentEntitlements。由于这两个商品在同一个订阅组，currentEntitlements 只会返回最新的那个（即 Level 1 的年付订阅）。
     - 代码逻辑：获取最新 Transaction -> 验证 -> 解锁 Level 1 对应的功能 -> 更新 UI 显示“年费会员”。
     */
    case monthly  = "cn.vincents.pro.monthly" // 按月订阅，Level 2
    case yearly   = "cn.vincents.pro.yearly"  // 按年订阅, Level 1
    
    case coins    = "cn.vincents.coin.100"    // 消耗型
}

/// 用于在 for-await 循环中收集权益结果，避免 Swift 6 并发捕获可变变量错误
@available(iOS 15.0, *)
private actor EntitlementCollector {
    private var ids: Set<String> = []
    private var expirations: [Date] = []
    
    func add(productID: String, expiration: Date?) {
        ids.insert(productID)
        if let e = expiration { expirations.append(e) }
    }
    
    func result() -> (Set<String>, Date?) {
        (ids, expirations.max())
    }
}

// MARK: - StoreKit2 内购
@available(iOS 15.0, *)
public class VHLInPurchase2: ObservableObject {
    static let shared = VHLInPurchase2()

    public typealias TransactionUpdate = ((Transaction) async -> ())
    
    public enum IPError: Error {
        case storeKit(error: StoreKitError)             //
        case purchase(error: Product.PurchaseError)     // 购买错误
        case purchaseCanceledByUser                     // 用户取消购买
        case purchaseInPending                          // 购买被挂起
        case userCancelledRefundProcess                 // 用户取消退款流程
        case failedVerification                         // 验证错误
        case unknownError                               // 一般的错误
    }
    
    // 用于驱动 UI 显示的商品列表
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>() // 已买过的 ID (非消耗/订阅)
    @Published private(set) var subscriptionExpirationDate: Date? = nil // 订阅过期时间 (StoreKit 2 Transaction.expirationDate)
    @Published private(set) var coinBalance: Int = 0 // 消耗品余额
    @Published private(set) var introOfferEligibility: [String: Bool] = [:] // 订阅体验/首购优惠资格缓存
    @Published private(set) var subscriptionStatus: String = "无订阅" // 订阅详细状态
    
    /// 已处理的消耗型交易 ID，防止重复加币
    private let processedConsumableTransactionIDsKey = "VHLInPurchase2_processedConsumableTransactionIDs"
    private var processedConsumableTransactionIDs: Set<UInt64> {
        get {
            (UserDefaults.standard.array(forKey: processedConsumableTransactionIDsKey) as? [Int])?
                .compactMap { UInt64(exactly: $0) }
                .reduce(into: Set()) { $0.insert($1) } ?? []
        }
        set {
            UserDefaults.standard.set(Array(newValue).map { Int($0) }, forKey: processedConsumableTransactionIDsKey)
        }
    }
    
    // 最后一次联网的可信时间（联网成功获取状态时更新）
    private var lastKnownValidDate: Date {
        get { UserDefaults.standard.object(forKey: "VHLInPurchase2_lastKnownValidDate") as? Date ?? Date.distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "VHLInPurchase2_lastKnownValidDate") }
    }
    
    private var updatesTask: Task<Void, Never>? = nil
    
    //最大允许离线时间（秒）
    var maxOfflineAllowed: TimeInterval = 7 * 24 * 60 * 60 // 默认 7 天，可按需调整
    
    deinit {
        updatesTask?.cancel()
    }
    
    private init() {
        // 1. App 启动时立即开始监听交易变化
        updatesTask = listenForTransactions()
    }
    
    // MARK: - 监听交易更新 (核心)
    // 处理应用外购买、自动续费、退款等情况
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // 监听到变化，交给统一处理方法
                    await self.handleTransaction(transaction)
                    
                    // 结束交易 (如果不 finish，下次启动还会收到)
                    await transaction.finish()

                    self.log("监听到交易更新并已处理: \(transaction.productID)")
                } catch {
                    self.log("监听到的交易验证失败: \(error)")
                }
            }
        }
    }
}

// MARK: - 1. 获取商品
extension VHLInPurchase2 {
    func requestProducts(_ productIDs: Set<String>) async -> [Product] {
        if productIDs.isEmpty { return [] }
        
        log("开始请求商品列表: \(productIDs.joined(separator: ", "))")
        do {
            // 这里会返回合法的 Product 对象数组
            let products = try await Product.products(for: productIDs)
            
            // 按 product.id 合并，避免 index 越界；在同步块内完成，避免 Swift 6 并发捕获可变变量
            let currentProducts = self.products
            let merged: [Product] = {
                var result = currentProducts
                for product in products {
                    if let idx = result.firstIndex(where: { $0.id == product.id }) {
                        result[idx] = product
                    } else {
                        result.append(product)
                    }
                }
                return result
            }()
            
            await MainActor.run {
                self.products = merged
            }
            
            for product in products {
                displayProductInfo(product)
                await updateIntroEligibility(for: product)
            }
            
            // 加载完商品后，立即检查用户当前的购买状态
            await refreshCustomerProductStatus()
            
            return products
        } catch {
            log("获取商品失败: \(error)")
        }
        
        return []
    }
}

// MARK: - 2. 发起购买
extension VHLInPurchase2 {
    /// 购买指定商品
    /// - Parameter product: 商品对象
    @discardableResult
    func purchase(_ product: Product, for appAccountToken: UUID? = nil) async -> FlowResult {
        log("准备购买商品: \(product.displayName) (\(product.id))，价格 \(product.displayPrice)")
        do {
            // 发起购买请求
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            
            let result = try await product.purchase(options: options)
            
            // 处理购买结果
            switch result {
            case .success(let verification):
                // 购买成功，需验证交易
                log("购买成功返回，开始校验凭证...")
                let transaction = try checkVerified(verification)
                log("校验通过，交易 ID: \(transaction.id)")
                
                // 购买成功即表示当前在线，更新可信时间，避免 isOfflineExpired 误判为受限模式
                updateLastKnownValidDate()
                
                // 购买成功后，统一调用处理逻辑
                await handleTransaction(transaction)
                
                // 告诉苹果交易完成
                await transaction.finish()
                log("已完成交易并上报 finish")
                return .success(transaction)
            case .userCancelled:
                log("用户取消了支付")
                return .cancelled("用户取消")
            case .pending:
                log("交易挂起 (如家长控制)")
                return .pending("交易挂起")
            @unknown default:
                log("未知状态")
                return .failure(nil)
            }
        } catch {
            log("购买失败: \(error)")
            return .failure(error)
        }
    }
    
    // 手动强制恢复
    @discardableResult
    func restorePurchases() async -> FlowResult {
        log("开始恢复购买")
        do {
            // 1. 强制同步 App Store 交易记录
            // 这可能会提示用户输入 Apple ID 密码
            try await AppStore.sync()

            // 只有上面 sync 成功后才更新最后可信时间
            updateLastKnownValidDate()
            
            // 2. 同步完成后，重新检查权益
            await refreshCustomerProductStatus()
            
            // 遍历当前有效权益，返回第一个验证通过的 transaction（状态已在上方 updateCustomerProductStatus 中更新，这里只取 transaction 对象用于返回值）
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try checkVerified(result)
                    log("Restore found entitlement: \(transaction.productID) - \(transaction.id)")
                    return .success(transaction)
                } catch {
                    log("恢复时验证失败，跳过此条: \(error)")
                    continue
                }
            }

            log("恢复完成，但未发现已购商品")
            return .failure(nil)
        } catch {
            log("Restore failed: \(error)")
            return .failure(error)
        }
    }
}

// MARK: - 检查当前权益
extension VHLInPurchase2 {
    // 处理交易的统一逻辑（购买成功、自动续费、退款等都会走到这里）
    private func handleTransaction(_ transaction: Transaction) async {
        if transaction.productType == .consumable {     // 消耗品
            // 【情况 A】：消耗型商品 (金币)
            // 消耗型商品是“一次性”的，不会存在于 currentEntitlements 中
            // 所以我们必须在这里手动处理计数
            // 建议：真实项目中应记录 transaction.id 防止重复加币
            var processed = processedConsumableTransactionIDs
            guard !processed.contains(transaction.id) else {
                log("消耗型交易已处理过，跳过: \(transaction.id)")
                return
            }
            processed.insert(transaction.id)
            processedConsumableTransactionIDs = processed
            await MainActor.run {
                self.coinBalance += 100
            }
            log("金币到账 +100")
        } else {
            // 【情况 B】：订阅 或 非消耗型 (永久版)
            // ⚠️ 关键点：不要只是 insert 进去，而是触发“全量刷新”
            // 当用户从月付升级到年付，Apple 的 currentEntitlements 会自动把月付去掉，只留年付
            // 所以我们重新拉取一次，就能得到正确的唯一状态。
            await refreshCustomerProductStatus()
        }
    }
}

// MARK: - 同步刷新购买信息
extension VHLInPurchase2 {
    /// 同步用户购买信息，更新订阅状态（手动刷新）
    /// - Returns: 是否同步成功
    @discardableResult
    func sync() async -> Bool {
        do {
            // 先与 App Store 同步最新交易状态（在线时有效）触发弹框
            try await AppStore.sync()
            updateLastKnownValidDate()
        } catch {
            log("刷新订阅状态失败: \(error)")
            await refreshCustomerProductStatus()
            return false
        }
        
        await refreshCustomerProductStatus()
        return true
    }
    
    // 刷新用户购买状态（在线/离线都可调用，离线时会根据最后可信时间判断是否进入受限模式）
    func refreshCustomerProductStatus() async {
        // 使用 Actor 收集结果，避免 Swift 6 下 "captured var in concurrently-executing code" 错误
        let collector = EntitlementCollector()
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if transaction.isUpgraded {
                    log("忽略已升级的旧订阅: \(transaction.productID)")
                    continue
                }
                
                if let revocationDate = transaction.revocationDate, revocationDate < Date() {
                    log("该权益已被撤销/升级覆盖: \(transaction.productID)")
                    continue
                }
                
                if transaction.productType == .autoRenewable {
                    if let expiration = transaction.expirationDate, expiration > Date()
                        && !isOfflineExpired(expirationDate: expiration) {
                        await collector.add(productID: transaction.productID, expiration: expiration)
                    }
                    await checkSubscriptionDetails(transaction)
                } else {
                    await collector.add(productID: transaction.productID, expiration: nil)
                }
            } catch {
                log("权益验证失败: \(error)")
            }
        }
        
        let (activePurchasedIds, latestExpiration) = await collector.result()
        
        await MainActor.run {
            self.purchasedProductIDs = activePurchasedIds
            self.subscriptionExpirationDate = latestExpiration
            if self.purchasedProductIDs.isEmpty {
                self.subscriptionStatus = "无订阅"
                self.subscriptionExpirationDate = nil
            }
        }
        
        if activePurchasedIds.count > 0 {
            log("权益已刷新，当前生效: \(activePurchasedIds.joined(separator: ", "))")
        } else {
            log("权益已刷新，当前无有效订阅或非消耗品")
        }
    }
    
    /// 更新最后可信时间（在联网成功验证后调用）
    private func updateLastKnownValidDate() {
        lastKnownValidDate = Date()
    }
    
    private func isOfflineExpired(expirationDate: Date) -> Bool {
        let now = Date()
        
        // 从未成功联网过（首次安装 / 全新设备），无离线历史可参考，以 App Store 返回的过期时间为准，不进入受限模式
        guard lastKnownValidDate > Date.distantPast else { return false }
        
        // 检测系统时间回拨
        if now < lastKnownValidDate {
            print("⚠️ 检测到系统时间回拨，进入受限模式")
            return true
        }
        
        // 检查离线时长
        let offlineDuration = now.timeIntervalSince(lastKnownValidDate)
        if offlineDuration > maxOfflineAllowed {
            print("⚠️ 离线时间超过允许值（\(offlineDuration) 秒），进入受限模式")
            return true
        }
        
        // 检查基于最后可信时间的过期判断
        if lastKnownValidDate > expirationDate {
            print("⚠️ 最后可信时间已过期")
            return true
        }
        
        return false
    }
}

// MARK: - 票据验证
extension VHLInPurchase2 {
    // 验证交易真实性
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            // 验证失败（可能是盗版或证书不对），抛出错误，不给权益
            throw StoreError.failedVerification
        case .verified(let safe):
            // 验证成功，返回安全的交易对象
            // 这里可以调动后台的验证
            return safe
        }
    }
}

// MARK: - 商品检查
extension VHLInPurchase2 {
    // 检查订阅详细信息 (如：是否会续期)
    private func checkSubscriptionDetails(_ transaction: Transaction) async {
        // 通过 productID 找到对应的 Product
        guard let product = products.first(where: { $0.id == transaction.productID }),
              let subscription = product.subscription else { return }
        
        do {
            let statuses = try await subscription.status
            guard let status = statuses.first else { return }
            
            let renewalInfo = try checkVerified(status.renewalInfo)
            
            var statusText = ""
            switch status.state {
            case .subscribed: statusText = "订阅中"
            case .expired: statusText = "已过期"
            case .inGracePeriod: statusText = "宽限期 (扣费失败但可用)"
            case .revoked: statusText = "已撤销"
            case .inBillingRetryPeriod: statusText = "扣费重试中"
            default: statusText = "未知状态"
            }
            
            let autoRenewText = renewalInfo.willAutoRenew ? "自动续订开启" : "自动续订已关"
            self.subscriptionStatus = "\(statusText) - \(autoRenewText)"
        } catch {
            log("无法获取订阅详情: \(error)")
        }
    }
    
    // 检查是否有优惠
    func checkIntroOffer(for product: Product) async -> Bool {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer else { return false }
        
        // 检查用户是否有资格享受这个优惠
        // StoreKit 2 会自动根据用户历史判断 isEligible
        let isEligible = await subscription.isEligibleForIntroOffer

        if isEligible {
            if introOffer.paymentMode == .freeTrial {
                log("\(product.displayName) - 免费试用 \(introOffer.period.value) \(introOffer.period.unit)")
            } else {
                log("\(product.displayName) - 首月仅需: \(introOffer.price)")
            }
        } else {
            log("\(product.displayName) - 原价: \(product.price)")
        }
        return isEligible
    }

    // 缓存体验/首购优惠资格，供 UI 使用
    private func updateIntroEligibility(for product: Product) async {
        let eligible = await checkIntroOffer(for: product)
        await MainActor.run {
            introOfferEligibility[product.id] = eligible
        }
    }
}

// MARK: - 6. 日志工具
extension VHLInPurchase2 {
    nonisolated private func log(_ message: String) {
        // 独立于 MainActor，便于在后台 Task.detached 中调用
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let time = formatter.string(from: Date())
        debugPrint("[StoreKit2] [\(time)] \(message)")
    }
    
    // 辅助方法：打印产品详情
    func displayProductInfo(_ product: Product) {
        debugPrint("--------------------------------------------------")
        debugPrint("商品 ID: \(product.id)")
        debugPrint("名称: \(product.displayName)")
        debugPrint("描述: \(product.description)")
        debugPrint("价格: \(product.displayPrice)")  // 已格式化的价格字符串
        debugPrint("价格数值: \(product.price)")     // Decimal 类型
        debugPrint("货币代码: \(product.priceFormatStyle.currencyCode)")
        debugPrint("类型: \(product.type.rawValue)")
        debugPrint("支持家庭共享: \(product.isFamilyShareable ? "是" : "否")")

        // 订阅专属信息
        if let subscription = product.subscription {
            debugPrint("━━━ 订阅信息 ━━━")
            debugPrint("订阅组 ID: \(subscription.subscriptionGroupID)")
            debugPrint("订阅周期: \(periodText(subscription.subscriptionPeriod, count: 1))")

            // 介绍性优惠（新用户优惠）
            if let introOffer = subscription.introductoryOffer {
                let introDescription = periodText(introOffer.period, count: introOffer.periodCount)
                debugPrint("新用户优惠: \(introOffer.displayPrice) • \(introDescription) • \(introOffer.paymentMode.rawValue)")
            } else {
                debugPrint("新用户优惠: 无")
            }

            // 推介优惠
            if subscription.promotionalOffers.isEmpty {
                debugPrint("推介优惠: 无")
            } else {
                debugPrint("推介优惠 \(subscription.promotionalOffers.count) 个：")
                for offer in subscription.promotionalOffers {
                    let description = periodText(offer.period, count: offer.periodCount)
                    debugPrint("  - \(String(describing: offer.id)): \(offer.displayPrice) • \(description) • \(offer.paymentMode.rawValue)")
                }
            }
        } else {
            debugPrint("非订阅商品，无订阅附加信息")
        }
    }
    
    /// 辅助方法：格式化周期文本
    private func periodText(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "天"
        case .week: unit = "周"
        case .month: unit = "月"
        case .year: unit = "年"
        @unknown default: unit = "周期"
        }
        let base = period.value > 1 ? "\(period.value)\(unit)" : unit
        return count > 1 ? "\(count) x \(base)" : base
    }
}

// MARK: - 退款
@available(iOS 15.0, *)
extension VHLInPurchase2 {
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @MainActor
    /// 开始退款流程
    func beginRefundProcess(for productID: String, in scene: UIWindowScene) async throws {
        guard case .verified(let transaction) = await Transaction.latest(for: productID)
        else { throw IPError.failedVerification }
        
        do {
            let status = try await transaction.beginRefundRequest(in: scene)
            
            switch status {
            case .success:
                break
            case .userCancelled:
                throw IPError.userCancelledRefundProcess
            @unknown default:
                throw IPError.unknownError
            }
        } catch {
            throw error
        }
    }
}

// MARK: - 订阅管理
@available(iOS 15.0, *)
extension VHLInPurchase2 {
    /// 显示订阅管理页面
    func showManageSubscriptions(in scene: UIWindowScene) async throws {
        try await AppStore.showManageSubscriptions(in: scene)
    }
    
    @available(iOS 16.0, *)
    /// 弹出兑换优惠码页面
    func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
}

// MARK: - 判断首次购买版本
extension VHLInPurchase2 {
    // orderedAscending: version1 < version2
    func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").map { Int($0) ?? 0 }
        let v2Components = version2.split(separator: ".").map { Int($0) ?? 0 }
        
        // 补齐长度
        let maxCount = max(v1Components.count, v2Components.count)
        let paddedV1 = v1Components + Array(repeating: 0, count: maxCount - v1Components.count)
        let paddedV2 = v2Components + Array(repeating: 0, count: maxCount - v2Components.count)
        
        for (num1, num2) in zip(paddedV1, paddedV2) {
            if num1 < num2 {
                return .orderedAscending
            } else if num1 > num2 {
                return .orderedDescending
            }
        }
        return .orderedSame
    }
    
    /// 是否为付费用户
    func isLegacyPaidUser(targetVersion: String) async -> Bool {
        do {
            let appTransaction = try await AppTransaction.shared

            switch appTransaction {
            case .verified(let transaction):
                // The version string from the first install
                let originalVersion = transaction.originalAppVersion
                let originalPurchaseDate = transaction.originalPurchaseDate

                log("用户最初购买的版本: \(originalVersion), 首次购买日期: \(originalPurchaseDate)")
                
                let result = compareVersions(originalVersion, targetVersion)
                if result == .orderedAscending {  // 首次购买版本小于目标版本
                    return true
                }
                return false
            case .unverified:
                // Transaction couldn't be verified, treat as new user
                return false
            }
        } catch {
            // No transaction available
            return false
        }
    }
}

/**

 //// https://www.51cto.com/article/708077.html
 //// https://github.com/ShenJieSuzhou/PurchaseX/
 /// swift 并发编程 https://swift.bootcss.com/02_language_guide/28_Concurrency
 https://juejin.cn/post/7577215663968190506
 
 ** 参照的这个 **
 https://github.com/lexiaoyao20/StoreKitDemo
 
 https://juejin.cn/post/7551258620349431854
 
 https://juejin.cn/post/7096063372159877150
 
 https://juejin.cn/post/7096063372159877150
 
 增加断网判断
 https://blog.csdn.net/weixin_44309889/article/details/150006217
 
 iOS StoreKit 2 新特性解析
 https://www.51cto.com/article/708077.html
 
 将 iOS 应用从预付费迁移到免费增值
 https://www.donnywals.com/migrating-an-ios-app-from-paid-up-front-to-freemium/?utm_source=fatbobman%20weekly%20issue%20122&utm_medium=web
 
 */
