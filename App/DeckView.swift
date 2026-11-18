import ConclaveEngine
import SwiftUI

/// The selected deck: its head, the card list in sections, and the picked card in the inspector on the right
/// (the Windows app's Karten tab). Edits collect in the deck's `DeckEditor` (Undo steps back through them) and
/// File › Save (⌘S) saves them as one new version.
struct DeckView: View {
    @Environment(EngineModel.self) private var engine
    @Environment(\.undoManager) private var undoManager
    let summary: DeckSummary
    @State private var editor: DeckEditor?
    @State private var loadError: Error?
    @State private var selection: CardRow.ID?
    @State private var search = ""
    @State private var suggestions: [String] = []
    @State private var isAdding = false
    @State private var addError: String?
    /// A typed name that means more than one card; the dialog asks which.
    @State private var ambiguous: CardLookup?
    @AppStorage("deckGrouping") private var grouping: DeckGrouping = .category
    @AppStorage("showCardInspector") private var showInspector = true

    var body: some View {
        content
            .navigationTitle(summary.name)
            .navigationSubtitle(subtitle)
            // a new version (saved here or on another device, then reloaded) loads the deck again
            .task(id: "\(summary.slug)#\(summary.version ?? 0)") { await load() }
            .task(id: search) { await suggest() }
            .onChange(of: editor?.slug, initial: true) { editor?.undoManager = undoManager }
            .onChange(of: undoManager) { editor?.undoManager = undoManager }
            .focusedSceneValue(\.deckEditor, editor)
            .searchable(text: $search, placement: .toolbar, prompt: Text("Add a Card"))
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { name in
                    Text(name).searchCompletion(name)
                }
            }
            .onSubmit(of: .search) { addTyped() }
            .inspector(isPresented: $showInspector) {
                CardInspector(row: selectedRow, currency: editor?.saved.currency ?? "eur")
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
                    if editor?.isSaving == true || isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { save() } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(editor?.hasChanges != true)
                        .help("Save your changes as a new version of the deck (⌘S)")
                    }
                }
                ToolbarItem {
                    Button { showInspector.toggle() } label: {
                        Label("Card Details", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the picked card")
                }
            }
            .confirmationDialog("Which card do you mean?", isPresented: isAsking, presenting: ambiguous) { found in
                ForEach(found.choices, id: \.self) { name in
                    Button(name) { pick(name, from: found) }
                }
            } message: { found in
                Text("“\(found.name)” is also part of another card.")
            }
            .alert("Card Not Added", isPresented: isShowing($addError)) {
                Button("OK") {}
            } message: {
                Text(addError ?? "")
            }
            .alert("Deck Not Saved", isPresented: savedFailed) {
                Button("OK") {}
            } message: {
                Text(editor?.saveError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if let editor, editor.slug == summary.slug {
            let deck = editor.shown
            VStack(spacing: 0) {
                DeckHeader(deck: deck, summary: summary)
                Divider()
                CardTable(deck: deck, grouping: grouping, selection: $selection, editor: editor)
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
            VStack(spacing: 8) {
                ProgressView("Loading Deck…")
                Text("The first time, Conclave looks up every card on Scryfall. That can take a few seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if engine.cardDatabaseRun.running {
                    Text("The card database is downloading. Decks open faster once it's done.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if engine.cardDatabase?.available == false {
                    Text("Download the card database once, and decks open in a moment.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Download Card Database") { engine.downloadCardDatabase() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The commanders, or how many changes wait for ⌘S.
    private var subtitle: String {
        if let count = editor?.changes?.count, editor?.slug == summary.slug {
            return String(localized: "\(count) unsaved changes")
        }
        return summary.commanders.joined(separator: " & ")
    }

    private var selectedRow: CardRow? {
        guard let editor, let selection else { return nil }
        return editor.shown.sections(by: grouping).lazy.flatMap(\.rows).first { $0.id == selection }
    }

    private var isAsking: Binding<Bool> {
        Binding { ambiguous != nil } set: { if !$0 { ambiguous = nil } }
    }

    private var savedFailed: Binding<Bool> {
        Binding { editor?.saveError != nil } set: { if !$0 { editor?.saveError = nil } }
    }

    private func load() async {
        guard let client = engine.client else { return }
        if editor?.slug != summary.slug {
            // edits made earlier in this deck show at once, the saved deck follows
            editor = engine.editors[summary.slug]
            selection = nil
            loadError = nil  // an error belongs to the deck it came from
        }
        do {
            let loaded = try await client.deck(summary.slug)
            guard !Task.isCancelled else { return }
            editor = engine.editor(for: loaded)
            loadError = nil
        } catch {
            // picking another deck cancels this load: URLSession then throws URLError.cancelled, which is no error
            guard !Task.isCancelled, !isCancellation(error) else { return }
            if editor == nil { loadError = error }
        }
    }

    private func save() {
        guard let editor else { return }
        Task { await engine.save(editor) }
    }

    /// Names that start with the typed text, a moment after typing pauses.
    private func suggest() async {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let client = engine.client else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let names = try? await client.autocomplete(text), !Task.isCancelled else { return }
        suggestions = names
    }

    /// Looks the typed name up (English or German) and adds the card; asks first when the name means more than one.
    private func addTyped() {
        let name = search.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isAdding else { return }
        Task {
            guard let found = await lookUp(name) else { return }
            if found.choices.count > 1 {
                ambiguous = found
            } else {
                add(found)
            }
        }
    }

    private func pick(_ name: String, from found: CardLookup) {
        if name == found.name {
            add(found)
        } else {
            Task { if let card = await lookUp(name) { add(card) } }
        }
    }

    private func lookUp(_ name: String) async -> CardLookup? {
        guard let client = engine.client else { return nil }
        isAdding = true
        defer { isAdding = false }
        do {
            return try await client.card(named: name)
        } catch EngineError.notFound {
            addError = String(localized: "Conclave doesn't know a card called “\(name)”.")
        } catch {
            if !isCancellation(error) { addError = message(for: error) }
        }
        return nil
    }

    private func add(_ card: CardLookup) {
        guard let editor else { return }
        if editor.draft.commanders.contains(card.name) {
            addError = String(localized: "“\(card.name)” is this deck's commander.")
            return
        }
        editor.add(card)
        search = ""
        suggestions = []
        selection = card.name
    }
}

/// Binds an optional message to an alert: shown while there is one, cleared when it closes.
func isShowing(_ text: Binding<String?>) -> Binding<Bool> {
    Binding { text.wrappedValue != nil } set: { if !$0 { text.wrappedValue = nil } }
}

extension FocusedValues {
    /// The deck in the front window, for File › Save.
    @Entry var deckEditor: DeckEditor?
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

/// The cards in sections, as a table: copies, name, cost, type and price. Right-click a card to change it,
/// Delete takes the selected one out.
struct CardTable: View {
    let deck: Deck
    let grouping: DeckGrouping
    @Binding var selection: CardRow.ID?
    let editor: DeckEditor

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
                ManaText(row.facts?.manaCost ?? "")
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
        .contextMenu(forSelectionType: CardRow.ID.self) { ids in
            if let row = ids.first.flatMap({ id in sections.lazy.flatMap(\.rows).first { $0.id == id } }) {
                CardMenu(row: row, editor: editor)
            }
        }
        .onDeleteCommand {
            if let row = sections.lazy.flatMap(\.rows).first(where: { $0.id == selection }), !row.isCommander {
                editor.edit(String(localized: "Remove Card")) { $0.remove(row.name) }
            }
        }
    }
}

/// What a right-click on a card offers: copies, category, the maybe list, taking it out. Nothing for a commander.
struct CardMenu: View {
    let row: CardRow
    let editor: DeckEditor

    var body: some View {
        let name = row.name
        if row.onMaybeList {
            Button("Move to Deck") { editor.edit(String(localized: "Move to Deck")) { $0.add(name) } }
            Divider()
            Button("Remove from Maybe List") { editor.edit(String(localized: "Remove Card")) { $0.remove(name) } }
        } else if !row.isCommander {
            Button("Add a Copy") {
                editor.edit(String(localized: "Change Copies")) { $0.setQuantity(name, row.qty + 1) }
            }
            Button("Remove a Copy") {
                editor.edit(String(localized: "Change Copies")) { $0.setQuantity(name, row.qty - 1) }
            }
            .disabled(row.qty <= 1)
            Picker("Category", selection: category) {
                ForEach(categories, id: \.self) { category in
                    Text(categoryTitle(category)).tag(category)
                }
            }
            .pickerStyle(.menu)
            Button("Move to Maybe List") { editor.edit(String(localized: "Move to Maybe List")) { $0.moveToMaybe(name) } }
            Divider()
            Button("Remove from Deck") { editor.edit(String(localized: "Remove Card")) { $0.remove(name) } }
        }
    }

    /// The engine's categories, plus the card's own word when it has one of its own.
    private var categories: [String] {
        let known = Deck.categoryOrder + ["Tutor", "Counterspell"]
        guard let own = row.category, !known.contains(own) else { return known }
        return known + [own]
    }

    private var category: Binding<String> {
        Binding { row.category ?? "" } set: { new in
            editor.edit(String(localized: "Change Category")) { $0.setCategory(row.name, new) }
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
                        ManaText(facts.manaCost, style: .title3)
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
