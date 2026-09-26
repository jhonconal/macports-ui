import SwiftUI
import MacPortsUICore

/// "Dependencies" tab: layered DAG visualization of installed ports and
/// their relationships, rendered with SwiftUI Canvas. Data comes from the
/// MacPorts registry.db (via the `sqlite3` CLI); focus defaults to the
/// globally selected port.
struct GraphView: View {
    @EnvironmentObject var service: MacPortsService

    @State private var focusText = ""

    private var graph: DependencyGraph? { service.dependencyGraph }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if service.isGraphLoading {
                ProgressView("Loading registry…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if graph == nil {
                unavailable
            } else {
                graphCanvas
            }
        }
    }

    // MARK: controls

    private var controlBar: some View {
        HStack(spacing: 8) {
            TextField("Focus port", text: $focusText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit { applyFocus() }
                .onAppear { focusText = service.graphFocus ?? "" }
                .onChange(of: service.graphFocus) { focusText = $0 ?? "" }
            Button("Show", action: applyFocus)
                .disabled(focusText.isEmpty)

            Picker("Scope", selection: $service.graphScope) {
                ForEach(GraphScope.allCases, id: \.self) { s in
                    switch s {
                    case .dependencies: Text("Dependencies").tag(s)
                    case .dependents: Text("Dependents").tag(s)
                    case .both: Text("Both").tag(s)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Spacer()
            if let g = graph {
                Text("\(g.nodes.count) ports · \(g.edgeCount) edges")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Reload") { Task { await service.loadGraph() } }
                .buttonStyle(.borderless)
        }
        .padding(8)
    }

    private func applyFocus() {
        let f = focusText.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return }
        service.graphFocus = f
        service.selectedPortName = f
        Task { await service.loadDetail(for: f) }
    }

    // MARK: canvas

    @ViewBuilder
    private var graphCanvas: some View {
        let layout = graph.map { GraphLayoutEngine.layout(focus: service.graphFocus ?? "", graph: $0, scope: service.graphScope) }
        if let layout, !layout.nodes.isEmpty {
            GeometryReader { geo in
                // Auto-fit the graph into the viewport (never upscale); the
                // scroll view still allows panning when content is larger.
                let scale = min(1,
                                 geo.size.width / max(layout.size.width, 1),
                                 geo.size.height / max(layout.size.height, 1))
                ScrollView([.horizontal, .vertical]) {
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: scale, y: scale)
                        for e in layout.edges {
                            var path = Path()
                            path.move(to: e.from)
                            let control = CGPoint(x: (e.from.x + e.to.x) / 2,
                                                  y: (e.from.y + e.to.y) / 2)
                            path.addQuadCurve(to: e.to, control: control)
                            ctx.stroke(path,
                                       with: .color(e.hot ? Color.orange.opacity(0.85) : .gray.opacity(0.25)),
                                       lineWidth: e.hot ? 1.5 : 1)
                        }
                        for n in layout.nodes {
                            let rect = CGRect(x: n.x - 82, y: n.y - 12, width: 164, height: 24)
                            let bg: Color = n.isFocus ? Color.accentColor
                                : n.isDependent ? Color.teal
                                : Color.gray.opacity(0.85)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(bg.opacity(n.isFocus ? 1 : 0.85)))
                            if n.isFocus {
                                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 8),
                                           with: .color(.white.opacity(0.9)), lineWidth: 2)
                            }
                            ctx.draw(Text(n.name).font(.system(size: 11, weight: n.isFocus ? .bold : .regular)),
                                     at: CGPoint(x: n.x, y: n.y))
                        }
                    }
                    .frame(width: layout.size.width * scale, height: layout.size.height * scale)
                    .onTapGesture { location in
                        // location is in canvas space; convert to layout space.
                        let p = CGPoint(x: location.x / scale, y: location.y / scale)
                        if let hit = layout.hitTest(p) {
                            focusText = hit.name
                            applyFocus()
                        }
                    }
                    // Center small graphs inside the scroll viewport.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        } else {
            let focusLabel = service.graphFocus ?? "\u{2205}"
            let scopeWord = service.graphScope == .dependents ? "dependents" : "dependencies"
            VStack(spacing: 8) {
                Image(systemName: "point.3.dotted.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("\"\(focusLabel)\" has no \(scopeWord) among installed ports.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Try a different focus, or another scope.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("Dependency graph unavailable (registry.db or sqlite3 not found).").foregroundStyle(.secondary)
            Button("Retry") { Task { await service.loadGraph() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - hit test helper

extension GraphLayout {
    /// Nearest placed node within a small radius of `p`, or nil.
    func hitTest(_ p: CGPoint) -> PlacedNode? {
        let nearest = nodes.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }
        guard let n = nearest,
              hypot(n.x - p.x, n.y - p.y) < 100 else { return nil }
        return n
    }
}
