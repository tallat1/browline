import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct WeatherTests {
    @Test func parsesForecastAndPlace() throws {
        let forecast = Data("""
        {"current":{"time":"2026-10-16T00:30","interval":900,"temperature_2m":12.5,"weather_code":80,"is_day":0},
         "daily":{"time":["2026-10-16"],"temperature_2m_max":[12.5],"temperature_2m_min":[8.7]}}
        """.utf8)
        let conditions = try WeatherMonitor.parseForecast(forecast)
        #expect(conditions == .init(temperature: 12.5, code: 80, isDay: false, high: 12.5, low: 8.7))
        let place = Data(#"{"results":[{"name":"Ankara","latitude":39.92,"longitude":32.85,"country":"Türkiye"}]}"#.utf8)
        #expect(try WeatherMonitor.parsePlace(place) == .init(name: "Ankara", latitude: 39.92, longitude: 32.85, country: "Türkiye"))
        #expect(try WeatherMonitor.parsePlace(Data(#"{"generationtime_ms":0.1}"#.utf8)) == nil)
        #expect(throws: WeatherMonitor.WeatherError.badResponse) { try WeatherMonitor.parseForecast(Data("{}".utf8)) }
    }

    @Test func symbols() {
        #expect(WeatherMonitor.symbolName(code: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherMonitor.symbolName(code: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherMonitor.symbolName(code: 81, isDay: true) == "cloud.heavyrain.fill")
        #expect(WeatherMonitor.symbolName(code: 96, isDay: true) == "cloud.bolt.rain.fill")
    }
}
