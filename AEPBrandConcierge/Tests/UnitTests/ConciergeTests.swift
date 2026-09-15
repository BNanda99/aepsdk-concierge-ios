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
import AEPCore
import AEPTestUtils
@testable import AEPBrandConcierge

/// Verifies the `Concierge` extension's app-facing data-handoff listener: decodes a
/// `ConciergeDataHandoffEvent` from the request event's data, validates its shape, and
/// responds accepted/rejected accordingly. Does not exercise forwarding/merging - that
/// isn't implemented yet.
final class ConciergeTests: XCTestCase {
    var mockRuntime: TestableExtensionRuntime!
    var concierge: Concierge!

    override func setUp() {
        super.setUp()
        mockRuntime = TestableExtensionRuntime()
        concierge = Concierge(runtime: mockRuntime)
        concierge.onRegistered()
    }

    // MARK: - Helpers

    private func dispatchDataHandoff(payload: Any?) -> Event? {
        let event = Event(name: "test data handoff event",
                          type: ConciergeConstants.EventType.concierge,
                          source: ConciergeConstants.EventSource.dataHandoff,
                          data: payload.map { [ConciergeConstants.DataHandoffEventData.Key.PAYLOAD: $0] })
        mockRuntime.simulateComingEvents(event)
        return mockRuntime.firstEvent
    }

    private func rejectReason(of response: Event?) -> ConciergeDataHandoffRejectReason? {
        (response?.data?[ConciergeConstants.DataHandoffEventData.Key.REJECT_REASON] as? String)
            .flatMap(ConciergeDataHandoffRejectReason.init(rawValue:))
    }

    // MARK: - Tests

    func test_validPayload_respondsAccepted() {
        let payload = ConciergeDataHandoffEvent(routingHint: "successful-checkout",
                                                xdmFields: ["commerce": ["order": ["purchaseID": "123"]]])

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, true)
        XCTAssertNil(response?.data?[ConciergeConstants.DataHandoffEventData.Key.REJECT_REASON])
    }

    func test_validPayload_withLocalMessage_respondsAccepted() {
        let payload = ConciergeDataHandoffEvent(routingHint: "successful-checkout",
                                                xdmFields: ["commerce": ["order": ["purchaseID": "123"]]],
                                                localMessage: "Your order is confirmed!")

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, true)
        XCTAssertNil(response?.data?[ConciergeConstants.DataHandoffEventData.Key.REJECT_REASON])
    }

    func test_missingOrMiscastPayload_respondsRejected() {
        let response = dispatchDataHandoff(payload: "not the right type")

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, false)
        XCTAssertEqual(rejectReason(of: response), .missingEventData)
    }

    func test_emptyRoutingHint_respondsRejected() {
        let payload = ConciergeDataHandoffEvent(routingHint: "",
                                                xdmFields: ["commerce": ["order": ["purchaseID": "123"]]])

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, false)
        XCTAssertEqual(rejectReason(of: response), .missingRoutingHint)
    }

    func test_emptyXdmFields_respondsRejected() {
        let payload = ConciergeDataHandoffEvent(routingHint: "successful-checkout", xdmFields: [:])

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, false)
        XCTAssertEqual(rejectReason(of: response), .emptyXdmFields)
    }

    func test_nonSerializableXdmFields_respondsRejected() {
        let payload = ConciergeDataHandoffEvent(routingHint: "successful-checkout",
                                                xdmFields: ["commerce": Date()])

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, false)
        XCTAssertEqual(rejectReason(of: response), .invalidXdmFieldValue)
    }

    func test_reservedTopLevelKey_respondsRejected() {
        let payload = ConciergeDataHandoffEvent(routingHint: "successful-checkout",
                                                xdmFields: ["identityMap": ["ECID": [["id": "abc"]]]])

        let response = dispatchDataHandoff(payload: payload)

        XCTAssertEqual(response?.data?[ConciergeConstants.DataHandoffEventData.Key.ACCEPTED] as? Bool, false)
        XCTAssertEqual(rejectReason(of: response), .reservedKeyCollision)
    }

    // MARK: - readyForEvent

    func test_readyForEvent_dataHandoffEvent_stillRequiresConfigurationAndEdgeIdentity() {
        // No Configuration/EdgeIdentity shared state has been set up on mockRuntime at all -
        // data-handoff events are not exempted from the extension's hard dependency on both.
        let event = Event(name: "test data handoff event",
                          type: ConciergeConstants.EventType.concierge,
                          source: ConciergeConstants.EventSource.dataHandoff,
                          data: nil)

        XCTAssertFalse(concierge.readyForEvent(event))
    }
}
