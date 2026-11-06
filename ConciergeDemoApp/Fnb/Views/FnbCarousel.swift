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
import UIKit

/// Horizontally scrolling row of fixed-width, equal-height tiles. `contentInset` lets the row
/// scroll edge to edge inside a padded card. Falls back to a full-width vertical stack at
/// accessibility text sizes so large text never truncates inside a narrow tile.
struct FnbCarousel<Item: Identifiable, Tile: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [Item]
    let tileWidth: CGFloat
    var spacing: CGFloat = 12
    var contentInset: CGFloat = 0
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(items) { item in tile(item).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(.horizontal, contentInset)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        tile(item).frame(width: tileWidth).frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, contentInset)
                .padding(.vertical, 1)
            }
        }
    }
}

/// Lets a control scroll the enclosing chat transcript so a registered view's top edge lines up
/// with the top of the visible area. The transcript is the only vertical scroll container, so
/// this mirrors a "jump to section" without the card owning its own vertical scroll.
final class FnbScrollTargets {
    private final class WeakView { weak var view: UIView? }
    private var targets: [String: WeakView] = [:]

    func register(_ view: UIView, id: String) {
        let box = WeakView()
        box.view = view
        targets[id] = box
    }

    func scroll(to id: String) {
        guard let view = targets[id]?.view else { return }
        var ancestor = view.superview
        while let candidate = ancestor {
            if let scrollView = candidate as? UIScrollView,
               scrollView.contentSize.height > scrollView.bounds.height {
                let insets = scrollView.adjustedContentInset
                let frame = view.convert(view.bounds, to: scrollView)
                let minimum = -insets.top
                let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
                let target = min(max(frame.minY - insets.top - 8, minimum), maximum)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target),
                                            animated: !UIAccessibility.isReduceMotionEnabled)
                return
            }
            ancestor = candidate.superview
        }
    }
}

struct FnbScrollAnchor: UIViewRepresentable {
    let id: String
    let targets: FnbScrollTargets

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        targets.register(view, id: id)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        targets.register(uiView, id: id)
    }
}
