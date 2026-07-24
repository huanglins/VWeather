//
//  AppConfiguration.swift
//  VWeather
//
//  需要随上架信息调整的产品与支持配置。
//

import Foundation

enum AppConfiguration {
    enum Store {
        /// 永久会员的 App Store Connect 商品 ID。
        /// 修改时需要同步更新 VWeather.storekit 和 App Store Connect。
        static let membershipProductID = "cn.vincents.VWeather.pro"

        /// App Store 页面中的数字产品 ID，上架后填写，例如 "1234567890"。
        /// 未配置时，“给个好评”会回退为系统应用内评分请求。
        static let appStoreProductID = ""

        static var writeReviewURL: URL? {
            guard !appStoreProductID.isEmpty else { return nil }
            return URL(string: "https://apps.apple.com/app/id\(appStoreProductID)?action=write-review")
        }
    }

    enum Support {
        /// 功能许愿与用户反馈的接收邮箱，后续可直接在此替换。
        static let email = "support@vincents.cn"
    }
}
