import AppKit
import Foundation
import Observation

/// Hava durumu, Open-Meteo'dan (anahtarsız, ücretsiz). Konum izni istenmez: kullanıcı şehri yazar,
/// koordinatlar bir kez bulunur. Yarım saatte bir ve uyanınca güncellenir; kapalıyken ağ isteği yok.
@MainActor
@Observable
public final class WeatherMonitor {
    public struct Place: Codable, Equatable, Sendable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        public var country: String?

        public init(name: String, latitude: Double, longitude: Double, country: String? = nil) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.country = country
        }
    }

    public struct Conditions: Equatable, Sendable {
        public var temperature: Double
        /// WMO hava kodu.
        public var code: Int
        public var isDay: Bool
        public var high: Double?
        public var low: Double?
    }

    public enum WeatherError: Error, Equatable, CustomStringConvertible {
        case notFound
        case badResponse

        public var description: String {
            switch self {
            case .notFound: "şehir bulunamadı"
            case .badResponse: "beklenmeyen yanıt"
            }
        }
    }

    public private(set) var conditions: Conditions?
    public private(set) var place: Place?
    public private(set) var lastError: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var wakeToken: NSObjectProtocol?
    @ObservationIgnored private static let session = URLSession(configuration: .ephemeral)

    public static let refreshInterval: Duration = .seconds(30 * 60)

    public init() {}

    /// İdempotent: aynı yer için çalışıyorsa bir şey yapmaz.
    public func start(place: Place) {
        guard place != self.place || task == nil else { return }
        stop()
        self.place = place
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        wakeToken = nil
        place = nil
        conditions = nil
        lastError = nil
    }

    public func refresh() async {
        guard let place else { return }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        do {
            let (data, _) = try await Self.session.data(from: components.url!)
            guard self.place == place else { return }
            conditions = try Self.parseForecast(data)
            lastError = nil
            Log.integrations.notice("Hava durumu güncellendi")
        } catch {
            lastError = String(describing: error)
            Log.integrations.error("Hava durumu alınamadı: \(String(describing: error), privacy: .public)")
        }
    }

    /// Şehir adından ilk sonuç.
    public static func geocode(_ name: String, language: String = Locale.current.language.languageCode?.identifier ?? "en")
        async throws -> Place {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1"),
                                 URLQueryItem(name: "language", value: language), URLQueryItem(name: "format", value: "json")]
        let (data, _) = try await session.data(from: components.url!)
        guard let place = try parsePlace(data) else { throw WeatherError.notFound }
        return place
    }

    // MARK: - Ayrıştırma

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var weather_code: Int
            var is_day: Int
        }
        struct Daily: Decodable {
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
        }
        var current: Current
        var daily: Daily?
    }

    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
        }
        var results: [Result]?
    }

    nonisolated static func parseForecast(_ data: Data) throws -> Conditions {
        guard let response = try? JSONDecoder().decode(ForecastResponse.self, from: data) else { throw WeatherError.badResponse }
        return Conditions(temperature: response.current.temperature_2m, code: response.current.weather_code,
                          isDay: response.current.is_day != 0,
                          high: response.daily?.temperature_2m_max.first ?? nil,
                          low: response.daily?.temperature_2m_min.first ?? nil)
    }

    nonisolated static func parsePlace(_ data: Data) throws -> Place? {
        guard let response = try? JSONDecoder().decode(GeocodingResponse.self, from: data) else { throw WeatherError.badResponse }
        return response.results?.first.map { Place(name: $0.name, latitude: $0.latitude, longitude: $0.longitude, country: $0.country) }
    }

    /// WMO kodundan SF Symbol (gece ve gündüz).
    public nonisolated static func symbolName(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}
