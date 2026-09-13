import Foundation

public enum MarkdownFileExporter {
    public static func suggestedBaseName(for markdown: String) -> String {
        guard let firstLine = markdown
            .split(whereSeparator: \Character.isNewline)
            .map({ String($0).trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else {
            return "Aparte"
        }

        var name = firstLine.replacingOccurrences(
            of: "^(#{1,6}|[-*+]|[0-9]+\\.)\\s+",
            with: "",
            options: .regularExpression
        )
        for marker in ["**", "__", "*", "_", "`", "<u>", "</u>"] {
            name = name.replacingOccurrences(of: marker, with: "")
        }
        name = name.replacingOccurrences(of: "/", with: "-")
        name = name.replacingOccurrences(of: ":", with: "-")
        name = name.components(separatedBy: .controlCharacters).joined()
        name = name.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        name = String(name.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return name.isEmpty ? "Aparte" : name
    }
}
