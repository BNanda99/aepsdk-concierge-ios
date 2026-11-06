/*
 Copyright 2026 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import SwiftUI
import AEPBrandConcierge
import AEPServices
import AEPCore

@MainActor
enum FnbCardRegistration {
    static let orders = FnbOrderStore.shared
    private static var observingIdentity = false

    static func register(locationOptions: FnbLocationOptions = FnbLocationOptions(),
                         menuOptions: FnbMenuOptions = FnbMenuOptions(),
                         cartOptions: FnbCartOptions = .stage,
                         parkingOptions: ParkingEventOptions = ParkingEventOptions(),
                         openCheckout: ((URL) -> Bool)? = nil) {
        if !observingIdentity {
            observingIdentity = true
            MobileCore.registerEventListener(type: EventType.genericIdentity, source: EventSource.requestReset) { _ in
                Task { @MainActor in
                    orders.identityDidReset()
                    ParkWhizBookingStore.shared.identityDidReset()
                }
            }
        }
        Concierge.registerCardRenderer(type: "kings.fnblocation") { element, context, saveState in
            AnyView(FnbLocationsCard(element: element, context: context, saveState: saveState,
                                     options: locationOptions))
        }
        Concierge.registerCardRenderer(type: "kings.menu") { element, context, saveState in
            AnyView(FnbMenuCard(element: element, context: context, saveState: saveState, options: menuOptions))
        }
        Concierge.registerCardRenderer(type: "kings.fnbcart") { element, context, saveState in
            AnyView(FnbCartCard(element: element, context: context, saveState: saveState,
                                options: cartOptions, openCheckout: openCheckout))
        }
        Concierge.registerCardRenderer(type: ParkingCardTypes.events) { element, context, saveState in
            AnyView(ParkingEventsCard(element: element, context: context, saveState: saveState,
                                      options: parkingOptions))
        }
    }

    static func receive(type: String, element: [String: Any], context: [String: Any]) {
        guard let cardId = context["cardId"] as? String,
              let sessionId = context["sessionId"] as? String else { return }
        let stale = context["isStale"] as? Bool == true
        let isLatest = context["isLatest"] as? Bool == true
        switch type {
        case "kings.fnblocation":
            orders.locationsShown(cardId: cardId, sessionId: sessionId, eventId: element["eventId"],
                                  stale: stale, isLatest: isLatest)
        case "kings.menu":
            orders.menuShown(cardId: cardId, sessionId: sessionId, stale: stale)
        case "kings.fnbcart":
            let summary = FnbOrderSummary.map(element["entity_info"], fallbackId: element["entityId"])
            orders.cartShown(cardId: cardId, sessionId: sessionId, orderId: summary?.id ?? element["entityId"],
                             paid: summary?.paid == true, stale: stale, isLatest: isLatest)
        default: break
        }
    }
}

struct FnbImage: View {
    let url: URL?
    let showsPlaceholder: Bool
    let badge: String?
    let height: CGFloat?
    let aspectRatio: CGFloat?
    let cornerRadius: CGFloat?
    @Environment(\.conciergeTheme) private var theme

    init(url: URL?, showsPlaceholder: Bool = false, badge: String? = nil, height: CGFloat? = nil,
         aspectRatio: CGFloat? = nil, cornerRadius: CGFloat? = nil) {
        self.url = url
        self.showsPlaceholder = showsPlaceholder
        self.badge = badge
        self.height = height
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
    }

    @ViewBuilder
    private var frame: some View {
        if let aspectRatio {
            Color.clear.aspectRatio(aspectRatio, contentMode: .fit).frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: height ?? FnbStyle.tileImageHeight(theme))
        }
    }

    @ViewBuilder
    var body: some View {
        if url != nil || showsPlaceholder || badge != nil {
            frame
                .overlay { artwork }
                .overlay(alignment: .topLeading) {
                    if let badge { FnbTag(text: badge).padding(6) }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? FnbStyle.imageRadius(theme),
                                            style: .continuous))
                .accessibilityElement(children: badge == nil ? .ignore : .combine)
                .accessibilityHidden(badge == nil)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        FnbStyle.imagePlaceholder(theme)
    }
}

struct FnbTag: View {
    @Environment(\.conciergeTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(FnbStyle.tagText(theme))
            .background(FnbStyle.tagBackground(theme), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct FnbPrimaryButtonStyle: ButtonStyle {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var minimumHeight: CGFloat?
    /// Looks disabled but stays tappable, so a tap can explain what is missing.
    var isMuted = false

    func makeBody(configuration: Configuration) -> some View {
        let height = max(44, minimumHeight ?? FnbStyle.buttonHeight(theme))
        let shape = RoundedRectangle(cornerRadius: min(FnbStyle.buttonRadius(theme), height / 2),
                                     style: .continuous)
        return configuration.label
            .font(.subheadline.weight(.bold))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .foregroundColor(isEnabled ? FnbStyle.onAccent(theme) : FnbStyle.secondaryText(theme))
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .background((isEnabled && !isMuted ? FnbStyle.accent(theme) : FnbStyle.disabled(theme))
                .opacity(configuration.isPressed ? 0.8 : 1), in: shape)
            .contentShape(shape)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Uses primary text for contrast against the card and an accent outline.
struct FnbOutlinedButtonStyle: ButtonStyle {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height = max(44, FnbStyle.buttonHeight(theme))
        let shape = RoundedRectangle(cornerRadius: min(FnbStyle.buttonRadius(theme), height / 2),
                                     style: .continuous)
        let color = isEnabled ? FnbStyle.primaryText(theme) : FnbStyle.secondaryText(theme)
        return configuration.label
            .font(.subheadline.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .overlay(shape.stroke(isEnabled ? FnbStyle.accent(theme) : FnbStyle.disabled(theme), lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FnbLocationsCard: View {
    @Environment(\.conciergeTheme) private var theme
    @ObservedObject private var orders = FnbCardRegistration.orders
    let element: [String: Any]
    let context: [String: Any]
    let options: FnbLocationOptions
    @StateObject private var runtime: FnbActionRuntime

    init(element: [String: Any], context: [String: Any], saveState: @escaping ([String: Any]) -> Void,
         options: FnbLocationOptions) {
        self.element = element
        self.context = context
        self.options = options
        let state = context["state"] as? [String: Any] ?? [:]
        _runtime = StateObject(wrappedValue: FnbActionRuntime(state: state, save: saveState))
    }

    private var stands: [FnbStand] { FnbStand.map(element["entity_info"], options: options) }
    private var cardId: String { context["cardId"] as? String ?? "" }
    private var sessionId: String { context["sessionId"] as? String ?? "" }
    private var stale: Bool { context["isStale"] as? Bool == true }
    private var gated: Bool {
        runtime.activeAction != nil ||
        context["isBusy"] as? Bool == true || !orders.isSessionActive(sessionId, stale: stale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = runtime.errorMessage {
                Text(error).font(.caption).foregroundColor(FnbStyle.errorColor(theme))
            }
            if stands.isEmpty {
                Text("This content isn't available right now.")
                    .font(.subheadline)
                    .foregroundColor(FnbStyle.secondaryText(theme))
            } else {
                let showsImages = stands.contains { $0.image != nil }
                FnbCarousel(items: stands, tileWidth: FnbStyle.locationTileWidth(theme),
                            spacing: theme.layout.productCardCarouselSpacing) { stand in
                    let actionKey = "location:\(stand.id)"
                    let isUnconfirmed = runtime.unconfirmed.contains(actionKey)
                    FnbLocationTile(stand: stand, showsImage: showsImages, closedLabel: options.closedLabel,
                                    actionLabel: runtime.activeActionKey == actionKey
                                        ? options.pendingCtaLabel : options.ctaLabel,
                                    isUnconfirmed: isUnconfirmed,
                                    isActionDisabled: gated || !stand.isOpen || isUnconfirmed) {
                        select(stand)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            FnbCardRegistration.receive(type: "kings.fnblocation", element: element, context: context)
            runtime.adopt(context["state"] as? [String: Any] ?? [:])
        }
        .onChange(of: contextRevision) { _ in
            runtime.adopt(context["state"] as? [String: Any] ?? [:])
        }
        // A rolled-back newer card promotes this one; let it claim what only the newest may.
        .onChange(of: context["isLatest"] as? Bool == true) { isLatest in
            if isLatest { FnbCardRegistration.receive(type: "kings.fnblocation", element: element, context: context) }
        }
    }

    private var contextRevision: Int { (context["state"] as? [String: Any])?["rev"] as? Int ?? 0 }

    private func select(_ stand: FnbStand) {
        guard !gated, stand.isOpen else { return }
        runtime.perform(key: "location:\(stand.id)", hint: FnbHandoff.viewMenuHint,
                        fields: { _ in FnbHandoff.viewMenu(locationId: stand.id) },
                        copy: FnbHandoff.viewMenuCopy(stand.title), selected: stand.id,
                        canSend: !gated)
    }
}

struct FnbMenuCard: View {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var orders = FnbCardRegistration.orders
    let element: [String: Any]
    let context: [String: Any]
    let options: FnbMenuOptions
    @StateObject private var runtime: FnbMenuRuntime
    @State private var customization: FnbItem?
    @State private var selectedCategory: String?
    @State private var scrollTargets = FnbScrollTargets()

    init(element: [String: Any], context: [String: Any], saveState: @escaping ([String: Any]) -> Void,
         options: FnbMenuOptions) {
        self.element = element
        self.context = context
        self.options = options
        let state = context["state"] as? [String: Any] ?? [:]
        _runtime = StateObject(wrappedValue: FnbMenuRuntime(state: state, save: saveState, quantityRule: options.quantity))
    }

    private var currencyCode: String { options.currencyCode }
    private var payload: [String: Any] {
        PayloadRead.object(element["entity_info"]) ?? [:]
    }
    private var firstEntry: [String: Any] {
        PayloadRead.rows(element["entity_info"], limit: 2_000).first ?? [:]
    }
    private var menuInfo: [String: Any] {
        PayloadRead.object(firstEntry["location"]) ?? payload
    }
    private var items: [FnbItem] { FnbItem.map(element["entity_info"]) }
    private var itemsById: [String: FnbItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var categories: [String] {
        items.reduce(into: [String]()) { values, item in
            if !values.contains(item.categoryId) { values.append(item.categoryId) }
        }
    }
    private var locationId: String? {
        return PayloadRead.id(menuInfo["id"] ?? menuInfo["locationId"] ?? firstEntry["locationId"])
    }
    private var state: [String: Any] { context["state"] as? [String: Any] ?? [:] }
    private var status: String { runtime.status }
    private var cardId: String { context["cardId"] as? String ?? "" }
    private var sessionId: String { context["sessionId"] as? String ?? "" }
    private var stale: Bool { context["isStale"] as? Bool == true }
    private var busy: Bool { context["isBusy"] as? Bool == true }
    private var orderingAvailable: Bool {
        PayloadRead.bool(menuInfo["orderingEnabled"]) != false &&
            PayloadRead.bool(menuInfo["isPaused"]) != true &&
            PayloadRead.bool(menuInfo["isActive"]) != false
    }
    private var isLatest: Bool { context["isLatest"] as? Bool == true }
    private var actionable: Bool {
        orders.isMenuActionable(cardId: cardId, sessionId: sessionId, stale: stale, isLatest: isLatest)
    }
    private var editable: Bool {
        actionable && status == "draft"
    }

    private var categoryList: [FnbCategory] {
        categories.map { categoryId in
            FnbCategory(id: categoryId,
                        title: items.first(where: { $0.categoryId == categoryId })?.category ?? "Menu")
        }
    }
    private var activeCategory: FnbCategory? {
        categoryList.first { $0.id == selectedCategory } ?? categoryList.first
    }
    private var draftCount: Int { runtime.draft.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        let padding = FnbStyle.contentPadding(theme)
        let spacing = FnbStyle.dimension("--fnb-grid-spacing", theme: theme, fallback: 12)
        let shape = RoundedRectangle(cornerRadius: FnbStyle.cardRadius(theme), style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header.padding(padding)
            if items.isEmpty {
                Text("This content isn't available right now.")
                    .font(.subheadline)
                    .foregroundColor(FnbStyle.secondaryText(theme))
                    .padding(.horizontal, padding)
            }
            if categoryList.count > 1 {
                FnbCategoryChips(categories: categoryList, selection: activeCategory?.id,
                                 contentInset: padding) { categoryId in
                    selectedCategory = categoryId
                    scrollTargets.scroll(to: categoryId)
                }
                .padding(.bottom, 8)
            }
            ForEach(categoryList) { category in
                categoryRow(category, padding: padding, spacing: spacing)
                    .padding(.vertical, spacing / 2)
                    .background(FnbScrollAnchor(id: category.id, targets: scrollTargets))
            }
            cartFooter.padding(padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(FnbStyle.primaryText(theme))
        .background(FnbStyle.cardBackground(theme), in: shape)
        .clipShape(shape)
        .overlay(shape.stroke(FnbStyle.border(theme), lineWidth: 1))
        .sheet(item: $customization) { item in
            sheet(for: item)
        }
        .onAppear {
            FnbCardRegistration.receive(type: "kings.menu", element: element, context: context)
            runtime.adopt(state)
            if runtime.status == "added" || runtime.status == "unconfirmed" {
                orders.markMenuSubmitted(cardId: cardId, sessionId: sessionId)
            }
        }
        .onChange(of: contextRevision) { _ in runtime.adopt(state) }
        .onChange(of: status) { newStatus in
            if newStatus == "added" || newStatus == "unconfirmed" {
                orders.markMenuSubmitted(cardId: cardId, sessionId: sessionId)
            }
        }
    }

    private func categoryRow(_ category: FnbCategory, padding: CGFloat, spacing: CGFloat) -> some View {
        let categoryItems = items.filter { $0.categoryId == category.id }
        let reservesDetailLine = categoryItems.contains { !$0.detail.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            Text(category.title)
                .font(.callout.weight(.bold))
                .padding(.horizontal, padding)
                .accessibilityAddTraits(.isHeader)
            FnbCarousel(items: categoryItems, tileWidth: FnbStyle.tileWidth(theme), spacing: spacing,
                        contentInset: padding) { item in
                FnbMenuItemCard(item: item, currencyCode: currencyCode,
                                quantity: runtime.quantity(for: item.id),
                                maximumQuantity: options.quantity.maximum,
                                isEditable: editable && orderingAvailable,
                                reservesDetailLine: reservesDetailLine,
                                open: { customization = item }) {
                    if item.modifierGroups.isEmpty { add(item, modifiers: []) } else { customization = item }
                } decrement: {
                    runtime.decrement(productId: item.id)
                }
            }
        }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    headerTitle
                    headerStatus
                }
            } else {
                HStack(spacing: 8) {
                    headerTitle
                    headerStatus
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(FnbStyle.statusColor(online: orderingAvailable, theme: theme))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(PayloadRead.text(menuInfo["title"] ?? menuInfo["name"] ?? menuInfo["locationLabel"],
                              fallback: "Menu"))
                .font(.headline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var headerStatus: some View {
        if !orderingAvailable {
            Text("Ordering unavailable").font(.caption).foregroundColor(FnbStyle.secondaryText(theme))
        } else if let waitTime = PayloadRead.string(menuInfo["waitTime"]) {
            Text(String(PayloadRead.text(waitTime).prefix(40)))
                .font(.caption)
                .foregroundColor(FnbStyle.secondaryText(theme))
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        let message: String? = {
            switch status {
            case "added": return "Added to cart. This menu is no longer active."
            case "unconfirmed": return "We couldn't confirm the last add. Ask Concierge before retrying those items."
            case "submitting": return "Adding your items…"
            default: return actionable ? runtime.errorMessage : "This menu is no longer active."
            }
        }()
        if let message {
            Text(message)
                .font(.caption)
                .foregroundColor(status == "draft" ? FnbStyle.errorColor(theme) : FnbStyle.primaryText(theme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var cartFooter: some View {
        let cartBar = options.cartBar
        VStack(alignment: .leading, spacing: 8) {
            statusMessage
            if !(cartBar.hideWhenEmpty && runtime.draft.isEmpty && status != "submitting") {
                Button {
                    guard let locationId else { return }
                    runtime.submit(locationId: locationId,
                                   venueId: PayloadRead.id(firstEntry["venueId"] ?? menuInfo["venueId"]),
                                   eventId: PayloadRead.id(firstEntry["eventId"] ?? menuInfo["eventId"]),
                                   locationName: PayloadRead.text(menuInfo["title"] ?? menuInfo["name"]),
                                   menuItems: itemsById,
                                   canSend: !busy && actionable && orderingAvailable)
                } label: {
                    HStack(spacing: 8) {
                        if status == "submitting" { ProgressView().tint(FnbStyle.onAccent(theme)) }
                        Text(status == "submitting" ? "SENDING…" :
                            (cartBar.showCount ? "\(cartBar.label.uppercased()) (\(draftCount))"
                                : cartBar.label.uppercased()))
                    }
                }
                .buttonStyle(FnbPrimaryButtonStyle())
                .disabled(!editable || !orderingAvailable || busy || locationId == nil ||
                          runtime.draft.isEmpty || !cartBar.enabled)
            }
        }
    }

    private func sheet(for item: FnbItem) -> some View {
        FnbCustomizeSheet(item: item, quantityRule: options.quantity,
                          instructions: options.instructions, currencyCode: currencyCode,
                          addToCartLabel: options.addToCartLabel) { modifiers, quantity, note in
            add(item, modifiers: modifiers, quantity: quantity, note: note)
            customization = nil
        }
        .conciergeTheme(theme)
    }

    private var contextRevision: Int { state["rev"] as? Int ?? 0 }

    private func add(_ item: FnbItem, modifiers: [FnbModifierSelection],
                     quantity: Int = 1, note: String? = nil) {
        guard editable, let locationId else { return }
        var modifierCents = 0
        for group in modifiers {
            let matching = item.modifierGroups.first { PayloadRead.id($0["id"]) == group.groupId }
            let options = PayloadRead.rows(matching?["modifiers"], limit: 50)
            for option in options where group.modifiers.contains(PayloadRead.id(option["id"]) ?? "") {
                let cents = PayloadRead.cents(option["price"]) ?? 0
                guard cents <= 1_000_000_000 - modifierCents else { return }
                modifierCents += cents
            }
        }
        let unit = item.cents <= 1_000_000_000 - modifierCents ? item.cents + modifierCents : nil
        let next = FnbLine(id: item.id, name: item.name, quantity: quantity, locationId: locationId,
                           note: note, selectedModifiers: modifiers, unitCents: unit)
        runtime.add(next)
    }
}

struct FnbCartCard: View {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var orders = FnbCardRegistration.orders
    let element: [String: Any]
    let context: [String: Any]
    let checkoutBase: String
    let checkoutVenueId: String?
    let allowedCheckoutHosts: Set<String>
    let openCheckout: ((URL) -> Bool)?
    let currencyCode: String
    let checkoutLabel: String
    let showMoreLabel: String?
    @Environment(\.openURL) private var openURL
    @State private var checkoutFailed = false
    @State private var checkoutOpening = false
    @StateObject private var runtime: FnbActionRuntime

    init(element: [String: Any], context: [String: Any], saveState: @escaping ([String: Any]) -> Void,
         options: FnbCartOptions, openCheckout: ((URL) -> Bool)?) {
        self.element = element
        self.context = context
        self.checkoutBase = options.checkoutBase
        self.checkoutVenueId = options.checkoutVenueId
        self.allowedCheckoutHosts = options.allowedCheckoutHosts
        self.openCheckout = openCheckout
        self.currencyCode = options.currencyCode
        self.checkoutLabel = options.checkoutLabel
        self.showMoreLabel = options.showMoreLabel
        let state = context["state"] as? [String: Any] ?? [:]
        _runtime = StateObject(wrappedValue: FnbActionRuntime(state: state, save: saveState))
    }

    private var order: [String: Any] { PayloadRead.object(element["entity_info"]) ?? [:] }
    private var summary: FnbOrderSummary? {
        FnbOrderSummary.map(element["entity_info"], fallbackId: element["entityId"])
    }
    private var lines: [FnbOrderLine] { summary?.lines ?? [] }
    private var orderId: String? { summary?.id }
    private var paid: Bool { summary?.paid == true }
    private var cardId: String { context["cardId"] as? String ?? "" }
    private var sessionId: String { context["sessionId"] as? String ?? "" }
    private var stale: Bool { context["isStale"] as? Bool == true }
    private var isLatest: Bool { context["isLatest"] as? Bool == true }
    private var archived: Bool { orders.isOrderArchived(orderId) }
    private var actionable: Bool {
        orders.isCartActionable(cardId: cardId, sessionId: sessionId, orderId: orderId, stale: stale,
                                isLatest: isLatest)
    }
    private var blocked: Bool {
        runtime.activeAction != nil ||
        context["isBusy"] as? Bool == true || !orders.isSessionActive(sessionId, stale: stale)
    }
    private var unresolvedOrder: Bool {
        !runtime.unconfirmed.isEmpty || !runtime.pendingRemovals.isEmpty
    }
    private var checkoutAllowed: Bool {
        orders.canOpenCheckout(cardId: cardId, sessionId: sessionId, orderId: orderId,
                               stale: stale, isLatest: isLatest, unresolved: unresolvedOrder)
    }
    private var checkout: URL? {
        guard let venue = checkoutVenueId ?? PayloadRead.id(order["venueId"]), let event = PayloadRead.id(order["eventId"]),
              let guid = summary?.guid else { return nil }
        return FnbHandoff.checkoutURL(base: checkoutBase, venueId: venue, eventId: event,
                                      guid: guid, allowedHosts: allowedCheckoutHosts)
    }

    var emptyStateMessage: String? {
        if orderId == nil { return "This content isn't available right now." }
        return lines.isEmpty ? "Your cart is empty." : nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FnbStyle.cardRadius(theme), style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            header
            if let emptyStateMessage {
                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundColor(FnbStyle.secondaryText(theme))
            } else {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { divider }
                    lineRow(line)
                }
                divider
                totals
            }
            notices
            if paid {
                Text("Paid. Your order is being prepared.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(FnbStyle.secondaryText(theme))
            } else if let checkout, !lines.isEmpty {
                Button(checkoutLabel) { open(checkout) }
                    .buttonStyle(FnbPrimaryButtonStyle())
                    .disabled(blocked || !checkoutAllowed || checkoutOpening)
            }
            if orderId != nil, lines.last?.locationId != nil, let showMoreLabel, !archived {
                Button(showMoreLabel) { sendMore() }
                    .buttonStyle(FnbOutlinedButtonStyle())
                    .disabled(blocked || !actionable || runtime.unconfirmed.contains("showMore"))
            }
        }
        .padding(FnbStyle.contentPadding(theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(FnbStyle.primaryText(theme))
        .background(FnbStyle.cardBackground(theme), in: shape)
        .clipShape(shape)
        .overlay(shape.stroke(FnbStyle.border(theme), lineWidth: 1))
        .onAppear {
            FnbCardRegistration.receive(type: "kings.fnbcart", element: element, context: context)
            runtime.adopt(context["state"] as? [String: Any] ?? [:])
        }
        .onChange(of: contextRevision) { _ in
            runtime.adopt(context["state"] as? [String: Any] ?? [:])
        }
        // A rolled-back newer card promotes this one; let it claim what only the newest may.
        .onChange(of: context["isLatest"] as? Bool == true) { isLatest in
            if isLatest { FnbCardRegistration.receive(type: "kings.fnbcart", element: element, context: context) }
        }
    }

    private var contextRevision: Int { (context["state"] as? [String: Any])?["rev"] as? Int ?? 0 }

    private var divider: some View {
        Rectangle().fill(FnbStyle.border(theme)).frame(height: 1).accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(FnbStyle.statusColor(online: true, theme: theme))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(summary?.venueName ?? "Your order")
                .font(.headline.weight(.bold))
                .foregroundColor(FnbStyle.primaryText(theme))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
        }
    }

    private func lineRow(_ line: FnbOrderLine) -> some View {
        let removing = runtime.pendingRemovals.contains("remove:\(line.id)")
        let textColor = removing ? FnbStyle.secondaryText(theme) : FnbStyle.primaryText(theme)
        let detail = [line.modifiers, line.note.map { "note: \($0)" }, line.standName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(line.title) × \(line.quantity)")
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let amount = line.subtotal {
                    Text(FnbStyle.price(cents: amount, currencyCode: currencyCode))
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(textColor)
            HStack(spacing: 8) {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(FnbStyle.secondaryText(theme))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if removing {
                    Text("Removing…")
                        .font(.caption)
                        .foregroundColor(FnbStyle.secondaryText(theme))
                } else if !paid {
                    let enabled = !blocked && actionable && orderId != nil &&
                        !runtime.unconfirmed.contains("remove:\(line.id)") &&
                        !orders.removals.contains(FnbOrderStore.removalKey(orderId: orderId ?? "", line: line))
                    Button("Remove") { remove(line) }
                        .font(.caption.weight(.bold))
                        .foregroundColor(enabled ? FnbStyle.primaryText(theme) : FnbStyle.secondaryText(theme))
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                        .disabled(!enabled)
                        .accessibilityLabel("Remove \(line.title)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var totals: some View {
        VStack(spacing: 4) {
            totalRow("Subtotal", cents: summary?.subtotal)
            if let discount = summary?.discount, discount > 0 { totalRow("Discount", cents: -discount) }
            if let fees = summary?.fees, fees > 0 { totalRow("Fees", cents: fees) }
            if let tip = summary?.tip, tip > 0 { totalRow("Tip", cents: tip) }
            totalRow("Tax", cents: summary?.tax)
            totalRow("Total", cents: summary?.total, emphasized: true)
        }
    }

    @ViewBuilder
    private func totalRow(_ title: String, cents: Int?, emphasized: Bool = false) -> some View {
        if let cents {
            let amount = FnbStyle.price(cents: abs(cents), currencyCode: currencyCode)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(cents < 0 ? "−\(amount)" : amount)
            }
            .font(emphasized ? .subheadline.weight(.bold) : .footnote)
            .foregroundColor(emphasized ? FnbStyle.primaryText(theme) : FnbStyle.secondaryText(theme))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let error = runtime.errorMessage { errorText(error) }
        if checkoutFailed { errorText("Checkout could not be opened. Please try again.") }
        if !runtime.unconfirmed.isEmpty {
            noticeText("We couldn't confirm the last action. Ask Concierge for the latest cart.")
        }
        if !runtime.pendingRemovals.isEmpty {
            noticeText("Waiting for an updated order from the restaurant.")
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundColor(FnbStyle.errorColor(theme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func noticeText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundColor(FnbStyle.secondaryText(theme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func open(_ checkout: URL) {
        guard !blocked, checkoutAllowed, !checkoutOpening else { return }
        let identityRevision = orders.identityRevision
        checkoutOpening = true
        if let openCheckout {
            checkoutFailed = !openCheckout(checkout)
            if !checkoutFailed, orders.identityRevision == identityRevision {
                orders.checkoutDidOpen(orderId: orderId, sessionId: sessionId, identityRevision: identityRevision)
            }
            checkoutOpening = false
        } else {
            openURL(checkout) { accepted in
                guard orders.identityRevision == identityRevision,
                      orders.isSessionActive(sessionId, stale: stale) else { return }
                checkoutFailed = !accepted
                if accepted {
                    orders.checkoutDidOpen(orderId: orderId, sessionId: sessionId, identityRevision: identityRevision)
                }
                checkoutOpening = false
            }
        }
    }

    private func remove(_ line: FnbOrderLine) {
        guard !blocked, !paid, actionable, let orderId,
              !runtime.unconfirmed.contains("remove:\(line.id)"),
              !runtime.pendingRemovals.contains("remove:\(line.id)") else { return }
        guard let fields = FnbHandoff.removeFromCart(locationId: line.locationId,
                                                     productId: line.productId,
                                                     modifiers: line.modifiers) else { return }
        let key = FnbOrderStore.removalKey(orderId: orderId, line: line)
        guard let token = orders.beginRemoval(key: key, cardId: cardId, sessionId: sessionId,
                                              orderId: orderId, stale: stale, isLatest: isLatest) else { return }
        runtime.perform(key: "remove:\(line.id)", hint: "remove-from-cart",
                        fields: { _ in fields }, copy: "Removing \(PayloadRead.text(line.title)) from your order.",
                        canSend: !blocked) { result in
            let neverStarted: Bool
            if case .failure(let error) = result {
                neverStarted = FnbHandoff.neverStarted(error)
            } else {
                neverStarted = false
            }
            orders.finishRemoval(key: key, token: token, neverStarted: neverStarted)
        }
    }

    private func sendMore() {
        guard !blocked, actionable, let locationId = lines.last?.locationId else { return }
        runtime.perform(key: "showMore", hint: FnbHandoff.viewMenuHint,
                        fields: { _ in FnbHandoff.viewMenu(locationId: locationId) },
                        copy: FnbHandoff.showMoreText, canSend: !blocked)
    }
}
