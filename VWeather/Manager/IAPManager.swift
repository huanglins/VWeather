//
//  IAPManager.swift
//  VWeather
//
//  内购业务管理器（StoreKit 2）。封装 VHLInPurchase2，提供占位产品与权益检查。
//  ** 产品为占位：真实上架前需在 App Store Connect 创建对应产品并替换 pid。**
//

import Foundation
import StoreKit

class IAPManager {
    static let shared = IAPManager()

    private let store = VHLInPurchase2.shared

    /// 占位产品：一次性解锁 Pro（非消耗型）。后续在 ASC 建真产品后替换 pid。
    let proProduct = VHLProduct(pid: "cn.vincents.VWeather.pro",
                                name: "VWeather Pro",
                                price: 0,
                                type: .permanent)

    var allProductIDs: Set<String> { [proProduct.pid] }

    /// 是否已解锁 Pro（供后续功能门控调用）
    var isPro: Bool {
        store.purchasedProductIDs.contains(proProduct.pid)
    }

    private init() {}

    /// 加载产品信息（价格等）；同时触发 VHLInPurchase2 的交易监听与权益刷新。
    @discardableResult
    func loadProducts() async -> [Product] {
        await store.requestProducts(allProductIDs)
    }

    /// 购买 Pro，返回购买后是否已解锁。
    @discardableResult
    func purchasePro() async -> Bool {
        var product = store.products.first(where: { $0.id == proProduct.pid })
        if product == nil {
            _ = await loadProducts()   // 尚未加载到产品，先加载
            product = store.products.first(where: { $0.id == proProduct.pid })
        }
        guard let product else { return false }
        _ = await store.purchase(product)
        return isPro
    }

    /// 恢复购买
    func restore() async {
        _ = await store.restorePurchases()
    }
}
