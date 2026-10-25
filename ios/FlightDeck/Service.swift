import Foundation
import Security
import SwiftUI

enum Vault {
    static let service = "com.gregority9.flightdeck"
    static func read(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String, _ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw ServiceError.message("Nie udało się zapisać klucza w pęku kluczy.")
        }
    }
}
enum ServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct API {
    var base: String
    var token: String
    static var saved: API { API(base: Vault.read("server"), token: Vault.read("token")) }
    var ready: Bool { !base.isEmpty && !token.isEmpty }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let components = URLComponents(string: base), components.scheme == "https",
              components.host != nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ServiceError.message("W Ustawieniach wpisz adres serwera HTTPS i klucz dostępu.")
        }
        guard let rootURL = components.url else { throw ServiceError.message("Nieprawidłowy adres serwera") }
        let root = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + path) else { throw ServiceError.message("Nieprawidłowy adres serwera") }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Do not follow redirects: a misconfigured server must not redirect this bearer token.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.message("Brak odpowiedzi serwera") }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ServiceError.message(detail?["detail"] as? String ?? "Błąd \(http.statusCode). Sprawdź dane i ustawienia.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data.isEmpty ? Data("{\"ok\":true}".utf8) : data)
    }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
@MainActor final class FlightStore: ObservableObject {
    @Published var query = FlightQuery()
    @Published var response: SearchResponse?
    @Published var alerts: [PriceAlert] = []
    @Published var events: [PriceEvent] = []
    @Published var loading = false
    @Published var error: String?
    @Published var recent: [FlightQuery] = []
    @Published var configured = API.saved.ready
    init() {
        if let data = UserDefaults.standard.data(forKey: "recent"),
           let saved = try? JSONDecoder().decode([FlightQuery].self, from: data) { recent = saved }
    }
    func search() async {
        guard !loading else { return }
        loading = true; error = nil; response = nil
        let snapshot = query
        defer { loading = false }
        do {
            response = try await API.saved.request("/v1/search", method: "POST", body: API.saved.encode(snapshot))
            recent.removeAll { $0 == snapshot }; recent.insert(snapshot, at: 0); recent = Array(recent.prefix(8))
            UserDefaults.standard.set(try? JSONEncoder().encode(recent), forKey: "recent")
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard API.saved.ready else { return }
        do {
            async let a: [PriceAlert] = API.saved.request("/v1/alerts")
            async let e: [PriceEvent] = API.saved.request("/v1/events")
            (alerts, events) = try await (a, e)
        } catch { self.error = error.localizedDescription }
    }
    func addAlert(query: FlightQuery, price: Double) async throws {
        struct Body: Encodable { let query: FlightQuery; let targetPrice: Double }
        let _: PriceAlert = try await API.saved.request("/v1/alerts", method: "POST", body: API.saved.encode(Body(query: query, targetPrice: price)))
        await refresh()
    }
    func remove(_ alert: PriceAlert) async {
        do { let _: OK = try await API.saved.request("/v1/alerts/\(alert.id)", method: "DELETE"); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func toggle(_ alert: PriceAlert) async {
        struct Body: Encodable { let active: Bool }
        do {
            let _: OK = try await API.saved.request("/v1/alerts/\(alert.id)", method: "PATCH", body: API.saved.encode(Body(active: !alert.active)))
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}
