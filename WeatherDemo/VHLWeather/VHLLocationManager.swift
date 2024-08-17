//
//  LocationManager.swift
//  QuickLauncher
//
//  Created by Vincent on 2023/3/22.
//

import Foundation
import CoreLocation


// 在 info.plist 增加定位权限
// NSLocationWhenInUseUsageDescription
// 在小组件中获取位置还需要添加 Widget Wants Location 

struct VHLLocationModel: Codable {
    var latitude: Double = 0        // 纬度
    var longitude: Double = 0       // 经度
    var country: String?            // 国家
    var countryCode: String?        // 国家
    var province: String?           // 省
    var city: String?               // 城市
    var area: String?               // 地区 渝北区
    var adcode: String?
    var citycode: String?
    var address: String?            // 具体地址
    
    var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: 定位管理
class VHLLocationManager: NSObject {
    static let manager = VHLLocationManager()
    
    lazy private(set) var locationManager: CLLocationManager = {
        var m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest /// 定位精度
        return m
    }()
    
    var locationCompletionBlock: ((VHLLocationModel?, Error?) -> ())?
    
    private(set) var currentLocationModel: VHLLocationModel? // 用户定位信息的模型
    /// 是否单次定位
    private var isAloneLocaion: Bool = false
    
    override init() {
        
    }
    
    // 定位权限
    static func authorizationStatus() -> CLAuthorizationStatus {
        return CLLocationManager().authorizationStatus
    }
    static func authorized() -> Bool {
        let status: CLAuthorizationStatus = authorizationStatus()
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }
    /// 是否已经请求授权
    static func hasRequestedAuth() -> Bool {
        let status: CLAuthorizationStatus = authorizationStatus()
        return status != .notDetermined
    }
}

// MARK: - 请求定位
extension VHLLocationManager {
    func startUpdatingLocationWhenInUse() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    func startUpdatingLocationAlways() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    func startMonitoringSignificantLocationChanges() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()
    }
    func stopMonitoringSignificantLocationChanges() {
        locationManager.stopMonitoringSignificantLocationChanges()
    }
}

// MARK: - public method
extension VHLLocationManager {
    /// 单次定位
    func aloneReGeocodeLocation(_ completionBlock: @escaping ((VHLLocationModel?, Error?) -> ())) {
        isAloneLocaion = true
        serialReGeocodeLocation(completionBlock)
    }

    /// 连续定位
    func serialReGeocodeLocation(_ completionBlock: @escaping ((VHLLocationModel?, Error?) -> ())) {
        self.locationCompletionBlock = completionBlock
        startUpdatingLocationAlways()
    }
    
    /// 重大位置更新
    func singificantLocationChanges(_ completionBlock: @escaping ((VHLLocationModel?, Error?) -> ())) {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            self.locationCompletionBlock = completionBlock
            startMonitoringSignificantLocationChanges()
        } else {
            aloneReGeocodeLocation(completionBlock)
        }
    }
}

// MARK: - Delegate
extension VHLLocationManager: CLLocationManagerDelegate {
    // 授权状态变更
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            self.locationCompletionBlock?(nil, nil)
            return
        }
        
        if location.coordinate.latitude > 0 && location.coordinate.longitude > 0 {
            if isAloneLocaion { // 单次定位成功就停止定位
                stopUpdatingLocation()
            }
        }
        
        // 地理位置反编码
        // let locale = Locale(identifier: "en-US")
        // NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en-US"];
        CLGeocoder().reverseGeocodeLocation(location, preferredLocale: nil) { (marks, error) in
            if let error {
                print("地理位置反编码失败: ", error.localizedDescription)
            }
            /**

             //
             if let addressInfo = placemark.addressDictionary {

                model.province = addressInfo["State"] as? String
                model.city = addressInfo["City"] as? String
                model.area = addressInfo["SubLocality"] as? String
                model.address = addressInfo["name"] as? String
             }

              po placemark.addressDictionary
              ▿ Optional<Dictionary<AnyHashable, Any>>
                    ▿ key : AnyHashable("Country")
                    - value : 中国
                    ▿ key : AnyHashable("Thoroughfare")
                    - value : 桃园路
                    ▿ key : AnyHashable("FormattedAddressLines")
                    ▿ value : 1 element
                      - 0 : 中国广东省深圳市罗湖区桃园路211号
                    ▿ key : AnyHashable("SubLocality")
                    - value : 罗湖区
                    ▿ key : AnyHashable("City")
                    - value : 深圳市
                    ▿ key : AnyHashable("Street")
                    - value : 桃园路211号
                    ▿ key : AnyHashable("State")
                    - value : 广东省
                    ▿ key : AnyHashable("Name")
                    - value : 桃园路211号
                    ▿ key : AnyHashable("SubThoroughfare")
                    - value : 211号
                    ▿ key : AnyHashable("CountryCode")
                    - value : CN
             */
            
            var model = VHLLocationModel()
            model.latitude = location.coordinate.latitude
            model.longitude = location.coordinate.longitude
            
            defer {
                self.currentLocationModel = model
                self.locationCompletionBlock?(model, nil)
            }
            
            // 地理位置反编码信息
            guard let placemarks = marks, placemarks.count > 0 else {
                return
            }
            
            let placemark = placemarks[0]
            model.country = placemark.country
            model.countryCode = placemark.isoCountryCode
            model.province = placemark.administrativeArea
            model.city = placemark.locality
            model.area = placemark.subLocality
            model.address = placemark.name
        }
    }
    
    // 定位失败
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//        if !VHLLocationManager.hasRequestedAuth() {
//            return
//        }
        
        print("定位失败", error.localizedDescription)
        self.locationCompletionBlock?(nil, error)
    }
}
