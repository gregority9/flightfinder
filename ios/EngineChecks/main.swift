import Foundation

@main struct EngineChecks {
    static func main() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        func point(_ price: Double?, hours: Double, error: String? = nil) -> PricePoint {
            PricePoint(checkedAt: ISO8601DateFormatter().string(from: stamp.addingTimeInterval(hours * 3600)), price: price, error: error)
        }
        let history = [point(100, hours: -30), point(100, hours: -24), point(100, hours: -18), point(100, hours: -12), point(1000, hours: -6)]
        let result = DealPolicy.assess(history, now: stamp)
        precondition(result.baseline == 100 && result.threshold == 85)
        precondition(DealPolicy.shouldNotify(price: 80, threshold: result.threshold, previous: nil))
        precondition(!DealPolicy.shouldNotify(price: 80, threshold: result.threshold, previous: 80))
        precondition(DealPolicy.shouldNotify(price: 75, threshold: result.threshold, previous: 80))
        precondition(!DealPolicy.shouldNotify(price: 90, threshold: result.threshold, previous: nil))
        precondition(DealPolicy.assess(Array(history.prefix(4)), now: stamp).threshold == nil)
        let repeated = (0..<20).map { point(100, hours: -Double($0) / 600) }
        precondition(DealPolicy.assess(repeated, now: stamp).threshold == nil)
        let shortSpan = (1...6).map { point(100, hours: -Double($0)) }
        precondition(DealPolicy.assess(shortSpan, now: stamp).threshold == nil)
        precondition(DealPolicy.assess(history + [point(nil, hours: -2), point(0, hours: -1)], now: stamp).threshold == 85)
        precondition(DealPolicy.assess(history, now: stamp.addingTimeInterval(31 * 86400)).threshold == nil)
        let q = FlightQuery()
        let alert = PriceAlert(id: "test", query: q, targetPrice: 0, automatic: true, active: true,
                              checkedAt: nil, lastPrice: 80, error: nil, baseline: 100, lastNotifiedPrice: 80, history: history)
        let restored = try JSONDecoder().decode(PriceAlert.self, from: JSONEncoder().encode(alert))
        precondition(restored.effectiveTarget == 85 && restored.history.count == 5 && restored.lastNotifiedPrice == 80)
        let engine = try FliCore(scriptURL: URL(fileURLWithPath: "ios/FlightDeck/Engine/fli-engine.js"))
        let airports: [AirportItem] = try engine.call("airports", ["GDN"])
        precondition(airports.first?.code == "GDN")
        let text = try engine.queryText(q)
        let request: EngineRequest = try engine.call("request", [text])
        precondition(request.url.hasPrefix("https://www.google.com/travel/flights?tfs="))
        let page = try String(contentsOfFile: "engine/tests/search-page.html", encoding: .utf8)
        let parsed: EnginePage = try engine.call("decodePage", [text, page])
        precondition(!parsed.rows.isEmpty)
        print("PASS: JavaScriptCore codecs, warmup, median, deduplication, expiry and persisted automatic alert")
    }
}
