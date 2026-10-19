import SwiftUI

struct CatalogShelf: View {
    let items: [TVItem]
    let active: TVDestination?
    let pending: TVDestination?
    let feedback: String?
    var inputs = false
    var action: (TVItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var scrollID: String?
    @State private var edges = CatalogEdges(start: true, end: false)
    @FocusState private var focusedID: String?
    private var firstIndex: Int { items.firstIndex { $0.stableID == scrollID } ?? 0 }
    private var lastStart: Int { max(0, items.count - (inputs ? 2 : 3)) }
    private var pagesInputs: [[TVItem]] { stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) } }

    var body: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 8) {
            if inputs {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(pagesInputs.enumerated()), id: \.offset) { _, page in
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(page, id: \.stableID) { item in inputCard(item) }
                            }.frame(width: 312).id(page.first?.stableID ?? "")
                        }
                    }.scrollTargetLayout().padding(.horizontal, 2).padding(.vertical, 3)
                }
                .scrollTargetBehavior(.viewAligned).scrollPosition(id: $scrollID, anchor: .leading)
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                .frame(height: 126)
                .onScrollGeometryChange(for: CatalogEdges.self) { geometry in
                    CatalogEdges(start: geometry.contentOffset.x <= 1, end: geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 1)
                } action: { _, value in edges = value }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items, id: \.stableID) { item in appTile(item).id(item.stableID) }
                    }.scrollTargetLayout().padding(.horizontal, 3).padding(.top, 3)
                }
                .scrollTargetBehavior(.viewAligned).scrollPosition(id: $scrollID, anchor: .leading)
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                .frame(height: 126)
                .onScrollGeometryChange(for: CatalogEdges.self) { geometry in
                    CatalogEdges(start: geometry.contentOffset.x <= 1, end: geometry.contentOffset.x + geometry.containerSize.width >= geometry.contentSize.width - 1)
                } action: { _, value in edges = value }
            }
            HStack(spacing: 8) {
                Text(feedback ?? (pending.map { "Opening \(AppBrand($0.name).title)…" } ?? "\(items.count) \(inputs ? "inputs" : "apps") on your TV"))
                    .font(.system(size: 10)).foregroundStyle(feedback == nil ? Color.secondary : .orange)
                    .lineLimit(1).help(feedback ?? "Apps and inputs reported by your TV")
                Spacer(minLength: 2)
                if items.count > (inputs ? 4 : 3) {
                    pageButton("chevron.left", title: "Previous \(inputs ? "inputs" : "apps")", disabled: edges.start) { move(-1) }
                    pageButton("chevron.right", title: "Next \(inputs ? "inputs" : "apps")", disabled: edges.end) { move(1) }
                }
            }.frame(height: 24).padding(.horizontal, 3)
        }
        .onChange(of: focusedID) { _, id in
            guard let id else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                if inputs, let index = items.firstIndex(where: { $0.stableID == id }) { scrollID = items[(index / 4) * 4].stableID }
                else if let index = items.firstIndex(where: { $0.stableID == id }), index < firstIndex || index >= firstIndex + 3 {
                    scrollID = items[min(index, lastStart)].stableID
                }
            }
        }
        .onChange(of: items.map(\.stableID)) { _, ids in
            if let scrollID, !ids.contains(scrollID) { self.scrollID = ids.first }
        }
        .onAppear {
            if let scrollID { proxy.scrollTo(scrollID, anchor: .leading) }
        }
        }
    }
    private func move(_ direction: Int) {
        let destination = inputs ? min(max(0, (firstIndex / 4 + direction) * 4), (pagesInputs.count - 1) * 4) : min(max(0, firstIndex + direction * 3), lastStart)
        guard items.indices.contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9)) { scrollID = items[destination].stableID }
    }
    private func pageButton(_ symbol: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 25, height: 22).contentShape(Capsule()) }
            .buttonStyle(.glass).buttonBorderShape(.capsule).disabled(disabled)
            .help(title).accessibilityLabel(title)
    }
    private func appTile(_ item: TVItem) -> some View {
        let brand = AppBrand(item.name)
        let current = active?.matches(item) == true
        let loading = pending?.matches(item) == true
        return Button { action(item) } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(brand.background)
                    CatalogArtwork(url: item.artworkURL).frame(width: 80, height: 80)
                }
                .frame(width: 80, height: 80).clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.6 : 0.12), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) { stateBadge(current: current, loading: loading).padding(5) }
                Text(brand.title).font(.system(size: 10, weight: current ? .semibold : .medium))
                    .foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 80, height: 28, alignment: .top)
            }.contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(CatalogTileStyle()).focusable().focused($focusedID, equals: item.stableID)
        .accessibilityLabel("Open \(brand.title)")
        .accessibilityValue(loading ? "Opening, awaiting TV" : current ? "Active on TV" : "")
        .help(loading ? "Waiting for the TV to open \(item.name)" : "Open \(item.name)")
        .onKeyPress(.return) { action(item); return .handled }
        .onKeyPress(.leftArrow) { focusItem(item, direction: -1); return .handled }
        .onKeyPress(.rightArrow) { focusItem(item, direction: 1); return .handled }
    }
    private func inputCard(_ item: TVItem) -> some View {
        let platform = TVPlatform(reportedName: item.name, connected: true)
        let current = active?.matches(item) == true
        let loading = pending?.matches(item) == true
        return Button { action(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: platform.symbol).font(.system(size: 19, weight: .regular)).frame(width: 25)
                Text(platform.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if loading { ProgressView().controlSize(.mini) }
                else if current { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.system(size: 12)) }
            }
            .padding(.horizontal, 12).frame(height: 56)
            .background(Color.primary.opacity(current ? 0.10 : 0.045), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.08), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 14))
        }.buttonStyle(CatalogTileStyle()).focusable().focused($focusedID, equals: item.stableID)
            .help("Switch to \(platform.name)").accessibilityLabel("Switch to \(platform.name)")
            .accessibilityValue(loading ? "Switching, awaiting TV" : current ? "Active on TV" : "")
            .onKeyPress(.return) { action(item); return .handled }
            .onKeyPress(.leftArrow) { focusItem(item, direction: -1); return .handled }
            .onKeyPress(.rightArrow) { focusItem(item, direction: 1); return .handled }
            .onKeyPress(.upArrow) { focusItem(item, direction: -2); return .handled }
            .onKeyPress(.downArrow) { focusItem(item, direction: 2); return .handled }
    }
    @ViewBuilder private func stateBadge(current: Bool, loading: Bool) -> some View {
        if loading || current {
            ZStack {
                Circle().fill(Color.black.opacity(0.8))
                if loading { ProgressView().controlSize(.mini).tint(.white).scaleEffect(0.7) }
                else { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
            }.frame(width: 19, height: 19).accessibilityHidden(true)
        }
    }
    private func focusItem(_ item: TVItem, direction: Int) {
        guard let index = items.firstIndex(where: { $0.stableID == item.stableID }) else { return }
        focusedID = items[min(max(0, index + direction), items.count - 1)].stableID
    }
}

