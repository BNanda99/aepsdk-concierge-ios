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

import AEPCore
import AEPServices
import AEPBrandConcierge
import AEPEdge
import AEPEdgeIdentity
import AEPEdgeConsent

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        MobileCore.setLogLevel(.trace)

        let extensions = [
            AEPEdgeIdentity.Identity.self,
            Edge.self,
            Concierge.self
        ]

        MobileCore.registerExtensions(extensions) {
            MobileCore.configureWith(appId: "/staging/a0ff8cfcfb87/9d363ab429c8/launch-481f6ff16749-development")

            let identityMap = IdentityMap()
            identityMap.add(
                item: IdentityItem(id: "22e8b663dd7d0ca003fea59bd163d97bf2f4c84538bfb3875b9a86b30aefc9cd"),
                withNamespace: "Email_LC_SHA256"
            )
            AEPEdgeIdentity.Identity.updateIdentities(with: identityMap)

            do {
                try Concierge.updateXDMContext(KingsHostContext.demoFacts)
                try Concierge.updateXDMContext([
                    "_sacramentokings": [
                        "conciergeContext": [
                            "userContext": [
                                "email": "visampath+Diego@adobe.com",
                                "nbaid": "abc123",
                                "tmid": "rvt122"
                            ]
                        ]
                    ]
                ])
            } catch {
                Log.error(label: "ConciergeDemoApp", "Failed to set login user context: \(error)")
            }

            // TODO: - temporary override of datastream and server until we get that sorted out
//            MobileCore.updateConfigurationWith(configDict: [
//                "concierge.configId": "6acf9d12-5018-4f84-8224-aac4900782f0",
//                "concierge.server": "edge-int.adobedc.net",
//                "concierge.region": "va7"
//            ])
        }

        Concierge.setEdgeTrackingEnabled(enable: true)
        FnbCardRegistration.register()

        #if DEBUG
        // URLProtocol.registerClass isn't reliably consulted for ConciergeChatService's custom
        // URLSession (or once the connection negotiates HTTP/3 QUIC) — inserting the class
        // directly into the injected configuration's protocolClasses is. Inert unless
        // ContentView.syncBuyNowMock() arms it for the Testing tab's Buy Now Mock scenario, so
        // chat opened from any other tab still reaches the real Concierge service.
        let mockSessionConfiguration = URLSessionConfiguration.default
        mockSessionConfiguration.protocolClasses = [BuyNowMockURLProtocol.self] + (mockSessionConfiguration.protocolClasses ?? [])
        Concierge.urlSessionConfigurationForTesting = mockSessionConfiguration
        #endif

        return true
    }
}
