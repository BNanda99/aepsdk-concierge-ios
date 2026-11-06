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

/// "Customize your order" sheet: artwork, item details, modifier groups, optional
/// instructions, quantity, and a pinned add action. On iOS 16+ the sheet sizes itself to its
/// content, so short items read as a compact card while long ones can expand.
struct FnbCustomizeSheet: View {
    @Environment(\.conciergeTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var imageHeight: CGFloat = 200
    let item: FnbItem
    let quantityRule: FnbQuantityRule
    let instructionsConfig: FnbInstructionsConfig?
    let currencyCode: String
    let addToCartLabel: String
    let add: ([FnbModifierSelection], Int, String?) -> Void
    @State private var selections: [String: Set<String>] = [:]
    @State private var quantity: Int
    @State private var instructions = ""
    @State private var scrollContentHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0
    @FocusState private var instructionsFocused: Bool

    init(item: FnbItem, quantityRule: FnbQuantityRule, instructions: FnbInstructionsConfig?,
         currencyCode: String, addToCartLabel: String,
         add: @escaping ([FnbModifierSelection], Int, String?) -> Void) {
        self.item = item
        self.quantityRule = quantityRule
        self.instructionsConfig = instructions
        self.currencyCode = currencyCode
        self.addToCartLabel = addToCartLabel
        self.add = add
        _quantity = State(initialValue: quantityRule.defaultValue)
    }

    private struct ModifierGroup: Identifiable {
        let id: String
        let name: String
        let isMultiSelect: Bool
        let minimum: Int
        let maximum: Int
        let options: [ModifierOption]
    }

    private struct ModifierOption: Identifiable {
        let id: String
        let name: String
        let cents: Int
    }

    private var groups: [ModifierGroup] {
        item.modifierGroups.enumerated().map { index, group in
            let isMultiSelect = group["isMultiSelect"] as? Bool == true
            let options = PayloadRead.rows(group["modifiers"], limit: 50).compactMap { option -> ModifierOption? in
                guard let optionId = PayloadRead.id(option["id"]), option["isActive"] as? Bool != false else { return nil }
                return ModifierOption(id: optionId, name: PayloadRead.text(option["name"], fallback: "Option"),
                                      cents: PayloadRead.cents(option["price"]) ?? 0)
            }
            return ModifierGroup(id: PayloadRead.id(group["id"]) ?? "\(index)",
                                 name: PayloadRead.text(group["name"], fallback: "Options"),
                                 isMultiSelect: isMultiSelect,
                                 minimum: PayloadRead.int(group["minimumSelections"], maximum: 50) ?? 0,
                                 maximum: PayloadRead.int(group["maximumSelections"], maximum: 50) ??
                                    (isMultiSelect ? 50 : 1),
                                 options: options)
        }
    }

    private func isSatisfied(_ group: ModifierGroup) -> Bool {
        let count = selections[group.id]?.count ?? 0
        return count >= group.minimum && count <= max(group.minimum, group.maximum)
    }

    private var isValid: Bool { groups.allSatisfy(isSatisfied) }

    private var lineTotalCents: Int? {
        var unitCents = item.cents
        for group in groups {
            for option in group.options where selections[group.id]?.contains(option.id) == true {
                guard option.cents <= 1_000_000_000 - unitCents else { return nil }
                unitCents += option.cents
            }
        }
        let (total, overflow) = unitCents.multipliedReportingOverflow(by: quantity)
        return overflow ? nil : total
    }

    private var horizontalPadding: CGFloat { FnbStyle.contentPadding(theme) + 4 }

    var body: some View {
        VStack(spacing: 0) {
            header.background(heightReader { chromeHeight = $0 + addButtonHeightEstimate })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FnbImage(url: item.image, showsPlaceholder: true, height: min(imageHeight, 280),
                             cornerRadius: FnbStyle.tileRadius(theme))
                        .overlay(RoundedRectangle(cornerRadius: FnbStyle.tileRadius(theme), style: .continuous)
                            .stroke(FnbStyle.border(theme), lineWidth: 1))
                    details
                    ForEach(groups) { group in groupSection(group) }
                    if let instructionsConfig { instructionsSection(instructionsConfig) }
                    quantitySection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
                .background(heightReader { scrollContentHeight = $0 })
            }
            addButton
        }
        .foregroundColor(FnbStyle.primaryText(theme))
        .tint(FnbStyle.accent(theme))
        .background(FnbStyle.sheetBackground(theme).ignoresSafeArea())
        .modifier(FnbSheetPresentation(contentHeight: scrollContentHeight + chromeHeight,
                                       background: FnbStyle.sheetBackground(theme),
                                       cornerRadius: FnbStyle.cardRadius(theme)))
        .onAppear(perform: applyDefaultSelections)
    }

