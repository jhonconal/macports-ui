import Foundation

/// Pure, side-effect-free parsers for `port` command output.
///
/// These are isolated so they can be unit-tested against captured real
/// `port` output without touching the filesystem or launching processes.
public enum PortOutputParser {

    // MARK: - port installed

    /// Parses the output of `port installed` / `port installed -q`.
    ///
    /// Each port line looks like:
    ///   `  curl @8.22.0_0+brotli+http2+idn+psl+ssl+zstd (active)`
    /// The token after `@` may carry `+variant` suffixes.
    public static func parseInstalled(_ text: String) -> [InstalledPort] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*(\S+) @(\S+?)\s*\((\w+)\)\s*$"#)
        var result: [InstalledPort] = []
        for raw in text.components(separatedBy: .newlines) {
            guard let g = groups(regex, raw),
                  let name = g[1], let versionToken = g[2], let state = g[3]
            else { continue }
            let parts = versionToken.components(separatedBy: "+")
            let version = parts.first ?? versionToken
            let variants = Array(parts.dropFirst())
            result.append(InstalledPort(name: name, version: version,
                                       variants: variants, state: state))
        }
        return result
    }

    // MARK: - port outdated

    /// Parses `port outdated`. Lines look like:
    ///   `  sqlite3 @3.44.0_0 (available: 3.45.0_0)`
    public static func parseOutdated(_ text: String) -> [OutdatedPort] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*(\S+) @(\S+?)\s*\(available:\s*(\S+)\)\s*$"#)
        var result: [OutdatedPort] = []
        for raw in text.components(separatedBy: .newlines) {
            guard let g = groups(regex, raw),
                  let name = g[1], let installed = g[2], let available = g[3]
            else { continue }
            result.append(OutdatedPort(name: name,
                                       installedVersion: installed,
                                       availableVersion: available))
        }
        return result
    }

    // MARK: - port search

    /// Parses `port search <term>`. Each entry is:
    ///   `name @version (cat, cat)`
    ///   `optional summary line(s)`
    ///   (blank line or next entry)
    public static func parseSearch(_ text: String) -> [SearchHit] {
        let headerRegex = try! NSRegularExpression(
            pattern: #"^(\S+) @(\S+?)\s*\(([^)]*)\)\s*$"#)
        var hits: [SearchHit] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let g = groups(headerRegex, line),
               let name = g[1], let version = g[2], let cats = g[3] {
                let categories = cats
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                hits.append(SearchHit(name: name, version: version,
                                      categories: categories, summary: ""))
            } else if let last = hits.indices.last {
                var summary = hits[last].summary
                if !summary.isEmpty { summary += " " }
                summary += line
                hits[last].summary = summary
            }
        }
        return hits
    }

    // MARK: - port info

    /// Parses `port info <name>` into a `PortDetail`.
    public static func parseInfo(_ text: String) -> PortDetail? {
        let lines = text.components(separatedBy: .newlines)
        var name = "", version = "", categories: [String] = []
        var subports: [String] = []
        var variantsAll: [String] = []
        var variantsEnabled: [String] = []
        var extract: [String] = [], build: [String] = [], lib: [String] = []
        var homepage: String?
        var summaryLines: [String] = []
        var inDescription = false

        let headerRegex = try! NSRegularExpression(
            pattern: #"^(\S+) @(\S+?)\s*\(([^)]*)\)\s*$"#)

        func list(_ s: String) -> [String] {
            s.components(separatedBy: ",")
             .map { $0.trimmingCharacters(in: .whitespaces) }
             .filter { !$0.isEmpty }
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if name.isEmpty,
               let g = groups(headerRegex, line),
               let n = g[1] {
                name = n
                version = g[2] ?? ""
                categories = list(g[3] ?? "")
                continue
            }
            switch true {
            case line.hasPrefix("Sub-ports:"):
                subports = list(tail(line, "Sub-ports:"))
            case line.hasPrefix("Variants:"):
                let v = list(tail(line, "Variants:"))
                variantsAll = v.map(variantBase)
                variantsEnabled = v.filter { $0.hasPrefix("[+]") }.map(variantBase)
            case line.hasPrefix("Description:"):
                inDescription = true
                let rest = tail(line, "Description:")
                if !rest.isEmpty { summaryLines.append(rest) }
            case line.hasPrefix("Homepage:"):
                homepage = tail(line, "Homepage:")
            case line.hasPrefix("Extract Dependencies:"):
                extract = list(tail(line, "Extract Dependencies:"))
            case line.hasPrefix("Build Dependencies:"):
                build = list(tail(line, "Build Dependencies:"))
            case line.hasPrefix("Library Dependencies:"):
                lib = list(tail(line, "Library Dependencies:"))
            case line.hasPrefix("Platforms:"),
                 line.hasPrefix("License:"),
                 line.hasPrefix("Maintainers:"):
                inDescription = false
            default:
                if inDescription && !line.isEmpty {
                    summaryLines.append(line)
                }
            }
        }

        guard !name.isEmpty else { return nil }
        return PortDetail(name: name, version: version, categories: categories,
                          summary: summaryLines.joined(separator: " "),
                          homepage: homepage, subports: subports,
                          variantsEnabled: variantsEnabled, variantsAll: variantsAll,
                          extractDeps: extract, buildDeps: build, libraryDeps: lib)
    }

    /// Strips the optional `[+]` marker from a variant token.
    public static func variantBase(_ token: String) -> String {
        token.hasPrefix("[+]") ? String(token.dropFirst(3)) : token
    }

    // MARK: - macports.conf

    /// Parses a MacPorts configuration file (`macports.conf` / `sources.conf`)
    /// into a `[key: value]` map. Lines are `key<whitespace>value` (values may
    /// contain spaces, joined back with a single space); blank lines and whole
    /// `#` comment lines are skipped.
    public static func parseMacportsConf(_ text: String) -> [String: String] {
        var d: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(omittingEmptySubsequences: true,
                                   whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            d[String(parts[0])] = parts.dropFirst().joined(separator: " ")
        }
        return d
    }

    // MARK: - port diskusage

    /// Extracts total bytes from `port diskusage <name>` output.
    public static func parseDiskUsageBytes(_ text: String) -> Int64? {
        guard let g = groups(try! NSRegularExpression(pattern: #"\b(\d{3,})\b"#),
                             text) else { return nil }
        return g[1].flatMap(Int64.init)
    }

    // MARK: - helpers

    /// Returns the captured groups (0 = full match) of the first match of
    /// `regex` in `s`, or `nil` when there is no match. A non-participating
    /// group is `nil`.
    private static func groups(_ regex: NSRegularExpression, _ s: String) -> [String?]? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = regex.firstMatch(in: s, options: [], range: range) else { return nil }
        var out: [String?] = []
        out.reserveCapacity(m.numberOfRanges)
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound {
                out.append(nil)
            } else if let sr = Range(r, in: s) {
                out.append(String(s[sr]))
            } else {
                out.append(nil)
            }
        }
        return out
    }

    /// Drops a `Label:` prefix and trims surrounding whitespace.
    private static func tail(_ line: String, _ label: String) -> String {
        guard line.hasPrefix(label) else { return "" }
        return String(line.dropFirst(label.count))
            .trimmingCharacters(in: .whitespaces)
    }
}
