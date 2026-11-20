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
import WebKit
import AEPBrandConcierge

enum ParkWhizPurchase {
    static func isAllowedURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased() else { return false }
        return host == "parkwhiz.com" || host.hasSuffix(".parkwhiz.com")
    }

    static func bookingId(_ body: Any) -> String? {
        let object: [String: Any]?
        if let source = body as? String {
            guard source.utf8.count <= 16_384, let data = source.data(using: .utf8) else { return nil }
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } else {
            object = PayloadRead.object(body)
        }
        guard let object, object["source"] as? String == "ParkWhiz",
              object["action"] as? String == "purchase",
              let value = PayloadRead.object(object["value"]), value["status"] as? String == "success" else { return nil }
        return PayloadRead.string(value["bookingId"])
    }
}

enum ParkWhizHandoffStatus: Equatable {
    case idle
    case sending
    case succeeded
    case rejected
    case uncertain
    case recordingFailed

    var message: String? {
        switch self {
        case .idle: return nil
        case .sending: return "Sending booking status…"
        case .succeeded: return "Booking status sent."
        case .rejected: return "Booking status was rejected."
        case .uncertain: return "Status delivery couldn't be confirmed. No retry is available."
        case .recordingFailed: return "Booking details couldn't be saved."
        }
    }
}

@MainActor
final class ParkWhizBookingStore: ObservableObject {
    static let shared = ParkWhizBookingStore()
    @Published private(set) var identityRevision = 0
    @Published private(set) var handoffStatus = ParkWhizHandoffStatus.idle
    private(set) var bookingIds: [String] = []
    private let publish: ([String: Any]) throws -> Void
    private let send: (String, [String: Any],
                       @escaping @MainActor (Result<Void, ConciergeDataHandoffError>) -> Void) throws -> Void
    private var retryableBookingId: String?
    private var activeAttempt: UUID?

    init(publish: @escaping ([String: Any]) throws -> Void = { try Concierge.updateXDMContext($0) },
         send: @escaping (String, [String: Any],
                          @escaping @MainActor (Result<Void, ConciergeDataHandoffError>) -> Void) throws -> Void = {
             hint, fields, completion in
             Concierge.sendDataHandoff(routingHint: hint, xdmFields: fields, completion: completion)
         }) {
        self.publish = publish
        self.send = send
    }

    @discardableResult
    func receive(_ body: Any, origin: URL, identityRevision: Int) -> String? {
        guard identityRevision == self.identityRevision, ParkWhizPurchase.isAllowedURL(origin),
              let booking = ParkWhizPurchase.bookingId(body), !bookingIds.contains(booking) else { return nil }
        let updated = bookingIds + [booking]
        do {
            try publish(["_sacramentokings": ["conciergeContext": [
                "parkingBookings": ["pastBookings": updated.map { ["bookingId": $0] }]
            ]]])
        } catch {
            guard identityRevision == self.identityRevision else { return nil }
            handoffStatus = .recordingFailed
            return nil
        }
        guard identityRevision == self.identityRevision else { return nil }
        bookingIds = updated
        sendStatus(for: booking, identityRevision: identityRevision)
        return booking
    }

    func retryStatus() {
        guard handoffStatus == .rejected, let booking = retryableBookingId else { return }
        sendStatus(for: booking, identityRevision: identityRevision)
    }

    func identityDidReset() {
        identityRevision += 1
        bookingIds.removeAll()
        retryableBookingId = nil
        activeAttempt = nil
        handoffStatus = .idle
    }

    private func sendStatus(for booking: String, identityRevision: Int) {
        guard identityRevision == self.identityRevision else { return }
        let attempt = UUID()
        activeAttempt = attempt
        handoffStatus = .sending
        retryableBookingId = nil
        let fields: [String: Any] = ["_sacramentokings": [
            "conciergeAction": ["parkingHandoff": ["bookingId": booking]]
        ]]

        do {
            try send("parking-booking-status", fields) { [weak self] result in
                guard let self, self.identityRevision == identityRevision,
                      self.activeAttempt == attempt else { return }
                self.activeAttempt = nil
                switch result {
                case .success:
                    self.handoffStatus = .succeeded
                    self.retryableBookingId = nil
                case .failure(let error):
                    if Self.isKnownRejection(error) {
                        self.handoffStatus = .rejected
                        self.retryableBookingId = booking
                    } else {
                        self.handoffStatus = .uncertain
                        self.retryableBookingId = nil
                    }
                }
            }
        } catch {
            guard identityRevision == self.identityRevision, activeAttempt == attempt else { return }
            activeAttempt = nil
            handoffStatus = .uncertain
            retryableBookingId = nil
        }
    }

