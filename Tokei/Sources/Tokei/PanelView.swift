import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var store: Store
    @State private var sel: RangeKey = .today
    @State private var claudeModelsOpen = false
    @State private var geminiModelsOpen = false
    @State private var settingsOpen = false
    @AppStorage("showClaude") private var showClaude = true
    @AppStorage("showCodex") private var showCodex = true
    @AppStorage("showGemini") private var showGemini = true
    @AppStorage("showGrok") private var showGrok = true

    private var visibleCount: Int {
        [showClaude, showCodex, showGemini, showGrok].filter { $0 }.count
    }
    private var useWide: Bool { visibleCount > 2 }
    private var panelWidth: CGFloat { useWide ? 640 : Theme.panelWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if let u = store.usage {
                SegmentedTabs(sel: $sel)
                if useWide {
                    HStack(alignment: .top, spacing: 13) {
                        VStack(alignment: .leading, spacing: 13) {
                            if showClaude { Card(tint: Theme.claude) { claudeBlock(u.claude, u.claude.ranges.get(sel)) } }
                            if showCodex  { Card(tint: Theme.codex)  { codexBlock(u.codex, u.codex.ranges.get(sel)) } }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 13) {
                            if showGemini { Card(tint: Theme.gemini) { geminiBlock(u.gemini.ranges.get(sel)) } }
                            if showGrok   { Card(tint: Theme.grok)   { grokBlock(u.grok.ranges.get(sel), model: u.grok.model) } }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    if showClaude { Card(tint: Theme.claude) { claudeBlock(u.claude, u.claude.ranges.get(sel)) } }
                    if showCodex  { Card(tint: Theme.codex)  { codexBlock(u.codex, u.codex.ranges.get(sel)) } }
                    if showGemini { Card(tint: Theme.gemini) { geminiBlock(u.gemini.ranges.get(sel)) } }
                    if showGrok   { Card(tint: Theme.grok)   { grokBlock(u.grok.ranges.get(sel), model: u.grok.model) } }
                }
            } else {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 90)
            }
            footer
        }
        .padding(Theme.outerPad)
        .frame(width: panelWidth)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - 品牌头部
    var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 0) {
                Text("Tokei")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(0.5)
                Text("时计 · AI 用量")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tTertiary)
            }
            Spacer()
            Text(store.lastUpdated)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.tTertiary)
            Button { settingsOpen.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tTertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $settingsOpen, arrowEdge: .bottom) { settingsContent }
        }
    }

    // MARK: - Claude 卡片
    @ViewBuilder
    func claudeBlock(_ c: ClaudeStat, _ r: ClaudeRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Claude Code", tint: Theme.claude, hit: r.hit)
            CostHeadline(cost: r.cost, caption: "\(sel.label) ≈成本", tint: Theme.claude)
            sessionCountRow(r.sessions, tint: Theme.claude)
            metricGrid([
                (.init("arrow.down", "输入", Fmt.human(r.in))),
                (.init("arrow.up", "输出", Fmt.human(r.out))),
                (.init("bolt.fill", "缓存读", Fmt.human(r.cr))),
                (.init("square.stack.3d.up.fill", "缓存写", Fmt.human(r.cw))),
            ], tint: Theme.claude)
            if !r.models.isEmpty {
                modelDisclosure(r.models.map { ModelRow(name: $0.name, pin: $0.pin, pout: $0.pout, cost: $0.cost) },
                                open: $claudeModelsOpen, tint: Theme.claude)
            }
            if c.q5 != nil || c.q7 != nil { thinDivider }
            if let q5 = c.q5 {
                quotaRow(title: "5h 剩余", pct: 100 - q5, reset: c.q5_reset, tint: Theme.claude)
            }
            if let q7 = c.q7 {
                quotaRow(title: "周剩余", pct: 100 - q7, reset: c.q7_reset, tint: Theme.claude)
            }
            disclaimer
        }
    }

    // MARK: - Codex 卡片
    @ViewBuilder
    func codexBlock(_ x: CodexStat, _ r: CodexRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Codex", tint: Theme.codex, hit: r.hit)
            CostHeadline(cost: r.cost, caption: "\(sel.label) ≈成本", tint: Theme.codex)
            sessionCountRow(r.sessions, tint: Theme.codex)
            metricGrid({
                var items: [Metric] = [
                    .init("arrow.down", "输入", Fmt.human(r.in)),
                    .init("bolt.fill", "缓存读", Fmt.human(r.cached)),
                    .init("arrow.up", "输出", Fmt.human(r.out)),
                ]
                if r.reason > 0 { items.append(.init("brain", "推理", Fmt.human(r.reason))) }
                return items
            }(), tint: Theme.codex)
            if x.p5 != nil || x.pw != nil { thinDivider }
            if let p5 = x.p5 {
                quotaRow(title: "5h 剩余", pct: 100 - p5, reset: x.r5, tint: Theme.codex)
            }
            if let pw = x.pw {
                quotaRow(title: "周剩余", pct: 100 - pw, reset: x.rw, tint: Theme.codex)
            }
            if let plan = x.plan {
                HStack {
                    Text("plan").font(.system(size: 11)).foregroundStyle(Theme.tTertiary)
                    Spacer()
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.tSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.codex.opacity(0.16)))
                }
            }
            disclaimer
        }
    }

    // MARK: - Gemini 卡片(完整成本卡,无配额)
    @ViewBuilder
    func geminiBlock(_ r: GeminiRange) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHead("Gemini CLI", tint: Theme.gemini, hit: r.hit)
            CostHeadline(cost: r.cost, caption: "\(sel.label) ≈成本", tint: Theme.gemini)
            sessionCountRow(r.sessions, tint: Theme.gemini)
            metricGrid({
                var items: [Metric] = [
                    .init("arrow.down", "输入", Fmt.human(r.in)),
                    .init("arrow.up", "输出", Fmt.human(r.out)),
                    .init("bolt.fill", "缓存", Fmt.human(r.cached)),
                ]
                if r.thoughts > 0 { items.append(.init("brain", "推理", Fmt.human(r.thoughts))) }
                return items
            }(), tint: Theme.gemini)
            if !r.models.isEmpty {
                modelDisclosure(r.models.map { ModelRow(name: $0.name, pin: $0.pin, pout: $0.pout, cost: $0.cost) },
                                open: $geminiModelsOpen, tint: Theme.gemini)
            }
            disclaimer
        }
    }

    // MARK: - Grok 卡片(降级:仅上下文 token,不估成本)
    @ViewBuilder
    func grokBlock(_ r: GrokRange, model: String?) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHeadPlain("Grok CLI", tint: Theme.grok)
            sessionCountRow(r.sessions, tint: Theme.grok)
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.grok)
                Text("累计上下文")
                    .font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
                Spacer(minLength: 6)
                Text(Fmt.human(r.tokens))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.tPrimary)
                    .contentTransition(.numericText())
                Text("token").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
            }
            if let model, !model.isEmpty {
                HStack {
                    Text("model").font(.system(size: 11)).foregroundStyle(Theme.tTertiary)
                    Spacer()
                    Text(model)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.tSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.grok.opacity(0.16)))
                }
            }
            Text("仅上下文 token,非消耗量;成本 —")
                .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
        }
    }

    // MARK: - 复用片段
    struct Metric { var icon, label, value: String
        init(_ i: String, _ l: String, _ v: String) { icon = i; label = l; value = v } }

    // 模型明细行(Claude / Gemini 共用)。
    struct ModelRow: Identifiable {
        var name: String
        var pin: Double
        var pout: Double
        var cost: Double
        var id: String { name }
    }

    func cardHead(_ title: String, tint: Color, hit: Double) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Circle().fill(tint.gradient).frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.6), radius: 3)
                Text(title).font(.system(size: 14, weight: .bold))
            }
            Spacer()
            HStack(spacing: 6) {
                Text("命中").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
                RingGauge(value: hit, tint: tint, size: 38)
            }
        }
    }

    // 无命中环的卡头(Grok 无缓存命中数据)。
    func cardHeadPlain(_ title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint.gradient).frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)
            Text(title).font(.system(size: 14, weight: .bold))
            Spacer()
        }
    }

    func metricGrid(_ items: [Metric], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: 9) {
            ForEach(items.indices, id: \.self) { i in
                MetricCell(icon: items[i].icon, label: items[i].label,
                           value: items[i].value, tint: tint)
            }
        }
    }

    var thinDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    func sessionCountRow(_ n: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
            Text("\(sel.label)会话")
                .font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            Spacer(minLength: 6)
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.tPrimary)
                .contentTransition(.numericText())
            Text("个").font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
        }
    }

    func sessionRow(_ name: String, _ total: Int) -> some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9)).foregroundStyle(Theme.tTertiary)
            Text("本会话 \(name)").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            Spacer()
            Text(Fmt.human(total))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.tSecondary)
        }
    }

    var disclaimer: some View {
        Text("按 API 价估,非订阅实付")
            .font(.system(size: 9))
            .foregroundStyle(Theme.tTertiary)
    }

    @ViewBuilder
    func modelDisclosure(_ models: [ModelRow], open: Binding<Bool>, tint: Color) -> some View {
        Button {
            open.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9)).foregroundStyle(tint)
                Text("按模型 (\(models.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tTertiary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: open, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 9) {
                Text("按模型 · \(sel.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tSecondary)
                ForEach(models) { m in
                    HStack(spacing: 7) {
                        Circle().fill(tint.opacity(0.7)).frame(width: 5, height: 5)
                        Text(m.name).font(.system(size: 11.5)).foregroundStyle(Theme.tPrimary)
                            .lineLimit(1)
                        Text("\(Fmt.price(m.pin))/\(Fmt.price(m.pout))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.tSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        Spacer(minLength: 8)
                        Text(String(format: "$%.2f", m.cost))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.tPrimary)
                    }
                }
            }
            .padding(14)
            .frame(width: 238)
            .background(Theme.bg)
            .environment(\.colorScheme, .dark)
        }
    }

    func quotaRow(title: String, pct: Double, reset: Int?, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.tSecondary)
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pct <= 15 ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.tPrimary))
                Text("· \(Fmt.reset(reset))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.tTertiary)
            }
            MiniBar(value: pct, tint: pct <= 15 ? .red : tint)
        }
    }

    var footer: some View {
        HStack(spacing: 4) {
            Spacer()
            IconButton(icon: "arrow.clockwise", label: "刷新") { store.refresh() }
            IconButton(icon: "power", label: "退出") { NSApp.terminate(nil) }
        }
    }

    var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tTertiary)
                Text("显示卡片")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tSecondary)
            }
            VStack(spacing: 2) {
                settingsRow("Claude Code", tint: Theme.claude, isOn: $showClaude)
                settingsRow("Codex", tint: Theme.codex, isOn: $showCodex)
                settingsRow("Gemini CLI", tint: Theme.gemini, isOn: $showGemini)
                settingsRow("Grok CLI", tint: Theme.grok, isOn: $showGrok)
            }
        }
        .padding(14)
        .frame(width: 200)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
    }

    func settingsRow(_ name: String, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint.gradient).frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.4), radius: 2)
            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.tPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
