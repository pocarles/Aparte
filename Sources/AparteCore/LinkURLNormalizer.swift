import Foundation

public enum LinkURLNormalizer {
    public static func normalize(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        let hasWebScheme = trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://")

        if trimmed.range(
            of: "^[A-Za-z][A-Za-z0-9+.-]*:",
            options: .regularExpression
        ) != nil, !hasWebScheme {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host,
            !host.isEmpty
        else {
            return nil
        }
        guard hasWebScheme || host.contains(".") else { return nil }
        return components.url
    }
}
