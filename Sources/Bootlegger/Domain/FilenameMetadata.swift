import Foundation

/// Conservative filename suggestions never replace metadata already supplied by the user.
enum FilenameMetadata {
    static func albumTitle(from url: URL) -> String {
        let original = url.deletingPathExtension().lastPathComponent
        var name = original
        // Preserve dotted names such as R.E.M. while treating other punctuation as separators.
        if let pattern = try? NSRegularExpression(pattern: #"\b(?:[A-Za-z]\.){2,}(?:[A-Za-z])?"#) {
            for match in pattern.matches(in: name, range: NSRange(name.startIndex..., in: name)).reversed() {
                if let range = Range(match.range, in: name) {
                    name.replaceSubrange(
                        range, with: name[range].replacingOccurrences(of: ".", with: "\u{E000}"))
                }
            }
        }
        name = name.replacingOccurrences(of: #"[_\-.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\u{E000}", with: ".")
        let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let minorWords: Set<String> = [
            "a", "an", "and", "as", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to", "with",
        ]
        let acronyms: Set<String> = [
            "AC", "DC", "DJ", "MC", "BBC", "MTV", "U2", "ABBA", "INXS", "NOFX", "NIN", "REM", "R.E.M.", "ELO",
            "LCD", "UK", "US", "USA", "II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII",
        ]
        return words.enumerated().map { index, word in
            if acronyms.contains(word.uppercased()) { return word.uppercased() }
            let hasInteriorUppercase = word.dropFirst().contains(where: { $0.isUppercase })
            if hasInteriorUppercase && word.contains(where: { $0.isLowercase }) { return word }
            let lower = word.lowercased()
            if index > 0 && index < words.count - 1 && minorWords.contains(lower) { return lower }
            return lower.capitalized(with: Locale(identifier: "en_US_POSIX"))
        }.joined(separator: " ")
    }

    static func year(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let pattern = try? NSRegularExpression(pattern: #"(?<![0-9])(?:19|20)[0-9]{2}(?![0-9])"#),
            let match = pattern.matches(in: name, range: NSRange(name.startIndex..., in: name)).last,
            let range = Range(match.range, in: name)
        else { return nil }
        return String(name[range])
    }
}
