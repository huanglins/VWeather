//
//  ContentView.swift
//  WeatherDemo
//
//  Created by vincent on 2024/8/19.
//

import SwiftUI

struct ContentView: View {
    @State var weatherModel: WeatherModel?
        
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
                Text("\(weatherModel?.locationModel?.area ?? "")")
                Text("\(weatherModel?.weatherModel?.temperature ?? 0.0)")
                Text("上次更新时间: \(weatherModel?.date?.formatted() ?? "")")
            }
            .padding()
        }.navigationTitle("Weather")
            .onAppear {
                
                // 请求天气信息
                WeatherManager.manager.requestCurrentWeatherInfo { wModel, error in
                    weatherModel = wModel
                }
            }
    }
}

#Preview {
    ContentView()
}
