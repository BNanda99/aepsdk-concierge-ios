/*
 Copyright 2025 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import UIKit
import SwiftUI
import Combine
import AEPBrandConcierge

/// Simple UIKit screen showcasing the UIKit-based Concierge presentation API.
final class ConciergeUIKitDemoViewController: UIViewController {
    var handleLink: ((URL) -> Bool)?
    private var parkingResetObserver: AnyCancellable?
    private let openButton: UIButton = {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Open chat (UIKit)"
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 18, weight: .bold)
            return outgoing
        }
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(openButton)

        NSLayoutConstraint.activate([
            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
    }

    @objc private func openTapped() {
        Concierge.present(on: self, surfaces: ["web://edge-int.adobedc.net/brand-concierge/pages/745F37C35E4B776E0A49421B@AdobeOrg/acom_m15/index.html"], title: "Concierge", subtitle: "Powered by Adobe", handleLink: { [weak self] url in
            guard let self else { return false }
            if ParkWhizPurchase.isAllowedURL(url) {
                self.openParkingCheckout(url)
                return true
            }
            return self.handleLink?(url) ?? false
        })
    }

    private func openParkingCheckout(_ url: URL) {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIHostingController<ParkWhizBookingSheet>) else { return }
        let store = ParkWhizBookingStore.shared
        let checkout = ParkWhizCheckout(url: url, identityRevision: store.identityRevision)
        let controller = UIHostingController(rootView: ParkWhizBookingSheet(checkout: checkout))
        parkingResetObserver = store.$identityRevision.dropFirst().sink { [weak controller] _ in
            controller?.dismiss(animated: true)
        }
        presenter.present(controller, animated: true)
    }
}
