import Foundation
import JavaScriptCore

struct EngineRequest: Decodable { let url: String }
struct EngineRow: Decodable { let wire: String; let price: Double?; let currency: String? }
struct EnginePage: Decodable { let rows: [EngineRow] }
struct EngineEnvelope<T: Decodable>: Decodable { let data: T?; let error: String? }

enum ServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
// Owned by NativeFlightProvider's actor; JSContext never crosses actors or runs Google scripts.
final class FliCore {
    private let context: JSContext
    init(scriptURL: URL? = nil) throws {
        guard let context = JSContext(),
              let url = scriptURL ?? Bundle.main.url(forResource: "fli-engine", withExtension: "js") ?? Bundle.main.url(forResource: "fli-engine", withExtension: "js", subdirectory: "Engine") else {
            throw ServiceError.message("Brak silnika Fli w aplikacji. Zainstaluj ponownie najnowszy plik IPA.")
        }
        self.context = context
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        if let exception = context.exception { throw ServiceError.message("Nie udało się uruchomić Fli: \(exception)") }
    }
    func call<T: Decodable>(_ method: String, _ arguments: [Any]) throws -> T {
        context.exception = nil
        let output = context.objectForKeyedSubscript("FlightEngine")?.objectForKeyedSubscript(method)?.call(withArguments: arguments)
        guard context.exception == nil, let text = output?.toString(), let data = text.data(using: .utf8) else {
            throw ServiceError.message("Błąd lokalnego silnika wyszukiwania.")
        }
        let envelope = try JSONDecoder().decode(EngineEnvelope<T>.self, from: data)
        if let error = envelope.error { throw ServiceError.message(error) }
        guard let value = envelope.data else { throw ServiceError.message("Brak danych w odpowiedzi Fli.") }
        return value
    }
    func queryText(_ query: FlightQuery) throws -> String {
        String(decoding: try JSONEncoder().encode(query), as: UTF8.self)
    }
}

actor NativeFlightProvider {
    static let shared = NativeFlightProvider()
    private var engine: FliCore?
    private var cache: [String: (Date, SearchResponse)] = [:]
    private var lastRequest = Date.distantPast
    private let session = URLSession(configuration: .ephemeral, delegate: GoogleRedirects(), delegateQueue: nil)
    private func core() throws -> FliCore {
        if let engine { return engine }
        let value = try FliCore(); engine = value; return value
    }
    func airports(_ text: String) throws -> [AirportItem] { try core().call("airports", [text]) }
    private func page(_ urlString: String) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: urlString), url.scheme == "https", url.host == "www.google.com", url.path == "/travel/flights" else {
            throw ServiceError.message("Nieprawidłowy adres wyszukiwania.")
        }
        let delay = 0.35 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        var request = URLRequest(url: url, timeoutInterval: 35)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("pl,en-US;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("SOCS=CAISNQgQEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjQwMzE3LjA5X3AwGgJlbiADGgYIgLC_rwY", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), http.url?.host == "www.google.com" else {
            throw ServiceError.message("Google odmówiło wyszukiwania lub wymaga zgody. Spróbuj później albo w innej sieci.")
        }
        guard data.count <= 12_000_000, let html = String(data: data, encoding: .utf8) else {
            throw ServiceError.message("Nieprawidłowa odpowiedź Google Flights.")
        }
        return html
    }
    func search(_ query: FlightQuery) async throws -> SearchResponse {
        let core = try core(), text = try core.queryText(query)
        let request: EngineRequest = try core.call("request", [text])
        if let (date, response) = cache[text], Date().timeIntervalSince(date) < 300 {
            return SearchResponse(query: response.query, offers: response.offers, checkedAt: response.checkedAt, cached: true, note: response.note)
        }
        let html = try await page(request.url)
        let parsed: EnginePage = try core.call("decodePage", [text, html])
        var offers: [Offer] = []
        var partial = false
        for row in query.returnDate == nil ? parsed.rows : Array(parsed.rows.prefix(5)) {
            try Task.checkCancellation()
            if query.returnDate != nil {
                do {
                    let backRequest: EngineRequest = try core.call("request", [text, row.wire])
                    let backHTML = try await page(backRequest.url)
                    let back: EnginePage = try core.call("decodePage", [text, backHTML])
                    for returned in back.rows {
                        let raw = String(decoding: try JSONEncoder().encode([row.wire, returned.wire]), as: UTF8.self)
                        let offer: Offer = try core.call("offer", [text, raw]); offers.append(offer)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { partial = true }
            } else {
                let raw = String(decoding: try JSONEncoder().encode([row.wire]), as: UTF8.self)
                let offer: Offer = try core.call("offer", [text, raw]); offers.append(offer)
            }
        }
        if partial && offers.isEmpty { throw ServiceError.message("Nie udało się pobrać lotów powrotnych. Spróbuj ponownie później.") }
        offers.sort { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
        let note = "Cena łącznie dla wszystkich pasażerów. Potwierdź cenę i bagaż przed zakupem." + (partial ? " Część lotów powrotnych jest niedostępna — wyniki są niepełne." : "")
        let response = SearchResponse(query: query, offers: offers, checkedAt: ISO8601DateFormatter().string(from: Date()), cached: false, note: note)
        cache = cache.filter { Date().timeIntervalSince($0.value.0) < 300 }
        if cache.count >= 30 { cache.removeValue(forKey: cache.keys.first!) }
        cache[text] = (Date(), response)
        return response
    }
}
final class GoogleRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url?.scheme == "https" && request.url?.host == "www.google.com" && request.url?.path == "/travel/flights"
        completionHandler(allowed ? request : nil)
    }
}
