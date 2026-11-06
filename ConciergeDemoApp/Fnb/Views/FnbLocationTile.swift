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

/// A restaurant card laid out like the SDK's product card: optional artwork with the section
/// badge pinned to its corner (or leading the text when there is no artwork), title,
/// description, then the detail line and the action anchored to the bottom.
struct FnbLocationTile: View {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledImageHeight: CGFloat = 190
    let stand: FnbStand
    let showsImage: Bool
    let closedLabel: String
    let actionLabel: String
    let isUnconfirmed: Bool
    let isActionDisabled: Bool
    let select: () -> Void

    private var badge: String? { stand.isOpen ? stand.section : closedLabel }
    private var layout: ConciergeLayout { theme.layout }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FnbStyle.cardRadius(theme), style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsImage { artwork }
            VStack(alignment: .leading, spacing: 8) {
                if !showsImage, let badge { FnbBadge(text: badge) }
                Text(stand.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(theme.colors.productCard.titleColor.color)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if !stand.description.isEmpty {
                    Text(stand.description)
                        .font(.caption)
                        .foregroundColor(theme.colors.productCard.subtitleColor.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, showsImage ? 24 : 16)
            Spacer(minLength: 0)
            if !stand.detail.isEmpty {
                Text(stand.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(FnbStyle.color("--simple-card-detail-color", theme: theme,
                                                    fallback: FnbStyle.secondaryText(theme)))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            if isUnconfirmed {
                Text("We couldn't confirm this request. Ask Concierge before trying again.")
                    .font(.caption2)
                    .foregroundColor(FnbStyle.errorColor(theme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Button(action: select) {
                Text(actionLabel)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(FnbCapsuleButtonStyle())
            .disabled(isActionDisabled)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .accessibilityHint(stand.title)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.productCard.backgroundColor?.color ?? FnbStyle.cardBackground(theme), in: shape)
        .overlay(shape.stroke(theme.colors.productCard.outlineColor.color, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { if !isActionDisabled { select() } }
        .opacity(stand.isOpen ? 1 : FnbStyle.dimension("--simple-card-disabled-opacity", theme: theme,
                                                        fallback: 0.45, range: 0...1))
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        let height = min(scaledImageHeight, layout.productImageHeight * 1.5)
        return FnbImage(url: stand.image, showsPlaceholder: true, height: height,
                        cornerRadius: FnbStyle.imageRadius(theme))
            .frame(maxWidth: min(layout.productImageWidth, layout.productCardWidth - 32))
            .overlay(alignment: .bottomLeading) {
                if let badge {
                    FnbBadge(text: badge)
                        .padding(FnbStyle.dimension("--simple-card-badge-inset", theme: theme, fallback: 0))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
    }
}

/// Section badge on a location card, styled with the product-card badge tokens.
struct FnbBadge: View {
    @Environment(\.conciergeTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundColor(theme.colors.productCard.badgeTextColor.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(theme.colors.productCard.badgeBackgroundColor.color,
                        in: RoundedRectangle(cornerRadius: FnbStyle.dimension("--simple-card-badge-border-radius",
                                                                              theme: theme, fallback: 0),
                                             style: .continuous))
    }
}

/// Accent capsule that hugs its label, used for card actions such as "View menu".
struct FnbCapsuleButtonStyle: ButtonStyle {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.layout.productCardCtaButtonBorderRadius, style: .continuous)
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(isEnabled ? theme.colors.productCardCtaButton.text.color : FnbStyle.secondaryText(theme))
            .padding(.horizontal, theme.layout.productCardCtaButtonHorizontalPadding)
            .padding(.vertical, theme.layout.productCardCtaButtonVerticalPadding)
            .frame(minHeight: 44)
            .background((isEnabled ? theme.colors.productCardCtaButton.background.color : FnbStyle.disabled(theme))
                .opacity(configuration.isPressed ? 0.8 : 1), in: shape)
            .contentShape(shape)
    }
}

/// Reserves vertical space for a fixed set of text lines (one entry per line, in the given font)
/// so sibling cards in a carousel line up while content stays packed at the top.
struct FnbReservedLines<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let lineFonts: [Font]
    let spacing: CGFloat
    let content: Content

    init(lineFonts: [Font], spacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.lineFonts = lineFonts
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.fixedSize(horizontal: false, vertical: true)
        } else {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(lineFonts.indices, id: \.self) { index in Text(" ").font(lineFonts[index]) }
                }
                .hidden()
                .accessibilityHidden(true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
