import ConclaveEngine
import SwiftUI

/// The selected deck: its head, the card list in sections, and the picked card in the inspector on the right
/// (the Windows app's Karten tab, without editing yet).
struct DeckView: View {
    @Environment(EngineModel.self) private var engine
    let summary: DeckSummary
    @State private var deck: Deck?
    @State private var loadError: Error?
    @State private var selection: CardRow.ID?
    @AppStorage("deckGrouping") private var grouping: DeckGrouping = .category
    @AppStorage("showCardInspector") private var showInspector = true

    var body: some View {
        content
            .navigationTitle(summary.name)
            .navigationSubtitle(summary.commanders.joined(separator: " & "))
            // a new version (saved on another device, then reloaded) loads the deck again
            .task(id: "\(summary.slug)#\(summary.version ?? 0)") { await load() }
            .inspector(isPresented: $showInspector) {
                CardInspector(row: selectedRow, currency: deck?.currency ?? "eur")
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
            }
            .toolbar {
                ToolbarItem {
                    Picker("Group By", selection: $grouping) {
                        Text("Category").tag(DeckGrouping.category)
                        Text("Type").tag(DeckGrouping.type)
                        Text("Mana Value").tag(DeckGrouping.manaValue)
                    }
                    .pickerStyle(.menu)
                    .help("Group the cards by category, type or mana value")
                }
                ToolbarItem {
                    Button { showInspector.toggle() } label: {
                        Label("Card Details", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the picked card")
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let deck, deck.slug == summary.slug {
            VStack(spacing: 0) {
                DeckHeader(deck: deck, summary: summary)
                Divider()
                CardTable(deck: deck, grouping: grouping, selection: $selection)
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Deck Didn't Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message(for: loadError))
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else {
            ProgressView("Loading Deck…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedRow: CardRow? {
        guard let deck, let selection else { return nil }
        return deck.sections(by: grouping).lazy.flatMap(\.rows).first { $0.id == selection }
    }

    private func load() async {
        guard let client = engine.client else { return }
        if deck?.slug != summary.slug {
            deck = nil
            selection = nil
        }
        do {
            deck = try await client.deck(summary.slug)
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = error
        }
    }
}

/// Name, commanders and the deck's numbers above the list.
struct DeckHeader: View {
    let deck: Deck
    let summary: DeckSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deck.name)
                .font(.title.bold())
            if !deck.commanders.isEmpty {
                Text(deck.commanders.joined(separator: " & "))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Text("\(deck.cardCount) cards")
                if deck.proxy {
                    Text("Proxy")
                } else if let price = deck.price {
                    Text(price, format: .currency(code: deck.currency.uppercased()))
                }
                if let bracket = deck.bracket {
                    LabeledContent("Bracket", value: "\(bracket)")
                }
                if let version = deck.version {
                    LabeledContent("Version", value: "\(version)")
                }
                if let updated = summary.updated {
                    LabeledContent("Saved") {
                        Text(updated, format: .relative(presentation: .named))
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if summary.needsRevalidation {
                Label("Changed on another device. The deck check runs again soon.",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if deck.cardDataError != nil {
                Label("Card pictures and prices are missing right now. Conclave couldn't reach Scryfall.",
                      systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// The cards in sections, as a table: copies, name, cost, type and price.
struct CardTable: View {
    let deck: Deck
    let grouping: DeckGrouping
    @Binding var selection: CardRow.ID?

    var body: some View {
        let sections = deck.sections(by: grouping)
        Table(of: CardRow.self, selection: $selection) {
            TableColumn("Qty") { row in
                Text(row.qty, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 28, ideal: 32, max: 44)
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    Text(row.name)
                        .lineLimit(1)
                    if row.facts?.gameChanger == true {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                            .help("Game Changer")
                            .accessibilityLabel("Game Changer")
                    }
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("Cost") { row in
                ManaCostView(cost: row.facts?.manaCost ?? "")
            }
            .width(min: 60, ideal: 96)
            TableColumn("Type") { row in
                Text(row.facts?.typeLine ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 200)
            TableColumn("Price") { row in
                if let price = row.facts?.price(deck.currency) {
                    Text(price * Double(row.qty), format: .currency(code: deck.currency.uppercased()))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 56, ideal: 72, max: 100)
        } rows: {
            ForEach(sections) { section in
                Section(sectionTitle(section.key) + " (\(section.count))") {
                    ForEach(section.rows) { row in
                        TableRow(row)
                    }
                }
            }
        }
    }
}

/// A mana cost as small coloured circles. Magic's own symbol font comes in a later step.
struct ManaCostView: View {
    let cost: String

    var body: some View {
        let symbols = ManaCost.symbols(cost)
        HStack(spacing: 2) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: symbol.count > 2 ? 6 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Self.fill(symbol)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(symbols.joined(separator: " "))
    }

    /// Magic's own pip colours (content, like the card art), the same as the iPhone app's.
    static func fill(_ symbol: String) -> Color {
        switch ManaCost.color(of: symbol) {
        case "W": Color(red: 1.00, green: 0.98, blue: 0.84)
        case "U": Color(red: 0.67, green: 0.88, blue: 0.98)
        case "B": Color(red: 0.80, green: 0.76, blue: 0.75)
        case "R": Color(red: 0.98, green: 0.67, blue: 0.56)
        case "G": Color(red: 0.61, green: 0.83, blue: 0.68)
        default: Color(red: 0.80, green: 0.76, blue: 0.75)
        }
    }
}

/// The picked card, big: its picture (both faces), cost, type, price and a link to Scryfall.
struct CardInspector: View {
    let row: CardRow?
    let currency: String
    @State private var showBack = false

    var body: some View {
        if let row {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    CardPicture(url: showBack ? row.facts?.imageBack : row.facts?.image)
                    if row.facts?.imageBack != nil {
                        Button(showBack ? "Show Front" : "Turn Over") { showBack.toggle() }
                    }
                    Text(row.name)
                        .font(.headline)
                    if let facts = row.facts {
                        ManaCostView(cost: facts.manaCost)
                        Text(facts.typeLine)
                            .foregroundStyle(.secondary)
                        if let price = facts.price(currency) {
                            LabeledContent("Price") {
                                Text(price, format: .currency(code: currency.uppercased()))
                            }
                        }
                        if facts.gameChanger {
                            Label("Game Changer", systemImage: "bolt.fill")
                        }
                        if let page = facts.scryfallPage {
                            Link("Show on Scryfall", destination: page)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: row.id) { showBack = false }
        } else {
            ContentUnavailableView("No Card Selected", systemImage: "rectangle.portrait",
                                   description: Text("Select a card in the list to see it here."))
        }
    }
}

/// A card picture in the card's own shape, or an empty card while it loads or when there is none.
struct CardPicture: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A section's title in the user's language.
func sectionTitle(_ key: SectionKey) -> String {
    switch key {
    case .commander: String(localized: "Commander")
    case .category(let name): categoryTitle(name)
    case .type(let type): typeTitle(type)
    case .manaValue(let value): value >= 7 ? String(localized: "Mana Value 7+") : String(localized: "Mana Value \(value)")
    case .maybe: String(localized: "Maybe List")
    }
}

/// The deck categories the engine knows (`CATEGORY_LABELS` in the web app); a user's own word stays as it is.
func categoryTitle(_ name: String) -> String {
    switch name {
    case "Ramp": String(localized: "Ramp")
    case "Draw": String(localized: "Card Draw")
    case "Removal": String(localized: "Removal")
    case "Board Wipe": String(localized: "Board Wipes")
    case "Protection": String(localized: "Protection")
    case "Synergy": String(localized: "Synergy")
    case "Win Condition": String(localized: "Win Conditions")
    case "Utility": String(localized: "Utility")
    case "Land": String(localized: "Lands")
    case "Tutor": String(localized: "Tutors")
    case "Counterspell": String(localized: "Counterspells")
    default: name
    }
}

func typeTitle(_ type: CardType) -> String {
    switch type {
    case .creature: String(localized: "Creatures")
    case .planeswalker: String(localized: "Planeswalkers")
    case .battle: String(localized: "Battles")
    case .artifact: String(localized: "Artifacts")
    case .enchantment: String(localized: "Enchantments")
    case .instant: String(localized: "Instants")
    case .sorcery: String(localized: "Sorceries")
    case .land: String(localized: "Lands")
    case .other: String(localized: "Other")
    }
}
