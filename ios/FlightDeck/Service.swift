import Foundation
import SwiftUI
import UserNotifications

@MainActor final class FlightStore: ObservableObject {
    @Published var query = FlightQuery()
    @Published var response: SearchResponse?
    @Published var alerts: [PriceAlert] = []
    @Published var events: [PriceEvent] = []
    @Published var loading = false
    @Published var checking = false
    @Published var checkProgress = ""
    @Published var error: String?
    @Published var recent: [FlightQuery] = []
    private var checkTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private let provider = NativeFlightProvider.shared
    private let storageURL: URL
    private struct Snapshot: Codable {
        let version: Int
        let alerts: [PriceAlert]
        let events: [PriceEvent]
        let recent: [FlightQuery]
        let response: SearchResponse?
    }
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlightDeck", isDirectory: true)
        storageURL = directory.appendingPathComponent("device-data-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: storageURL.path) {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: storageURL))
                guard snapshot.version == 1 else { throw ServiceError.message("Nieobsługiwana wersja zapisanych danych.") }
                alerts = snapshot.alerts; events = snapshot.events; recent = snapshot.recent; response = snapshot.response
                if let first = recent.first { query = first }
            } else if let data = UserDefaults.standard.data(forKey: "recent"),
                      let previous = try? JSONDecoder().decode([FlightQuery].self, from: data) { recent = previous }
        } catch { self.error = "Nie udało się odczytać zapisanych danych. \(error.localizedDescription)" }
    }
    private func persist() {
        do {
            let data = try JSONEncoder().encode(Snapshot(version: 1, alerts: alerts, events: events, recent: recent, response: response))
            try data.write(to: storageURL, options: .atomic)
        } catch { self.error = "Nie udało się zapisać danych na telefonie. \(error.localizedDescription)" }
    }
    func search() async {
        guard !loading else { return }
        loading = true; error = nil; response = nil
        let snapshot = query
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.loading = false }
            do {
                let result = try await self.provider.search(snapshot)
                try Task.checkCancellation()
                self.response = result
                self.recent.removeAll { $0 == snapshot }; self.recent.insert(snapshot, at: 0)
                self.recent = Array(self.recent.prefix(8)); self.persist()
                let matching = self.alerts.filter { $0.query == snapshot && $0.active }.map(\.id)
                for id in matching { await self.observe(result, alertID: id) }
            } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        searchTask = task
        await task.value
        searchTask = nil
    }
    func suspend() { checkTask?.cancel(); searchTask?.cancel() }
    func refresh(force: Bool = false) async {
        guard checkTask == nil else { return }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.runChecks(force: force)
        }
        checkTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        checkTask = nil
    }
    private func runChecks(force: Bool) async {
        checking = true
        defer { checking = false; checkProgress = "" }
        let ids = alerts.filter(\.active).map(\.id)
        for (index, id) in ids.enumerated() {
            if Task.isCancelled { break }
            guard let alert = alerts.first(where: { $0.id == id }), alert.active else { continue }
            if alert.query.departureDate < FlightQuery.day(Date()) {
                if let i = alerts.firstIndex(where: { $0.id == id }) { alerts[i].active = false; alerts[i].error = "Termin minął"; persist() }
                continue
            }
            if !force, let checked = alert.checkedAt,
               Date().timeIntervalSince(PricePoint(checkedAt: checked, price: nil, error: nil).date) < 900 { continue }
            checkProgress = "Sprawdzam \(index + 1)/\(ids.count): \(alert.query.route)"
            do {
                let result = try await provider.search(alert.query)
                try Task.checkCancellation()
                await observe(result, alertID: id)
            } catch is CancellationError { break }
            catch {
                if Task.isCancelled { break }
                if let i = alerts.firstIndex(where: { $0.id == id }) {
                    alerts[i].checkedAt = ISO8601DateFormatter().string(from: Date())
                    alerts[i].error = error.localizedDescription
                    persist()
                }
            }
        }
    }
    private func observe(_ response: SearchResponse, alertID: String) async {
        guard let i = alerts.firstIndex(where: { $0.id == alertID }), alerts[i].active else { return }
        if alerts[i].history.contains(where: { $0.checkedAt == response.checkedAt }) { return }
        let best = response.offers.filter { $0.currency == response.query.currency && ($0.price ?? 0) > 0 }
            .min { $0.price! < $1.price! }
        let assessment = DealPolicy.assess(alerts[i].history)
        alerts[i].baseline = assessment.baseline
        alerts[i].checkedAt = response.checkedAt
        guard let best, let price = best.price else {
            alerts[i].error = response.offers.isEmpty ? "Brak dostępnych połączeń w tym sprawdzeniu" : "Brak cen w wybranej walucie"
            persist(); return
        }
        let threshold = alerts[i].automatic ? assessment.threshold : alerts[i].targetPrice
        let notify = DealPolicy.shouldNotify(price: price, threshold: threshold, previous: alerts[i].lastNotifiedPrice)
        if let threshold, price > threshold { alerts[i].lastNotifiedPrice = nil }
        alerts[i].lastPrice = price; alerts[i].error = nil
        alerts[i].history.append(PricePoint(checkedAt: response.checkedAt, price: price, error: nil))
        alerts[i].history = Array(alerts[i].history.suffix(200))
        // Show the first established baseline without claiming the current price triggered it.
        if alerts[i].baseline == nil { alerts[i].baseline = DealPolicy.assess(alerts[i].history).baseline }
        var pendingEvent: PriceEvent?
        if notify {
            alerts[i].lastNotifiedPrice = price
            let saving = assessment.baseline.map { Int((1 - price / $0) * 100) }
            let detail = alerts[i].automatic ? "\(saving ?? 15)% poniżej mediany wcześniejszych pomiarów." : "Cena osiągnęła ustawiony przez Ciebie próg."
            let event = PriceEvent(id: UUID().uuidString, createdAt: response.checkedAt,
                title: "\(response.query.route): \(money(price, response.query.currency))",
                body: "\(detail) Wylot \(response.query.departureDate). Cena łącznie dla \(response.query.adults) os.",
                bookingUrl: best.bookingUrl, delivered: 0, deliveryError: nil)
            events.insert(event, at: 0); events = Array(events.prefix(100)); pendingEvent = event
        }
        persist()
        if let event = pendingEvent {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent(); content.title = event.title; content.body = event.body; content.sound = .default
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
                if let e = events.firstIndex(where: { $0.id == event.id }) { events[e].delivered = 1; persist() }
            } catch {
                if let e = events.firstIndex(where: { $0.id == event.id }) { events[e].deliveryError = "Nie udało się wyświetlić powiadomienia."; persist() }
            }
        }
    }
    func addAlert(query: FlightQuery, price: Double?, automatic: Bool) async throws {
        if !automatic && (!(price?.isFinite ?? false) || (price ?? 0) <= 0) { throw ServiceError.message("Podaj poprawną cenę.") }
        let id: String
        if let i = alerts.firstIndex(where: { $0.query == query }) {
            alerts[i].automatic = automatic; alerts[i].targetPrice = price ?? 0; alerts[i].active = true; alerts[i].lastNotifiedPrice = nil
            id = alerts[i].id
        } else {
            guard alerts.count < 10 else { throw ServiceError.message("Limit 10 obserwowanych tras. Usuń niepotrzebne.") }
            id = UUID().uuidString
            alerts.insert(PriceAlert(id: id, query: query, targetPrice: price ?? 0, automatic: automatic, active: true,
                checkedAt: nil, lastPrice: nil, error: nil, baseline: nil, lastNotifiedPrice: nil, history: []), at: 0)
        }
        persist()
        if let response, response.query == query { await observe(response, alertID: id) }
        Task { await refresh() }
    }
    func remove(_ alert: PriceAlert) async {
        alerts.removeAll { $0.id == alert.id }; persist()
    }
    func toggle(_ alert: PriceAlert) async {
        if let i = alerts.firstIndex(where: { $0.id == alert.id }) { alerts[i].active.toggle(); persist() }
        await refresh()
    }
}
