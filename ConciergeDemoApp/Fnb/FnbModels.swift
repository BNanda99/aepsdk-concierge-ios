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

import Foundation
import CoreFoundation
import AEPBrandConcierge
import AEPServices
import Combine
import SwiftUI

enum FnbCurrency {
    static func validated(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3,
              code.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return "USD" }
        return code
    }
}

struct FnbLocationOptions {
    let ctaLabel: String
    let pendingCtaLabel: String
    let closedLabel: String
    let sectionLabelPrefix: String

    init(ctaLabel: String = "View menu", pendingCtaLabel: String = "Opening menu…",
         closedLabel: String = "Closed", sectionLabelPrefix: String = "Section ") {
        self.ctaLabel = PayloadRead.label(ctaLabel, fallback: "View menu")
        self.pendingCtaLabel = PayloadRead.label(pendingCtaLabel, fallback: "Opening menu…")
        self.closedLabel = PayloadRead.label(closedLabel, fallback: "Closed")
        self.sectionLabelPrefix = PayloadRead.text(sectionLabelPrefix)
    }
}

struct FnbQuantityRule {
    let minimum: Int
    let maximum: Int
    let defaultValue: Int
    let step: Int

    init(minimum: Int = 1, maximum: Int = 20, defaultValue: Int = 1, step: Int = 1) {
        let minimum = Swift.min(Swift.max(minimum, 1), 99)
        let maximum = Swift.min(Swift.max(maximum, minimum), 99)
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = Swift.min(Swift.max(defaultValue, minimum), maximum)
        self.step = Swift.min(Swift.max(step, 1), maximum)
    }
}

struct FnbInstructionsConfig {
    let label: String
    let placeholder: String
    let maxLength: Int

    init(label: String = "Optional instructions",
         placeholder: String = "e.g. no ice, light ice…", maxLength: Int = 140) {
        self.label = PayloadRead.label(label, fallback: "Optional instructions")
        self.placeholder = PayloadRead.label(placeholder, fallback: "Special instructions")
        self.maxLength = Swift.min(Swift.max(maxLength, 1), 140)
    }

    static let notesEnabled = FnbInstructionsConfig()
}

struct FnbCartBarConfig {
    let label: String
    let showCount: Bool
    let hideWhenEmpty: Bool
    let enabled: Bool

    init(label: String = "Add to cart", showCount: Bool = true,
         hideWhenEmpty: Bool = false, enabled: Bool = true) {
        self.label = PayloadRead.label(label, fallback: "Add to cart")
        self.showCount = showCount
        self.hideWhenEmpty = hideWhenEmpty
        self.enabled = enabled
    }
}

struct FnbMenuOptions {
    let currencyCode: String
    let quantity: FnbQuantityRule
    let instructions: FnbInstructionsConfig?
    let addToCartLabel: String
    let cartBar: FnbCartBarConfig

    init(currencyCode: String = "USD", quantity: FnbQuantityRule = FnbQuantityRule(),
         instructions: FnbInstructionsConfig? = nil, addToCartLabel: String = "Add to order",
         cartBar: FnbCartBarConfig = FnbCartBarConfig()) {
        self.currencyCode = FnbCurrency.validated(currencyCode)
        self.quantity = quantity
        self.instructions = instructions
        self.addToCartLabel = PayloadRead.label(addToCartLabel, fallback: "Add to order")
        self.cartBar = cartBar
    }
}

struct FnbCartOptions {
    let checkoutBase: String
    let checkoutVenueId: String?
    let allowedCheckoutHosts: Set<String>
    let currencyCode: String
    let checkoutLabel: String
    let showMoreLabel: String?

