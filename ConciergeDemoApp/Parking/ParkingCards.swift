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

enum ParkingCardTypes {
    /// `entity_info`: an event the fan can park for - `{ event_id, name, start_time, end_time }`.
    static let events = "kings.parkingevents"
}

struct ParkingEventOptions {
    var ctaLabel = "See parking"
    var pendingCtaLabel = "Finding lots\u{2026}"
}

struct ParkingEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String

    var tile: FnbStand {
        FnbStand(id: id, title: title, description: "", section: nil, detail: detail,
                 isOpen: true, image: nil, order: 0)
    }
}

enum ParkingEventsMapper {
    static let searchParkingHint = "search-parking"
    static let maxEvents = 20

    /// Reads one event object, `[event]`, or `{ "events": [event] }`. Keeps vendor (date) order.
    static func map(_ payload: Any?) -> [ParkingEvent] {
        var seen = Set<String>()
        var events: [ParkingEvent] = []
        for row in rows(payload) {
            guard events.count < maxEvents else { break }
            guard let id = PayloadRead.id(row["event_id"]) else { continue }
            let title = PayloadRead.text(row["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(id).inserted else { continue }
            events.append(ParkingEvent(id: id, title: title,
                                       detail: ParkingEventTime.format(row["start_time"]) ?? ""))
        }
        return events
    }

    private static func rows(_ payload: Any?) -> [[String: Any]] {
        if let list = payload as? [Any] { return PayloadRead.rows(list, limit: 500) }
        guard let object = payload as? [String: Any] else { return [] }
        if let list = object["events"] as? [Any] { return PayloadRead.rows(list, limit: 500) }
        return object["event_id"] != nil ? [object] : []
    }

    /// `search-parking` lookup: the finalized action contract carries event IDs as strings.
    static func searchParking(eventId: String) -> [String: Any]? {
        guard let id = PayloadRead.id(eventId) else { return nil }
        return ["_sacramentokings": ["conciergeAction": ["searchParking": ["eventId": id]]]]
    }

    static func selectEventMessage(_ title: String) -> String {
        let safe = PayloadRead.text(title).replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Finding parking for this game." : "Finding parking for \(String(safe.prefix(60)))."
    }
}

/// Formats vendor timestamps such as `2026-12-13T18:00:00.000-08:00` as "Sat, Dec 13 · 6:00 PM".
/// The venue's offset is kept for display, so fans elsewhere still see the tip-off time on their
/// ticket; a timestamp without an offset is read in the device's zone.
enum ParkingEventTime {
    private static let regex = try? NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*(Z|z|[+-]\d{2}:?\d{2})?$"#)

    static func format(_ raw: Any?, deviceZone: TimeZone = .current) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let year = group(1).flatMap(Int.init), let month = group(2).flatMap(Int.init),
              let day = group(3).flatMap(Int.init), let hour = group(4).flatMap(Int.init),
              let minute = group(5).flatMap(Int.init),
              (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute),
              let zone = zone(group(7), deviceZone: deviceZone) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                             hour: hour, minute: minute)),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = "EEE, MMM d '\u{00B7}' h:mm a"
        return formatter.string(from: date)
    }

    private static func zone(_ offset: String?, deviceZone: TimeZone) -> TimeZone? {
        guard let offset, !offset.isEmpty else { return deviceZone }
        if offset.lowercased() == "z" { return TimeZone(secondsFromGMT: 0) }
        let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
              hours <= 18, minutes < 60 else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (offset.hasPrefix("-") ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}

struct ParkingEventsCard: View {
    @Environment(\.conciergeTheme) private var theme
    let element: [String: Any]
    let context: [String: Any]
    let options: ParkingEventOptions
    @StateObject private var runtime: FnbActionRuntime

    init(element: [String: Any], context: [String: Any], saveState: @escaping ([String: Any]) -> Void,
         options: ParkingEventOptions) {
        self.element = element
        self.context = context
        self.options = options
        let state = context["state"] as? [String: Any] ?? [:]
        _runtime = StateObject(wrappedValue: FnbActionRuntime(state: state, save: saveState))
    }

    private var events: [ParkingEvent] { ParkingEventsMapper.map(element["entity_info"]) }
    private var gated: Bool {
        runtime.activeAction != nil ||
        context["isBusy"] as? Bool == true || context["isStale"] as? Bool == true
    }
    private var contextRevision: Int { (context["state"] as? [String: Any])?["rev"] as? Int ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = runtime.errorMessage {
                Text(error).font(.caption).foregroundColor(FnbStyle.errorColor(theme))
            }
            if events.isEmpty {
                Text("This content isn't available right now.")
                    .font(.subheadline)
                    .foregroundColor(FnbStyle.secondaryText(theme))
            } else {
                FnbCarousel(items: events, tileWidth: FnbStyle.locationTileWidth(theme),
                            spacing: theme.layout.productCardCarouselSpacing) { event in
                    let key = actionKey(event)
                    let isUnconfirmed = runtime.unconfirmed.contains(key)
                    FnbLocationTile(stand: event.tile, showsImage: false, closedLabel: "",
                                    actionLabel: runtime.activeActionKey == key
                                        ? options.pendingCtaLabel : options.ctaLabel,
                                    isUnconfirmed: isUnconfirmed,
                                    isActionDisabled: gated || isUnconfirmed ||
                                        ParkingEventsMapper.searchParking(eventId: event.id) == nil) {
                        select(event)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { runtime.adopt(context["state"] as? [String: Any] ?? [:]) }
        .onChange(of: contextRevision) { _ in
            runtime.adopt(context["state"] as? [String: Any] ?? [:])
        }
    }

    private func actionKey(_ event: ParkingEvent) -> String { "parking:\(event.id)" }

    private func select(_ event: ParkingEvent) {
        guard !gated, let fields = ParkingEventsMapper.searchParking(eventId: event.id) else { return }
        runtime.perform(key: actionKey(event), hint: ParkingEventsMapper.searchParkingHint,
                        fields: { _ in fields }, copy: ParkingEventsMapper.selectEventMessage(event.title),
                        selected: event.id, canSend: !gated)
    }
}
