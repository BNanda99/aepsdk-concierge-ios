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
import CoreFoundation

enum PayloadRead {
    static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    static func rows(_ value: Any?, limit: Int) -> [[String: Any]] {
        guard limit > 0 else { return [] }
        if let row = object(value) { return [row] }
        guard let array = value as? [Any] else { return [] }
        return array.prefix(limit).compactMap(object)
    }

    static func string(_ value: Any?) -> String? {
        let text: String
        if let value = value as? String {
            text = value
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite {
            text = number.stringValue
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 140, trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }

    static func id(_ value: Any?) -> String? {
        let source: String?
        if value is String {
            source = string(value)
        } else {
            source = integerId(value).map(String.init)
        }
        guard let source, source.count <= 64 else { return nil }
        return source
    }

    static func urlId(_ value: String) -> String? {
        guard let source = id(value),
              source.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return source
    }

    static func integerId(_ value: Any?) -> Int64? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.range(of: #"^[+-]?[0-9]{1,19}$"#, options: .regularExpression) != nil else { return nil }
            return Int64(trimmed)
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        if let decimal = number as? NSDecimalNumber {
            let value = decimal.decimalValue
            guard !value.isNaN, value >= Decimal(Int64.min), value <= Decimal(Int64.max) else { return nil }
            let integer = decimal.int64Value
            return Decimal(integer) == value ? integer : nil
        }
        let encoding = String(cString: number.objCType)
        if encoding == "d" || encoding == "f" {
            let value = number.doubleValue
            guard value.isFinite, abs(value) <= 9_007_199_254_740_992,
                  value.rounded() == value else { return nil }
            return Int64(exactly: value)
        }
        return Int64(number.stringValue)
    }

    static func int(_ value: Any?, minimum: Int = 0, maximum: Int = 99) -> Int? {
        guard let number = integerId(value), let result = Int(exactly: number),
              result >= minimum, result <= maximum else { return nil }
        return result
    }

    static func bool(_ value: Any?) -> Bool? {
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func text(_ value: Any?, fallback: String = "") -> String {
        let raw = (value as? String).flatMap { $0.count <= 4_096 ? $0 : nil } ?? string(value) ?? fallback
        var cleaned = raw.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "",
                                               options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(?:script|style)\b[^>]*>.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"</?[A-Za-z][^>]*>"#, with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " "]
        for (encoded, decoded) in entities where encoded != "&amp;" {
            cleaned = cleaned.replacingOccurrences(of: encoded, with: decoded)
        }
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        return String(cleaned.prefix(140))
    }

    static func label(_ value: String, fallback: String) -> String {
        let cleaned = text(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func cents(_ value: Any?, allowNegative: Bool = false) -> Int? {
        guard let source = string(value), source.count <= 64,
              source.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?$"#,
                           options: .regularExpression) != nil,
              let decimal = Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN else { return nil }
        var amount = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 0, .plain)
        guard !rounded.isNaN, rounded >= (allowNegative ? -1_000_000_000 : 0),
              rounded <= 1_000_000_000 else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func httpsImage(_ value: Any?) -> URL? {
        guard let raw = value as? String else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2_048,
              let url = URL(string: text), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil else { return nil }
        return url
    }

    static func artwork(_ row: [String: Any]) -> URL? {
        httpsImage(row["mobileImageUrl"]) ?? httpsImage(row["imageUrl"]) ??
        httpsImage(row["mobileImage"]) ?? httpsImage(row["image"])
    }
}
