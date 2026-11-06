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

struct FnbCategory: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Scrolling category tabs. The selected category is filled with the accent color; the rest use
/// the tab background. Selecting a tab jumps to that category's row.
struct FnbCategoryChips: View {
    @Environment(\.conciergeTheme) private var theme
    let categories: [FnbCategory]
    let selection: String?
    var contentInset: CGFloat = 0
    let select: (String) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FnbStyle.tabRadius(theme), style: .continuous)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isSelected = selection == category.id
                    Button { select(category.id) } label: {
                        Text(category.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? FnbStyle.onAccent(theme) : FnbStyle.tabText(theme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(isSelected ? FnbStyle.accent(theme) : FnbStyle.tabBackground(theme), in: shape)
                            .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu categories")
    }
}
