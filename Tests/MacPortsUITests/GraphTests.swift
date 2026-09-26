import Testing
@testable import MacPortsUICore

/// Graph provider parsing + layout engine tests (pure, no I/O).
@Suite struct GraphTests {

    // MARK: parseGraph

    @Test func parsesNodesAndEdges() {
        let nodes = """
        [{"name":"curl"},{"name":"zlib"},{"name":"openssl"},{"name":"host-only"}]
        """
        let edges = """
        [{"src":"curl","dst":"zlib"},{"src":"curl","dst":"openssl"},
         {"src":"openssl","dst":"zlib"},{"src":"curl","dst":"ghost"}]
        """
        let g = GraphProvider.parseGraph(nodesJSON: nodes, edgesJSON: edges)
        #expect(g.nodes == Set(["curl", "zlib", "openssl", "host-only"]))
        // "ghost" is not installed → edge dropped.
        #expect(g.forward["curl"] == Set(["zlib", "openssl"]))
        #expect(g.reverse["zlib"] == Set(["curl", "openssl"]))
        #expect(g.edgeCount == 3)
    }

    @Test func emptyGraphFromEmptyJSON() {
        let g = GraphProvider.parseGraph(nodesJSON: "[]", edgesJSON: "[]")
        #expect(g.nodes.isEmpty)
        #expect(g.edgeCount == 0)
    }

    @Test func garbageJSONYieldsEmptyGraph() {
        let g = GraphProvider.parseGraph(nodesJSON: "not json", edgesJSON: "also not")
        #expect(g.nodes.isEmpty)
        #expect(g.edgeCount == 0)
    }

    // MARK: layout engine

    private func smallGraph() -> DependencyGraph {
        GraphProvider.parseGraph(
            nodesJSON: """
            [{"name":"app"},{"name":"lib"},{"name":"base"},{"name":"other"}]
            """,
            edgesJSON: """
            [{"src":"app","dst":"lib"},{"src":"lib","dst":"base"},
             {"src":"other","dst":"lib"}]
            """)
    }

    @Test func forwardScopeLevels() {
        let layout = GraphLayoutEngine.layout(focus: "app", graph: smallGraph(),
                                              scope: .dependencies)
        let names = Set(layout.nodes.map(\.name))
        // app + lib + base, not "other" (a dependent, not a dependency).
        #expect(names == Set(["app", "lib", "base"]))
        func level(_ n: String) -> Int {
            layout.nodes.first { $0.name == n }!.level
        }
        #expect(level("app") == 0)
        #expect(level("lib") == 1)
        #expect(level("base") == 2)
    }

    @Test func reverseScopeIncludesDependents() {
        let layout = GraphLayoutEngine.layout(focus: "lib", graph: smallGraph(),
                                              scope: .dependents)
        let names = Set(layout.nodes.map(\.name))
        #expect(names == Set(["lib", "app", "other"]))
        let negative = layout.nodes.filter { $0.level < 0 }.map(\.name).sorted()
        #expect(negative == ["app", "other"])
    }

    @Test func bothScopeCombinesSides() {
        let layout = GraphLayoutEngine.layout(focus: "lib", graph: smallGraph(),
                                              scope: .both)
        let names = Set(layout.nodes.map(\.name))
        #expect(names == Set(["lib", "app", "other", "base"]))
    }

    @Test func edgesConnectPlacedNodesOnly() {
        let layout = GraphLayoutEngine.layout(focus: "app", graph: smallGraph(),
                                              scope: .dependencies)
        // All edge endpoints must be within the layout bounds and hot.
        for e in layout.edges {
            #expect(e.hot)
        }
        #expect(layout.edges.count == 2) // app->lib, lib->base
    }

    @Test func unknownFocusYieldsEmptyLayout() {
        let layout = GraphLayoutEngine.layout(focus: "nope", graph: smallGraph(),
                                              scope: .dependencies)
        #expect(layout.nodes.isEmpty)
    }
}
