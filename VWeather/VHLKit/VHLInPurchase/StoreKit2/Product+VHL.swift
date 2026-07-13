////
////  Product+VHL.swift
////  EverList
////
////  Created by Vincent on 2022/9/6.
////  Copyright © 2022 Darnel Studio. All rights reserved.
////
//
import Foundation
import StoreKit

@available(iOS 15.0, *)
public extension Product {
    /// 是否可以获得优惠
    var isEligibleForIntroOffer: Bool {
        get async {
            await subscription?.isEligibleForIntroOffer ?? false
        }
    }
    
    /// 是否有激活的订阅
    var hasActiveSubscription: Bool {
        get async {
            await (try? subscription?.status.first?.state == Product.SubscriptionInfo.RenewalState.subscribed) ?? false
        }
    }
}

// MARK: - 筛选产品
@available(iOS 15.0, *)
public extension Array where Element == Product {
    /// 消耗品
    var consumableProducts: [Product] {
        return self.filter({ p in p.type == .consumable })
    }
    /// 订阅类商品
    var subscriptionProducts: [Product] {
        return self.filter({ p in p.type == .autoRenewable })
    }
}
