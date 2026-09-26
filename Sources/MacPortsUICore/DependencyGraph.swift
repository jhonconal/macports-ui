import Foundation

// MARK: - Dependency graph model + provider

/// An installed-ports dependency graph.
/// - `forward[port]` = the dependencies `port` needs.
/// - `reverse[dep]`  = the installed ports that depend on `dep`.
public struct DependencyGraph: Sendable {
    public var nodes: Set<String>
    public var forward: [String: Set<String>]
    public var reverse: [String: Set<String>]

    public init(nodes: Set<String>,
                forward: [String: Set<String>],
                reverse: [String: Set<String>]) {
        self.nodes = nodes; self.forward = forward; self.reverse = reverse
    }

    public var edgeCount: Int {
        forward.values.reduce(0) { $0 + $1.count }
    }

    /// All (src, dst) edges where src depends on dst.
    public var edges: [(src: String, dst: String)] {
        forward.flatMap { src, deps in
            deps.map { (src, $0) }
        }
    }
}

/// Builds the installed dependency graph by reading MacPorts' SQLite
/// `registry.db` through the `sqlite3` CLI (`-json`). Read-only; no elevation
/// and no Swift C binding (which the current CLT SDK can't build).
public enum GraphProvider {
    public static let registryDB = MacPortsLocator.defaultRegistryDB
    public static let sqlite3Path = MacPortsLocator.defaultSqlite3Path

    /// Returns true when the pieces needed to read the registry are present.
    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: sqlite3Path) &&
        FileManager.default.fileExists(atPath: registryDB)
    }

    /// Loads the full installed graph.
    public static func loadInstalledGraph() throws -> DependencyGraph {
        let nodes = try ProcessSpawner.run(
            executable: sqlite3Path,
            arguments: ["-json", registryDB, "SELECT name FROM ports;"])
        let edges = try ProcessSpawner.run(
            executable: sqlite3Path,
            arguments: ["-json", registryDB,
                        "SELECT p.name AS src, d.name AS dst " +
                        "FROM dependencies d JOIN ports p ON p.id=d.id;"])
        return parseGraph(nodesJSON: nodes.stdout, edgesJSON: edges.stdout)
    }

    /// Pure, testable parse of two `sqlite3 -json` outputs into a graph.
    /// Edges whose destination is not an installed port are dropped so the
    /// graph stays closed over the installed node set.
    public static func parseGraph(nodesJSON: String, edgesJSON: String) -> DependencyGraph {
        let nodeSet = Set(nameArray(nodesJSON))
        let edgePairs = objectArray(edgesJSON).compactMap { o -> (String, String)? in
            guard let s = o["src"] as? String, let d = o["dst"] as? String else { return nil }
            return (s, d)
        }
        var forward: [String: Set<String>] = [:]
        var reverse: [String: Set<String>] = [:]
        for (src, dst) in edgePairs {
            guard nodeSet.contains(src), nodeSet.contains(dst) else { continue }
            forward[src, default: []].insert(dst)
            reverse[dst, default: []].insert(src)
        }
        return DependencyGraph(nodes: nodeSet, forward: forward, reverse: reverse)
    }

    // JSON helpers (JSONSerialization over a `sqlite3 -json` document).
    private static func objectArray(_ text: String) -> [[String: Any]] {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    private static func nameArray(_ text: String) -> [String] {
        objectArray(text).compactMap { $0["name"] as? String }
    }
}

// MARK: - Layout engine

/// A placed node / edge for rendering.
public struct GraphLayout: Sendable {
    public struct PlacedNode: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let level: Int        // forward deps: >=0 (0 = focus); dependents: <0
        public let x: CGFloat
        public let y: CGFloat
        public let isFocus: Bool
        public let isDependent: Bool // on the "who depends on me" side
    }
    public struct PlacedEdge: Identifiable, Sendable {
        public let id: String
        public let from: CGPoint    // depender (parent)
        public let to: CGPoint      // dependency (child)
        public let hot: Bool        // part of the focus closure
    }
    public let nodes: [PlacedNode]
    public let edges: [PlacedEdge]
    public let size: CGSize
}

