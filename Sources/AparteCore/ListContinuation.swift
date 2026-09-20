import Foundation

/// The small amount of list syntax needed by the editor's Return key behavior.
///
/// A list item is exactly a line whose text starts with a visible marker. There
/// is no hidden list state, so deleting the marker ends the item. Keeping the
/// parser here makes those decisions independent of AppKit.
public enum ListContinuation {
    public struct Marker: Equatable, Sendable {
        public let kind: AparteListKind
        public let number: Int?
        public let prefix: String

        public var utf16Length: Int { prefix.utf16.count }

        public init(kind: AparteListKind, number: Int? = nil, prefix: String) {
            self.kind = kind
            self.number = number
            self.prefix = prefix
        }
    }

    /// Returns the visible marker at the beginning of `line`, if any.
    /// Trailing whitespace belongs to the prefix, matching the ordered parser,
    /// so a wrapped line indents under the item text rather than the marker.
    public static func marker(in line: String) -> Marker? {
        let bullets = ["• ", "- ", "* ", "+ "]
        if let bullet = bullets.first(where: { line.hasPrefix($0) }) {
            return Marker(kind: .unordered, prefix: prefixConsumingWhitespace(in: line, from: bullet.endIndex))
        }

        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isASCII, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }

        guard !digits.isEmpty, index < line.endIndex, line[index] == "." else {
            return nil
        }
        let whitespaceStart = line.index(after: index)
        guard whitespaceStart < line.endIndex,
              line[whitespaceStart].isWhitespace else {
            return nil
        }
        let prefix = prefixConsumingWhitespace(in: line, from: line.index(after: whitespaceStart))

        guard let number = parsedNumber(digits) else { return nil }
        return Marker(
            kind: .ordered,
            number: number,
            prefix: prefix
        )
    }

    /// `from` is the first character after the required marker whitespace.
    private static func prefixConsumingWhitespace(in line: String, from start: String.Index) -> String {
        var end = start
        while end < line.endIndex, line[end].isWhitespace {
            end = line.index(after: end)
        }
        return String(line[..<end])
    }

    public static func isEmptyItem(in line: String, marker: Marker) -> Bool {
        let contentStart = line.index(line.startIndex, offsetBy: marker.prefix.count)
        return line[contentStart...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Produces the marker for the following item while retaining the typed
    /// unordered prefix.
    public static func nextMarker(after marker: Marker) -> String {
        switch marker.kind {
        case .unordered:
            return marker.prefix
        case .ordered:
            let nextNumber: Int
            if let number = marker.number {
                nextNumber = number == Int.max ? Int.max : number + 1
            } else {
                nextNumber = 1
            }
            return "\(nextNumber). "
        }
    }

    private static func parsedNumber(_ digits: String) -> Int? {
        var number = 0
        for scalar in digits.unicodeScalars {
            guard scalar.value >= 48, scalar.value <= 57 else { return nil }
            let digit = Int(scalar.value - 48)
            let (shifted, shiftOverflow) = number.multipliedReportingOverflow(by: 10)
            let (result, addOverflow) = shifted.addingReportingOverflow(digit)
            guard !shiftOverflow, !addOverflow else { return nil }
            number = result
        }
        return number
    }
}
