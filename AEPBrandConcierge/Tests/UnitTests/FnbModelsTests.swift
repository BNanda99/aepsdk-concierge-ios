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

import XCTest
@testable import AEPBrandConcierge
import AEPCore
import AEPServices

final class FnbModelsTests: XCTestCase {
    @MainActor
    func testOrderPublishingAndClearingPreservesHostOwnedContextAndTransientActions() throws {
        let held = ConciergeXDMContextStore(sessionIDProvider: { "session" })
        let hostFacts: [String: Any] = [
            "userContext": ["userId": "user-1"],
            "parkingBookings": [["bookingId": "booking-1"]],
            "currentGame": ["eventId": "202"],
            "upcomingGame": ["eventId": "203"]
        ]
        try held.update(["_sacramentokings": ["conciergeContext": hostFacts]])
        let store = FnbOrderStore(publish: { patch in
            do {
                try held.update(patch)
            } catch {
                XCTFail("Unexpected invalid context patch: \(error)")
            }
        })
        store.locationsShown(cardId: "locations", sessionId: "session", eventId: 202, stale: false, isLatest: true)
        store.cartShown(cardId: "cart", sessionId: "session", orderId: "42", paid: false, stale: false, isLatest: true)
        store.checkoutDidOpen(orderId: "42", sessionId: "session")
        var expected = hostFacts
        expected["fnbOrders"] = ["eventId": 202, "pastOrders": [["orderId": 42]]]
        let snapshot = held.snapshot(for: "session")
        XCTAssertEqual(snapshot as NSDictionary,
                       ["_sacramentokings": ["conciergeContext": expected]] as NSDictionary)
        let action = try XCTUnwrap(FnbHandoff.viewMenu(locationId: "12"))
        let composed = ConciergeXDMContextStore.merging(action, over: snapshot)
        let namespace = try XCTUnwrap(composed["_sacramentokings"] as? [String: Any])
        XCTAssertEqual(namespace["conciergeContext"] as? NSDictionary, expected as NSDictionary)
        XCTAssertNotNil(namespace["conciergeAction"])
        store.identityDidReset()
        XCTAssertEqual(held.snapshot(for: "session") as NSDictionary,
                       ["_sacramentokings": ["conciergeContext": hostFacts]] as NSDictionary)
    }

    override func tearDown() {
        NativeCardRegistry.resetForTesting()
        super.tearDown()
    }

    @MainActor
    func testLatestTranscriptMenuRemainsActionableWhenAppearanceOrderDiffers() throws {
        FnbCardRegistration.register()
        let session = UUID().uuidString
        let controller = ChatController(configuration: nil,
            chatService: MockChatService(configuration: ConciergeConfiguration()), speechCapturer: nil, speaker: nil)
        let elements = try CardJSONValue.decode([MultimodalElement].self, from: Data("""
        [{"type":"kings.fnblocation","eventId":202},
         {"type":"kings.menu","id":"old"},
         {"type":"kings.menu","id":"new"},
         {"type":"kings.fnbcart","entity_info":{"id":42}}]
        """.utf8))
        let payload = try JSONDecoder().decode(ConversationPayload.self, from: Data("{}".utf8))
        controller.renderElementsForTesting(elements, turnId: UUID(), payload: payload, sessionId: session)
        let store = FnbCardRegistration.orders
        XCTAssertEqual(controller.messages.count, 4)
        guard let older = nativeCard(at: 1, in: controller),
              let newer = nativeCard(at: 2, in: controller) else {
            return XCTFail("Expected menus in transcript order")
        }
        for index in [0, 2, 1, 3] {
            guard let card = nativeCard(at: index, in: controller) else {
                return XCTFail("Expected native card")
            }
            FnbCardRegistration.receive(type: card.element["type"] as? String ?? "",
                                        element: card.element, context: card.context)
        }
        FnbCardRegistration.receive(type: older.element["type"] as? String ?? "",
                                    element: older.element, context: older.context)
        XCTAssertEqual(store.currentOrderId, 42)
        XCTAssertFalse(older.isLatest)
        XCTAssertTrue(newer.isLatest)
        XCTAssertFalse(store.isMenuActionable(cardId: older.cardId, sessionId: session, stale: false,
                                              isLatest: older.isLatest))
        XCTAssertTrue(store.isMenuActionable(cardId: newer.cardId, sessionId: session, stale: false,
                                             isLatest: newer.isLatest),
                      "the newer menu stays actionable even though the older one appeared last")
    }

    func testLocationFilteringAndNoUnsafeArtwork() {
        let payload: [[String: Any]] = [
            ["id": 1, "name": "Cafe", "isActive": true, "isPaused": true,
             "mobileImageUrl": "http://example.com/a.png"],
            ["id": 1, "name": "Duplicate", "isActive": true],
            ["id": 2, "name": "Inactive", "isActive": false]
        ]
        let stands = FnbStand.map(payload)
        XCTAssertEqual(stands.count, 1)
        XCTAssertEqual(stands.first?.title, "Cafe")
        XCTAssertEqual(stands.first?.isOpen, false)
        XCTAssertNil(stands.first?.image)
    }

    func testLocationMapperUsesTapin2FieldsAndKeepsPausedStandsClosed() throws {
        let stands = FnbStand.map([
            [
                "id": 9, "title": "Cafe", "section": "Club", "isActive": true,
                "description": "<p>Late-night food</p>",
                "orderingEnabled": false, "isPaused": true, "waitTime": "10 min",
                "isPickup": true, "isDelivery": true,
                "imageUrlMobile": "https://example.com/mobile.png",
                "imageUrl": "https://example.com/fallback.png"
            ],
            ["id": 10, "title": "Inactive", "isActive": false]
        ])

        XCTAssertEqual(stands.count, 1)
        XCTAssertEqual(stands[0].title, "Cafe")
        XCTAssertEqual(stands[0].description, "Late-night food")
        XCTAssertFalse(stands[0].isOpen)
        XCTAssertEqual(stands[0].detail, "Closed right now")
        XCTAssertEqual(stands[0].image?.absoluteString, "https://example.com/mobile.png")
        XCTAssertNil(stands[0].section)
    }

    func testLocationOptionsApplySectionAndClosedCopy() {
        let options = FnbLocationOptions(ctaLabel: "Choose", pendingCtaLabel: "Loading",
                                         closedLabel: "Unavailable", sectionLabelPrefix: "Area ")
        let stands = FnbStand.map([
            ["id": 1, "title": "Open", "description": "Fresh food", "section": "Club",
             "isActive": true],
            ["id": 2, "title": "Paused", "section": "Balcony", "isPaused": true,
             "isActive": true]
        ], options: options)

        XCTAssertEqual(stands[0].section, "Area Club")
        XCTAssertEqual(stands[0].description, "Fresh food")
        XCTAssertEqual(stands[1].section, nil)
        XCTAssertEqual(stands[1].detail, "Unavailable right now")
    }

    func testWidgetOptionsClampQuantityAndValidateCurrency() {
        let quantity = FnbQuantityRule(minimum: -2, maximum: 1_000, defaultValue: 500, step: 200)
        let options = FnbMenuOptions(currencyCode: "cad", quantity: quantity,
                                     instructions: FnbInstructionsConfig(maxLength: 500),
                                     addToCartLabel: "Add item",
                                     cartBar: FnbCartBarConfig(label: "Order", showCount: false))
        let cartOptions = FnbCartOptions(currencyCode: "1n!", showMoreLabel: " ")

        XCTAssertEqual(quantity.minimum, 1)
        XCTAssertEqual(quantity.maximum, 99)
        XCTAssertEqual(quantity.defaultValue, 99)
        XCTAssertEqual(quantity.step, 99)
        XCTAssertEqual(options.currencyCode, "CAD")
        XCTAssertEqual(options.instructions?.maxLength, 140)
        XCTAssertEqual(options.addToCartLabel, "Add item")
        XCTAssertFalse(options.cartBar.showCount)
        XCTAssertEqual(cartOptions.currencyCode, "USD")
        XCTAssertNil(cartOptions.showMoreLabel)
    }