public enum GraphScope: String, CaseIterable, Sendable {
    case dependencies   // focus + what it needs
    case dependents     // focus + what needs it
    case both
}

/// Computes a layered (left-to-right by dependency depth) layout.
public enum GraphLayoutEngine {

    /// Positions `focus` at level 0, forward dependencies at increasing
    /// positive levels, and (when requested) dependents at negative levels.
    public static func layout(focus: String, graph: DependencyGraph,
                             scope: GraphScope) -> GraphLayout {
        // Unknown focus → nothing to lay out (the UI shows a hint instead).
        guard graph.nodes.contains(focus) else {
            return GraphLayout(nodes: [], edges: [], size: CGSize(width: 0, height: 0))
        }
        let colW: CGFloat = 190
        let rowH: CGFloat = 46
        let margin: CGFloat = 24
        let labelH: CGFloat = 24

        var level: [String: Int] = [focus: 0]

        func bfs(_ adjacency: [String: Set<String>], from start: String, sign: Int) {
            var frontier = [start]
            var seen: Set<String> = [start]
            var dist = 1
            while !frontier.isEmpty {
                var next: [String] = []
                for node in frontier {
                    for neighbor in adjacency[node] ?? [] {
                        guard seen.insert(neighbor).inserted else { continue }
                        level[neighbor] = sign * dist
                        next.append(neighbor)
                    }
                }
                dist += 1
                frontier = next
            }
        }

        if scope == .dependencies || scope == .both {
            bfs(graph.forward, from: focus, sign: +1)
        }
        if scope == .dependents || scope == .both {
            bfs(graph.reverse, from: focus, sign: -1)
        }

        // Group by level, keep a stable order.
        var byLevel: [Int: [String]] = [:]
        for (name, l) in level {
            byLevel[l, default: []].append(name)
        }
        for l in byLevel.keys {
            byLevel[l]?.sort()
        }

        // Assign coordinates. Every level column shares one centerline
        // (y = 0) so the DAG reads left→right; then the whole content is
        // shifted so its top-left lands at `margin` (no negative coords).
        let nodeHalfW: CGFloat = 82 // half width of the node rect
        var raw: [String: (name: String, level: Int, x: CGFloat, y: CGFloat)] = [:]
        let minLevel = byLevel.keys.min() ?? 0
        for (l, names) in byLevel {
            let x = CGFloat(l - minLevel) * colW + margin + colW / 2
            let total = CGFloat(names.count) * rowH
            for (i, name) in names.enumerated() {
                let y = total / 2 - CGFloat(i) * rowH - rowH / 2
                raw[name] = (name, l, x, y)
            }
        }
        let minYRaw = raw.values.map { $0.y }.min() ?? 0
        let shiftY = margin - minYRaw

        var placed: [String: GraphLayout.PlacedNode] = [:]
        for (name, t) in raw {
            placed[name] = GraphLayout.PlacedNode(
                id: name, name: t.name, level: t.level,
                x: t.x, y: t.y + shiftY,
                isFocus: t.name == focus,
                isDependent: t.level < 0)
        }

        // Edges between placed nodes, drawn rect-edge to rect-edge.
        var edges: [GraphLayout.PlacedEdge] = []
        for e in graph.edges {
            guard let a = placed[e.src], let b = placed[e.dst] else { continue }
            // Draw from the depender (src) toward its dependency (dst).
            let from = CGPoint(x: a.x + nodeHalfW, y: a.y)
            let to   = CGPoint(x: b.x - nodeHalfW, y: b.y)
            let hot = level[e.src] != nil && level[e.dst] != nil
            edges.append(GraphLayout.PlacedEdge(id: "\(e.src)->\(e.dst)",
                                                from: from, to: to, hot: hot))
        }

        // Bounds (content is now guaranteed to start at `margin`).
        let xs = placed.values.map { $0.x }
        let ys = placed.values.map { $0.y }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let size = CGSize(width: (maxX - minX) + colW + margin * 2,
                          height: (maxY - minY) + labelH + margin * 2)

        let nodes = placed.values.sorted { ($0.level, $0.y) < ($1.level, $1.y) }
        return GraphLayout(nodes: nodes, edges: edges, size: size)
    }
}
