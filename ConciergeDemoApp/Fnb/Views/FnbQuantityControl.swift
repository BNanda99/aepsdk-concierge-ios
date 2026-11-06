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

/// Quantity control in two looks:
/// - `.tile`: a compact chip for artwork corners. A round `+` at zero, otherwise `− n +`. Glyphs are
///   drawn at `--fnb-stepper-size` while each button keeps a 44-point touch target.
/// - `.pill`: `− n +` inside a bordered rounded rectangle, used in the customize sheet.
/// VoiceOver reads either as a single adjustable element.
struct FnbQuantityControl: View {
    enum Style { case tile, pill }

    @Environment(\.conciergeTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let quantity: Int
    let label: String
    var style: Style = .pill
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    private var glyphSize: CGFloat { FnbStyle.stepperSize(theme) }
    private var targetInset: CGFloat { max(0, (44 - glyphSize) / 2) }

    var body: some View {
        Group {
            switch style {
            case .tile: tileBody
            case .pill: pillBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(quantity)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { increment() }
            case .decrement: if canDecrement { decrement() }
            @unknown default: break
            }
        }
    }

    private var tileBody: some View {
        HStack(spacing: -targetInset * 2) {
            if quantity > 0 {
                tileGlyph("minus", enabled: canDecrement, action: decrement)
                Text("\(quantity)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundColor(FnbStyle.stepperContent(theme))
                    .frame(minWidth: 16)
                    .padding(.horizontal, targetInset * 2)
            }
            tileGlyph("plus", enabled: canIncrement, action: increment)
        }
        .background(
            Capsule()
                .fill(FnbStyle.stepperBackground(theme))
                .overlay(Capsule().stroke(FnbStyle.border(theme), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(targetInset)
        )
        .padding(-targetInset)
    }

    private func tileGlyph(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize * 0.45, weight: .bold))
                .foregroundColor(FnbStyle.stepperContent(theme))
                .frame(width: glyphSize, height: glyphSize)
                .padding(targetInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled && isEnabled ? 1 : 0.4)
    }

    private var pillBody: some View {
        let shape = RoundedRectangle(cornerRadius: FnbStyle.tileRadius(theme), style: .continuous)
        return HStack(spacing: 0) {
            pillGlyph("minus", enabled: canDecrement, action: decrement)
            Text("\(quantity)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundColor(FnbStyle.primaryText(theme))
                .frame(minWidth: 20)
                .padding(.horizontal, 12)
            pillGlyph("plus", enabled: canIncrement, action: increment)
        }
        .padding(.horizontal, 8)
        .overlay(shape.stroke(FnbStyle.border(theme), lineWidth: 1))
    }

    private func pillGlyph(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundColor(enabled && isEnabled ? FnbStyle.primaryText(theme) : FnbStyle.disabled(theme))
                .frame(minWidth: 44, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