    func testLocationStableOrderAndCatalogFilter() {
        let stands = FnbStand.map([
            ["id": "late", "orderId": 2],
            ["id": "first", "orderId": 1],
            ["id": "next", "orderId": 1]
        ])
        XCTAssertEqual(stands.map(\.id), ["first", "next", "late"])
        let entries: [[String: Any]] = [
            ["category": ["id": "drinks", "name": "Drinks", "isActive": true, "orderId": 1],
             "product": ["id": 4, "name": "Soda", "eventPrice": 4.5, "price": 5]],
            ["category": ["id": "hidden", "name": "Hidden", "isActive": false],
             "product": ["id": 5, "name": "Unlisted"]],
            ["category": ["id": "drinks", "name": "Drinks"], "product": ["id": 4, "name": "Duplicate"]]
        ]
        let items = FnbItem.map(entries)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.cents, 450)
        XCTAssertNil(items.first?.originalCents)
    }

    func testInvalidEventPriceFallsBackToPriceAndOnlyHigherOriginalPriceIsShown() {
        let items = FnbItem.map([
            ["category": ["id": 1, "name": "Drinks"],
             "product": ["id": "valid", "eventPrice": "invalid", "price": 5, "originalPrice": 6]],
            ["category": ["id": 1, "name": "Drinks"],
             "product": ["id": "lower", "eventPrice": 4, "price": 5, "originalPrice": 3]]
        ])

        XCTAssertEqual(items.map(\.cents), [500, 400])
        XCTAssertEqual(items.first?.originalCents, 600)
        XCTAssertNil(items.last?.originalCents)
    }

    func testMenuVisibilityAndPublicModifierConstraintsMapToNormalizedFields() throws {
        let items = FnbItem.map([
            [
                "isVisible": false, "category": ["id": "cat", "title": "Menu"],
                "product": ["id": 1, "title": "Hidden", "price": 1]
            ],
            [
                "category": ["id": "cat", "title": "Menu"],
                "product": [
                    "id": 2, "title": "Soda", "price": 1,
                    "modifierGroups": [
                        ["id": 1, "title": "Private", "showPublic": false,
                         "modifiers": [["id": 1, "title": "Hidden option"]]],
                        ["id": 2, "title": "Flavor", "minQuantity": 2, "maxQuantity": 3,
                         "maxOnePerSelection": false,
                         "modifiers": [
                            ["id": 1, "title": "Cola", "priceDiff": 0.5],
                            ["id": 2, "title": "Lemon", "isArchived": true],
                            ["id": 3, "title": "Lime", "isActive": false],
                            ["id": 4, "title": "Orange"],
                            ["id": 5, "title": "Grape"]
                         ]]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(items.count, 1)
        let group = try XCTUnwrap(items[0].modifierGroups.first)
        XCTAssertEqual(group["name"] as? String, "Flavor")
        XCTAssertEqual(group["minimumSelections"] as? Int, 2)
        XCTAssertEqual(group["maximumSelections"] as? Int, 3)
        XCTAssertEqual(group["isMultiSelect"] as? Bool, true)
        XCTAssertEqual(group["maxOnePerSelection"] as? Bool, false)
        let options = PayloadRead.rows(group["modifiers"], limit: 50)
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0]["price"] as? Double, 0.5)
    }

    func testAddToCartMatchesKingsActionContract() throws {
        let lines = [
            FnbLine(id: "789012", name: "Nachos", quantity: 2, locationId: "123456",
                    note: "No ice", selectedModifiers: [
                        FnbModifierSelection(groupId: "301", isMultiSelect: false, modifiers: ["4501"],
                                             options: ["4501", "4502"])
                    ]),
            FnbLine(id: "405", name: "Soda", quantity: 1, locationId: "123456",
                    note: nil, selectedModifiers: [])
        ]
        let first = try XCTUnwrap(FnbHandoff.addToCart(lines: lines))
        let data = try JSONSerialization.data(withJSONObject: first, options: [.sortedKeys])
        XCTAssertEqual(String(data: data, encoding: .utf8),
                       #"{"_sacramentokings":{"conciergeAction":{"addToCart":{"products":[{"locationId":123456,"#
                       + #""modifierGroups":[{"isMultiSelect":false,"modifiers":[{"id":4501,"isSelected":true}]}],"#
                       + #""productId":789012,"quantity":2},{"locationId":123456,"#
                       + #""productId":405,"quantity":1}]}}}}"#)
        XCTAssertNil(first["actionId"])
        let root = try XCTUnwrap(first["_sacramentokings"] as? [String: Any])
        let actions = try XCTUnwrap(root["conciergeAction"] as? [String: Any])
        let add = try XCTUnwrap(actions["addToCart"] as? [String: Any])
        XCTAssertNil(add["eventId"])
        XCTAssertNil(add["orderId"], "per-turn actions do not duplicate held order state")
        XCTAssertNil(FnbHandoff.addToCart(lines: [FnbLine(id: "abc", name: "N", quantity: 1, locationId: "1",
                                                          note: nil, selectedModifiers: [])]))
        XCTAssertNil(FnbHandoff.addToCart(lines: [FnbLine(id: "1", name: "N", quantity: 0, locationId: "1",
                                                          note: nil, selectedModifiers: [])]))
        XCTAssertNil(FnbHandoff.addToCart(lines: [FnbLine(id: "1", name: "N", quantity: 1, locationId: "1",
                                                          note: nil, selectedModifiers: [
            FnbModifierSelection(groupId: "3", isMultiSelect: false, modifiers: ["9"], options: ["8"])
        ])]), "selected options must belong to the group")
        XCTAssertEqual(PayloadRead.integerId("99999999999999999999"), nil)
        XCTAssertEqual(PayloadRead.integerId(123), 123)
    }

    func testSafeCheckoutAndIntegerParsing() {
        XCTAssertEqual(PayloadRead.text("a < b <script>\nprivate()</script> yes"), "a < b  yes")
        XCTAssertNil(PayloadRead.int(NSNumber(value: true)))
        XCTAssertNil(PayloadRead.int(1.5))
        XCTAssertNil(PayloadRead.int(Double.infinity))
        XCTAssertEqual(PayloadRead.int(9_007_199_254_740_993 as Int64, maximum: Int.max), 9_007_199_254_740_993)
        XCTAssertNil(FnbHandoff.checkoutURL(base: "https://tapin2.co.evil.test",
                                            venueId: "1", eventId: "2", guid: "3"))
        XCTAssertNil(FnbHandoff.checkoutURL(base: "https://tapin2.co/attacker?inject=1",
                                            venueId: "1", eventId: "2", guid: "3"))
        XCTAssertNil(FnbHandoff.checkoutURL(base: "https://user@tapin2.co",
                                            venueId: "1", eventId: "2", guid: "3"))
        XCTAssertEqual(FnbHandoff.checkoutURL(base: " https://mobile-stg.tapin2.co ",
                                               venueId: "101", eventId: "202", guid: "303")?.absoluteString,
                       "https://mobile-stg.tapin2.co/Review/Index/101?eventId=202&orderId=303")
        XCTAssertNil(FnbHandoff.checkoutURL(base: "https://tapin2.co.evil.example",
                                            venueId: "1", eventId: "2", guid: "3",
                                            allowedHosts: ["tapin2.co"]))
        XCTAssertNotNil(FnbHandoff.checkoutURL(base: "https://checkout.example.org",
                                               venueId: "1", eventId: "2", guid: "3",
                                               allowedHosts: ["example.org"]))
    }

    func testCartSummaryUsesServerAmountsAndSafeFallbackId() throws {
        let order: [String: Any] = [
            "id": NSNull(), "guid": "checkout-9", "subtotalNet": 8.5,
            "totalNet": 9.25, "discountNet": -1,
            "items": [["id": "line-7", "quantity": 2,
                       "product": ["name": "Burger", "price": 4]]]
        ]
        let summary = try XCTUnwrap(FnbOrderSummary.map(order, fallbackId: "12345"))
        XCTAssertEqual(summary.id, "12345")
        XCTAssertEqual(summary.guid, "checkout-9")
        XCTAssertEqual(summary.total, 925)
        XCTAssertEqual(summary.discount, 100)
        XCTAssertEqual(summary.lines.count, 1)
        XCTAssertNil(FnbOrderSummary.map(["id": "null"], fallbackId: NSNull()))
    }

    func testCartLineFallbackAndDisplaySanitizeModifiersNotesAndStand() throws {
        let summary = try XCTUnwrap(FnbOrderSummary.map([
            "id": 1,
            "distinctLocations": [["id": 303, "title": "Market Cafe"]],
            "items": [[
                "id": 9, "locationId": 303, "quantity": 2, "pricePer": 5,
                "product": ["id": 404, "title": "Soda"],
                "modifiers": [["title": "Large"], ["name": "Lemon"]],
                "note": "light <b>ice</b>"
            ]]
        ], fallbackId: nil))
        XCTAssertEqual(summary.subtotal, 1_000)
        XCTAssertEqual(summary.total, 1_000)
        XCTAssertEqual(summary.lines[0].modifiers, "Large, Lemon")
        XCTAssertEqual(summary.lines[0].standName, "Market Cafe")
        XCTAssertEqual(summary.lines[0].note, "light ice")
        XCTAssertEqual(summary.lines[0].pricePer, 500)
    }

    func testCartFallbackTotalsDoNotWrapOnOverflow() throws {
        let summary = try XCTUnwrap(FnbOrderSummary.map([
            "id": 1,
            "items": [[
                "id": 9, "quantity": 99, "pricePer": 10_000_000,
                "product": ["title": "Large order"]
            ]]
        ], fallbackId: nil))
        XCTAssertNil(summary.subtotal)
        XCTAssertNil(summary.total)
    }

    func testTapin2StageCatalogFixtureMapsVendorFieldNamesAndLimits() throws {
        let payload = try fixture("tapin2_stage_raw") as? [[String: Any]]
        let items = FnbItem.map(payload)

        XCTAssertEqual(items.count, 33)
        XCTAssertEqual(Set(items.map(\.category)).count, 8)
        let soda = try XCTUnwrap(items.first { $0.name == "Fountain Soda" })
        XCTAssertEqual(soda.id, "1364015")
        XCTAssertEqual(soda.category, "Beverages")
        XCTAssertEqual(soda.cents, 500)
        XCTAssertEqual(soda.modifierGroups.count, 1)
        XCTAssertEqual(soda.modifierGroups[0]["name"] as? String, "Fountain Soda Flavor")
        XCTAssertEqual(PayloadRead.text(PayloadRead.rows(soda.modifierGroups[0]["modifiers"], limit: 50).first?["name"]),
                       "Coke")

        let churro = try XCTUnwrap(items.first { $0.name == "\"Light The Beam\" Churro" })
        XCTAssertEqual(churro.cents, 800)
        XCTAssertTrue(churro.detail.contains("Churro"))
    }

    func testTapin2StageCartFixturesMapServerTotalsModifiersAndCheckout() throws {
        let order = try fixture("tapin2_stage_cart_add") as? [String: Any]
        let summary = try XCTUnwrap(FnbOrderSummary.map(order, fallbackId: nil))
        XCTAssertEqual(summary.id, "695685")
        XCTAssertEqual(summary.guid, "68f4aac9-1b2b-49ed-ac78-92d7f26feb00")
        XCTAssertEqual(summary.venueName, "Golden 1 Concierge")
        XCTAssertEqual(summary.subtotal, 4_200)
        XCTAssertEqual(summary.tax, 357)
        XCTAssertEqual(summary.total, 4_557)
        XCTAssertEqual(summary.lines.count, 1)
        XCTAssertEqual(summary.lines[0].id, "2035854")
        XCTAssertEqual(summary.lines[0].productId, "1364190")
        XCTAssertEqual(summary.lines[0].title, "Veggie Nachos")
        XCTAssertEqual(summary.lines[0].pricePer, 1_400)
        XCTAssertEqual(summary.lines[0].subtotal, 4_200)
        XCTAssertEqual(summary.lines[0].modifiers, "No modifiers")
        XCTAssertEqual(summary.lines[0].standName, "Market Cafe 122")
        XCTAssertEqual(FnbHandoff.checkoutURL(base: "https://mobile-stg.tapin2.co",
                                              venueId: "1000010528", eventId: "36747",
                                              guid: summary.guid!)?.absoluteString,
                       "https://mobile-stg.tapin2.co/Review/Index/1000010528?eventId=36747&orderId=68f4aac9-1b2b-49ed-ac78-92d7f26feb00")

        let singleOrder = try fixture("tapin2_stage_cart_add_single") as? [String: Any]
        let single = try XCTUnwrap(FnbOrderSummary.map(singleOrder, fallbackId: "null"))
        XCTAssertEqual(single.id, "686123")
        XCTAssertEqual(single.lines[0].id, "2064019")
        XCTAssertEqual(single.lines[0].standName, "Market Cafe 122")
        XCTAssertEqual(single.total, 1_519)
        XCTAssertFalse(single.paid)
    }

    func testRawMapperTraversalAndOutputBudgets() {
        let locations = (0..<501).map { ["id": $0, "title": "Stand \($0)"] as [String: Any] }
        XCTAssertEqual(FnbStand.map(locations).count, 50)

        let products = (0..<2_001).map { index in
            [
                "orderId": index,
                "category": ["id": 1, "title": "Menu"],
                "product": ["id": index + 1, "title": "Item \(index)", "price": 1]
            ] as [String: Any]
        }
        XCTAssertEqual(FnbItem.map(products).count, 500)

        let orderLines = (0..<501).map { index in
            [
                "id": index + 1, "quantity": 1,
                "product": ["title": "Item \(index)", "id": index + 1],
                "pricePer": 1
            ] as [String: Any]
        }
        XCTAssertEqual(FnbOrderSummary.map(["id": 1, "items": orderLines], fallbackId: nil)?.lines.count, 50)
    }

    func testCartAddTranscriptCopyIsBoundedAndContainsNoMachinePayload() {
        let lines = (0..<7).map {
            FnbLine(id: "\($0 + 1)", name: "Item \($0)", quantity: 1, locationId: "303",
                    note: nil, selectedModifiers: [])
        }
        let copy = FnbHandoff.cartAddMessage(lines: lines, locationName: "Market Cafe")
        XCTAssertEqual(copy.components(separatedBy: "\n").first, "Adding to your cart from Market Cafe:")
        XCTAssertTrue(copy.contains("and 2 more items"))
        XCTAssertFalse(copy.contains("cartAdd"))
        XCTAssertFalse(copy.contains("actionId"))
    }

    func testThemeParsingAndEstimateLimits() {
        XCTAssertNotNil(FnbThemeValue.color("#abc"))
        XCTAssertNotNil(FnbThemeValue.color("#abcd"))
        XCTAssertNotNil(FnbThemeValue.color("rgba(12, 20, 30, 0.5)"))
        XCTAssertNotNil(FnbThemeValue.color("transparent"))
        XCTAssertNil(FnbThemeValue.color("rgba(300, 20, 30, 1)"))
        XCTAssertNil(FnbThemeValue.color("rgb(1, 2, NaN)"))
        XCTAssertEqual(FnbThemeValue.dimension(" 132DP ", fallback: 100), 132)
        XCTAssertEqual(FnbThemeValue.dimension("NaNpx", fallback: 100), 100)
        XCTAssertEqual(FnbThemeValue.dimension("-1", fallback: 100), 100)
        XCTAssertEqual(FnbThemeValue.dimension("999999", fallback: 100), 100)
        XCTAssertEqual(PayloadRead.text("a < b <script>hidden").trimmingCharacters(in: .whitespaces), "a < b")
        XCTAssertEqual(PayloadRead.text(String(repeating: "🙂", count: 160)).count, 140)
        XCTAssertNil(PayloadRead.cents("1e999999"))
        XCTAssertEqual(PayloadRead.httpsImage("https://example.com/\(String(repeating: "a", count: 150))")?.scheme,
                       "https")
    }

    func testFnbStyleOverridesApplyWithBoundedDimensions() {
        var theme = ConciergeTheme()
        theme.customVariables = [
            "--fnb-tile-width": "999",
            "--fnb-card-corner-radius": "-1",
            "--simple-card-disabled-opacity": "0.8",
            "--simple-card-detail-font-weight": "900"
        ]

        XCTAssertEqual(FnbStyle.tileWidth(theme), 320)
        XCTAssertEqual(FnbStyle.cardRadius(theme), 16)
        XCTAssertEqual(FnbStyle.dimension("--simple-card-disabled-opacity", theme: theme,
                                           fallback: 0.45, range: 0...1), 0.8)
    }

    /// The live card in `controller`'s row at `index`, resolved the way `NativeCardView` does.
    @MainActor
    private func nativeCard(at index: Int, in controller: ChatController) -> NativeCard? {
        guard controller.messages.indices.contains(index),
              case .nativeCard(let cardId) = controller.messages[index].template else { return nil }
        return controller.nativeCards.card(withId: cardId)
    }

    private func fixture(_ name: String) throws -> Any {
        let bundles = [Bundle(for: FnbModelsTests.self), Bundle.main]
        let roots = bundles.flatMap { [$0.bundleURL, $0.resourceURL].compactMap { $0 } }
        let url = try XCTUnwrap(roots.map { $0.appendingPathComponent("\(name).json") }
            .first { FileManager.default.fileExists(atPath: $0.path) },
                                "Could not find \(name).json in bundles: \(roots.map(\.path))")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @MainActor
    func testMenuLineMergeDecrementAndBoundedEstimate() {
        let runtime = FnbMenuRuntime(state: [:], save: { _ in },
                                     send: { _, _, _, _ in XCTFail("Unexpected send") })
        let plain = FnbLine(id: "404", name: "Nachos", quantity: 1, locationId: "303",
                            note: nil, selectedModifiers: [], unitCents: 450)
        let special = FnbLine(id: "404", name: "Nachos", quantity: 1, locationId: "303",
                              note: "No salt", selectedModifiers: [], unitCents: 450)
        runtime.add(plain)
        runtime.add(special)
        runtime.add(plain)
        XCTAssertEqual(runtime.draft.map(\.quantity), [2, 1])
        XCTAssertEqual(runtime.estimatedTotal, 1350)
        runtime.decrement(productId: "404")
        XCTAssertEqual(runtime.draft.map(\.quantity), [1, 1])
        runtime.decrement(productId: "404")
        XCTAssertEqual(runtime.draft.map(\.note), ["No salt"])
        runtime.decrement(productId: "404")
        XCTAssertTrue(runtime.draft.isEmpty)
    }

    @MainActor
    func testMenuRuntimeUsesConfiguredQuantityBoundsAndStep() {
        let rule = FnbQuantityRule(minimum: 2, maximum: 5, defaultValue: 2, step: 2)
        let runtime = FnbMenuRuntime(state: [:], save: { _ in }, quantityRule: rule,
                                     send: { _, _, _, _ in XCTFail("Unexpected send") })
        let line = FnbLine(id: "404", name: "Nachos", quantity: 2, locationId: "303",
                           note: nil, selectedModifiers: [])

        runtime.add(line)
        runtime.add(line)
        runtime.add(line)
        XCTAssertEqual(runtime.draft.first?.quantity, 4)
        runtime.decrement(productId: "404")
        XCTAssertEqual(runtime.draft.first?.quantity, 2)
        runtime.decrement(productId: "404")
        XCTAssertTrue(runtime.draft.isEmpty)
    }

    @MainActor
    func testInvalidMenuIdsSurfaceAnErrorWithoutSendingOrDiscardingDraft() {
        for ids in [("burger-123", "303", "202"), ("404", "stand-A", "202")] {
            let runtime = FnbMenuRuntime(state: [:], save: { _ in },
                                         send: { _, _, _, _ in XCTFail("Invalid draft must not be sent") })
            runtime.add(FnbLine(id: ids.0, name: "Nachos", quantity: 1, locationId: ids.1,
                                note: nil, selectedModifiers: []))
            runtime.submit(locationId: ids.1, venueId: nil, eventId: ids.2, canSend: true)
            XCTAssertEqual(runtime.status, "draft")
            XCTAssertEqual(runtime.draft.count, 1)
            XCTAssertEqual(runtime.errorMessage, "These items couldn't be added. Ask Concierge for an updated menu.")
        }
    }

    @MainActor
    func testMenuAcceptedClearsDraftWithoutPublishingLegacyAppOrder() throws {
        var snapshots: [[String: Any]] = []
        var sends: [(String, [String: Any], String)] = []
        var complete: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbMenuRuntime(state: [:], save: { snapshots.append($0) },
                                     send: { hint, fields, copy, callback in
                                         sends.append((hint, fields, copy))
                                         complete = callback
                                     }, makeId: { "action-1" })
        let line = FnbLine(id: "404", name: "Nachos", quantity: 2, locationId: "303",
                           note: nil, selectedModifiers: [])
        runtime.add(line)
        XCTAssertEqual(runtime.draft.first?.quantity, 2)
        runtime.submit(locationId: "303", venueId: "101", eventId: "event-B", canSend: true)
        XCTAssertEqual(sends.count, 1)
        XCTAssertEqual(sends.first?.0, "add-to-cart")
        XCTAssertNil(sends.first?.1["actionId"])
        let namespace = try XCTUnwrap(sends.first?.1["_sacramentokings"] as? [String: Any])
        let action = try XCTUnwrap(namespace["conciergeAction"] as? [String: Any])
        XCTAssertNotNil(action["addToCart"])
        XCTAssertEqual(snapshots.last?["status"] as? String, "submitting")
        XCTAssertTrue(sends.first?.2.contains("Nachos") == true)
        runtime.submit(locationId: "303", venueId: nil, eventId: nil, canSend: true)
        XCTAssertEqual(sends.count, 1)
        complete?(.success(()))
        XCTAssertTrue(runtime.draft.isEmpty)
        XCTAssertEqual(runtime.status, "added")
        runtime.add(line)
        XCTAssertEqual(runtime.status, "added")
        XCTAssertTrue(runtime.draft.isEmpty, "A submitted menu stays permanently read-only")
    }

    @MainActor
    func testMenuUnknownOutcomeDoesNotReplayAndRestoredSubmissionStaysLocked() {
        var snapshots: [[String: Any]] = []
        var sends = 0
        var complete: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbMenuRuntime(state: [:], save: { snapshots.append($0) },
                                     send: { _, _, _, callback in sends += 1; complete = callback },
                                     makeId: { "action-1" })
        let line = FnbLine(id: "404", name: "Nachos", quantity: 1, locationId: "303",
                           note: nil, selectedModifiers: [])
        runtime.add(line)
        runtime.submit(locationId: "303", venueId: nil, eventId: nil, canSend: true)
        let restored = FnbMenuRuntime(state: snapshots.last ?? [:], save: { _ in },
                                      send: { _, _, _, _ in XCTFail("Restoration sent an action") })
        XCTAssertEqual(restored.status, "submitting")
        restored.submit(locationId: "303", venueId: nil, eventId: nil, canSend: true)
        complete?(.failure(.noResponse))
        XCTAssertEqual(runtime.status, "unconfirmed")
        XCTAssertTrue(runtime.draft.isEmpty)
        runtime.submit(locationId: "303", venueId: nil, eventId: nil, canSend: true)
        XCTAssertEqual(sends, 1)
    }

    @MainActor
    func testCardActionsNeverStartedRetryAndUnknownCannotRepeat() {
        var snapshots: [[String: Any]] = []
        var actionIds: [String] = []
        var complete: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbActionRuntime(state: [:], save: { snapshots.append($0) },
                                       send: { _, _, _, callback in
                                           actionIds.append(snapshots.last?["activeAction"] as? String ?? "")
                                           complete = callback
                                       }, makeId: { "stable-id" })
        let fields: (String) -> [String: Any] = { _ in
            FnbHandoff.removeFromCart(locationId: "2", productId: "1", modifiers: nil) ?? [:]
        }
        runtime.perform(key: "remove:l1", hint: "remove-from-cart", fields: fields,
                        copy: "Remove", canSend: true)
        XCTAssertNotNil(snapshots.last?["activeAction"])
        XCTAssertEqual(runtime.activeActionKey, "remove:l1")
        complete?(.failure(.chatInProgress))
        XCTAssertNil(runtime.activeAction)
        XCTAssertNil(runtime.activeActionKey)
        XCTAssertEqual(runtime.errorMessage, "Wait for the current response before trying again.")
        runtime.perform(key: "remove:l1", hint: "remove-from-cart", fields: fields,
                        copy: "Remove", canSend: true)
        XCTAssertEqual(actionIds, ["stable-id", "stable-id"])
        complete?(.failure(.noResponse))
        runtime.perform(key: "remove:l1", hint: "remove-from-cart", fields: fields,
                        copy: "Remove", canSend: true)
        XCTAssertEqual(actionIds.count, 2)
        XCTAssertTrue(runtime.unconfirmed.contains("remove:l1"))
        runtime.nativeCardDidDispose()
        XCTAssertTrue(runtime.disposed)
    }

    @MainActor
    func testLookupHandoffsCarryNoActionIdAndKeepLocalGuards() {
        var sent: [(String, [String: Any], String?)] = []
        var complete: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbActionRuntime(state: [:], save: { _ in }, send: { hint, fields, copy, callback in
            sent.append((hint, fields, copy))
            complete = callback
        }, makeId: { "local-id" })
        runtime.perform(key: "location:303", hint: FnbHandoff.viewMenuHint,
                        fields: { _ in FnbHandoff.viewMenu(locationId: "303") },
                        copy: FnbHandoff.viewMenuCopy("Market [Cafe]"), canSend: true)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].0, "view-menu")
        XCTAssertEqual(sent[0].1 as NSDictionary,
                       ["_sacramentokings": ["conciergeAction": ["viewMenu": ["locationId": "303"]]]] as NSDictionary)
        XCTAssertEqual(sent[0].2, "Opening the menu at Market Cafe.")
        XCTAssertEqual(runtime.activeAction, "local-id")
        runtime.perform(key: "location:303", hint: FnbHandoff.viewMenuHint,
                        fields: { _ in FnbHandoff.viewMenu(locationId: "303") },
                        copy: "dup", canSend: true)
        XCTAssertEqual(sent.count, 1)
        complete?(.failure(.noResponse))
        runtime.perform(key: "location:303", hint: FnbHandoff.viewMenuHint,
                        fields: { _ in FnbHandoff.viewMenu(locationId: "303") },
                        copy: "again", canSend: true)
        XCTAssertEqual(sent.count, 1, "unconfirmed lookups stay blocked")

        runtime.perform(key: "showMore", hint: FnbHandoff.showMoreText,
                        fields: { ["actionId": $0, "orderId": "o1"] }, copy: FnbHandoff.showMoreText,
                        canSend: true)
        XCTAssertEqual(sent.count, 1, "lookups reject payloads that leak an action ID")
        runtime.perform(key: "showMore", hint: FnbHandoff.showMoreText,
                        fields: { _ in FnbHandoff.viewMenu(locationId: "303") }, copy: FnbHandoff.showMoreText,
                        canSend: true)
        XCTAssertEqual(sent.last?.0, "Show more restaurants")
        XCTAssertEqual(sent.last?.2, "Show more restaurants")
        XCTAssertNil(sent.last?.1["actionId"])
        XCTAssertFalse(FnbHandoff.viewMenu(locationId: "stand A").isEmpty)
        XCTAssertTrue(FnbHandoff.viewMenu(locationId: " ").isEmpty)
    }

    func testKingsActionPayloadsUseFinalizedNamespaceAndOnlySelectedModifiers() throws {
        let line = FnbLine(
            id: "404", name: "Nachos", quantity: 2, locationId: "303", note: "local note",
            selectedModifiers: [
                FnbModifierSelection(groupId: "required-sauces", isMultiSelect: false,
                                     modifiers: ["10"], options: ["10", "11"]),
                FnbModifierSelection(groupId: "toppings", isMultiSelect: true,
                                     modifiers: ["20", "21"], options: ["20", "21", "22"])
            ])
        let fields = try XCTUnwrap(FnbHandoff.addToCart(lines: [line]))
        let root = try XCTUnwrap(fields["_sacramentokings"] as? [String: Any])
        let actions = try XCTUnwrap(root["conciergeAction"] as? [String: Any])
        let add = try XCTUnwrap(actions["addToCart"] as? [String: Any])
        let products = try XCTUnwrap(add["products"] as? [[String: Any]])
        XCTAssertEqual(products as NSArray, [[
            "locationId": Int64(303),
            "productId": Int64(404),
            "quantity": 2,
            "modifierGroups": [
                ["isMultiSelect": false, "modifiers": [["id": Int64(10), "isSelected": true]]],
                ["isMultiSelect": true, "modifiers": [
                    ["id": Int64(20), "isSelected": true], ["id": Int64(21), "isSelected": true]
                ]]
            ]
        ]] as NSArray)
        XCTAssertNil(add["eventId"])
        XCTAssertNil(add["orderId"])
        XCTAssertNil(fields["actionId"])
        XCTAssertNil(fields["_app"])

        let menuItem = try XCTUnwrap(FnbItem.map([[
            "category": ["id": "snacks", "name": "Snacks"],
            "product": ["id": "404", "name": "Nachos", "price": 5, "modifierGroups": [
                ["id": "required-sauces", "isMultiSelect": true,
                 "modifiers": [["id": "10", "title": "Salsa"]]]
            ]]
        ]]).first)
        let currentMenuFields = try XCTUnwrap(FnbHandoff.addToCart(lines: [line], menuItems: ["404": menuItem]))
        let currentRoot = try XCTUnwrap(currentMenuFields["_sacramentokings"] as? [String: Any])
        let currentActions = try XCTUnwrap(currentRoot["conciergeAction"] as? [String: Any])
        let currentAdd = try XCTUnwrap(currentActions["addToCart"] as? [String: Any])
        let currentProduct = try XCTUnwrap((currentAdd["products"] as? [[String: Any]])?.first)
        let currentGroup = try XCTUnwrap((currentProduct["modifierGroups"] as? [[String: Any]])?.first)
        XCTAssertEqual(currentGroup["isMultiSelect"] as? Bool, true)

        let remove = try XCTUnwrap(FnbHandoff.removeFromCart(locationId: "303", productId: "404",
                                                              modifiers: "Cheese, Jalapeno"))
        XCTAssertEqual(remove as NSDictionary, [
            "_sacramentokings": ["conciergeAction": ["removeFromCart": ["products": [[
                "locationId": Int64(303), "productId": Int64(404), "modifier": "Cheese, Jalapeno"
            ]]]]]
        ] as NSDictionary)
        XCTAssertNil(FnbHandoff.removeFromCart(locationId: "303", productId: "line-9", modifiers: nil))
        let noModifier = try XCTUnwrap(FnbHandoff.removeFromCart(locationId: "303", productId: "404", modifiers: "No modifiers"))
        XCTAssertEqual(noModifier as NSDictionary, [
            "_sacramentokings": ["conciergeAction": ["removeFromCart": ["products": [[
                "locationId": Int64(303), "productId": Int64(404)
            ]]]]]
        ] as NSDictionary)
        XCTAssertNil(FnbHandoff.addToCart(lines: [
            FnbLine(id: "-1", name: "Bad ID", quantity: 1, locationId: "303",
                    note: nil, selectedModifiers: [])
        ]))
        XCTAssertEqual(FnbHandoff.viewMenu(locationId: "303") as NSDictionary,
                       ["_sacramentokings": ["conciergeAction": ["viewMenu": ["locationId": "303"]]]] as NSDictionary)
    }

    @MainActor
    func testFirstDisplayedCardsCheckoutReopenAndFutureOrders() throws {
        var patches: [[String: Any]] = []
        let store = FnbOrderStore(publish: { patches.append($0) })
        store.locationsShown(cardId: "first-location", sessionId: "s", eventId: 202, stale: false, isLatest: true)
        store.locationsShown(cardId: "second-location", sessionId: "s", eventId: 101, stale: false, isLatest: true)
        store.locationsShown(cardId: "first-location", sessionId: "s", eventId: 303, stale: false, isLatest: false)
        XCTAssertEqual(patches.count, 2, "Each first-displayed location occurrence publishes once")
        store.menuShown(cardId: "first-menu", sessionId: "s", stale: false)
        store.menuShown(cardId: "second-menu", sessionId: "s", stale: false)
        store.menuShown(cardId: "first-menu", sessionId: "s", stale: false)
        XCTAssertFalse(store.isMenuActionable(cardId: "first-menu", sessionId: "s", stale: false, isLatest: false))
        XCTAssertTrue(store.isMenuActionable(cardId: "second-menu", sessionId: "s", stale: false, isLatest: true),
                      "Reappearing an older menu doesn't make it newest")
        store.cartShown(cardId: "cart", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        store.checkoutDidOpen(orderId: "42", sessionId: "s")
        let archivedPatchCount = patches.count
        XCTAssertTrue(store.canOpenCheckout(cardId: "cart", sessionId: "s", orderId: "42", stale: false, isLatest: true, unresolved: true))
        store.checkoutDidOpen(orderId: "42", sessionId: "s")
        XCTAssertEqual(patches.count, archivedPatchCount)
        XCTAssertNil(store.currentOrderId)
        store.menuShown(cardId: "post-checkout-menu", sessionId: "s", stale: false)
        XCTAssertTrue(store.isMenuActionable(cardId: "post-checkout-menu", sessionId: "s", stale: false, isLatest: true))
        store.cartShown(cardId: "archived-copy", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertNil(store.currentOrderId, "Archived snapshots must never become current again")
        XCTAssertFalse(store.isCartActionable(cardId: "archived-copy", sessionId: "s", orderId: "42", stale: false, isLatest: true))
        store.menuShown(cardId: "future-menu", sessionId: "s", stale: false)
        XCTAssertTrue(store.isMenuActionable(cardId: "future-menu", sessionId: "s", stale: false, isLatest: true))
        XCTAssertFalse(store.isMenuActionable(cardId: "second-menu", sessionId: "s", stale: false, isLatest: false))
        store.cartShown(cardId: "future-cart", sessionId: "s", orderId: "43", paid: false, stale: false, isLatest: true)
        store.checkoutDidOpen(orderId: "43", sessionId: "s")
        let context = try XCTUnwrap((patches.last?["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        let archived = try XCTUnwrap(context["fnbOrders"] as? [String: Any])
        XCTAssertEqual(archived["pastOrders"] as? [NSDictionary],
                       [["orderId": Int64(42)] as NSDictionary, ["orderId": Int64(43)] as NSDictionary])
    }

    @MainActor
    func testOnlyLatestCurrentCartCanMutateAndRemovalReservationsSettleWithSnapshots() throws {
        let store = FnbOrderStore(publish: { _ in })
        store.cartShown(cardId: "old", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        store.cartShown(cardId: "latest", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        store.cartShown(cardId: "late", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertFalse(store.isCartActionable(cardId: "old", sessionId: "s", orderId: "42", stale: false, isLatest: false))
        XCTAssertFalse(store.isCartActionable(cardId: "latest", sessionId: "s", orderId: "42", stale: false, isLatest: false))
        XCTAssertTrue(store.isCartActionable(cardId: "late", sessionId: "s", orderId: "42", stale: false, isLatest: true))
        XCTAssertFalse(store.isCartActionable(cardId: "late", sessionId: "s", orderId: "99", stale: false, isLatest: true))
        let token = try XCTUnwrap(store.beginRemoval(key: "same-wire-product", cardId: "late",
                                                    sessionId: "s", orderId: "42", stale: false, isLatest: true))
        XCTAssertNil(store.beginRemoval(key: "same-wire-product", cardId: "late",
                                        sessionId: "s", orderId: "42", stale: false, isLatest: true))
        store.finishRemoval(key: "same-wire-product", token: token, neverStarted: true)
        XCTAssertFalse(store.removals.contains("same-wire-product"), "Never-started rejection permits retry")
        let accepted = try XCTUnwrap(store.beginRemoval(key: "same-wire-product", cardId: "late",
                                                       sessionId: "s", orderId: "42", stale: false, isLatest: true))
        store.finishRemoval(key: "same-wire-product", token: accepted, neverStarted: false)
        XCTAssertTrue(store.removals.contains("same-wire-product"))
        store.cartShown(cardId: "updated", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertTrue(store.removals.isEmpty)
        let next = try XCTUnwrap(store.beginRemoval(key: "same-wire-product", cardId: "updated",
                                                   sessionId: "s", orderId: "42", stale: false, isLatest: true))
        store.finishRemoval(key: "same-wire-product", token: accepted, neverStarted: true)
        XCTAssertTrue(store.removals.contains("same-wire-product"), "A prior snapshot callback cannot unlock the new action")
        store.finishRemoval(key: "same-wire-product", token: next, neverStarted: true)
        store.cartShown(cardId: "different-order", sessionId: "s", orderId: "99", paid: false, stale: false, isLatest: true)
        XCTAssertEqual(store.currentOrderId, 42)
        XCTAssertFalse(store.isCartActionable(cardId: "different-order", sessionId: "s", orderId: "99", stale: false, isLatest: true))
        XCTAssertFalse(store.isCartActionable(cardId: "updated", sessionId: "s", orderId: "42", stale: false, isLatest: false))
    }

    @MainActor
    func testIdentityResetInvalidatesMirrorsAndLateCheckoutCallbacks() {
        let store = FnbOrderStore(publish: { _ in })
        store.cartShown(cardId: "before", sessionId: "old", orderId: "42", paid: false, stale: false, isLatest: true)
        let revision = store.identityRevision
        store.identityDidReset()
        store.checkoutDidOpen(orderId: "42", sessionId: "old", identityRevision: revision)
        store.cartShown(cardId: "late", sessionId: "old", orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertNil(store.currentOrderId)
        XCTAssertFalse(store.isOrderArchived("42"))
        store.cartShown(cardId: "after", sessionId: "new", orderId: "42", paid: false, stale: false, isLatest: true)
        store.checkoutDidOpen(orderId: "42", sessionId: "new", identityRevision: revision)
        XCTAssertEqual(store.currentOrderId, 42, "Even matching IDs must not admit an old-identity checkout callback")
        XCTAssertFalse(store.isOrderArchived("42"))
    }

    @MainActor
    func testProductionRegistrationObservesIdentityReset() async {
        let ready = expectation(description: "MobileCore event hub started")
        MobileCore.registerExtensions([]) { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        FnbCardRegistration.register()
        let store = FnbCardRegistration.orders
        let parking = ParkWhizBookingStore.shared
        parking.receive(["source": "ParkWhiz", "action": "purchase",
                         "value": ["status": "success", "bookingId": "reset-regression"]],
                        origin: URL(string: "https://parkwhiz.com")!, identityRevision: parking.identityRevision)
        XCTAssertFalse(parking.bookingIds.isEmpty)
        store.cartShown(cardId: UUID().uuidString, sessionId: UUID().uuidString,
                        orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertEqual(store.currentOrderId, 42)
        let revision = store.identityRevision
        MobileCore.dispatch(event: Event(name: "Fnb reset regression", type: EventType.genericIdentity,
                                         source: EventSource.requestReset, data: nil))
        for _ in 0..<100 where store.identityRevision == revision {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(store.identityRevision, revision)
        XCTAssertNil(store.currentOrderId)
        XCTAssertTrue(store.claimedCartCardIds.isEmpty)
        XCTAssertTrue(parking.bookingIds.isEmpty)
    }

    func testUnfulfillableRequiredModifierGroupsRejectProductRatherThanRelaxingMinimum() {
        let groups: [[String: Any]] = [
            ["id": "required", "minQuantity": 1, "modifiers": [["id": "1", "title": "Sold out", "isActive": false]]],
            ["id": "required", "minQuantity": 2, "modifiers": [["id": "1", "title": "Only one"]]],
            ["id": "required", "minQuantity": 2, "maximumSelections": 1,
             "modifiers": [["id": "1", "title": "One"], ["id": "2", "title": "Two"]]],
            ["id": "required", "minQuantity": 51, "modifiers": [["id": "1", "title": "One"]]]
        ]
        for group in groups {
            XCTAssertTrue(FnbItem.map([["category": ["id": "c", "title": "Menu"],
                "product": ["id": "1", "title": "Required choice", "price": 5, "modifierGroups": [group]]]]).isEmpty)
        }
        let optional = ["id": "optional", "minQuantity": 0, "modifiers": []] as [String: Any]
        XCTAssertEqual(FnbItem.map([["category": ["id": "c", "title": "Menu"],
            "product": ["id": "1", "title": "Optional choice", "price": 5, "modifierGroups": [optional]]]]).count, 1)
    }

    @MainActor
    func testFnbOrderStoreDeduplicatesDisplaysAndArchivesCheckout() throws {
        var patches: [[String: Any]] = []
        let store = FnbOrderStore(publish: { patches.append($0) })

        store.locationsShown(cardId: "locations-1", sessionId: "session-1", eventId: "202", stale: false, isLatest: true)
        store.locationsShown(cardId: "locations-1", sessionId: "session-1", eventId: "303", stale: false, isLatest: true)
        XCTAssertEqual(patches.count, 1)
        let initialContext = try XCTUnwrap((patches[0]["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        let fnbOrders = try XCTUnwrap(initialContext["fnbOrders"] as? [String: Any])
        XCTAssertEqual(fnbOrders["eventId"] as? Int64, 202)

        store.menuShown(cardId: "menu-1", sessionId: "session-1", stale: false)
        XCTAssertTrue(store.isMenuActionable(cardId: "menu-1", sessionId: "session-1", stale: false, isLatest: true))
        store.markMenuSubmitted(cardId: "menu-1", sessionId: "session-1")
        XCTAssertFalse(store.isMenuActionable(cardId: "menu-1", sessionId: "session-1", stale: false, isLatest: true))
        store.menuShown(cardId: "menu-2", sessionId: "session-1", stale: false)
        XCTAssertFalse(store.isMenuActionable(cardId: "menu-1", sessionId: "session-1", stale: false, isLatest: false))
        XCTAssertTrue(store.isMenuActionable(cardId: "menu-2", sessionId: "session-1", stale: false, isLatest: true))

        store.cartShown(cardId: "cart-1", sessionId: "session-1", orderId: "42", paid: false, stale: false, isLatest: true)
        store.cartShown(cardId: "cart-1", sessionId: "session-1", orderId: "43", paid: false, stale: false, isLatest: true)
        XCTAssertEqual(store.currentOrderId, 42)
        store.checkoutDidOpen(orderId: "42", sessionId: "session-1")
        XCTAssertNil(store.currentOrderId)
        XCTAssertTrue(store.isOrderArchived("42"))
        XCTAssertFalse(store.isMenuActionable(cardId: "menu-2", sessionId: "session-1", stale: false, isLatest: true))
        let archivedContext = try XCTUnwrap((patches.last?["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        let archive = try XCTUnwrap(archivedContext["fnbOrders"] as? [String: Any])
        XCTAssertTrue(archive["currentOrder"] is NSNull)
        XCTAssertEqual(archive["pastOrders"] as? [NSDictionary], [["orderId": Int64(42)] as NSDictionary])
        let patchCount = patches.count
        store.checkoutDidOpen(orderId: "42", sessionId: "session-1")
        XCTAssertEqual(patches.count, patchCount, "Reopening an archived checkout must not archive twice")

        store.menuShown(cardId: "menu-new-session", sessionId: "session-2", stale: false)
        XCTAssertFalse(store.isOrderArchived("42"))
        XCTAssertTrue(store.isMenuActionable(cardId: "menu-new-session", sessionId: "session-2", stale: false, isLatest: true))
        let cleared = try XCTUnwrap((patches.last?["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        XCTAssertTrue(cleared["fnbOrders"] is NSNull)

        store.identityDidReset()
        XCTAssertTrue(store.closedMenuCardIds.isEmpty)
        XCTAssertFalse(store.isMenuActionable(cardId: "menu-new-session", sessionId: "session-2", stale: false, isLatest: true))
        let reset = try XCTUnwrap((patches.last?["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        XCTAssertTrue(reset["fnbOrders"] is NSNull)
    }

    @MainActor
    func testNewerCardsDisplayedFirstKeepOwnershipWhenOlderCardsAppearLater() throws {
        var patches: [[String: Any]] = []
        let store = FnbOrderStore(publish: { patches.append($0) })
        // SwiftUI can show the newer row first; isLatest, not display order, decides which card leads.
        store.locationsShown(cardId: "new-locations", sessionId: "s", eventId: 202, stale: false, isLatest: true)
        store.locationsShown(cardId: "old-locations", sessionId: "s", eventId: 101, stale: false, isLatest: false)
        XCTAssertEqual(patches.count, 1, "an older locations card must not overwrite the event")
        let context = try XCTUnwrap((patches.last?["_sacramentokings"] as? [String: Any])?["conciergeContext"] as? [String: Any])
        XCTAssertEqual((context["fnbOrders"] as? [String: Any])?["eventId"] as? Int64, 202)

        store.menuShown(cardId: "new-menu", sessionId: "s", stale: false)
        store.menuShown(cardId: "old-menu", sessionId: "s", stale: false)
        XCTAssertTrue(store.isMenuActionable(cardId: "new-menu", sessionId: "s", stale: false, isLatest: true))
        XCTAssertFalse(store.isMenuActionable(cardId: "old-menu", sessionId: "s", stale: false, isLatest: false))

        store.cartShown(cardId: "new-cart", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        let token = try XCTUnwrap(store.beginRemoval(key: "line", cardId: "new-cart", sessionId: "s",
                                                    orderId: "42", stale: false, isLatest: true))
        store.finishRemoval(key: "line", token: token, neverStarted: false)
        store.cartShown(cardId: "old-cart", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: false)
        XCTAssertTrue(store.removals.contains("line"), "an older cart must not settle the newer cart's removals")
        XCTAssertTrue(store.isCartActionable(cardId: "new-cart", sessionId: "s", orderId: "42", stale: false, isLatest: true))
        XCTAssertFalse(store.isCartActionable(cardId: "old-cart", sessionId: "s", orderId: "42", stale: false, isLatest: false))
    }

    @MainActor
    func testPromotedCartClaimsOrderAfterRollbackAndCheckoutClosesOnlyDisplayedMenus() {
        let store = FnbOrderStore(publish: { _ in })
        store.cartShown(cardId: "older-cart", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: false)
        XCTAssertNil(store.currentOrderId)
        // The newer cart was rolled back, so the SDK promotes the older one and the hook runs again.
        store.cartShown(cardId: "older-cart", sessionId: "s", orderId: "42", paid: false, stale: false, isLatest: true)
        XCTAssertEqual(store.currentOrderId, 42)
        XCTAssertTrue(store.isCartActionable(cardId: "older-cart", sessionId: "s", orderId: "42", stale: false, isLatest: true))

        store.cartShown(cardId: "paid-cart", sessionId: "s", orderId: "42", paid: true, stale: false, isLatest: true)
        XCTAssertFalse(store.isCartActionable(cardId: "paid-cart", sessionId: "s", orderId: "42", stale: false, isLatest: true),
                       "being newest doesn't make a paid snapshot actionable")

        store.menuShown(cardId: "menu", sessionId: "s", stale: false)
        store.checkoutDidOpen(orderId: "42", sessionId: "s")
        XCTAssertFalse(store.isMenuActionable(cardId: "menu", sessionId: "s", stale: false, isLatest: true),
                       "checkout closes every menu displayed before it, even the newest")
        store.menuShown(cardId: "later-menu", sessionId: "s", stale: false)
        XCTAssertTrue(store.isMenuActionable(cardId: "later-menu", sessionId: "s", stale: false, isLatest: true))
    }

    func testParkingEventsMapAndValidateEventId() {
        let events = ParkingEventsMapper.map(["events": [
            ["event_id": 123456, "name": "Kings vs Lakers", "start_time": "2026-12-13T18:00:00.000-08:00"],
            ["event_id": 123456, "name": "Duplicate"],
            ["event_id": 7, "name": "  "],
            ["name": "No id"],
            ["event_id": "789", "name": "Kings [vs] Suns", "start_time": "nope"]
        ]])
        XCTAssertEqual(events.map(\.id), ["123456", "789"])
        XCTAssertEqual(events[0].detail, "Sun, Dec 13 \u{00B7} 6:00 PM")
        XCTAssertEqual(events[1].detail, "")
        XCTAssertEqual(ParkingEventsMapper.map(["event_id": 1, "name": "Single"]).count, 1)
        XCTAssertEqual(ParkingEventsMapper.map([["event_id": 1, "name": "A"]]).count, 1)
        XCTAssertTrue(ParkingEventsMapper.map(["foo": 1]).isEmpty)
        XCTAssertEqual(ParkingEventsMapper.map((0..<30).map { ["event_id": $0 + 1, "name": "G\($0)"] }).count, 20)
        XCTAssertEqual(ParkingEventsMapper.selectEventMessage("Kings [vs] Suns"), "Finding parking for Kings vs Suns.")
        XCTAssertEqual(ParkingEventsMapper.selectEventMessage("[]"), "Finding parking for this game.")

        let fields = ParkingEventsMapper.searchParking(eventId: "123456")
        let namespace = fields?["_sacramentokings"] as? [String: Any]
        let actions = namespace?["conciergeAction"] as? [String: Any]
        let searchParking = actions?["searchParking"] as? [String: Any]
        XCTAssertEqual(searchParking?["eventId"] as? String, "123456")
        let data = try? JSONSerialization.data(withJSONObject: fields ?? [:])
        XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) },
                       #"{"_sacramentokings":{"conciergeAction":{"searchParking":{"eventId":"123456"}}}}"#)
        XCTAssertEqual(ParkingEventsMapper.searchParking(eventId: "event-abc")?["_sacramentokings"] as? NSDictionary,
                       ["conciergeAction": ["searchParking": ["eventId": "event-abc"]]] as NSDictionary)
        for bad in [" ", "", String(repeating: "1", count: 65)] {
            XCTAssertNil(ParkingEventsMapper.searchParking(eventId: bad), bad)
        }
    }

    func testParkingEventTimeFormatting() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(ParkingEventTime.format("2026-12-13T18:00:00Z"), "Sun, Dec 13 \u{00B7} 6:00 PM")
        XCTAssertEqual(ParkingEventTime.format("2026-12-13 09:05-0500"), "Sun, Dec 13 \u{00B7} 9:05 AM")
        XCTAssertEqual(ParkingEventTime.format("2026-12-13T00:30", deviceZone: pacific), "Sun, Dec 13 \u{00B7} 12:30 AM")
        for bad: Any? in [nil, 5, "", "2026-02-30T10:00:00Z", "2026-13-01T10:00Z", "2026-12-13T24:00Z", "tomorrow"] {
            XCTAssertNil(ParkingEventTime.format(bad))
        }
    }

    func testSharedIntegralAndBooleanCoercionsMatchAndroidWithoutLosingInt64Precision() {
        XCTAssertEqual(PayloadRead.integerId(Int64.max), Int64.max)
        XCTAssertEqual(PayloadRead.integerId(NSDecimalNumber(string: "9223372036854775807")), Int64.max)
        XCTAssertEqual(PayloadRead.integerId(9_007_199_254_740_992.0), 9_007_199_254_740_992)
        XCTAssertEqual(PayloadRead.integerId(" 123 "), 123)
        XCTAssertEqual(PayloadRead.int("20"), 20)
        for invalid: Any in [true, 0.1, Double.infinity, "1.5", "9223372036854775808",
                             NSDecimalNumber(string: "1.5"), 9_007_199_254_740_994.0] {
            XCTAssertNil(PayloadRead.integerId(invalid))
        }
        XCTAssertEqual(PayloadRead.bool(" TRUE "), true)
        XCTAssertEqual(PayloadRead.bool("false"), false)
        XCTAssertNil(PayloadRead.bool(1))
        XCTAssertNil(PayloadRead.id(1.5))
        XCTAssertEqual(PayloadRead.cents("1.005"), 101)
        XCTAssertEqual(PayloadRead.cents("1e2"), 10_000)
        XCTAssertNil(PayloadRead.cents("12USD"))
        XCTAssertNil(PayloadRead.cents("1e999999"))
    }

    func testEmptyModifierSelectionsAreOmittedAndAnyInvalidIdRejectsWholeAdd() throws {
        let line = FnbLine(id: "1", name: "Plain", quantity: 1, locationId: "2", note: nil,
                           selectedModifiers: [FnbModifierSelection(groupId: "optional", isMultiSelect: true,
                                                                    modifiers: [], options: [])])
        let expected = ["_sacramentokings": ["conciergeAction": ["addToCart": [
            "products": [["locationId": 2, "productId": 1, "quantity": 1]]
        ]]]] as NSDictionary
        XCTAssertEqual(try XCTUnwrap(FnbHandoff.addToCart(lines: [line])) as NSDictionary, expected)
        for invalid in ["+1", "-1", "1.5", "1e2", "9223372036854775808"] {
            let bad = FnbLine(id: invalid, name: "Bad", quantity: 1, locationId: "2", note: nil,
                              selectedModifiers: [])
            XCTAssertNil(FnbHandoff.addToCart(lines: [line, bad]))
        }
    }

    @MainActor
    func testThrownSenderAndLateCallbacksCannotReplayOrUnlockMenu() {
        enum Failure: Error { case deliveryUnknown }
        var sends = 0
        var late: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbMenuRuntime(state: [:], save: { _ in }, send: { _, _, _, completion in
            sends += 1
            late = completion
            throw Failure.deliveryUnknown
        })
        let line = FnbLine(id: "1", name: "Item", quantity: 1, locationId: "2", note: nil, selectedModifiers: [])
        runtime.add(line)
        runtime.submit(locationId: "2", venueId: nil, eventId: nil, canSend: true)
        XCTAssertEqual(runtime.status, "unconfirmed")
        runtime.add(line)
        late?(.failure(.chatInProgress))
        runtime.submit(locationId: "2", venueId: nil, eventId: nil, canSend: true)
        XCTAssertTrue(runtime.draft.isEmpty)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(runtime.status, "unconfirmed")
    }

    @MainActor
    func testActionCompletionSideEffectsRunOnlyOnceAndThrowsStayUnconfirmed() {
        enum Failure: Error { case deliveryUnknown }
        var callbacks = 0
        var late: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let runtime = FnbActionRuntime(state: [:], save: { _ in }, send: { _, _, _, completion in
            late = completion
        })
        runtime.perform(key: "remove:1", hint: "remove-from-cart",
                        fields: { _ in FnbHandoff.removeFromCart(locationId: "2", productId: "1", modifiers: nil)! },
                        copy: "Removing item.", canSend: true) { _ in callbacks += 1 }
        late?(.success(()))
        late?(.failure(.chatInProgress))
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(runtime.pendingRemovals.contains("remove:1"))
        let throwing = FnbActionRuntime(state: [:], save: { _ in }, send: { _, _, _, _ in
            throw Failure.deliveryUnknown
        })
        throwing.perform(key: "location:2", hint: "view-menu",
                         fields: { _ in FnbHandoff.viewMenu(locationId: "2") },
                         copy: "Opening menu.", canSend: true)
        XCTAssertTrue(throwing.unconfirmed.contains("location:2"))
    }

    @MainActor
    func testMenuDraftLimitsAndUnrelatedBusyTurnDoNotBlockLocalEdits() {
        let runtime = FnbMenuRuntime(state: [:], save: { _ in },
                                     send: { _, _, _, _ in XCTFail("Busy turn must not send") })
        for index in 1...21 {
            runtime.add(FnbLine(id: "\(index)", name: "Item", quantity: 1, locationId: "1",
                                note: nil, selectedModifiers: []))
        }
        XCTAssertEqual(runtime.draft.count, 20)
        runtime.submit(locationId: "1", venueId: nil, eventId: nil, canSend: false)
        runtime.decrement(productId: "1")
        XCTAssertEqual(runtime.draft.count, 19, "Local draft edits remain available during an unrelated request")
        let overflowing = FnbLine(id: "99", name: "Expensive", quantity: 20, locationId: "1", note: nil,
                                  selectedModifiers: [], unitCents: 1_000_000_000)
        runtime.add(overflowing)
        XCTAssertNil(runtime.estimatedTotal)
    }

    @MainActor
    func testSharedFixturesExerciseLocationsMenuAddCartRemoveAndCheckoutLifecycle() throws {
        let held = ConciergeXDMContextStore(sessionIDProvider: { "flow" })
        try held.update(KingsHostContext.demoFacts)
        let orders = FnbOrderStore { patch in
            do { try held.update(patch) } catch { XCTFail("Invalid patch: \(error)") }
        }
        orders.locationsShown(cardId: "locations", sessionId: "flow", eventId: 36747, stale: false, isLatest: true)
        orders.menuShown(cardId: "menu", sessionId: "flow", stale: false)
        let soda = try XCTUnwrap(FnbItem.map(try fixture("tapin2_stage_raw")).first { $0.id == "1364015" })
        let group = try XCTUnwrap(soda.modifierGroups.first)
        let option = try XCTUnwrap(PayloadRead.rows(group["modifiers"], limit: 50).first)
        let optionId = try XCTUnwrap(PayloadRead.id(option["id"]))
        let groupId = try XCTUnwrap(PayloadRead.id(group["id"]))
        var saved: [String: Any] = [:]
        var addCompletion: (@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void)?
        let menu = FnbMenuRuntime(state: [:], save: { saved = $0 }, send: { hint, fields, _, callback in
            XCTAssertEqual(hint, "add-to-cart")
            XCTAssertEqual(saved["status"] as? String, "submitting", "Persist before any network dispatch")
            let combined = ConciergeXDMContextStore.merging(fields, over: held.snapshot(for: "flow"))
            let namespace = combined["_sacramentokings"] as? [String: Any]
            XCTAssertNotNil((namespace?["conciergeContext"] as? [String: Any])?["userContext"])
            XCTAssertEqual(((namespace?["conciergeContext"] as? [String: Any])?["fnbOrders"] as? NSDictionary),
                           ["eventId": 36747])
            XCTAssertEqual(namespace?["conciergeAction"] as? NSDictionary, [
                "addToCart": ["products": [[
                    "locationId": 18342, "productId": 1364015, "quantity": 1,
                    "modifierGroups": [["isMultiSelect": group["isMultiSelect"] as? Bool ?? false,
                                        "modifiers": [["id": Int64(optionId)!, "isSelected": true]]]]
                ]]]
            ] as NSDictionary)
            addCompletion = callback
        })
        menu.add(FnbLine(id: soda.id, name: soda.name, quantity: 1, locationId: "18342", note: nil,
                         selectedModifiers: [FnbModifierSelection(groupId: groupId,
                            isMultiSelect: group["isMultiSelect"] as? Bool ?? false, modifiers: [optionId])],
                         unitCents: soda.cents))
        menu.submit(locationId: "18342", venueId: nil, eventId: nil, menuItems: [soda.id: soda], canSend: true)
        let restored = FnbMenuRuntime(state: saved, save: { _ in },
                                      send: { _, _, _, _ in XCTFail("A recreated pending card cannot resend") })
        XCTAssertEqual(restored.status, "submitting")
        addCompletion?(.success(()))
        restored.adopt(saved)
        XCTAssertEqual(restored.status, "added")
        orders.markMenuSubmitted(cardId: "menu", sessionId: "flow")
        XCTAssertFalse(orders.isMenuActionable(cardId: "menu", sessionId: "flow", stale: false, isLatest: true))

        let summary = try XCTUnwrap(FnbOrderSummary.map(try fixture("tapin2_stage_cart_add"), fallbackId: "null"))
        orders.cartShown(cardId: "cart", sessionId: "flow", orderId: summary.id,
                         paid: summary.paid, stale: false, isLatest: true)
        XCTAssertEqual(orders.currentOrderId, 695685)
        let line = try XCTUnwrap(summary.lines.first)
        let remove = try XCTUnwrap(FnbHandoff.removeFromCart(locationId: line.locationId,
                                                           productId: line.productId, modifiers: line.modifiers))
        XCTAssertEqual(remove as NSDictionary, [
            "_sacramentokings": ["conciergeAction": ["removeFromCart": [
                "products": [["locationId": Int64(line.locationId!)!, "productId": 1364190]]
            ]]]
        ] as NSDictionary)
        let reservation = try XCTUnwrap(orders.beginRemoval(key: "line", cardId: "cart", sessionId: "flow",
                                                           orderId: summary.id, stale: false, isLatest: true))
        orders.finishRemoval(key: "line", token: reservation, neverStarted: true)
        XCTAssertTrue(orders.removals.isEmpty)
        orders.checkoutDidOpen(orderId: summary.id, sessionId: "flow")
        XCTAssertNil(orders.currentOrderId)
        XCTAssertTrue(orders.isOrderArchived(summary.id))
        let final = held.snapshot(for: "flow")["_sacramentokings"] as? [String: Any]
        XCTAssertEqual((final?["conciergeContext"] as? [String: Any])?["fnbOrders"] as? NSDictionary,
                       ["eventId": 36747, "pastOrders": [["orderId": 695685]]])
    }

    @MainActor
    func testLateCallbackFromNeverStartedAttemptCannotCompleteRetryWithSameLogicalId() {
        var completions: [@MainActor (Result<Void, ConciergeDataHandoffError>) -> Void] = []
        let runtime = FnbMenuRuntime(state: [:], save: { _ in },
                                     send: { _, _, _, completion in completions.append(completion) },
                                     makeId: { "same-retry-id" })
        runtime.add(FnbLine(id: "1", name: "Item", quantity: 1, locationId: "2", note: nil, selectedModifiers: []))
        runtime.submit(locationId: "2", venueId: nil, eventId: nil, canSend: true)
        completions[0](.failure(.chatInProgress))
        runtime.submit(locationId: "2", venueId: nil, eventId: nil, canSend: true)
        completions[0](.success(()))
        XCTAssertEqual(runtime.status, "submitting")
        XCTAssertEqual(runtime.draft.count, 1)
        completions[1](.success(()))
        XCTAssertEqual(runtime.status, "added")

        completions.removeAll()
        let action = FnbActionRuntime(state: [:], save: { _ in },
                                      send: { _, _, _, completion in completions.append(completion) },
                                      makeId: { "same-retry-id" })
        func select() {
            action.perform(key: "location:2", hint: "view-menu",
                           fields: { _ in FnbHandoff.viewMenu(locationId: "2") },
                           copy: "Opening menu.", canSend: true)
        }
        select()
        completions[0](.failure(.chatInProgress))
        select()
        completions[0](.failure(.noResponse))
        XCTAssertEqual(action.activeAction, "same-retry-id")
        XCTAssertTrue(action.unconfirmed.isEmpty)
        completions[1](.success(()))
        XCTAssertNil(action.activeAction)
    }
}
