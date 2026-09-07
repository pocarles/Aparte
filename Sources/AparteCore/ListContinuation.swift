import Foundation

/// The small amount of list syntax needed by the editor's Return key behavior.
///
/// The editor stores list membership as an attribute, but pasted or newly typed
/// text can also have a visible Markdown-style marker before that attribute is
/// present. Keeping the parser here makes those decisions independent of AppKit.
public enum ListContinuation {
    public struct Marker: Equatable, Sendable {
        public let kind: AparteListKind
        public let number: Int?
        public let prefix: String

        public var utf16Length: Int { prefix.utf16.count }

        public init(kind: AparteListKind, number: Int? = nil, prefix: String = "") {
            self.kind = kind
            self.number = number
            self.prefix = prefix
        }
    }

    /// Returns a marker at the beginning of `line`.
    ///
    /// When a stored list kind is supplied, a line without a visible marker is
    /// still considered a list item. This is how native attributed lists are
    /// represented by some pasteboard providers.
    public static func marker(in line: String, listKind: AparteListKind? = nil) -> Marker? {
        let visible = visibleMarker(in: line)

        guard let listKind else { return visible }
        guard let visible else {
            return Marker(kind: listKind)
        }
        guard visible.kind == listKind else {
            return Marker(kind: listKind)
        }
        return visible
    }

    public static func isEmptyItem(in line: String, marker: Marker) -> Bool {
        let contentStart = line.index(line.startIndex, offsetBy: marker.prefix.count)
        return line[contentStart...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Produces the marker for the following item while retaining a typed
    /// unordered prefix when one was present.
    public static func nextMarker(after marker: Marker) -> String {
        switch marker.kind {
        case .unordered:
            return marker.prefix.isEmpty ? "• " : marker.prefix
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

    private static func visibleMarker(in line: String) -> Marker? {
        if line.hasPrefix("• ") {
            return Marker(kind: .unordered, prefix: "• ")
        }

        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return Marker(kind: .unordered, prefix: prefix)
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

        var prefixEnd = line.index(after: whitespaceStart)
        while prefixEnd < line.endIndex, line[prefixEnd].isWhitespace {
            prefixEnd = line.index(after: prefixEnd)
        }

        guard let number = parsedNumber(digits) else { return nil }
        return Marker(
            kind: .ordered,
            number: number,
            prefix: String(line[..<prefixEnd])
        )
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
