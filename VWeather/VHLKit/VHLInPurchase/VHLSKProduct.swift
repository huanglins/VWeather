//
//  VHLPorduct.swift
//  TunTunFocus
//
//  Created by vincent on 2026/3/19.
//

import StoreKit

extension Notification.Name {
    public static let VHLInAppPurchaseChangeNotification = NSNotification.Name("VHLInAppPurchaseChangeNotification")
}

/**
 使用内购管理需要自行修改：
 1. 共享密钥
 2. 如果需要自己服务器验证，需要修改自己服务器验证地址
 */
enum VHLSubscribeCycle {
    case week                                   // 一周
    case month                                  // 月度
    case quarter                                // 季度
    case halfYear                               // 半年
    case year                                   // 一年
}
enum VHLProductType: Equatable {
    case consumption                            // 消耗品    （60个金币）
    case permanent                              // 永久      （永久会员）
    case subscribe(cycle: VHLSubscribeCycle)    // 订阅      （包月会员）
    case nonRenewed                             // 非续期订阅 （一个月会员）
}

public class VHLProduct {
    var pid: String = ""                        // 产品id **
    var name: String = ""                       // 显示名称
    var quantity: Int = 1                       // 数量
    var price: Float = 0.0                      // 价格
    var originPrice: Float = 0.0                // 原价
    var type: VHLProductType = .consumption     // 类型（消耗品/永久/订阅）
    
    var product: SKProduct?                     // 当前产品 (StoreKit 1)
    
    /// StoreKit 2 商品对象 (iOS 15+)，与 product 二选一
    @available(iOS 15.0, *)
    public var storeKit2Product: StoreKit.Product?
    
    convenience init(pid: String, name: String, price: Float, originPrice: Float = 0.0, type: VHLProductType, quantity: Int = 1) {
        self.init()
        self.pid = pid
        self.name = name
        self.price = price
        self.originPrice = originPrice
        self.type = type
        self.quantity = quantity
    }
    
    /// 试用天数 (StoreKit 1 或 StoreKit 2)
    var trialDays: Int {
        if let product = self.product {
            // 限免期限
            if let period = product.introductoryPrice?.subscriptionPeriod {
                if period.unit == .day {
                    return period.numberOfUnits
                } else if period.unit == .week {
                    return period.numberOfUnits * 7
                }
            }
        }
        if #available(iOS 15.0, *), let p = storeKit2Product, let intro = p.subscription?.introductoryOffer {
            switch intro.period.unit {
            case .day: return intro.period.value
            case .week: return intro.period.value * 7
            case .month: return intro.period.value * 30
            case .year: return intro.period.value * 365
            @unknown default: return 0
            }
        }
        return 0
    }
    
    /// 是否已加载商品信息 (StoreKit 1 或 StoreKit 2)
    public var hasProductInfo: Bool {
        if product != nil { return true }
        if #available(iOS 15.0, *) { return storeKit2Product != nil }
        return false
    }
    
    /// 价格数值 (兼容 StoreKit 1/2)
    public var effectivePriceValue: Float {
        if let sk = product { return sk.price.floatValue }
        if #available(iOS 15.0, *), let p = storeKit2Product { return NSDecimalNumber(decimal: p.price).floatValue }
        return 0
    }
    
    /// 价格区域 (兼容 StoreKit 1/2)
    public var effectivePriceLocale: Locale {
        if let sk = product { return sk.priceLocale }
        return Locale.current
    }
    
    /// 本地化价格字符串 (兼容 StoreKit 1/2)
    public var effectiveLocalizedPrice: String? {
        if let sk = product {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = sk.priceLocale
            return formatter.string(from: sk.price)
        }
        if #available(iOS 15.0, *), let p = storeKit2Product { return p.displayPrice }
        return nil
    }
    
    /// 是否支持家庭共享 (兼容 StoreKit 1/2)
    public var effectiveIsFamilyShareable: Bool {
        if let sk = product { return sk.isFamilyShareable }
        if #available(iOS 15.0, *), let p = storeKit2Product { return p.isFamilyShareable }
        return false
    }
    
    /// 获取折扣
    var discount: CGFloat {
        guard let product = self.product else {
            return 1.0
        }
        for discount in product.discounts {
            switch discount.paymentMode {
            case .freeTrial:
                return 1
            case .payUpFront:
                print("提前支付折扣")
            case .payAsYouGo:
                print("")
            default:
                break
            }
        }
        return 1.0
    }
}
