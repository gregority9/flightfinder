import Foundation

struct DealAssessment {
    let baseline: Double?
    let threshold: Double?
    let sampleCount: Int
}
enum DealPolicy {
    static let discount = 0.15
    static let minimumSamples = 5
    static let minimumSpan: TimeInterval = 24 * 3600
    // Count at most one successful observation per 30-minute window. Reopening
    // the app or repeatedly pulling to refresh cannot manufacture a baseline.
    static func assess(_ history: [PricePoint], now: Date = Date()) -> DealAssessment {
        var buckets: [Int: (Date, Double)] = [:]
        for point in history.sorted(by: { $0.date < $1.date }) {
            guard point.error == nil, let price = point.price, price.isFinite, price > 0,
                  point.date <= now, now.timeIntervalSince(point.date) <= 30 * 86400 else { continue }
            let bucket = Int(point.date.timeIntervalSince1970 / 1800)
            if buckets[bucket] == nil { buckets[bucket] = (point.date, price) }
        }
        let samples = Array(buckets.values)
        let span = (samples.map(\.0).max() ?? now).timeIntervalSince(samples.map(\.0).min() ?? now)
        guard samples.count >= minimumSamples, span >= minimumSpan else {
            return DealAssessment(baseline: nil, threshold: nil, sampleCount: samples.count)
        }
        let prices = samples.map(\.1).sorted(), middle = prices.count / 2
        let median = prices.count.isMultiple(of: 2) ? (prices[middle - 1] + prices[middle]) / 2 : prices[middle]
        return DealAssessment(baseline: median, threshold: (median * (1 - discount) * 100).rounded() / 100, sampleCount: samples.count)
    }
    static func shouldNotify(price: Double, threshold: Double?, previous: Double?) -> Bool {
        guard price.isFinite, price > 0, let threshold, price <= threshold else { return false }
        return previous == nil || price < previous! * 0.99
    }
}
