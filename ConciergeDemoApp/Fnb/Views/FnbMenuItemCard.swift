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

/// One item in a category carousel: square artwork with tags and the quantity chip in its
/// corners, then the name (two lines reserved so tiles line up), optional metadata, and price.
struct FnbMenuItemCard: View {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: FnbItem
    let currencyCode: String
    let quantity: Int
    let maximumQuantity: Int
    let isEditable: Bool
    /// Keeps a metadata line even when this item has none, so tiles in a category line up.
    var reservesDetailLine = false
    var open: () -> Void = {}
    let add: () -> Void
    let decrement: () -> Void

    private var addLabel: String {
        item.modifierGroups.isEmpty ? "Add \(item.name)" : "Customize \(item.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FnbImage(url: item.image, showsPlaceholder: true, badge: item.isAlcohol ? "21+" : nil,
                     aspectRatio: 1, cornerRadius: 0)
                .overlay(alignment: .bottomTrailing) {
                    FnbQuantityControl(quantity: quantity,
                                       label: quantity == 0 ? addLabel : "Quantity of \(item.name)",
                                       style: .tile,
                                       canDecrement: quantity > 0,
                                       canIncrement: quantity < maximumQuantity,
                                       decrement: decrement, increment: add)
                        .disabled(!isEditable)
                        .padding(6)
                }
            FnbReservedLines(lineFonts: [.footnote.weight(.semibold), .footnote.weight(.semibold)],
                             spacing: 0) {
                Text(item.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                if reservesDetailLine {
                    Text(item.detail.isEmpty ? "Placeholder" : item.detail)
                        .font(.caption2)
                        .foregroundColor(FnbStyle.secondaryText(theme))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(item.detail.isEmpty ? 0 : 1)
                        .accessibilityHidden(item.detail.isEmpty)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(FnbStyle.price(cents: item.cents, currencyCode: currencyCode))
                        .font(.subheadline.weight(.semibold))
                    if let originalCents = item.originalCents {
                        let original = FnbStyle.price(cents: originalCents, currencyCode: currencyCode)
                        Text(original)
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(FnbStyle.secondaryText(theme))
                            .accessibilityLabel("Original price \(original)")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(FnbStyle.primaryText(theme))
        .background(FnbStyle.tileBackground(theme))
        .clipShape(RoundedRectangle(cornerRadius: FnbStyle.tileRadius(theme), style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: FnbStyle.tileRadius(theme), style: .continuous))
        .onTapGesture { if isEditable { open() } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Customize") { if isEditable { open() } }
    }
}
