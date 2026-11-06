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
import SwiftUI
@testable import AEPBrandConcierge

@MainActor
final class FnbCardsTests: XCTestCase {
    func testMenuItemCardFitsNarrowWidthAndGrowsForAccessibilityText() throws {
        let item = try XCTUnwrap(FnbItem.map([entry]).first)
        let row = FnbMenuItemCard(item: item, currencyCode: "USD", quantity: 0,
                                 maximumQuantity: 99, isEditable: true, add: {}, decrement: {})
        let regular = measure(row, width: 260, name: "Menu item card, narrow")
        let accessible = measure(row.environment(\.dynamicTypeSize, .accessibility3),
                                width: 260, name: "Menu item card, accessibility")
        XCTAssertGreaterThan(accessible.height, regular.height)
    }

    func testMenuItemNameBeyondTwoLinesGrowsAtAccessibilitySize() throws {
        var shortEntry = entry
        shortEntry["product"] = ["id": 1, "title": "Nachos", "price": 8]
        var longEntry = entry
        longEntry["product"] = ["id": 1, "title": String(repeating: "Loaded nachos ", count: 10), "price": 8]
        let shortItem = try XCTUnwrap(FnbItem.map([shortEntry]).first)
        let longItem = try XCTUnwrap(FnbItem.map([longEntry]).first)
        let short = FnbMenuItemCard(item: shortItem, currencyCode: "USD", quantity: 0,
                                    maximumQuantity: 99, isEditable: true, add: {}, decrement: {})
        let long = FnbMenuItemCard(item: longItem, currencyCode: "USD", quantity: 0,
                                   maximumQuantity: 99, isEditable: true, add: {}, decrement: {})
        let shortSize = measure(short.environment(\.dynamicTypeSize, .accessibility3), width: 260, name: "Short name")
        let longSize = measure(long.environment(\.dynamicTypeSize, .accessibility3), width: 260, name: "Full name")
        XCTAssertGreaterThan(longSize.height, shortSize.height + 100)
    }

    func testLocationTitleAndDetailGrowAtAccessibilitySize() throws {
        let short = try XCTUnwrap(FnbStand.map([["id": 1, "title": "Cafe", "waitTime": "10 minutes"]]).first)
        let long = try XCTUnwrap(FnbStand.map([["id": 2, "title": String(repeating: "Market Cafe ", count: 10),
                                              "waitTime": String(repeating: "Event detail ", count: 10)]]).first)
        func tile(_ stand: FnbStand) -> some View {
            FnbLocationTile(stand: stand, showsImage: false, closedLabel: "Closed",
                            actionLabel: "View menu", isUnconfirmed: false, isActionDisabled: false, select: {})
                .environment(\.dynamicTypeSize, .accessibility3)
        }
        let shortSize = measure(tile(short), width: 260, name: "Short location")
        let longSize = measure(tile(long), width: 260, name: "Full location")
        XCTAssertGreaterThan(longSize.height, shortSize.height + 100)
    }

    func testCartDistinguishesUnavailableContentFromValidEmptyCart() {
        let cardId = UUID().uuidString
        let context: [String: Any] = ["cardId": cardId]
        let unavailable = FnbCartCard(element: [:], context: context, saveState: { _ in },
                                      options: .stage, openCheckout: nil)
        let empty = FnbCartCard(element: ["entity_info": ["id": "123", "items": []]],
                                context: context, saveState: { _ in }, options: .stage, openCheckout: nil)
        XCTAssertEqual(unavailable.emptyStateMessage, "This content isn't available right now.")
        XCTAssertEqual(empty.emptyStateMessage, "Your cart is empty.")
    }

    func testQuantityControlFitsMenuItemCard() throws {
        let item = try XCTUnwrap(FnbItem.map([entry]).first)
        let row = FnbMenuItemCard(item: item, currencyCode: "USD", quantity: 2,
                                 maximumQuantity: 2, isEditable: true, add: {}, decrement: {})
        measure(row, width: 260, name: "Menu item card, quantity limit")
    }

    func testPrimaryActionGrowsInsteadOfTruncatingLongAccessibilityLabel() {
        let short = Button("View menu", action: {})
            .buttonStyle(FnbPrimaryButtonStyle())
            .environment(\.dynamicTypeSize, .accessibility3)
        let long = Button("View the restaurant menu", action: {})
            .buttonStyle(FnbPrimaryButtonStyle())
            .environment(\.dynamicTypeSize, .accessibility3)
        let shortSize = measure(short, width: 220, name: "Primary action, short")
        let longSize = measure(long, width: 220, name: "Primary action, wrapped")
        XCTAssertGreaterThan(longSize.height, shortSize.height)
    }

    func testMenuCategoriesAndActionsFitTranscriptWidth() {
        let context: [String: Any] = ["cardId": UUID().uuidString, "state": [:]]
        var secondEntry = entry
        secondEntry["category"] = ["id": 2, "title": "Beverages and refreshments"]
        secondEntry["product"] = ["id": 2, "title": "Fresh lemonade", "price": 5]
        let menu = FnbMenuCard(element: ["entity_info": [entry, secondEntry]],
                               context: context, saveState: { _ in }, options: FnbMenuOptions())
        measure(menu, width: 290, name: "Menu, category chips")
    }