    private var addButtonHeightEstimate: CGFloat { FnbStyle.buttonHeight(theme) + 40 }

    private func heightReader(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(proxy.size.height) }
                .onChange(of: proxy.size.height) { update($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Customize your order")
                .font(.headline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundColor(FnbStyle.secondaryText(theme))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, horizontalPadding)
        .padding(.trailing, horizontalPadding - 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if item.isAlcohol { FnbTag(text: "21+") }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(FnbStyle.price(cents: item.cents, currencyCode: currencyCode))
                    .font(.callout.weight(.bold))
                if let originalCents = item.originalCents {
                    Text(FnbStyle.price(cents: originalCents, currencyCode: currencyCode))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundColor(FnbStyle.secondaryText(theme))
                }
            }
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundColor(FnbStyle.secondaryText(theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionLabel(_ text: String, color: Color? = nil) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .kerning(0.5)
            .foregroundColor(color ?? FnbStyle.secondaryText(theme))
            .accessibilityAddTraits(.isHeader)
    }

    private func selectionHint(_ group: ModifierGroup) -> String {
        if group.minimum > 0 && group.minimum == group.maximum { return "Choose \(group.minimum)" }
        if group.minimum > 0 { return "Choose \(group.minimum)–\(group.maximum)" }
        return "Select up to \(group.maximum)"
    }

    private func groupSection(_ group: ModifierGroup) -> some View {
        let isRequired = group.minimum > 0
        let showsError = !isSatisfied(group)
        let errorColor: Color? = showsError ? FnbStyle.errorColor(theme) : nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel(group.name, color: errorColor)
                    if group.isMultiSelect || isRequired {
                        Text(selectionHint(group))
                            .font(.caption)
                            .foregroundColor(errorColor ?? FnbStyle.secondaryText(theme))
                    }
                }
                Spacer(minLength: 8)
                Text(isRequired ? "Required" : "Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(errorColor ?? (isRequired ? FnbStyle.primaryText(theme) : FnbStyle.secondaryText(theme)))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(errorColor ?? FnbStyle.border(theme), lineWidth: 1))
            }
            if showsError {
                Text("Please choose \(group.minimum)")
                    .font(.caption)
                    .foregroundColor(FnbStyle.errorColor(theme))
            }
            ForEach(group.options) { option in optionRow(option, in: group, showsError: showsError) }
        }
    }

    private func optionRow(_ option: ModifierOption, in group: ModifierGroup, showsError: Bool) -> some View {
        let selected = selections[group.id] ?? []
        let isSelected = selected.contains(option.id)
        let isAtLimit = group.isMultiSelect && !isSelected && selected.count >= group.maximum
        let title = option.cents > 0 ?
            "\(option.name) (+\(FnbStyle.priceText(cents: option.cents, currencyCode: currencyCode)))" :
            option.name
        let shape = RoundedRectangle(cornerRadius: FnbStyle.tileRadius(theme), style: .continuous)
        let indicator = group.isMultiSelect ?
            (isSelected ? "checkmark.square.fill" : "square") :
            (isSelected ? "largecircle.fill.circle" : "circle")
        let borderColor = showsError ? FnbStyle.errorColor(theme) :
            (isSelected ? FnbStyle.accent(theme) : FnbStyle.border(theme))
        return Button { toggle(option, in: group) } label: {
            HStack(spacing: 12) {
                Image(systemName: indicator)
                    .font(.title3)
                    .foregroundColor(isSelected ? FnbStyle.accent(theme) : FnbStyle.secondaryText(theme))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isAtLimit ? FnbStyle.secondaryText(theme) : FnbStyle.primaryText(theme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .overlay(shape.strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isAtLimit)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func instructionsSection(_ config: FnbInstructionsConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(config.label)
            instructionsField(config)
                .font(.body)
                .focused($instructionsFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(instructionsFocused ? FnbStyle.accent(theme) : FnbStyle.secondaryText(theme).opacity(0.7),
                            lineWidth: instructionsFocused ? 2 : 1))
                .accessibilityLabel(config.label)
                .onChange(of: instructions) { newValue in
                    if newValue.count > config.maxLength {
                        instructions = String(newValue.prefix(config.maxLength))
                    }
                }
            Text("\(instructions.count)/\(config.maxLength)")
                .font(.caption)
                .foregroundColor(FnbStyle.secondaryText(theme))
                .padding(.horizontal, 16)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func instructionsField(_ config: FnbInstructionsConfig) -> some View {
        let prompt = Text(config.placeholder).foregroundColor(FnbStyle.secondaryText(theme))
        if #available(iOS 16.0, *) {
            TextField("", text: $instructions, prompt: prompt, axis: .vertical).lineLimit(1...3)
        } else {
            TextField("", text: $instructions, prompt: prompt)
        }
    }

    private var quantitySection: some View {
        HStack {
            sectionLabel("Quantity")
            Spacer(minLength: 8)
            FnbQuantityControl(quantity: quantity, label: "Quantity",
                               canDecrement: quantity - quantityRule.step >= quantityRule.minimum,
                               canIncrement: quantity + quantityRule.step <= quantityRule.maximum,
                               decrement: { quantity = max(quantityRule.minimum, quantity - quantityRule.step) },
                               increment: { quantity = min(quantityRule.maximum, quantity + quantityRule.step) })
        }
    }

    private var addButton: some View {
        Button(action: submit) {
            Text(addToCartLabel.uppercased())
        }
        .buttonStyle(FnbPrimaryButtonStyle(isMuted: !isValid))
        .disabled(!isValid || lineTotalCents == nil)
        .accessibilityLabel(lineTotalCents.map {
            "\(addToCartLabel), \(FnbStyle.price(cents: $0, currencyCode: currencyCode))"
        } ?? addToCartLabel)
        .accessibilityHint(isValid ? "" : "Choose the required options first")
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(FnbStyle.sheetBackground(theme))
    }

    private func toggle(_ option: ModifierOption, in group: ModifierGroup) {
        var selected = selections[group.id] ?? []
        if selected.contains(option.id) {
            selected.remove(option.id)
        } else if group.isMultiSelect {
            guard selected.count < group.maximum else { return }
            selected.insert(option.id)
        } else {
            selected = [option.id]
        }
        selections[group.id] = selected
    }

    private func submit() {
        guard isValid, lineTotalCents != nil else { return }
        let choices = groups.compactMap { group -> FnbModifierSelection? in
            guard let modifiers = selections[group.id], !modifiers.isEmpty else { return nil }
            return FnbModifierSelection(groupId: group.id, isMultiSelect: group.isMultiSelect,
                                        modifiers: modifiers.sorted(), options: group.options.map(\.id))
        }
        let note = instructionsConfig == nil ? "" : PayloadRead.text(instructions)
        add(choices, quantity, note.isEmpty ? nil : note)
        dismiss()
    }

    private func applyDefaultSelections() {
        guard selections.isEmpty else { return }
        for (index, group) in item.modifierGroups.enumerated() {
            let groupId = PayloadRead.id(group["id"]) ?? "\(index)"
            let maximum = PayloadRead.int(group["maximumSelections"], maximum: 50) ?? 1
            let defaults = PayloadRead.rows(group["modifiers"], limit: 50).compactMap { option -> String? in
                guard option["isSelected"] as? Bool == true ||
                      option["isDefault"] as? Bool == true else { return nil }
                return PayloadRead.id(option["id"])
            }
            selections[groupId] = Set(defaults.prefix(maximum))
        }
    }
}

/// Sizes the sheet to its content on iOS 16+, still allowing it to expand to full height.
private struct FnbSheetPresentation: ViewModifier {
    let contentHeight: CGFloat
    let background: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(cornerRadius)
                .presentationBackground(background)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    @available(iOS 16.0, *)
    private var detents: Set<PresentationDetent> {
        contentHeight > 0 ? [.height(contentHeight), .large] : [.large]
    }
}
