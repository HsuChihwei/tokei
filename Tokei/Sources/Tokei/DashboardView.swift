import SwiftUI
import Charts

struct DailyCost: Codable, Identifiable {
    var date: String
    var claude: Double
    var codex: Double
    var total: Double
    var c_in: Int = 0
    var c_out: Int = 0
    var x_in: Int = 0
    var x_out: Int = 0
    var id: String { date }
}

struct ModelCost: Codable, Identifiable {
    var name: String
    var cost: Double
    var tool: String
    var `in`: Int?
    var out: Int?
    var cost_per_k: Double = 0
    var out_ratio: Double = 0
    var id: String { name }
}

struct DashboardData: Codable {
    var daily: [DailyCost]
    var models: [ModelCost]
}

struct DashboardView: View {
    @State private var daily: [DailyCost] = []
    @State private var models: [ModelCost] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 200)
            } else if daily.isEmpty {
                HStack { Spacer(); Text("暂无数据").font(.system(size: 14)).foregroundStyle(Theme.tTertiary); Spacer() }
                    .frame(height: 200)
            } else {
                summaryCards
                modelSection
                Divider().opacity(0.15)
                trendSection
                Divider().opacity(0.15)
                heatmapSection
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Summary

    var summaryCards: some View {
        let totalCost = daily.reduce(0) { $0 + $1.total }
        let totalTokens = daily.reduce(0) { $0 + $1.c_in + $1.c_out + $1.x_in + $1.x_out }
        let avgCost = daily.isEmpty ? 0 : totalCost / Double(daily.count)
        let maxDay = daily.max(by: { $0.total < $1.total })
        return HStack(spacing: 10) {
            sumCard("总成本", "$" + NumberFormatter.localizedString(from: NSNumber(value: Int(totalCost)), number: .decimal), Theme.claude)
            sumCard("总 Token", Fmt.human(totalTokens), Theme.codex)
            sumCard("日均", String(format: "$%.0f", avgCost), Theme.gemini)
            if let m = maxDay {
                sumCard("峰值", String(format: "$%.0f", m.total), Color.red.opacity(0.8))
            }
        }
    }

    func sumCard(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(tint.opacity(0.9))
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.05)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
        )
    }

    // MARK: - Model Chart

    var modelSection: some View {
        let sorted = models.sorted { (($0.in ?? 0) + ($0.out ?? 0)) > (($1.in ?? 0) + ($1.out ?? 0)) }
        let top = Array(sorted.prefix(8))
        let maxTokens = Double((top.first.map { ($0.in ?? 0) + ($0.out ?? 0) }) ?? 1)
        let maxCost = models.map(\.cost).max() ?? 1
        return VStack(alignment: .leading, spacing: 5) {
            Text("模型用量").font(.system(size: 14, weight: .bold))
            ForEach(top) { m in
                let tokens = (m.in ?? 0) + (m.out ?? 0)
                let tint = m.tool == "codex" ? Theme.codex : Theme.claude
                let costRatio = m.cost / maxCost
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tPrimary)
                        Spacer()
                        Text(Fmt.human(tokens) + " tok")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.tSecondary)
                        Text("·")
                            .foregroundStyle(Theme.tTertiary)
                        Text(String(format: "$%.0f", m.cost))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(costRatio > 0.5 ? .white : Theme.tSecondary)
                    }
                    GeometryReader { geo in
                        let logVal = tokens > 0 ? log10(Double(tokens)) : 0
                        let logMax = maxTokens > 0 ? log10(maxTokens) : 1
                        let ratio = logMax > 0 ? logVal / logMax : 0
                        let w = max(4, geo.size.width * CGFloat(ratio))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(tint.opacity(0.08))
                                .frame(width: geo.size.width)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [tint.opacity(0.6), tint, tint.opacity(0.8 + costRatio * 0.2)],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: w)
                                .shadow(color: tint.opacity(0.35), radius: 4)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    // MARK: - Trend

    @State private var trendDays = 30

    var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日均趋势").font(.system(size: 14, weight: .bold))
                Spacer()
                Picker("", selection: $trendDays) {
                    Text("14天").tag(14); Text("30天").tag(30); Text("90天").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .controlSize(.mini)
            }
            trendChart
        }
    }

    var trendChart: some View {
        let slice = Array(daily.suffix(trendDays))
        let ma7 = movingAverage(slice, window: 7)
        let step = max(1, slice.count / 5)
        let labelDates = Set(stride(from: 0, to: slice.count, by: step).map { slice[$0].date }
                             + [slice.last?.date ?? ""])

        return Chart {
            ForEach(Array(slice.enumerated()), id: \.offset) { i, d in
                BarMark(
                    x: .value("日期", d.date),
                    y: .value("成本", d.total)
                )
                .foregroundStyle(
                    LinearGradient(colors: [Theme.codex.opacity(0.5), Theme.claude.opacity(0.3)],
                                   startPoint: .bottom, endPoint: .top))
                .cornerRadius(2)
            }
            ForEach(Array(ma7.enumerated()), id: \.offset) { i, pt in
                AreaMark(
                    x: .value("日期", pt.date),
                    y: .value("7日均", pt.value)
                )
                .foregroundStyle(
                    LinearGradient(colors: [Theme.claude.opacity(0.20), Theme.claude.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("日期", pt.date),
                    y: .value("7日均", pt.value)
                )
                .foregroundStyle(Theme.claude)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks { v in
                if let s = v.as(String.self), labelDates.contains(s) {
                    AxisValueLabel {
                        Text(String(s.suffix(5)))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text("$\(Int(n))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.tTertiary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(Color.primary.opacity(0.06))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 110)
    }

    struct MAPoint: Identifiable {
        var date: String; var value: Double; var id: String { date }
    }

    func movingAverage(_ data: [DailyCost], window: Int) -> [MAPoint] {
        guard data.count >= window else {
            return data.map { MAPoint(date: $0.date, value: $0.total) }
        }
        var result: [MAPoint] = []
        for i in (window - 1)..<data.count {
            let sum = data[(i - window + 1)...i].reduce(0.0) { $0 + $1.total }
            result.append(MAPoint(date: data[i].date, value: sum / Double(window)))
        }
        return result
    }

    // MARK: - Heatmap

    @State private var heatRange = 1  // 0=日(7天) 1=月 2=年
    @State private var selectedCell: String? = nil

    var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("活跃热力")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Picker("", selection: $heatRange) {
                    Text("周").tag(0); Text("月").tag(1); Text("年").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .controlSize(.mini)
                .onChange(of: heatRange) { _ in selectedCell = nil }
            }
            if heatRange == 0 { weekStrip } else { heatmapGrid }
            if let sel = selectedCell, let day = daily.first(where: { $0.date == sel }) {
                heatDetail(day)
            }
            heatmapLegend
        }
    }

    func heatDetail(_ d: DailyCost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(d.date).font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.tPrimary)
                Spacer()
                Text(String(format: "$%.2f", d.total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Button { selectedCell = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(Theme.tTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.claude).frame(width: 6, height: 6)
                        Text("Claude").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.claude)
                    }
                    Text("输入 \(Fmt.human(d.c_in)) · 输出 \(Fmt.human(d.c_out))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                    Text(String(format: "$%.2f", d.claude))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.codex).frame(width: 6, height: 6)
                        Text("Codex").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.codex)
                    }
                    Text("输入 \(Fmt.human(d.x_in)) · 输出 \(Fmt.human(d.x_out))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tTertiary)
                    Text(String(format: "$%.2f", d.codex))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.tSecondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.claude.opacity(0.2), lineWidth: 0.5)))
    }

    var weekStrip: some View {
        let cal = Calendar.current
        let today = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let costMap = Dictionary(uniqueKeysWithValues: daily.map { ($0.date, $0.total) })
        let maxCost = daily.map(\.total).max() ?? 1

        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { r in
                    Text(dayLabels[r])
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.tTertiary)
                        .frame(width: 14, height: 20)
                }
            }
            ForEach(0..<1, id: \.self) { _ in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        let dayOffset = -(6 - i)
                        let adjustedIdx = ((cal.component(.weekday, from: today) + 5) % 7)
                        let startOffset = -(adjustedIdx + 6 - i)
                        let d = cal.date(byAdding: .day, value: dayOffset - (6 - ((cal.component(.weekday, from: today) + 5) % 7)) + i, to: today)!
                        let _ = 0
                        let realD = cal.date(byAdding: .day, value: -(6 - i), to: today)!
                        let ds = fmt.string(from: realD)
                        let cost = costMap[ds] ?? 0
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(heatColor(cost: cost, max: maxCost))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(selectedCell == ds ? Theme.claude : .clear, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedCell = selectedCell == ds ? nil : ds
                                    }
                                }
                            Text(String(ds.suffix(5)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.tTertiary)
                                .frame(width: 38, alignment: .leading)
                            if cost > 0 {
                                Text(String(format: "$%.0f", cost))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.tSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    var heatmapGrid: some View {
        let cal = Calendar.current
        let today = Date()
        let totalDays: Int = heatRange == 1 ? 35 : 371
        let startDate = cal.date(byAdding: .day, value: -(totalDays - 1), to: today)!
        let costMap = Dictionary(uniqueKeysWithValues: daily.map { ($0.date, $0.total) })
        let maxCost = daily.map(\.total).max() ?? 1

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

        struct Cell: Identifiable {
            var id: Int; var row: Int; var col: Int; var cost: Double; var dateStr: String
        }

        var cells: [Cell] = []
        let startWeekday = (cal.component(.weekday, from: startDate) + 5) % 7
        for i in 0..<totalDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let ds = fmt.string(from: d)
            let offset = startWeekday + i
            let row = offset % 7
            let col = offset / 7
            cells.append(Cell(id: i, row: row, col: col, cost: costMap[ds] ?? 0, dateStr: ds))
        }
        let cols = (cells.last?.col ?? 0) + 1
        let cellSize: CGFloat = heatRange == 1 ? 20 : 12
        let gap: CGFloat = heatRange == 1 ? 3 : 2
        let radius: CGFloat = heatRange == 1 ? 4 : 2.5

        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: gap) {
                ForEach(0..<7, id: \.self) { r in
                    Text(dayLabels[r])
                        .font(.system(size: heatRange == 2 ? 8 : 10, weight: .medium))
                        .foregroundStyle(Theme.tTertiary)
                        .frame(width: 16, height: cellSize)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { c in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { r in
                                    let cell = cells.first { $0.row == r && $0.col == c }
                                    let ds = cell?.dateStr ?? ""
                                    let cost = cell?.cost ?? 0
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .fill(heatColor(cost: cost, max: maxCost))
                                        .frame(width: cellSize, height: cellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                                            .strokeBorder(selectedCell == ds ? Theme.claude : .clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedCell = selectedCell == ds ? nil : ds
                                        }
                                    }
                                }
                            }
                            .id(c)
                        }
                        Color.clear.frame(width: 1, height: 1).id("heatEnd")
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("heatEnd", anchor: .trailing)
                    }
                }
                .onChange(of: heatRange) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("heatEnd", anchor: .trailing)
                    }
                }
            }
        }
    }

    static let heatColors: [Color] = [
        Color(red: 0.18, green: 0.20, blue: 0.24),       // L0: 深灰(无活动)
        Color(red: 0.45, green: 0.32, blue: 0.22),       // L1: 暗棕
        Color(red: 0.72, green: 0.42, blue: 0.25),       // L2: 暖铜
        Color(red: 0.90, green: 0.55, blue: 0.30),       // L3: 亮橙
        Color(red: 0.98, green: 0.72, blue: 0.35),       // L4: 金黄
    ]

    func heatColor(cost: Double, max: Double) -> Color {
        if cost <= 0 { return Color.primary.opacity(0.04) }
        let ratio = min(cost / max, 1.0)
        if ratio < 0.15 { return Self.heatColors[1] }
        if ratio < 0.35 { return Self.heatColors[2] }
        if ratio < 0.60 { return Self.heatColors[3] }
        return Self.heatColors[4]
    }

    var heatmapLegend: some View {
        HStack(spacing: 5) {
            Spacer()
            Text("少").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(i == 0 ? Color.primary.opacity(0.04) : Self.heatColors[i])
                    .frame(width: 12, height: 12)
            }
            Text("多").font(.system(size: 10)).foregroundStyle(Theme.tTertiary)
        }
    }

    func loadData() {
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["python3", DataLoader.scriptPath, "--daily-costs"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            let raw = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let result = try? JSONDecoder().decode(DashboardData.self, from: raw)
            DispatchQueue.main.async {
                daily = result?.daily ?? []
                models = result?.models ?? []
                loading = false
            }
        }
    }
}
