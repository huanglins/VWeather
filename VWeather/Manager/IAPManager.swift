//
//  IAPManager.swift
//  VWeather
//
//  内购业务管理器（StoreKit 2）。封装 VHLInPurchase2，提供占位产品与权益检查。
//  ** 产品为占位：真实上架前需在 App Store Connect 创建对应产品并替换 pid。**
//

import Combine
import Foundation
import StoreKit

final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    private let store = VHLInPurchase2.shared
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false

    /// 占位产品：一次性解锁 Pro（非消耗型）。后续在 ASC 建真产品后替换 pid。
    let proProduct = VHLProduct(pid: AppConfiguration.Store.membershipProductID,
                                name: "云雾永久会员",
                                price: 0,
                                type: .permanent)

    var allProductIDs: Set<String> { [proProduct.pid] }

    var proStoreProduct: Product? {
        products.first { $0.id == proProduct.pid }
    }

    var proPriceText: String? { proStoreProduct?.displayPrice }

    private init() {
        products = store.products
        isPro = store.purchasedProductIDs.contains(proProduct.pid)

        store.$products
            .combineLatest(store.$purchasedProductIDs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] products, purchasedIDs in
                guard let self else { return }
                self.products = products
                self.isPro = purchasedIDs.contains(self.proProduct.pid)
            }
            .store(in: &cancellables)
    }

    /// 加载产品信息（价格等）；同时触发 VHLInPurchase2 的交易监听与权益刷新。
    @discardableResult
    func loadProducts() async -> [Product] {
        let loadedProducts = await store.requestProducts(allProductIDs)
        await syncPublishedState()
        return loadedProducts
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
        await syncPublishedState()
        return store.purchasedProductIDs.contains(proProduct.pid)
    }

    /// 恢复购买
    @discardableResult
    func restore() async -> Bool {
        _ = await store.restorePurchases()
        await syncPublishedState()
        return store.purchasedProductIDs.contains(proProduct.pid)
    }

    private func syncPublishedState() async {
        let products = store.products
        let isPro = store.purchasedProductIDs.contains(proProduct.pid)
        await MainActor.run {
            self.products = products
            self.isPro = isPro
        }
    }
}
