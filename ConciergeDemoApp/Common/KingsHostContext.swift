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
import AEPBrandConcierge

enum KingsHostContext {
    static var demoFacts: [String: Any] {
        ["_sacramentokings": ["conciergeContext": [
            "userContext": ["loggedIn": true, "hasAssignedSeat": true, "seatSection": "114", "isCourtside": false],
            "currentGame": game(date: "2026-04-14T23:30:00.000Z", status: "Finished", season: "2025-26",
                                seasonType: "PlayIn", home: ("Hornets", "CHA"), away: ("Heat", "MIA")),
            "upcomingGame": game(date: "2027-04-11T22:00:00.000Z", status: "Scheduled", season: "2026-27",
                                 seasonType: "Regular Season", home: ("Heat", "MIA"), away: ("Magic", "ORL"))
        ]]]
    }

    private static func game(date: String, status: String, season: String, seasonType: String,
                             home: (String, String), away: (String, String)) -> [String: Any] {
        ["gameDateTimeUtc": date, "gameState": "active", "gameStatus": status,
         "seasonCode": season, "seasonType": seasonType,
         "homeTeam": ["name": home.0, "teamAbbreviation": home.1],
         "awayTeam": ["name": away.0, "teamAbbreviation": away.1]]
    }
}