    init(checkoutBase: String = "https://mobile.tapin2.co", checkoutVenueId: String? = nil,
         allowedCheckoutHosts: Set<String> = ["tapin2.co"],
         currencyCode: String = "USD",
         checkoutLabel: String = "Proceed to checkout",
         showMoreLabel: String? = "Show more restaurants") {
        self.checkoutBase = checkoutBase
        self.checkoutVenueId = checkoutVenueId
        self.allowedCheckoutHosts = allowedCheckoutHosts
        self.currencyCode = FnbCurrency.validated(currencyCode)
        self.checkoutLabel = PayloadRead.label(checkoutLabel, fallback: "Proceed to checkout")
        self.showMoreLabel = showMoreLabel.map {
            PayloadRead.text($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static let stage = FnbCartOptions(checkoutBase: "https://mobile-stg.tapin2.co", checkoutVenueId: "1000010528")
}

struct FnbStand: Identifiable {
    let id: String
    let title: String
    let description: String
    let section: String?
    let detail: String
    let isOpen: Bool
    let image: URL?
    let order: Int

    static func map(_ payload: Any?, options: FnbLocationOptions = FnbLocationOptions()) -> [FnbStand] {
        let root = PayloadRead.object(payload)
        let values = PayloadRead.rows(root?["locations"] ?? root?["results"] ?? root?["data"] ?? payload, limit: 500)
        var seen = Set<String>()
        let mapped = values.enumerated().compactMap { position, row -> (Int, FnbStand)? in
            guard let id = PayloadRead.id(row["id"] ?? row["locationId"]),
                  PayloadRead.bool(row["isActive"]) != false, seen.insert(id).inserted else { return nil }
            let open = PayloadRead.bool(row["isPaused"]) != true &&
                PayloadRead.bool(row["orderingEnabled"] ?? row["isOrderingEnabled"]) != false
            let section = PayloadRead.string(row["section"]).map {
                options.sectionLabelPrefix + String(PayloadRead.text($0).prefix(16))
            }.flatMap { $0 == options.sectionLabelPrefix ? nil : $0 }
            let wait = PayloadRead.string(row["waitTime"]).map { String(PayloadRead.text($0).prefix(40)) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let isPickup = PayloadRead.bool(row["isPickup"]) != false
            let isDelivery = PayloadRead.bool(row["isDelivery"]) == true
            let detail = !open ? "\(options.closedLabel) right now" :
                [wait, isDelivery ? (wait == nil ? "Delivery to your seat" : "Delivery") : nil,
                 wait == nil && !isDelivery && isPickup ? "Pickup" : nil]
                .compactMap { $0 }.joined(separator: " · ")
            let image = PayloadRead.httpsImage(row["imageUrlMobile"]) ?? PayloadRead.artwork(row)
            return (position, FnbStand(id: id,
                            title: PayloadRead.text(row["title"] ?? row["name"] ?? row["label"], fallback: "Location"),
                            description: PayloadRead.text(row["description"]),
                            section: open ? section : nil,
                            detail: detail,
                            isOpen: open,
                            image: image,
                            order: PayloadRead.int(row["orderId"], maximum: 100_000) ?? Int.max))
        }
        return mapped.sorted { left, right in
            left.1.order == right.1.order ? left.0 < right.0 : left.1.order < right.1.order
        }.prefix(50).map { $0.1 }
    }
}

struct FnbItem: Identifiable {
    let id: String
    let categoryId: String
    let category: String
    let name: String
    let detail: String
    let isAlcohol: Bool
    let cents: Int
    let originalCents: Int?
    let image: URL?
    let modifierGroups: [[String: Any]]
    let categoryOrder: Int
    let order: Int

    static func map(_ payload: Any?) -> [FnbItem] {
        let root = PayloadRead.object(payload)
        let values = PayloadRead.rows(root?["products"] ?? payload, limit: 2_000)
        var seen = Set<String>()
        var seenCategories = Set<String>()
        let mapped = values.enumerated().compactMap { position, entry -> (Int, FnbItem)? in
            let product = PayloadRead.object(entry["product"]) ?? entry
            let category = PayloadRead.object(entry["category"])
            let categoryName = PayloadRead.text(category?["title"] ?? category?["name"])
            let categoryId = PayloadRead.id(category?["id"] ?? entry["categoryId"])
            guard let id = PayloadRead.id(product["id"] ?? product["Id"]),
                  let categoryId, !categoryName.isEmpty,
                  PayloadRead.bool(entry["isVisible"]) != false,
                  PayloadRead.bool(entry["hideInMobile"] ?? entry["isMobileHidden"]) != true,
                  PayloadRead.bool(entry["isActive"]) != false,
                  PayloadRead.bool(product["isActive"]) != false,
                  PayloadRead.bool(product["isArchived"]) != true,
                  PayloadRead.bool(category?["isActive"]) != false, !seen.contains(id) else { return nil }
            if !seenCategories.contains(categoryId), seenCategories.count >= 50 { return nil }
            seenCategories.insert(categoryId)
            var unorderable = false
            var seenGroups = Set<String>()
            let rawGroups = PayloadRead.rows(product["modifierGroups"], limit: 100)
            if rawGroups.count > 20 { unorderable = true }
            let groups = rawGroups.prefix(20).compactMap { group -> [String: Any]? in
                let rawMinimum = group["minimumSelections"] ?? group["minQuantity"]
                let parsedMinimum = PayloadRead.int(rawMinimum, maximum: 50)
                if rawMinimum != nil, parsedMinimum == nil { unorderable = true }
                let minimum = parsedMinimum ?? 0
                guard let groupId = PayloadRead.id(group["id"]),
                      PayloadRead.bool(group["showPublic"]) != false else {
                    if minimum > 0 { unorderable = true }
                    return nil
                }
                guard seenGroups.insert(groupId).inserted else {
                    unorderable = true
                    return nil
                }
                var seenOptions = Set<String>()
                let options = PayloadRead.rows(group["modifiers"], limit: 250)
                    .filter {
                        guard let optionId = PayloadRead.id($0["id"]) else { return false }
                        return PayloadRead.bool($0["isActive"]) != false &&
                        PayloadRead.bool($0["isArchived"]) != true &&
                        !PayloadRead.text($0["title"] ?? $0["name"]).isEmpty &&
                        seenOptions.insert(optionId).inserted
                    }
                    .prefix(50)
                if options.isEmpty {
                    if minimum > 0 { unorderable = true }
                    return nil
                }
                let maxQuantity = PayloadRead.int(group["maxQuantity"], maximum: 50)
                let maximumValue = group["maximumSelections"] ?? group["maxQuantity"]
                let rawMaximum = PayloadRead.int(maximumValue, maximum: 50)
                if maximumValue != nil, rawMaximum == nil { unorderable = true }
                let multi = PayloadRead.bool(group["isMultiSelect"]) == true ||
                    PayloadRead.bool(group["maxOnePerSelection"]) == false ||
                    (maxQuantity.map { $0 > 1 } ?? false)
                let maximum = min(options.count, rawMaximum.flatMap { $0 > 0 ? $0 : nil } ?? (multi ? options.count : 1))
                if minimum > maximum { unorderable = true }
                let normalizedOptions = options.map { option -> [String: Any] in
                    ["id": PayloadRead.id(option["id"]) ?? "",
                     "name": PayloadRead.text(option["title"] ?? option["name"], fallback: "Option"),
                     "price": option["price"] ?? option["priceDiff"] ?? 0,
                     "isSelected": PayloadRead.bool(option["isSelected"]) == true,
                     "isDefault": PayloadRead.bool(option["isDefault"]) == true]
                }
                return ["id": groupId, "name": PayloadRead.text(group["title"] ?? group["name"], fallback: "Options"),
                        "modifiers": normalizedOptions, "isMultiSelect": multi,
                        "maxOnePerSelection": PayloadRead.bool(group["maxOnePerSelection"]) != false,
                        "minimumSelections": minimum, "maximumSelections": maximum]
            }
            guard !unorderable else {
                Log.warning(label: "FnbCards", "Excluded an item with unavailable required modifier choices.")
                return nil
            }
            guard let cents = PayloadRead.cents(product["eventPrice"]) ?? PayloadRead.cents(product["price"]) else { return nil }
            seen.insert(id)
            let originalCents = PayloadRead.cents(product["originalPrice"]).flatMap { $0 > cents ? $0 : nil }
            return (position, FnbItem(id: id, categoryId: categoryId, category: categoryName,
                           name: PayloadRead.text(product["title"] ?? product["name"], fallback: "Item"),
                           detail: PayloadRead.text(product["description"]),
                           isAlcohol: PayloadRead.bool(product["isAlcohol"]) == true,
                           cents: cents,
                           originalCents: originalCents,
                           image: PayloadRead.artwork(product),
                           modifierGroups: groups,
                           categoryOrder: PayloadRead.int(category?["orderId"], maximum: 100_000) ?? Int.max,
                           order: PayloadRead.int(entry["orderId"] ?? product["orderId"], maximum: 100_000) ?? Int.max))
        }
        return mapped.sorted { left, right in
            if left.1.categoryOrder != right.1.categoryOrder { return left.1.categoryOrder < right.1.categoryOrder }
            if left.1.order != right.1.order { return left.1.order < right.1.order }
            return left.0 < right.0
        }.prefix(500).map { $0.1 }
    }
}

struct FnbLine: Codable, Identifiable {
    let id: String
    let name: String
    var quantity: Int
    let locationId: String
    let note: String?
    let selectedModifiers: [FnbModifierSelection]
    var unitCents: Int?

    var identity: String {
        id + "|" + selectedModifiers.map {
            "\($0.groupId):\($0.modifiers.sorted().joined(separator: ","))"
        }.sorted().joined(separator: ";") + "|" + (note ?? "")
    }

}

struct FnbModifierSelection: Codable {
    let groupId: String
    let isMultiSelect: Bool
    /// Selected option IDs.
    let modifiers: [String]
    /// The menu's available IDs, retained locally to validate saved selections.
    var options: [String]?
}

enum FnbHandoff {
    static let viewMenuHint = "view-menu"
    static let showMoreText = "Show more restaurants"

    private static func action(_ name: String, fields: [String: Any]) -> [String: Any] {
        ["_sacramentokings": ["conciergeAction": [name: fields]]]
    }

    /// `view-menu` and `show-more` use a string location ID and no local action metadata.
    static func viewMenu(locationId: String) -> [String: Any] {
        guard let id = PayloadRead.id(locationId) else { return [:] }
        return action("viewMenu", fields: ["locationId": id])
    }

    static func viewMenuCopy(_ title: String) -> String {
        let name = PayloadRead.text(title).replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Opening the menu." : "Opening the menu at \(String(name.prefix(60)))."
    }

    static let addToCartHint = "add-to-cart"

    private static func actionInteger(_ value: String) -> Int64? {
        guard value.range(of: #"^[0-9]{1,19}$"#, options: .regularExpression) != nil else { return nil }
        return Int64(value)
    }

    /// Only selected modifiers are sent. Held order/event state stays separate from this action.
    static func addToCart(lines: [FnbLine], menuItems: [String: FnbItem] = [:]) -> [String: Any]? {
        guard !lines.isEmpty, lines.count <= 20 else { return nil }
        var products: [[String: Any]] = []
        for line in lines {
            guard let productId = actionInteger(line.id), let location = actionInteger(line.locationId),
                  productId >= 0, location >= 0, (1...99).contains(line.quantity) else { return nil }
            var groups: [[String: Any]] = []
            var seenGroups = Set<String>()
            for selection in line.selectedModifiers {
                guard !selection.modifiers.isEmpty else { continue }
                let menuGroup = menuItems[line.id]?.modifierGroups.first {
                    PayloadRead.id($0["id"]) == selection.groupId
                }
                let isMultiSelect = PayloadRead.bool(menuGroup?["isMultiSelect"]) ?? selection.isMultiSelect
                guard seenGroups.insert(selection.groupId).inserted, groups.count < 20,
                      Set(selection.modifiers).count == selection.modifiers.count,
                      isMultiSelect || selection.modifiers.count == 1 else { return nil }
                guard selection.options == nil ||
                        Set(selection.modifiers).isSubset(of: Set(selection.options ?? [])) else { return nil }
                var modifiers: [[String: Any]] = []
                for modifier in selection.modifiers {
                    guard let id = actionInteger(modifier) else { return nil }
                    modifiers.append(["id": id, "isSelected": true])
                }
                groups.append(["isMultiSelect": isMultiSelect, "modifiers": modifiers])
            }
            var product: [String: Any] = [
                "locationId": location, "productId": productId, "quantity": line.quantity
            ]
            if !groups.isEmpty { product["modifierGroups"] = groups }
            products.append(product)
        }
        let fields = action("addToCart", fields: ["products": products])
        return JSONSerialization.isValidJSONObject(fields) ? fields : nil
    }

    static func removeFromCart(locationId: String?, productId: String?, modifiers: String?) -> [String: Any]? {
        guard let location = locationId.flatMap(actionInteger),
              let product = productId.flatMap(actionInteger) else { return nil }
        var fields: [String: Any] = ["locationId": location, "productId": product]
        let selectedModifiers = PayloadRead.text(modifiers).trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedModifiers.isEmpty && selectedModifiers != "No modifiers" {
            fields["modifier"] = selectedModifiers
        }
        return action("removeFromCart", fields: ["products": [fields]])
    }

    static func checkoutURL(base: String, venueId: String, eventId: String, guid: String,
                            allowedHosts: Set<String> = ["tapin2.co"]) -> URL? {
        guard let venue = PayloadRead.urlId(venueId), let event = PayloadRead.urlId(eventId), let order = PayloadRead.urlId(guid),
              let components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              allowedHosts.contains(where: { approved in
                  let approved = approved.lowercased()
                  return !approved.isEmpty && (host == approved || host.hasSuffix("." + approved))
              }),
              components.user == nil, components.password == nil,
              (components.path.isEmpty || components.path == "/"),
              components.query == nil, components.fragment == nil else { return nil }
        var destination = components
        destination.path = "/Review/Index/\(venue)"
        destination.queryItems = [URLQueryItem(name: "eventId", value: event),
                                  URLQueryItem(name: "orderId", value: order)]
        return destination.url
    }

    static func cartAddMessage(lines: [FnbLine], locationName: String?) -> String {
        let safeLocation = PayloadRead.text(locationName)
        let heading = safeLocation.isEmpty ? "Adding to your cart:" : "Adding to your cart from \(safeLocation):"
        let rows = lines.prefix(5).map { line in
            let name = PayloadRead.text(line.name, fallback: "Item")
            let note = PayloadRead.text(line.note)
            return "• \(line.quantity) × \(name)\(note.isEmpty ? "" : " (\(note))")"
        }
        let remaining = lines.count - rows.count
        let tail = remaining > 0 ? ["• and \(remaining) more item\(remaining == 1 ? "" : "s")"] : []
        return ([heading] + rows + tail).joined(separator: "\n")
    }

    static func neverStarted(_ error: ConciergeDataHandoffError) -> Bool {
        switch error {
        case .chatInProgress, .noActiveSession, .missingEventData, .emptyXdmFields,
             .invalidXdmFieldValue, .reservedKeyCollision: return true
        default: return false
        }
    }

    static func retryMessage(_ error: ConciergeDataHandoffError) -> String {
        switch error {
        case .chatInProgress:
            return "Wait for the current response before trying again."
        case .noActiveSession:
            return "Open Concierge before trying this action again."
        default:
            return "This action couldn't be sent. Please try again."
        }
    }
}

struct FnbOrderSummary {
    let id: String
    let guid: String?
    let venueName: String?
    let lines: [FnbOrderLine]
    let paid: Bool
    let subtotal: Int?
    let tax: Int?
    let fees: Int?
    let discount: Int?
    let tip: Int?
    let total: Int?

    static func map(_ payload: Any?, fallbackId: Any?) -> FnbOrderSummary? {
        guard let order = PayloadRead.object(payload),
              let numericId = PayloadRead.integerId(order["id"]) ?? PayloadRead.integerId(fallbackId),
              numericId >= 0 else { return nil }
        let id = String(numericId)
        let locationRows = PayloadRead.rows(order["distinctLocations"], limit: 100)
        var locationNames: [String: String] = [:]
        for location in locationRows {
            guard let locationId = PayloadRead.id(location["id"]) else { continue }
            let name = PayloadRead.text(location["title"] ?? location["name"])
            if !name.isEmpty { locationNames[locationId] = name }
        }
        if let location = PayloadRead.object(order["location"]),
           let locationId = PayloadRead.id(location["id"]) {
            let name = PayloadRead.text(location["title"] ?? location["name"])
            if !name.isEmpty { locationNames[locationId] = name }
        }
        var seenLines = Set<String>()
        let mappedLines = PayloadRead.rows(order["items"], limit: 500).compactMap { row -> FnbOrderLine? in
            guard let line = FnbOrderLine.map(row, locationNames: locationNames),
                  seenLines.insert(line.id).inserted else { return nil }
            return line
        }
        let lines = Array(mappedLines.prefix(50))
        let lineSum = FnbOrderLine.checkedSubtotal(lines)
        let subtotal = PayloadRead.cents(order["subtotalNet"]) ?? lineSum
        let tax = PayloadRead.cents(order["taxAddedNet"]) ?? 0
        let fees = PayloadRead.cents(order["feeAddedNet"]) ?? 0
        let discount = PayloadRead.cents(order["discountNet"], allowNegative: true) ?? 0
        let tip = PayloadRead.cents(order["tipNet"]) ?? 0
        return FnbOrderSummary(id: id, guid: PayloadRead.id(order["guid"]),
                               venueName: PayloadRead.text(PayloadRead.object(order["venue"])?["title"]).nilIfEmpty,
                               lines: lines,
                               paid: PayloadRead.bool(order["isPaidInFull"] ?? order["isPaid"]) == true ||
                               (order["status"] as? String)?.lowercased() == "paid",
                               subtotal: subtotal, tax: tax, fees: fees, discount: abs(discount),
                               tip: tip, total: PayloadRead.cents(order["totalNet"]) ?? lineSum)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct FnbOrderLine {
    let id: String
    let productId: String?
    let locationId: String?
    let title: String
    let quantity: Int
    let pricePer: Int
    let subtotal: Int?
    let modifiers: String
    let standName: String?
    let note: String?

    static func map(_ row: [String: Any], locationNames: [String: String]) -> FnbOrderLine? {
        guard let id = PayloadRead.id(row["id"]),
              let quantity = PayloadRead.int(row["quantity"], minimum: 1),
              quantity <= 99 else { return nil }
        let product = PayloadRead.object(row["product"]) ?? [:]
        let title = PayloadRead.text(product["title"] ?? product["name"])
        guard !title.isEmpty else { return nil }
        let price = PayloadRead.cents(row["pricePer"] ?? row["unitPrice"]) ?? 0
        let subtotal: Int?
        if let amount = PayloadRead.cents(row["subtotal"]) {
            subtotal = amount
        } else {
            let (amount, overflow) = price.multipliedReportingOverflow(by: quantity)
            subtotal = !overflow && amount <= 1_000_000_000 ? amount : nil
        }
        return FnbOrderLine(
            id: id,
            productId: PayloadRead.id(product["id"]),
            locationId: PayloadRead.id(row["locationId"]),
            title: title,
            quantity: quantity,
            pricePer: price,
            subtotal: subtotal,
            modifiers: modifierSummary(row),
            standName: PayloadRead.id(row["locationId"]).flatMap { locationNames[$0] },
            note: PayloadRead.text(row["note"]).nilIfEmpty
        )
    }

    static func checkedSubtotal(_ lines: [FnbOrderLine]) -> Int? {
        var total = 0
        for line in lines {
            guard let subtotal = line.subtotal else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(subtotal)
            guard !overflow, sum <= 1_000_000_000 else { return nil }
            total = sum
        }
        return total
    }

    private static func modifierSummary(_ row: [String: Any]) -> String {
        let rawModifiers = row["modifiers"] as? [Any] ?? []
        let list = rawModifiers.prefix(100).compactMap { modifier -> String? in
            if let modifier = modifier as? String { return PayloadRead.text(modifier).nilIfEmpty }
            guard let modifier = PayloadRead.object(modifier) else { return nil }
            return PayloadRead.text(modifier["title"] ?? modifier["name"]).nilIfEmpty
        }
        let source = list.isEmpty
            ? (PayloadRead.string(row["modifier"]) ?? "").split(separator: ",").map(String.init)
            : list
        let labels = source.map { PayloadRead.text($0) }.filter { !$0.isEmpty }.prefix(10)
        return labels.isEmpty ? "No modifiers" : labels.joined(separator: ", ")
    }
}

typealias FnbSend = (_ hint: String, _ fields: [String: Any], _ copy: String,
                     _ completion: @escaping @MainActor (Result<Void, ConciergeDataHandoffError>) -> Void) throws -> Void

@MainActor
final class FnbMenuRuntime: ObservableObject {
    @Published private(set) var draft: [FnbLine] = []
    @Published private(set) var status = "draft"
    @Published private(set) var errorMessage: String?
    @Published private(set) var submitId: String?
    private(set) var revision = 0
    private let save: ([String: Any]) -> Void
    private let send: FnbSend
    private let makeId: () -> String
    private let quantityRule: FnbQuantityRule
    private var submissionAttempt: UUID?
    private(set) var disposed = false

    var estimatedTotal: Int? {
        var total = 0
        for line in draft {
            guard let unit = line.unitCents, (0...1_000_000_000).contains(unit) else { return nil }
            let (amount, multiplicationOverflow) = unit.multipliedReportingOverflow(by: line.quantity)
            let (sum, additionOverflow) = total.addingReportingOverflow(amount)
            guard !multiplicationOverflow, !additionOverflow, sum <= 1_000_000_000 else { return nil }
            total = sum
        }
        return total
    }

    func nativeCardDidDispose() { disposed = true }

    init(state: [String: Any], save: @escaping ([String: Any]) -> Void,
         quantityRule: FnbQuantityRule = FnbQuantityRule(),
         send: @escaping FnbSend = { hint, fields, copy, completion in
             Concierge.sendDataHandoff(routingHint: hint, xdmFields: fields,
                                       localMessage: copy, completion: completion)
         },
         makeId: @escaping () -> String = { UUID().uuidString }) {
        self.save = save
        self.send = send
        self.makeId = makeId
        self.quantityRule = quantityRule
        adopt(state)
    }

    func adopt(_ state: [String: Any]) {
        guard let incoming = PayloadRead.int(state["rev"], maximum: Int.max),
              incoming > revision || revision == 0 && incoming == 0 else { return }
        guard let status = state["status"] as? String,
              ["draft", "submitting", "added", "unconfirmed"].contains(status),
              let encoded = state["cart"] as? String, encoded.count <= 100_000,
              let data = encoded.data(using: .utf8),
              let lines = try? JSONDecoder().decode([FnbLine].self, from: data),
              lines.count <= 20,
              lines.allSatisfy({ (1...99).contains($0.quantity) &&
                  PayloadRead.id($0.id) != nil && PayloadRead.id($0.locationId) != nil }) else { return }
        revision = incoming
        draft = lines
        self.status = status
        submitId = state["submitId"] as? String
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(draft),
              let encoded = String(data: data, encoding: .utf8) else { return }
        revision += 1
        var snapshot: [String: Any] = ["cart": encoded, "status": status, "rev": revision]
        if let submitId { snapshot["submitId"] = submitId }
        save(snapshot)
    }

    func add(_ line: FnbLine) {
        guard !disposed, status == "draft", PayloadRead.id(line.id) != nil,
              PayloadRead.id(line.locationId) != nil,
              (1...quantityRule.maximum).contains(line.quantity),
              line.note == nil || (line.note?.count ?? 0) <= 140 else { return }
        if let index = draft.firstIndex(where: { $0.identity == line.identity }) {
            let (quantity, overflow) = draft[index].quantity.addingReportingOverflow(line.quantity)
            guard !overflow, quantity <= quantityRule.maximum else { return }
            draft[index].quantity = quantity
        } else {
            guard draft.count < 20 else { return }
            draft.append(line)
        }
        submitId = nil
        status = "draft"
        errorMessage = nil
        persist()
    }

    func decrement(productId: String) {
        guard !disposed, status == "draft" else { return }
        let index = draft.firstIndex { $0.id == productId && $0.selectedModifiers.isEmpty && $0.note == nil }
            ?? draft.lastIndex { $0.id == productId }
        guard let index else { return }
        if draft[index].quantity <= quantityRule.minimum { draft.remove(at: index) } else { draft[index].quantity = Swift.max(quantityRule.minimum,
                                                 draft[index].quantity - quantityRule.step) }
        submitId = nil
        status = "draft"
        errorMessage = nil
        persist()
    }

    func quantity(for productId: String) -> Int {
        draft.filter { $0.id == productId }.reduce(0) { $0 + $1.quantity }
    }

    func submit(locationId: String, venueId: String?, eventId: String?, orderId: String? = nil,
                locationName: String? = nil, menuItems: [String: FnbItem] = [:], canSend: Bool) {
        guard !disposed, canSend, status == "draft", !draft.isEmpty,
              PayloadRead.id(locationId) != nil else { return }
        // Tracked locally to guard duplicate taps and restored submissions; never sent.
        let actionId = submitId ?? makeId()
        guard let fields = FnbHandoff.addToCart(lines: draft, menuItems: menuItems) else {
            errorMessage = "These items couldn't be added. Ask Concierge for an updated menu."
            Log.warning(label: "FnbCards", "Add to cart rejected: the draft could not form a valid handoff.")
            return
        }
        let submitted = draft
        let attempt = UUID()
        submissionAttempt = attempt
        submitId = actionId
        status = "submitting"
        errorMessage = nil
        persist()
        let summary = FnbHandoff.cartAddMessage(lines: submitted, locationName: locationName)
        let completion: @MainActor (Result<Void, ConciergeDataHandoffError>) -> Void = { [self] result in
            guard !self.disposed, self.status == "submitting",
                  self.submitId == actionId, self.submissionAttempt == attempt else { return }
            self.submissionAttempt = nil
            switch result {
            case .success:
                self.draft = []
                self.status = "added"
                self.errorMessage = nil
                self.submitId = nil
                self.persist()
            case .failure(let error) where FnbHandoff.neverStarted(error):
                self.status = "draft"
                self.errorMessage = FnbHandoff.retryMessage(error)
                self.persist()
            case .failure:
                self.draft = []
                self.status = "unconfirmed"
                self.errorMessage = "We couldn't confirm the last add. Ask Concierge before retrying those items."
                self.submitId = nil
                self.persist()
            }
        }
        do {
            try send(FnbHandoff.addToCartHint, fields, summary, completion)
        } catch {
            Log.warning(label: "FnbCards", "Add delivery is unconfirmed after the sender threw: \(error)")
            completion(.failure(.noResponse))
        }
    }
}

/// App-owned F&B coordination across card instances. Which card is newest comes from the SDK's
/// `isLatest` context flag, never from display order: SwiftUI doesn't show transcript rows in
/// transcript order, so a card whose `onAppear` fires later can be older.
@MainActor
final class FnbOrderStore: ObservableObject {
    static let shared = FnbOrderStore()

    @Published private(set) var submittedMenuCardIds = Set<String>()
    /// Menus that checkout closed; menus displayed after checkout stay open.
    @Published private(set) var closedMenuCardIds = Set<String>()
    @Published private(set) var stateRevision = 0
    /// Carts whose snapshot claimed the current order when they were displayed as the newest cart.
    @Published private(set) var claimedCartCardIds = Set<String>()
    @Published private(set) var removals = Set<String>()
    private(set) var identityRevision = 0

    private(set) var currentOrderId: Int64?
    private var currentOrder: [String: Any]?
    private var pastOrders: [[String: Any]] = []
    private var seenCardIds = Set<String>()
    private var shownMenuCardIds = Set<String>()
    private var retiredSessionIds = Set<String>()
    private var activeSessionId: String?
    private var removalTokens: [String: UUID] = [:]
    private let publish: ([String: Any]) -> Void

    init(publish: @escaping ([String: Any]) -> Void = { patch in
        do {
            try Concierge.updateXDMContext(patch)
        } catch {
            Log.warning(label: "FnbCards", "Kings order context could not be updated: \(error)")
        }
    }) {
        self.publish = publish
    }

    private func prepareCard(cardId: String, sessionId: String, stale: Bool) -> Bool {
        guard !stale, let cardId = PayloadRead.id(cardId), let sessionId = PayloadRead.id(sessionId),
              !retiredSessionIds.contains(sessionId) else { return false }
        if activeSessionId != sessionId {
            let hadActiveSession = activeSessionId != nil
            if let activeSessionId { retiredSessionIds.insert(activeSessionId) }
            activeSessionId = sessionId
            seenCardIds.removeAll()
            shownMenuCardIds.removeAll()
            closedMenuCardIds.removeAll()
            submittedMenuCardIds.removeAll()
            currentOrderId = nil
            currentOrder = nil
            pastOrders.removeAll()
            clearPendingActions()
            identityRevision += 1
            stateRevision += 1
            if hadActiveSession {
                publish(["_sacramentokings": ["conciergeContext": ["fnbOrders": NSNull()]]])
            }
        }
        guard seenCardIds.insert(cardId).inserted else { return false }
        return true
    }

    private func clearPendingActions() {
        claimedCartCardIds.removeAll()
        removals.removeAll()
        removalTokens.removeAll()
    }

    /// Publishes the game once, and only from the newest locations card, so an older card that
    /// displays later can't overwrite it. Re-run when `isLatest` changes (rollback promotion).
    func locationsShown(cardId: String, sessionId: String, eventId: Any?, stale: Bool, isLatest: Bool) {
        guard isLatest, prepareCard(cardId: cardId, sessionId: sessionId, stale: stale),
              let event = PayloadRead.integerId(eventId), event >= 0 else { return }
        publishOrders(["eventId": event])
    }

    /// Records a displayed menu so checkout can close it; it doesn't decide which menu is newest.
    func menuShown(cardId: String, sessionId: String, stale: Bool) {
        guard prepareCard(cardId: cardId, sessionId: sessionId, stale: stale) else { return }
        shownMenuCardIds.insert(cardId)
    }

    func isMenuActionable(cardId: String, sessionId: String, stale: Bool, isLatest: Bool) -> Bool {
        guard isLatest, !stale, let cardId = PayloadRead.id(cardId), let sessionId = PayloadRead.id(sessionId),
              activeSessionId == sessionId, !retiredSessionIds.contains(sessionId),
              !submittedMenuCardIds.contains(cardId) else { return false }
        return !closedMenuCardIds.contains(cardId)
    }

    func isSessionActive(_ sessionId: String, stale: Bool) -> Bool {
        !stale && PayloadRead.id(sessionId) == activeSessionId
    }

    func markMenuSubmitted(cardId: String, sessionId: String) {
        guard activeSessionId == sessionId, shownMenuCardIds.contains(cardId) else { return }
        submittedMenuCardIds.insert(cardId)
        stateRevision += 1
    }

    /// Only the newest cart claims the current order, so an older cart that displays later can't.
    /// Re-run when `isLatest` changes (rollback promotion).
    func cartShown(cardId: String, sessionId: String, orderId: Any?, paid: Bool, stale: Bool, isLatest: Bool) {
        guard isLatest, prepareCard(cardId: cardId, sessionId: sessionId, stale: stale) else { return }
        // A fresh authoritative snapshot settles the preceding snapshot's removal reservations.
        removals.removeAll()
        removalTokens.removeAll()
        guard !paid, let id = PayloadRead.integerId(orderId), id >= 0,
              !pastOrders.contains(where: { PayloadRead.integerId($0["orderId"]) == id }),
              currentOrderId == nil || currentOrderId == id else { return }
        claimedCartCardIds.insert(cardId)
        guard currentOrderId == nil else { return }
        let order: [String: Any] = ["orderId": id]
        currentOrderId = id
        currentOrder = order
        stateRevision += 1
        publishOrders(["currentOrder": order])
    }

    func isOrderArchived(_ orderId: String?) -> Bool {
        guard let orderId, let id = PayloadRead.integerId(orderId) else { return false }
        return pastOrders.contains { PayloadRead.integerId($0["orderId"]) == id }
    }

    func isCartActionable(cardId: String, sessionId: String, orderId: String?, stale: Bool, isLatest: Bool) -> Bool {
        guard isLatest, isSessionActive(sessionId, stale: stale), claimedCartCardIds.contains(cardId),
              let orderId, let id = PayloadRead.integerId(orderId),
              currentOrderId == id, !isOrderArchived(orderId) else { return false }
        return true
    }

    static func removalKey(orderId: String, line: FnbOrderLine) -> String {
        // The wire cannot distinguish lines with the same product/location/modifier tuple.
        let parts = [orderId, line.locationId ?? "", line.productId ?? "", line.modifiers]
        return parts.map { "\($0.utf8.count):\($0)" }.joined()
    }

    func beginRemoval(key: String, cardId: String, sessionId: String, orderId: String?, stale: Bool,
                      isLatest: Bool) -> UUID? {
        guard isCartActionable(cardId: cardId, sessionId: sessionId, orderId: orderId, stale: stale,
                               isLatest: isLatest),
              removals.insert(key).inserted else { return nil }
        let token = UUID()
        removalTokens[key] = token
        return token
    }

    func finishRemoval(key: String, token: UUID, neverStarted: Bool) {
        guard removalTokens[key] == token else { return }
        if neverStarted {
            removalTokens.removeValue(forKey: key)
            removals.remove(key)
        }
    }

    func canOpenCheckout(cardId: String, sessionId: String, orderId: String?, stale: Bool, isLatest: Bool,
                         unresolved: Bool) -> Bool {
        isSessionActive(sessionId, stale: stale) &&
            (isOrderArchived(orderId) || (!unresolved &&
                isCartActionable(cardId: cardId, sessionId: sessionId, orderId: orderId, stale: stale,
                                 isLatest: isLatest)))
    }

    func checkoutDidOpen(orderId: String?, sessionId: String, identityRevision: Int? = nil) {
        guard identityRevision == nil || identityRevision == self.identityRevision else { return }
        guard let orderId, let id = PayloadRead.integerId(orderId), id >= 0,
              activeSessionId == sessionId, id == currentOrderId, let currentOrder else { return }
        pastOrders.append(currentOrder)
        self.currentOrder = nil
        currentOrderId = nil
        // Closes every menu displayed so far; a menu that arrives later is a new card and stays open.
        closedMenuCardIds.formUnion(shownMenuCardIds)
        clearPendingActions()
        stateRevision += 1
        publishOrders(["currentOrder": NSNull(), "pastOrders": pastOrders])
    }

    func identityDidReset() {
        if let activeSessionId { retiredSessionIds.insert(activeSessionId) }
        activeSessionId = nil
        seenCardIds.removeAll()
        shownMenuCardIds.removeAll()
        closedMenuCardIds.removeAll()
        submittedMenuCardIds.removeAll()
        currentOrderId = nil
        currentOrder = nil
        pastOrders.removeAll()
        clearPendingActions()
        identityRevision += 1
        stateRevision += 1
        publish(["_sacramentokings": ["conciergeContext": ["fnbOrders": NSNull()]]])
    }

    private func publishOrders(_ fields: [String: Any]) {
        publish(["_sacramentokings": ["conciergeContext": ["fnbOrders": fields]]])
    }
}

@MainActor
final class FnbActionRuntime: ObservableObject {
    @Published private(set) var activeAction: String?
    @Published private(set) var activeActionKey: String?
    @Published private(set) var selected: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingRemovals = Set<String>()
    @Published private(set) var unconfirmed = Set<String>()
    private(set) var retryIds: [String: String] = [:]
    private(set) var revision = 0
    private let save: ([String: Any]) -> Void
    private let send: FnbSend
    private let makeId: () -> String
    private var activeAttempt: UUID?
    private(set) var disposed = false

    func nativeCardDidDispose() { disposed = true }

    init(state: [String: Any], save: @escaping ([String: Any]) -> Void,
         send: @escaping FnbSend = { hint, fields, copy, completion in
             Concierge.sendDataHandoff(routingHint: hint, xdmFields: fields,
                                       localMessage: copy, completion: completion)
         },
         makeId: @escaping () -> String = { UUID().uuidString }) {
        self.save = save
        self.send = send
        self.makeId = makeId
        adopt(state)
    }

    func adopt(_ state: [String: Any]) {
        guard let incoming = PayloadRead.int(state["rev"], maximum: Int.max), incoming > revision else { return }
        revision = incoming
        selected = state["selected"] as? String
        activeAction = state["activeAction"] as? String
        activeActionKey = state["activeActionKey"] as? String
        pendingRemovals = Set(state["pendingRemovals"] as? [String] ?? [])
        unconfirmed = Set(state["unconfirmedActionKeys"] as? [String] ?? [])
        retryIds = state["retryActionIds"] as? [String: String] ?? [:]
    }

    private func persist() {
        revision += 1
        var snapshot: [String: Any] = [
            "rev": revision, "pendingRemovals": Array(pendingRemovals).sorted(),
            "unconfirmedActionKeys": Array(unconfirmed).sorted(), "retryActionIds": retryIds
        ]
        if let selected { snapshot["selected"] = selected }
        if let activeAction { snapshot["activeAction"] = activeAction }
        if let activeActionKey { snapshot["activeActionKey"] = activeActionKey }
        save(snapshot)
    }

    func perform(key: String, hint: String, fields: (String) -> [String: Any],
                 copy: String, selected: String? = nil, canSend: Bool,
                 completion: ((Result<Void, ConciergeDataHandoffError>) -> Void)? = nil) {
        guard !disposed, canSend, activeAction == nil, !unconfirmed.contains(key),
              !pendingRemovals.contains(key) else { return }
        // Lookups (view-menu, search-parking, show more) carry no action ID on the wire, but the
        // runtime still tracks one locally for duplicate-tap, retry and unconfirmed guards.
        let actionId = retryIds[key] ?? makeId()
        guard PayloadRead.id(actionId) != nil else { return }
        let payload = fields(actionId)
        guard !payload.isEmpty, JSONSerialization.isValidJSONObject(payload) else { return }
        guard payload["actionId"] == nil else { return }
        retryIds[key] = actionId
        let attempt = UUID()
        activeAttempt = attempt
        if let selected { self.selected = selected }
        activeAction = actionId
        activeActionKey = key
        errorMessage = nil
        persist()
        let finish: @MainActor (Result<Void, ConciergeDataHandoffError>) -> Void = { [self] result in
            guard !self.disposed, self.activeAction == actionId,
                  self.activeAttempt == attempt else { return }
            self.activeAttempt = nil
            completion?(result)
            self.activeAction = nil
            self.activeActionKey = nil
            switch result {
            case .success:
                self.errorMessage = nil
                self.retryIds.removeValue(forKey: key)
                if key.hasPrefix("remove:") { self.pendingRemovals.insert(key) }
            case .failure(let error) where FnbHandoff.neverStarted(error):
                self.errorMessage = FnbHandoff.retryMessage(error)
            case .failure:
                self.retryIds.removeValue(forKey: key)
                self.unconfirmed.insert(key)
                self.errorMessage = "We couldn't confirm the last action. Ask Concierge for the latest information."
            }
            self.persist()
        }
        do {
            try send(hint, payload, copy, finish)
        } catch {
            Log.warning(label: "FnbCards", "Action delivery is unconfirmed after the sender threw: \(error)")
            finish(.failure(.noResponse))
        }
    }
}

enum FnbThemeValue {
    static func dimension(_ value: String?, fallback: CGFloat, range: ClosedRange<CGFloat> = 0...1000) -> CGFloat {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return fallback }
        if text.hasSuffix("px") || text.hasSuffix("dp") { text = String(text.dropLast(2)) }
        guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite, range.contains(CGFloat(number)) else { return fallback }
        return CGFloat(number)
    }

    static func color(_ value: String?) -> Color? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if value == "transparent" { return Color.clear }
        if value.hasPrefix("#") {
            var hex = String(value.dropFirst())
            if hex.count == 3 || hex.count == 4 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return nil }
            let red = Double((number >> (hex.count == 8 ? 24 : 16)) & 255) / 255
            let green = Double((number >> (hex.count == 8 ? 16 : 8)) & 255) / 255
            let blue = Double((number >> (hex.count == 8 ? 8 : 0)) & 255) / 255
            let alpha = hex.count == 8 ? Double(number & 255) / 255 : 1
            return Color(red: red, green: green, blue: blue, opacity: alpha)
        }
        guard value.hasSuffix(")"),
              value.hasPrefix("rgb(") || value.hasPrefix("rgba("),
              let opening = value.firstIndex(of: "(") else { return nil }
        let parts = value[value.index(after: opening)..<value.index(before: value.endIndex)]
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == (value.hasPrefix("rgba(") ? 4 : 3),
              let red = Double(parts[0]), let green = Double(parts[1]), let blue = Double(parts[2]),
              [red, green, blue].allSatisfy({ $0.isFinite && (0...255).contains($0) }) else { return nil }
        let alpha = parts.count == 4 ? Double(parts[3]) : 1
        guard let alpha, alpha.isFinite, (0...1).contains(alpha) else { return nil }
        return Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
    }
}

enum FnbStyle {
    static func color(_ key: String, theme: ConciergeTheme, fallback: Color) -> Color {
        FnbThemeValue.color(theme.customVariables[key]) ?? fallback
    }

    static func dimension(_ key: String, theme: ConciergeTheme, fallback: CGFloat,
                          range: ClosedRange<CGFloat> = 0...1000) -> CGFloat {
        FnbThemeValue.dimension(theme.customVariables[key], fallback: fallback, range: range)
    }

    static func cardBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-card-background-color", theme: theme,
              fallback: theme.colors.productCard.backgroundColor?.color ??
                theme.colors.primary.container?.color ?? Color(UIColor.secondarySystemBackground))
    }

    static func border(_ theme: ConciergeTheme) -> Color {
        color("--fnb-card-border-color", theme: theme,
              fallback: theme.colors.productCard.outlineColor.color)
    }

    static func primaryText(_ theme: ConciergeTheme) -> Color {
        color("--fnb-text-primary-color", theme: theme,
              fallback: theme.colors.productCard.titleColor.color)
    }

    static func secondaryText(_ theme: ConciergeTheme) -> Color {
        color("--fnb-text-secondary-color", theme: theme,
              fallback: theme.colors.productCard.subtitleColor.color)
    }

    static func accent(_ theme: ConciergeTheme) -> Color {
        color("--fnb-accent-color", theme: theme,
              fallback: theme.colors.productCardCtaButton.background.color)
    }

    static func onAccent(_ theme: ConciergeTheme) -> Color {
        color("--fnb-on-accent-color", theme: theme,
              fallback: theme.colors.productCardCtaButton.text.color)
    }

    static func disabled(_ theme: ConciergeTheme) -> Color {
        color("--fnb-disabled-color", theme: theme,
              fallback: theme.colors.button.disabledBackground.color)
    }

    static func imagePlaceholder(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tile-image-placeholder-color", theme: theme,
              fallback: color("--simple-card-image-placeholder-color", theme: theme,
                              fallback: theme.colors.primary.secondary.color))
    }

    static func tileBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tile-background-color", theme: theme,
              fallback: theme.colors.productCard.backgroundColor?.color ?? cardBackground(theme))
    }

    static func tabText(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tab-text-color", theme: theme, fallback: primaryText(theme))
    }

    static func cardRadius(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-card-corner-radius", theme: theme, fallback: 16)
    }

    static func contentPadding(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-content-padding", theme: theme, fallback: 12)
    }

    static func tileWidth(_ theme: ConciergeTheme) -> CGFloat {
        let width = dimension("--fnb-tile-width", theme: theme, fallback: 132)
        return min(max(width, 96), 320)
    }

    static func tileImageHeight(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-tile-image-height", theme: theme, fallback: 112)
    }

    static func tileRadius(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-tile-corner-radius", theme: theme, fallback: 12)
    }

    static func imageRadius(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--simple-card-image-border-radius", theme: theme, fallback: 10)
    }

    static func buttonRadius(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-button-corner-radius", theme: theme, fallback: 999)
    }

    static func locationTileWidth(_ theme: ConciergeTheme) -> CGFloat {
        let width = dimension("--fnb-location-tile-width", theme: theme, fallback: theme.layout.productCardWidth)
        return min(max(width, 160), 320)
    }

    static func tabBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tab-background-color", theme: theme,
              fallback: theme.colors.primary.container?.color ?? tileBackground(theme))
    }

    static func tabRadius(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-tab-corner-radius", theme: theme, fallback: 20)
    }

    static func statusColor(online: Bool, theme: ConciergeTheme) -> Color {
        online ? color("--fnb-status-online-color", theme: theme, fallback: Color(red: 0.18, green: 0.49, blue: 0.2))
            : color("--fnb-status-offline-color", theme: theme, fallback: secondaryText(theme))
    }

    static func stepperBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-stepper-background-color", theme: theme, fallback: cardBackground(theme))
    }

    static func stepperContent(_ theme: ConciergeTheme) -> Color {
        color("--fnb-stepper-content-color", theme: theme, fallback: accent(theme))
    }

    static func stepperSize(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-stepper-size", theme: theme, fallback: 30, range: 24...44)
    }

    static func errorColor(_ theme: ConciergeTheme) -> Color {
        color("--fnb-error-color", theme: theme, fallback: .red)
    }

    static func sheetBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-sheet-background-color", theme: theme, fallback: cardBackground(theme))
    }

    static func tagBackground(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tag-background-color", theme: theme, fallback: Color.black.opacity(0.7))
    }

    static func tagText(_ theme: ConciergeTheme) -> Color {
        color("--fnb-tag-text-color", theme: theme, fallback: .white)
    }

    /// Full currency format, e.g. "$8.00", used for item and line prices.
    static func price(cents: Int, currencyCode: String) -> String {
        (Decimal(cents) / 100).formatted(Decimal.FormatStyle.Currency(code: currencyCode))
    }

    /// Drops a zero fraction, e.g. "$3" or "$1.50", used for option surcharges.
    static func priceText(cents: Int, currencyCode: String) -> String {
        let amount = Decimal(cents) / 100
        let style = Decimal.FormatStyle.Currency(code: currencyCode)
        return cents % 100 == 0 ? amount.formatted(style.precision(.fractionLength(0))) : amount.formatted(style)
    }

    static func buttonHeight(_ theme: ConciergeTheme) -> CGFloat {
        dimension("--fnb-button-height", theme: theme, fallback: 48)
    }
}
