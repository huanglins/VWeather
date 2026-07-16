//
//  WeatherWidgetBundle.swift
//  WeatherWidget
//
//  Created by vincent on 2024/8/19.
//

import WidgetKit
import SwiftUI

@main
struct MainWidgetBundle: WidgetBundle {
    var body: some Widget {
        CityWeatherWidget()
        SunEventWidget()
        WeatherWidget()
        // WeatherWidgetLiveActivity()
    }
}
