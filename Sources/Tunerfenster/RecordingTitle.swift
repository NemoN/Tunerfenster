import Foundation

enum RecordingTitle {
    static func withoutFolderPrefix(_ title: String, folders: [String]) -> String {
        let names = folders.compactMap(singleLine).sorted { $0.count > $1.count }
        var result = title
        while true {
            var removed = false
            for name in names {
                guard let prefix = result.range(of: name, options: [.anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: comparisonLocale) else { continue }
                let tail = result[prefix.upperBound...].trimmingCharacters(in: .whitespaces)
                guard let separator = tail.first, ":–—-".contains(separator) else { continue }
                let suffix = tail.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !suffix.isEmpty else { continue }
                result = suffix
                removed = true
                break
            }
            if !removed { return result }
        }
    }

    static func display(_ title: String, subtitle: String?, detail: String?) -> String {
        guard let base = singleLine(title), !words(base).isEmpty else { return title }
        let fields = Metadata(detail)
        let baseWords = words(base)
        let isSeriesTitle = fields.series.contains { words($0) == baseWords }

        // A different series label means the existing title is already more
        // specific (or inconsistent). Preserve it rather than replacing it.
        guard fields.series.isEmpty || isSeriesTitle else { return title }

        for candidate in fields.episodes + [subtitle].compactMap({ $0 }) {
            guard let candidate = singleLine(candidate), !isMetadata(candidate, genres: fields.genres) else { continue }
            let candidateWords = words(candidate)
            guard !candidateWords.isEmpty, candidateWords != baseWords else { continue }
            if contains(baseWords, candidateWords) { return title }

            let repeatsSeries = candidateWords.starts(with: baseWords)
            let suffix = removingPrefix(from: candidate, title: base, words: baseWords)
            guard !suffix.isEmpty, words(suffix) != baseWords, !isMetadata(suffix, genres: fields.genres) else { continue }

            // A separator may introduce an existing episode title. Extend these
            // only when metadata identifies the base as the series, or the
            // subtitle itself supplies the full series/episode title.
            if !isSeriesTitle && !repeatsSeries && base.range(of: #"[:–—]|\s-\s"#, options: .regularExpression) != nil {
                return title
            }
            return "\(base): \(suffix)"
        }
        return title
    }

    private struct Metadata {
        var series = [String]()
        var episodes = [String]()
        var genres = [String]()

        init(_ detail: String?) {
            // Only named fields count; prose is never guessed to be a title.
            for line in detail?.components(separatedBy: .newlines) ?? [] {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, let value = singleLine(String(parts[1])) else { continue }
                switch words(String(parts[0])).joined(separator: " ") {
                case "serie", "series", "serientitel", "series title": series.append(value)
                case "episode", "folgentitel", "episodentitel", "episode title": episodes.append(value)
                case "genre", "genres", "kategorie", "category": genres.append(value)
                default: break
                }
            }
        }
    }

    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}\p{M}]+"#)
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    private static func words(_ value: String) -> [String] {
        let text = value as NSString
        return wordPattern.matches(in: value, range: NSRange(location: 0, length: text.length)).map {
            text.substring(with: $0.range).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: comparisonLocale)
        }
    }

    private static func contains(_ title: [String], _ episode: [String]) -> Bool {
        guard !episode.isEmpty, episode.count <= title.count else { return false }
        return (0...(title.count - episode.count)).contains { start in
            Array(title[start..<(start + episode.count)]) == episode
        }
    }

    private static func removingPrefix(from candidate: String, title: String, words base: [String]) -> String {
        let titleText = title as NSString
        let titleMatches = wordPattern.matches(in: title, range: NSRange(location: 0, length: titleText.length))
        let ending = titleText.substring(from: NSMaxRange(titleMatches.last!.range)).trimmingCharacters(in: .whitespaces)
        var suffix = candidate
        while words(suffix).starts(with: base), words(suffix).count > base.count {
            let text = suffix as NSString
            let matches = wordPattern.matches(in: suffix, range: NSRange(location: 0, length: text.length))
            suffix = text.substring(from: NSMaxRange(matches[base.count - 1].range))
                .trimmingCharacters(in: .whitespaces)
            if !ending.isEmpty && suffix.hasPrefix(ending) { suffix.removeFirst(ending.count) }
            suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":–—-")))
        }
        return suffix
    }

    private static let genreWords = Set("""
        krimi krimireihe krimiserie kriminalfilm kriminalserie fernsehfilm spielfilm film filme serie serien reihe
        dokumentation dokumentar dokumentarfilm dokumentarserie dokumentationsreihe dokumentationsserie doku dokureihe dokuserie
        reportage magazin wissensmagazin komodie action actionfilm actionthriller thriller drama dramareihe dramaserie
        abenteuer abenteuerfilm liebesfilm romantik fantasy science fiction sci fi animation animationsfilm anime cartoon
        kinderfilm kinderserie kindersendung unterhaltung infotainment nachrichten musik sport sportmagazin talk talkshow
        show gameshow spielshow reality realityshow soap sitcom zeichentrick zeichentrickserie zeichentrickfilm
        crime criminal comedy documentary documentaries movie movies series serial tv television feature entertainment
        romance romantic adventure mystery news sports history historical nature natur science soap opera game lifestyle
        genre genres kategorie category hd stereo min minuten minutes
        """.split(whereSeparator: \.isWhitespace).map(String.init))
    private static let origins = Set(Locale.Region.isoRegions.map { $0.identifier.lowercased() }).union([
        "d", "usa", "deu", "ger", "gbr", "uk", "deutschland", "germany", "osterreich", "austria", "schweiz", "switzerland",
        "frankreich", "france", "britannien", "britain", "united", "kingdom", "states", "kanada", "canada", "italien", "italy",
        "german", "deutsch", "deutsche", "deutscher", "british", "britisch", "britische", "britischer", "english",
        "american", "amerikanisch", "amerikanische", "amerikanischer", "french", "franzosisch", "franzosische"
    ])

    private static func isMetadata(_ value: String, genres: [String]) -> Bool {
        // Broadcaster subtitles often contain just genre, origin and year.
        // Named Genre fields extend the vocabulary for server-specific genres.
        let separated = value.replacingOccurrences(of: #"(?<=\p{L})(?=\d{4}\b)"#, with: " ", options: .regularExpression)
        let tokens = words(separated)
        let knownGenres = genreWords.union(genres.flatMap(words))
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { token in
            isGenreWord(token, known: knownGenres) || origins.contains(token) ||
                (!token.isEmpty && token.count <= 4 && token.allSatisfy(\.isNumber))
        }
    }

    private static func isGenreWord(_ token: String, known: Set<String>) -> Bool {
        if known.contains(token) { return true }
        return ["serie", "series", "reihe", "film", "show", "magazin", "sendung", "doku", "drama"].contains { suffix in
            token.hasSuffix(suffix) && known.contains(String(token.dropLast(suffix.count)))
        }
    }

    private static func singleLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return trimmed
    }
}
