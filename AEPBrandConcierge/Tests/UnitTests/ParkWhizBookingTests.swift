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

@MainActor
final class ParkWhizBookingTests: XCTestCase {
    private let origin = URL(string: "https://www.parkwhiz.com")!

    private func purchase(_ booking: Any) -> [String: Any] {
        ["source": "ParkWhiz", "action": "purchase", "value": ["status": "success", "bookingId": booking]]
    }

    func testBookingPublishesBeforeExactStatusHandoffForStringAndNumericIds() throws {
        for booking: Any in ["118734521", 118734521] {
            var calls: [String] = []
            let store = ParkWhizBookingStore(publish: { fields in
                calls.append("record")
                XCTAssertEqual(fields as NSDictionary, [
                    "_sacramentokings": ["conciergeContext": ["parkingBookings": [
                        "pastBookings": [["bookingId": "118734521"]]
                    ]]]
                ] as NSDictionary)
            }, send: { hint, fields in
                calls.append(hint)
                let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
                XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) },
                    #"{"_sacramentokings":{"conciergeAction":{"parkingHandoff":{"bookingId":"118734521"}}}}"#)
            })
            XCTAssertEqual(store.receive(purchase(booking), origin: origin, identityRevision: 0), "118734521")
            XCTAssertEqual(calls, ["record", "parking-booking-status"])
            XCTAssertNil(store.receive(purchase(booking), origin: origin, identityRevision: 0))
            XCTAssertEqual(calls.count, 2)
        }
    }

    func testFullBookingListIsRepublishedAndIdentityResetClearsLocalMirror() {
        var patches: [NSDictionary] = []
        var sends = 0
        let store = ParkWhizBookingStore(publish: { patches.append($0 as NSDictionary) },
                                        send: { _, _ in sends += 1 })
        store.receive(purchase("one"), origin: origin, identityRevision: 0)
        store.receive(purchase("two"), origin: origin, identityRevision: 0)
        XCTAssertEqual(patches.last, [
            "_sacramentokings": ["conciergeContext": ["parkingBookings": [
                "pastBookings": [["bookingId": "one"], ["bookingId": "two"]]
            ]]]
        ] as NSDictionary)
        store.identityDidReset()
        XCTAssertTrue(store.bookingIds.isEmpty)
        XCTAssertNil(store.receive(purchase("late"), origin: origin, identityRevision: 0))
        store.receive(purchase("one"), origin: origin, identityRevision: 1)
        XCTAssertEqual(store.bookingIds, ["one"])
        XCTAssertEqual(sends, 3)
        XCTAssertEqual(patches.last, patches.first, "No prior-user IDs may be republished")
    }

    func testMalformedUnsuccessfulAndUntrustedMessagesDoNotRecordOrSend() {
        let store = ParkWhizBookingStore(publish: { _ in XCTFail("Unexpected record") },
                                        send: { _, _ in XCTFail("Unexpected send") })
        let malformed: [Any] = [
            "invalid", "{}", purchase(NSNull()), purchase(""), purchase("null"), purchase(true),
            ["source": "Attacker", "action": "purchase", "value": ["status": "success", "bookingId": "1"]],
            ["source": "ParkWhiz", "action": "cancel", "value": ["status": "success", "bookingId": "1"]],
            ["source": "ParkWhiz", "action": "purchase", "value": ["status": "failed", "bookingId": "1"]]
        ]
        for message in malformed {
            XCTAssertNil(store.receive(message, origin: origin, identityRevision: 0))
        }
        for source in ["http://parkwhiz.com", "https://parkwhiz.com.evil.test",
                       "https://evilparkwhiz.com", "https://user@parkwhiz.com", "https://parkwhiz.com:444"] {
            XCTAssertNil(store.receive(purchase("1"), origin: URL(string: source)!, identityRevision: 0))
        }
        XCTAssertTrue(store.bookingIds.isEmpty)
    }

    func testSerializedPurchaseEnvelopeAndExactOriginAllowlist() throws {
        let data = try JSONSerialization.data(withJSONObject: purchase(118734521))
        XCTAssertEqual(ParkWhizPurchase.bookingId(try XCTUnwrap(String(data: data, encoding: .utf8))), "118734521")
        for source in ["https://parkwhiz.com", "https://checkout.parkwhiz.com/widget", "https://parkwhiz.com:443"] {
            XCTAssertTrue(ParkWhizPurchase.isAllowedURL(URL(string: source)!))
        }
        XCTAssertNil(ParkWhizPurchase.bookingId(String(repeating: " ", count: 16_385)))
    }

    func testFailedContextPublicationDoesNotReportBookingOrSendHandoff() {
        enum Failure: Error { case rejected }
        let store = ParkWhizBookingStore(publish: { _ in throw Failure.rejected },
                                        send: { _, _ in XCTFail("Context must be recorded before sending") })
        XCTAssertNil(store.receive(purchase("1"), origin: origin, identityRevision: 0))
        XCTAssertTrue(store.bookingIds.isEmpty)
    }

    func testResetDuringPublicationCannotSendAnOldIdentityHandoff() {
        var store: ParkWhizBookingStore!
        store = ParkWhizBookingStore(publish: { _ in store.identityDidReset() },
                                     send: { _, _ in XCTFail("Old checkout callback survived reset") })
        XCTAssertNil(store.receive(purchase("old"), origin: origin, identityRevision: 0))
        XCTAssertTrue(store.bookingIds.isEmpty)
    }

    func testHostFactsMatchAndroidUnderConciergeContext() throws {
        let root = try XCTUnwrap(KingsHostContext.demoFacts["_sacramentokings"] as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["conciergeContext"])
        let context = try XCTUnwrap(root["conciergeContext"] as? [String: Any])
        XCTAssertEqual(Set(context.keys), ["userContext", "currentGame", "upcomingGame"])
        XCTAssertEqual(context["userContext"] as? NSDictionary,
                       ["loggedIn": true, "hasAssignedSeat": true, "seatSection": "114", "isCourtside": false])
        let upcoming = try XCTUnwrap(context["upcomingGame"] as? [String: Any])
        XCTAssertEqual(upcoming["gameDateTimeUtc"] as? String, "2027-04-11T22:00:00.000Z")
        XCTAssertEqual(upcoming["homeTeam"] as? NSDictionary, ["name": "Heat", "teamAbbreviation": "MIA"])
    }
}