    func testLocationAndLongActionLabelFitAtAccessibilitySize() {
        let context: [String: Any] = ["cardId": UUID().uuidString, "state": [:]]
        let locations = FnbLocationsCard(element: ["entity_info": [
            ["id": 1, "title": "Market Cafe 122", "section": "122",
             "description": "Mexican cuisine and drinks.", "isPickup": true],
            ["id": 2, "title": "Closed restaurant", "isPaused": true]
        ]], context: context, saveState: { _ in },
        options: FnbLocationOptions(ctaLabel: "View the restaurant menu"))
        measure(locations.environment(\.dynamicTypeSize, .accessibility3),
               width: 290, name: "Locations, accessibility")
    }

    func testCustomizeSheetFitsCompactWidthWithModifiersAndInstructions() throws {
        var customizable = entry
        customizable["product"] = ["id": 3, "title": "Loaded nachos", "price": 12,
                                   "description": "Tortilla chips, queso, pico de gallo",
                                   "modifierGroups": [["id": 9, "name": "Toppings", "isMultiSelect": true,
                                                       "maximumSelections": 2,
                                                       "modifiers": [["id": 1, "name": "Guacamole", "price": 2],
                                                                     ["id": 2, "name": "Jalapeños", "price": 0]]]]]
        let item = try XCTUnwrap(FnbItem.map([customizable]).first)
        XCTAssertFalse(item.modifierGroups.isEmpty)
        let sheet = FnbCustomizeSheet(item: item, quantityRule: FnbQuantityRule(),
                                      instructions: .notesEnabled, currencyCode: "USD",
                                      addToCartLabel: "Add to order") { _, _, _ in }
            .frame(height: 754)
        measure(sheet, width: 320, name: "Customize sheet, compact")
    }

    private var entry: [String: Any] {
        ["location": ["id": 122, "title": "Market Cafe 122"],
         "category": ["id": 1, "title": "Dessert"],
         "product": ["id": 1, "title": "\"Light The Beam\" Churro",
                     "description": "Churro, UBE Sugar, Spiced Chocolate Sauce", "price": 8]]
    }

    @discardableResult
    private func measure<Content: View>(_ content: Content, width: CGFloat, name: String) -> CGSize {
        var theme = ConciergeTheme()
        theme.customVariables = [
            "--fnb-card-background-color": "#1C2223",
            "--fnb-tile-background-color": "#222A2B",
            "--fnb-text-primary-color": "#FFFFFF",
            "--fnb-text-secondary-color": "#B5BABB",
            "--fnb-accent-color": "#9500FF",
            "--fnb-on-accent-color": "#FFFFFF"
        ]
        let controller = UIHostingController(rootView: content.conciergeTheme(theme)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(.container))
        controller.loadViewIfNeeded()
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(size.width, width + 0.5, name)
        XCTAssertGreaterThan(size.height, 44, name)
        XCTAssertTrue(size.height.isFinite, name)
        return size
    }

    @MainActor
    func testCardsOnlyCartResponseWithEmptyMessageRendersCartCard() throws {
        let bundles = [Bundle(for: FnbCardsTests.self), Bundle.main]
        let roots = bundles.flatMap { [$0.bundleURL, $0.resourceURL].compactMap { $0 } }
        let url = try XCTUnwrap(roots.map { $0.appendingPathComponent("tapin2_stage_cart_add.json") }
            .first { FileManager.default.fileExists(atPath: $0.path) })
        let order = try String(contentsOf: url)
        // BCOS `add_to_cart` envelope: empty `message`, and `id`/`entityId` stringify a missing orderId.
        let chunk = """
        {"conversationId":"conv","interactionId":"turn","state":"completed","response":{"message":"","multimodalElements":\
        {"elements":[{"id":"null","entityId":"null","type":"kings.fnbcart","cardType":"kings.fnbcart","entity_info":\(order)}]}}}
        """
        FnbCardRegistration.register()
        let payload = try CardJSONValue.decode(ConversationPayload.self, from: Data(chunk.utf8))
        XCTAssertEqual(payload.response?.message, "")
        let elements = try XCTUnwrap(payload.response?.multimodalElements?.elements)
        let configuration = ConciergeConfiguration()
        let service = MockChatService(configuration: configuration)
        service.plannedChunks = [payload]
        let controller = ChatController(configuration: configuration,
                                        chatService: service,
                                        speechCapturer: nil, speaker: nil)
        XCTAssertEqual(elements.count, 1)
        controller.applyTextChange("Show my cart")
        controller.sendMessage(isUser: true)
        let deadline = Date().addingTimeInterval(2)
        while (controller.messages.count < 2 || controller.chatState != .idle) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(controller.chatState, .idle)
        XCTAssertEqual(controller.messages.count, 2, "Only the user message and cart should remain")
        guard case .nativeCard(let cardId) = controller.messages.last?.template,
              let card = controller.nativeCards.card(withId: cardId) else {
            return XCTFail("Expected the cart to render as a native card")
        }
        defer { controller.messages.removeAll() }
        let summary = try XCTUnwrap(FnbOrderSummary.map(card.element["entity_info"], fallbackId: card.element["entityId"]))
        XCTAssertFalse(summary.lines.isEmpty)
    }
}