private struct CatalogEdges: Equatable {
    let start: Bool
    let end: Bool
}

private struct CatalogTileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(hovered ? 0.045 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

struct AppBrand {
    let title: String
    let background: Color
    init(_ name: String) {
        let key = TVDestination.canonical(name)
        let values: (String, String?)
        switch key {
        case "netflix": values = ("Netflix", "netflix.png")
        case "primevideo": values = ("Prime Video", "prime-tile.png")
        case "youtube": values = ("YouTube", "youtube-tile.png")
        case "appletv": values = ("Apple TV", "apple-tile.png")
        case "hotstardisney", "hotstardisneyplus", "disneyhotstar", "disneyplushotstar", "disney", "disneyplus": values = ("Disney+", "disney-tile.png")
        case "azamtvmax": values = ("AzamTV MAX", "azam-tile.png")
        case "vidaakids": values = ("VIDAA Kids", "kids-tile.jpg")
        case "haystacktvlocalworldnews", "haystacknews", "haystacktv": values = ("Haystack News", "haystack-tile.jpg")
        case "sabc", "sabcplus": values = ("SABC+", "sabc-tile.png")
        case "spotifymusicpodcasts": values = ("Spotify", nil)
        case "appstore": values = ("App Store", nil)
        case "tvbrowser": values = ("TV Browser", nil)
        case "vodondemand": values = ("VOD", nil)
        case "tvchannels": values = ("TV Channels", "channels-tile.jpg")
        default: values = (name, nil)
        }
        title = values.0
        background = key == "netflix" ? .black : Color(white: 0.08)
    }
}
