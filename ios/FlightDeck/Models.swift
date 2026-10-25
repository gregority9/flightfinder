import Foundation

struct FlightQuery: Codable, Equatable {
    var origin = "GDN"
    var destination = "ADB"
    var departureDate = Self.day(Calendar.current.date(byAdding: .day, value: 14, to: Date())!)
    var returnDate: String? = nil
    var adults = 1
    var currency = "PLN"
    var maxStops = 1
    var cabin = "ECONOMY"
    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ text: String) -> Date {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text) ?? Date()
    }
    var route: String { "\(origin) → \(destination)" }
}
struct AirportItem: Codable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
}
struct FlightLeg: Codable {
    let origin: String
    let destination: String
    let departure: String
    let arrival: String
    let airline: String
    let flightNumber: String
    let duration: Int
}
struct Journey: Codable {
    let legs: [FlightLeg]
    let duration: Int
    let stops: Int
}
struct Offer: Codable, Identifiable {
    let id: String
    let price: Double?
    let currency: String?
    let journeys: [Journey]
    let bookingUrl: String
    var totalDuration: Int { journeys.reduce(0) { $0 + $1.duration } }
}
struct SearchResponse: Codable {
    let query: FlightQuery
    let offers: [Offer]
    let checkedAt: String
    let cached: Bool
    let note: String
}
struct PriceAlert: Codable, Identifiable {
    let id: String
    let query: FlightQuery
    let targetPrice: Double
    let active: Bool
    let checkedAt: String?
    let lastPrice: Double?
    let error: String?
}
struct PricePoint: Codable, Identifiable {
    let checkedAt: String
    let price: Double?
    let error: String?
    var id: String { checkedAt }
    var date: Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: checkedAt) ?? ISO8601DateFormatter().date(from: checkedAt) ?? .distantPast
    }
}
struct PriceEvent: Codable, Identifiable {
    let id: String
    let createdAt: String
    let title: String
    let body: String
    let bookingUrl: String
    let delivered: Int
    let deliveryError: String?
}
struct ServerStatus: Codable {
    struct Notifications: Codable { let ntfy: Bool; let apns: Bool }
    let notifications: Notifications
    let checkIntervalSeconds: Int
}
struct OK: Decodable { let ok: Bool }
func money(_ price: Double?, _ currency: String?) -> String {
    guard let price else { return "Brak ceny" }
    guard let currency else { return String(format: "%.0f (waluta nieznana)", price) }
    return price.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
}
func clock(_ iso: String) -> String { String(iso.dropFirst(11).prefix(5)) }
func duration(_ minutes: Int) -> String { "\(minutes / 60) h \(minutes % 60) min" }
