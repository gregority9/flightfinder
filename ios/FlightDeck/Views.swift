import SwiftUI
import Charts
import UserNotifications

enum Theme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let card = Color(red: 0.085, green: 0.11, blue: 0.18)
    static let lime = Color(red: 0.78, green: 0.96, blue: 0.39)
}
extension View {
    func deckCard() -> some View { padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 24)) }
}
struct RootView: View {
    @EnvironmentObject var store: FlightStore
    @Environment(\.scenePhase) var phase
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { SearchView(openSettings: { tab = 2 }) }
                .tabItem { Label("Szukaj", systemImage: "airplane") }.tag(0)
            NavigationStack { AlertsView() }
                .tabItem { Label("Alerty", systemImage: "bell.badge") }.tag(1)
            NavigationStack { SettingsView() }
                .tabItem { Label("Ustawienia", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .task { await store.refresh() }
        .onChange(of: phase) { _, value in if value == .active { Task { await store.refresh() } } }
    }
}
struct SearchView: View {
    @EnvironmentObject var store: FlightStore
    var openSettings: () -> Void
    @State private var airportSide: Int?
    @State private var roundTrip = false
    @State private var sort = "price"
    @State private var alertQuery: FlightQuery?
    var offers: [Offer] {
        let rows = store.response?.offers ?? []
        return sort == "duration" ? rows.sorted { $0.totalDuration < $1.totalDuration } : rows.sorted { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("FLIGHTDECK", systemImage: "airplane.circle.fill").font(.caption.weight(.bold)).tracking(3).foregroundStyle(Theme.lime)
                    Spacer()
                    Text("TWÓJ NASTĘPNY LOT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text("Mniej za lot.\nWięcej na podróż.").font(.system(size: 36, weight: .bold, design: .rounded)).lineSpacing(-2)
                Text("Znajdź połączenie. Ustaw cenę. Ruszaj.").foregroundStyle(.secondary)
                if !store.configured {
                    Button(action: openSettings) {
                        Label("Połącz serwer, aby wyszukiwać loty", systemImage: "network")
                            .frame(maxWidth: .infinity).deckCard()
                    }
                }
                VStack(spacing: 18) {
                    Picker("Typ podróży", selection: $roundTrip) {
                        Text("W jedną stronę").tag(false); Text("Tam i z powrotem").tag(true)
                    }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        airportButton("SKĄD", store.query.origin, side: 0)
                        Button { let old = store.query.origin; store.query.origin = store.query.destination; store.query.destination = old } label: {
                            Image(systemName: "arrow.left.arrow.right").font(.title3).padding(12).background(.white.opacity(0.06), in: Circle())
                        }.accessibilityLabel("Zamień lotniska")
                        airportButton("DOKĄD", store.query.destination, side: 1)
                    }
                    Divider()
                    DatePicker("Wylot", selection: Binding(get: { FlightQuery.date(store.query.departureDate) }, set: {
                        store.query.departureDate = FlightQuery.day($0)
                        if let back = store.query.returnDate, back < store.query.departureDate { store.query.returnDate = store.query.departureDate }
                    }), in: Date()..., displayedComponents: .date)
                    if roundTrip {
                        DatePicker("Powrót", selection: Binding(get: { FlightQuery.date(store.query.returnDate ?? store.query.departureDate) }, set: {
                            store.query.returnDate = FlightQuery.day($0)
                        }), in: FlightQuery.date(store.query.departureDate)..., displayedComponents: .date)
                    }
                    HStack {
                        Stepper("\(store.query.adults) os.", value: $store.query.adults, in: 1...9)
                        Picker("Waluta", selection: $store.query.currency) {
                            ForEach(["PLN", "EUR", "TRY", "USD", "GBP"], id: \.self) { Text($0) }
                        }.labelsHidden()
                    }
                    Picker("Przesiadki", selection: $store.query.maxStops) {
                        Text("Bezpośrednio").tag(0); Text("Do 1").tag(1); Text("Do 2").tag(2)
                    }.pickerStyle(.segmented)
                    Picker("Klasa", selection: $store.query.cabin) {
                        Text("Economy").tag("ECONOMY"); Text("Premium economy").tag("PREMIUM_ECONOMY")
                        Text("Business").tag("BUSINESS"); Text("First").tag("FIRST")
                    }
                    Button { Task { await store.search() } } label: {
                        HStack {
                            if store.loading { ProgressView().tint(Theme.background) }
                            Text(store.loading ? "Szukam połączeń…" : "Znajdź loty").fontWeight(.bold)
                            Spacer(); Image(systemName: "arrow.up.right")
                        }.padding(18).foregroundStyle(Theme.background).background(Theme.lime, in: RoundedRectangle(cornerRadius: 16))
                    }.disabled(store.loading || !store.configured)
                }.deckCard()
                if let error = store.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).deckCard() }
                if let response = store.response {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(response.query.route).font(.title2.bold())
                            Text("\(response.query.departureDate) · \(offers.count) połączeń").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu { Button("Najtańsze") { sort = "price" }; Button("Najszybsze") { sort = "duration" } } label: { Label("Sortuj", systemImage: "arrow.up.arrow.down") }
                    }
                    Button { alertQuery = response.query } label: { Label("Obserwuj cenę tej trasy", systemImage: "bell.badge").frame(maxWidth: .infinity).deckCard() }
                    if offers.isEmpty { ContentUnavailableView("Brak wyników", systemImage: "airplane", description: Text("Zmień daty lub przesiadki. Dostawca może nie zwracać wszystkich połączeń.")) }
                    ForEach(offers) { offer in OfferCard(offer: offer) }
                    Text(response.note).font(.caption).foregroundStyle(.secondary)
                    Text("Sprawdzono: \(response.checkedAt.prefix(16).replacingOccurrences(of: "T", with: " ")) UTC\(response.cached ? " · pamięć do 5 min" : "")").font(.caption2).foregroundStyle(.secondary)
                } else if !store.recent.isEmpty {
                    Text("Ostatnio wyszukiwane").font(.title3.bold())
                    ForEach(Array(store.recent.enumerated()), id: \.offset) { _, query in
                        Button {
                            store.query = query; roundTrip = query.returnDate != nil
                            Task { await store.search() }
                        } label: {
                            HStack { VStack(alignment: .leading) { Text(query.route).font(.headline); Text(query.departureDate).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") }.deckCard()
                        }
                    }
                }
            }.padding(20)
        }
        .background(Theme.background).toolbar(.hidden, for: .navigationBar)
        .onChange(of: roundTrip) { _, value in store.query.returnDate = value ? (store.query.returnDate ?? store.query.departureDate) : nil }
        .sheet(isPresented: Binding(get: { airportSide != nil }, set: { if !$0 { airportSide = nil } })) {
            AirportPicker { airport in
                if airportSide == 0 { store.query.origin = airport.code } else { store.query.destination = airport.code }
                airportSide = nil
            }
        }
        .sheet(isPresented: Binding(get: { alertQuery != nil }, set: { if !$0 { alertQuery = nil } })) {
            if let query = alertQuery { AddAlertView(query: query) }
        }
    }
    func airportButton(_ label: String, _ code: String, side: Int) -> some View {
        Button { airportSide = side } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(code).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Wybierz lotnisko").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityLabel("\(label): \(code). Wybierz lotnisko")
    }
}
struct AirportPicker: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var rows: [AirportItem] = []
    @State private var error: String?
    let choose: (AirportItem) -> Void
    static let popular = [AirportItem(code: "GDN", name: "Gdańsk"), AirportItem(code: "WAW", name: "Warszawa Chopin"), AirportItem(code: "HAM", name: "Hamburg"), AirportItem(code: "BER", name: "Berlin"), AirportItem(code: "ADB", name: "Izmir"), AirportItem(code: "AYT", name: "Antalya"), AirportItem(code: "IST", name: "Istanbul"), AirportItem(code: "SAW", name: "Istanbul Sabiha Gökçen"), AirportItem(code: "ASR", name: "Kayseri"), AirportItem(code: "NRT", name: "Tokyo Narita")]
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(text.isEmpty ? Self.popular : rows) { airport in
                    Button { choose(airport) } label: {
                        HStack { Text(airport.code).font(.title3.bold()).foregroundStyle(Theme.lime); Text(airport.name).foregroundStyle(.primary) }
                    }
                }
                if text.count == 3 && rows.isEmpty {
                    Button("Użyj kodu \(text.uppercased())") { choose(AirportItem(code: text.uppercased(), name: text)) }
                }
            }.searchable(text: $text, prompt: "Miasto, lotnisko lub kod IATA")
            .navigationTitle("Wybierz lotnisko")
            .toolbar { Button("Gotowe") { dismiss() } }
            .task(id: text) {
                guard !text.isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
                    let result: [AirportItem] = try await API.saved.request("/v1/airports?q=\(escaped)")
                    guard !Task.isCancelled else { return }; rows = result; error = nil
                } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }.tint(Theme.lime)
    }
}
struct OfferCard: View {
    let offer: Offer
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(money(offer.price, offer.currency)).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(Theme.lime)
                Spacer(); Text(offer.journeys.count == 2 ? "TAM I Z POWROTEM" : "W JEDNĄ STRONĘ").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            ForEach(Array(offer.journeys.enumerated()), id: \.offset) { index, journey in
                if let first = journey.legs.first, let last = journey.legs.last {
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading) { Text(clock(first.departure)).font(.title2.bold()); Text(first.origin).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        VStack(spacing: 5) {
                            Text(duration(journey.duration)).font(.caption)
                            Image(systemName: "airplane").foregroundStyle(Theme.lime)
                            Text(journey.stops == 0 ? "Bezpośrednio" : "Przesiadki: \(journey.stops)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) { Text(clock(last.arrival)).font(.title2.bold()); Text(last.destination).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("\(first.departure.prefix(10)) → \(last.arrival.prefix(10)) · czas lokalny").font(.caption2).foregroundStyle(.secondary)
                    DisclosureGroup("Szczegóły lotów") {
                        ForEach(Array(journey.legs.enumerated()), id: \.offset) { _, leg in
                            Text("\(leg.airline) \(leg.flightNumber) · \(leg.origin) \(clock(leg.departure)) → \(leg.destination) \(clock(leg.arrival))")
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }
                    }.font(.caption)
                }
            }
            if let url = URL(string: offer.bookingUrl), url.scheme == "https" {
                Link(destination: url) { HStack { Text("Sprawdź w Google Flights"); Spacer(); Image(systemName: "arrow.up.right") }.font(.callout.bold()) }
            }
        }.deckCard()
    }
}
struct AddAlertView: View {
    @EnvironmentObject var store: FlightStore
    @Environment(\.dismiss) var dismiss
    let query: FlightQuery
    @State private var price = ""
    @State private var error: String?
    @State private var saving = false
    var amount: Double? { Double(price.replacingOccurrences(of: ",", with: ".")) }
    var body: some View {
        NavigationStack {
            Form {
                Section(query.route) { Text(query.departureDate); if let back = query.returnDate { Text("Powrót: \(back)") } }
                Section("Daj znać, gdy cena wyniesie maksymalnie") {
                    HStack { TextField("np. 350", text: $price).keyboardType(.decimalPad); Text(query.currency) }
                    Text("Cena łącznie dla \(query.adults) os. Serwer sprawdza trasę także po zamknięciu aplikacji.").font(.caption)
                }
                Section { Text("Powiadomienia wymagają uruchomionego serwera oraz skonfigurowanego APNs lub ntfy. Wyniki pojawią się również w zakładce Alerty.").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.orange) }
                Button(saving ? "Zapisuję…" : "Utwórz alert") {
                    guard let amount else { return }
                    saving = true
                    Task {
                        do { try await store.addAlert(query: query, price: amount); dismiss() }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.disabled(saving || (amount ?? 0) <= 0)
            }.navigationTitle("Obserwuj cenę").toolbar { Button("Zamknij") { dismiss() } }
        }
    }
}
struct AlertsView: View {
    @EnvironmentObject var store: FlightStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ty planujesz.\nMy pilnujemy cen.").font(.system(size: 32, weight: .bold, design: .rounded))
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                if store.alerts.isEmpty { ContentUnavailableView("Jeszcze bez alertów", systemImage: "bell", description: Text("Wyszukaj trasę i wybierz „Obserwuj cenę tej trasy”.")) }
                ForEach(store.alerts) { alert in
                    NavigationLink { AlertDetail(identifier: alert.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(alert.query.route).font(.title2.bold()); Spacer(); Image(systemName: alert.active ? "bell.fill" : "pause.circle").foregroundStyle(Theme.lime) }
                            Text("\(alert.query.departureDate) · do \(money(alert.targetPrice, alert.query.currency))").font(.callout).foregroundStyle(.secondary)
                            Text("Ostatnio: \(money(alert.lastPrice, alert.query.currency))").foregroundStyle(Theme.lime)
                            if let error = alert.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            if alert.checkedAt == nil { Text("Oczekuje na pierwsze sprawdzenie").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).deckCard()
                    }.buttonStyle(.plain)
                }
                if !store.events.isEmpty {
                    Text("Znalezione okazje").font(.title2.bold()).padding(.top)
                    ForEach(store.events) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title).font(.headline).foregroundStyle(Theme.lime)
                            Text(event.body).font(.callout)
                            Text(event.createdAt.prefix(16).replacingOccurrences(of: "T", with: " ") + " UTC").font(.caption2).foregroundStyle(.secondary)
                            if let error = event.deliveryError { Text(error).font(.caption).foregroundStyle(.orange) }
                            if let url = URL(string: event.bookingUrl), url.scheme == "https" { Link("Sprawdź aktualną cenę ↗", destination: url) }
                        }.frame(maxWidth: .infinity, alignment: .leading).deckCard()
                    }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Alerty").refreshable { await store.refresh() }
    }
}
struct AlertDetail: View {
    @EnvironmentObject var store: FlightStore
    @Environment(\.dismiss) var dismiss
    let identifier: String
    @State private var history: [PricePoint] = []
    @State private var error: String?
    @State private var confirmDelete = false
    var alert: PriceAlert? { store.alerts.first { $0.id == identifier } }
    var body: some View {
        ScrollView {
            if let alert {
                VStack(alignment: .leading, spacing: 22) {
                    Text(alert.query.route).font(.largeTitle.bold())
                    Text("Próg: \(money(alert.targetPrice, alert.query.currency))").foregroundStyle(Theme.lime)
                    Text("\(alert.query.departureDate)\(alert.query.returnDate.map { " → " + $0 } ?? "") · \(alert.query.adults) os.")
                    if history.contains(where: { $0.price != nil }) {
                        Chart {
                            ForEach(history.sorted { $0.date < $1.date }) { point in
                                if let price = point.price { LineMark(x: .value("Data", point.date), y: .value(alert.query.currency, price)).foregroundStyle(Theme.lime); PointMark(x: .value("Data", point.date), y: .value(alert.query.currency, price)).foregroundStyle(Theme.lime) }
                            }
                            RuleMark(y: .value("Próg", alert.targetPrice)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [5]))
                        }.frame(height: 210).deckCard()
                    } else { Text("Historia pojawi się po pierwszym udanym sprawdzeniu.").foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.orange) }
                    Button(alert.active ? "Wstrzymaj alert" : "Wznów alert") { Task { await store.toggle(alert) } }.buttonStyle(.bordered)
                    Button("Usuń alert", role: .destructive) { confirmDelete = true }
                    Text("Ostatnie sprawdzenia").font(.headline)
                    ForEach(history) { point in
                        VStack(alignment: .leading) {
                            Text(point.date, style: .date).font(.caption); Text(point.date, style: .time).font(.caption)
                            Text(point.error ?? money(point.price, alert.query.currency)).foregroundStyle(point.error == nil ? Color.primary : Color.orange)
                        }.frame(maxWidth: .infinity, alignment: .leading).deckCard()
                    }
                }.padding(20)
            }
        }.background(Theme.background).navigationTitle("Historia ceny")
        .task { await load() }.refreshable { await store.refresh(); await load() }
        .confirmationDialog("Usunąć alert i historię?", isPresented: $confirmDelete) {
            Button("Usuń", role: .destructive) { if let alert { Task { await store.remove(alert); if store.alerts.allSatisfy({ $0.id != identifier }) { dismiss() } } } }
        }
    }
    func load() async {
        do { history = try await API.saved.request("/v1/alerts/\(identifier)/history"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: FlightStore
    @State private var server = Vault.read("server")
    @State private var token = Vault.read("token")
    @State private var message: String?
    @State private var status: ServerStatus?
    @State private var busy = false
    @AppStorage("pushError") var pushError = ""
    var body: some View {
        Form {
            Section("Twój serwer") {
                TextField("https://loty.twojadomena.pl", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Klucz dostępu API", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(busy ? "Łączę…" : "Zapisz i sprawdź połączenie") {
                    busy = true
                    Task {
                        do {
                            let api = API(base: server.trimmingCharacters(in: .whitespacesAndNewlines), token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                            status = try await api.request("/v1/status")
                            try Vault.save("server", api.base); try Vault.save("token", api.token)
                            store.configured = true; message = "Połączono z serwerem."
                            if let device = UserDefaults.standard.string(forKey: "apnsToken") { try? await registerDevice(device) }
                            await store.refresh()
                        } catch { message = error.localizedDescription }
                        busy = false
                    }
                }.disabled(busy)
                if let message { Text(message).font(.caption) }
            }
            Section("Powiadomienia") {
                if let status {
                    LabeledContent("Sprawdzanie", value: "co \(status.checkIntervalSeconds / 60) min")
                    LabeledContent("APNs na serwerze", value: status.notifications.apns ? "Skonfigurowane" : "Wyłączone")
                    LabeledContent("ntfy na serwerze", value: status.notifications.ntfy ? "Skonfigurowane" : "Wyłączone")
                }
                Button("Włącz powiadomienia iPhone") {
                    Task { @MainActor in
                        do {
                            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                            if granted { pushError = ""; UIApplication.shared.registerForRemoteNotifications(); message = "Zgoda udzielona. Rejestruję urządzenie…" }
                            else { message = "Zezwól na powiadomienia w Ustawieniach iPhone’a." }
                        } catch { message = error.localizedDescription }
                    }
                }
                if !pushError.isEmpty { Text(pushError).font(.caption).foregroundStyle(.orange) }
                Text("APNs wymaga podpisu z uprawnieniem Push Notifications i konfiguracji klucza Apple na serwerze. Przy sideloadingu możesz odbierać alerty w aplikacji ntfy, subskrybując temat ustawiony na serwerze.").font(.caption).foregroundStyle(.secondary)
                Link("Otwórz ntfy", destination: URL(string: "https://ntfy.sh")!)
            }
            Section("O cenach") {
                Text("Źródło: Fli / Google Flights. Wyniki mogą być niepełne. Cena obejmuje wybraną liczbę dorosłych; bagaż i warunki taryfy sprawdź przed zakupem. Godziny lotów są lokalne dla lotnisk.").font(.caption)
                Text("To osobista aplikacja korzystająca z jednego chronionego serwera. Klucz jest przechowywany w pęku kluczy iPhone’a.").font(.caption)
            }
        }.navigationTitle("Ustawienia")
        .task { if API.saved.ready { status = try? await API.saved.request("/v1/status") } }
    }
}