    private static func isKnownRejection(_ error: ConciergeDataHandoffError) -> Bool {
        switch error {
        case .missingEventData, .emptyXdmFields, .invalidXdmFieldValue, .reservedKeyCollision,
             .noActiveSession, .chatInProgress:
            return true
        case .deliveryFailed, .emptyResponse, .deliveryTimeout, .noResponse:
            return false
        }
    }
}

struct ParkWhizCheckout: Identifiable {
    let id = UUID()
    let url: URL
    let identityRevision: Int
}

struct ParkWhizBookingSheet: View {
    let checkout: ParkWhizCheckout
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bookings = ParkWhizBookingStore.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ParkWhizWebView(checkout: checkout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let message = bookings.handoffStatus.message {
                    HStack(spacing: 12) {
                        Text(message)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if bookings.handoffStatus == .rejected {
                            Button("Retry status") { bookings.retryStatus() }
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Parking checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}

private struct ParkWhizWebView: UIViewRepresentable {
    let checkout: ParkWhizCheckout

    func makeCoordinator() -> Coordinator { Coordinator(identityRevision: checkout.identityRevision) }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "ParkWhizBridge")
        content.addUserScript(WKUserScript(source: Self.listener, injectionTime: .atDocumentStart,
                                          forMainFrameOnly: false))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if checkout.identityRevision == ParkWhizBookingStore.shared.identityRevision,
           ParkWhizPurchase.isAllowedURL(checkout.url) {
            view.load(URLRequest(url: checkout.url))
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ParkWhizBridge")
        uiView.configuration.userContentController.removeAllUserScripts()
        uiView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let identityRevision: Int
        init(identityRevision: Int) { self.identityRevision = identityRevision }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let origin = message.frameInfo.securityOrigin
            var parts = URLComponents()
            parts.scheme = origin.protocol
            parts.host = origin.host
            if origin.port != 0 { parts.port = origin.port }
            guard isCurrentIdentity, message.name == "ParkWhizBridge", let url = parts.url,
                  ParkWhizPurchase.isAllowedURL(url) else { return }
            ParkWhizBookingStore.shared.receive(message.body, origin: url, identityRevision: identityRevision)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard isCurrentIdentity, let url = navigationAction.request.url, url.scheme?.lowercased() == "https",
                  url.user == nil, url.password == nil else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private var isCurrentIdentity: Bool {
            identityRevision == ParkWhizBookingStore.shared.identityRevision
        }
    }

    // Both the sending frame and postMessage origin are checked; a payment iframe cannot forge
    // a ParkWhiz success message by posting into its parent.
    private static let listener = """
    (function () {
      function allowed(raw) {
        try {
          var u = new URL(raw);
          return u.protocol === 'https:' && (!u.port || u.port === '443') &&
            (u.hostname === 'parkwhiz.com' || u.hostname.endsWith('.parkwhiz.com'));
        } catch (_) { return false; }
      }
      if (!allowed(window.location.href) || window.__pwBridgeInstalled) return;
      window.__pwBridgeInstalled = true;
      window.addEventListener('message', function (event) {
        if (!allowed(event.origin)) return;
        var data = event.data;
        if (typeof data === 'string') {
          if (data.length > 16384) return;
          try { data = JSON.parse(data); } catch (_) { return; }
        }
        if (data && data.source === 'ParkWhiz' && data.action === 'purchase' &&
            data.value && data.value.status === 'success') {
          window.webkit.messageHandlers.ParkWhizBridge.postMessage({
            source: data.source, action: data.action,
            value: { status: data.value.status, bookingId: data.value.bookingId }
          });
        }
      });
    })();
    """
}
