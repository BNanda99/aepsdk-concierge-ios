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

/// Data the app hands to the Concierge SDK (via `Concierge.sendDataHandoff(...)`) to forward
/// toward the agent pipeline (Brand Concierge / Product Advisor), outside of normal user-typed
/// chat. Internal transport container between the public wrapper and the extension's listener -
/// not constructed by consumer apps directly.
///
/// `routingHint` is a keyword consumed only by Brand Concierge's current phrase-based router
/// (e.g. "successful-checkout") — the end user never sees it, and it is not conversational
/// content. It may become optional once a more deterministic, XDM-field-based routing
/// approach ships; both fields are required for now.
///
/// `xdmFields` is merged directly into the root of the XDM object the SDK forwards alongside
/// the routing hint — an ordinary nested dictionary, e.g.
/// `["commerce": ["order": ["purchaseID": "123"]]]`. The SDK never reads or validates the
/// business meaning of these values; the customer's own nesting defines the destination.
/// Must not use `identityMap` (or any other SDK-reserved top-level XDM key) as a top-level key.
///
/// `localMessage` is text rendered immediately in the chat transcript as a local, non-networked
/// message — distinct from `routingHint`/`xdmFields`, which are forwarded to Brand Concierge.
/// Present and non-empty -> shown immediately. `nil`/empty -> nothing shown locally; the
/// conversation only gets whatever Product Advisor eventually replies with, same as if this
/// field didn't exist.
struct ConciergeDataHandoffEvent {
    let routingHint: String
    let xdmFields: [String: Any]
    let localMessage: String?

    init(routingHint: String, xdmFields: [String: Any], localMessage: String? = nil) {
        self.routingHint = routingHint
        self.xdmFields = xdmFields
        self.localMessage = localMessage
    }
}
