import SwiftUI
import SwiftData

/// 表形式スコア入力画面。
/// 行＝回戦、列＝プレイヤー。各セルに点数を直接入力。
/// 合計・チップ・総合計は常に画面下部に固定表示。
struct TableScoreView: View {
    @Bindable var session: TableSession
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context

    /// rows[roundIndex][playerIndex] = 入力テキスト。
    @State private var rows: [[String]] = []
    @State private var chipText: [String] = []
    @State private var loaded = false
    @State private var showSettings = false

    private var participants: [Participant] { session.participants }
    private var n: Int { participants.count }

    private let labelW: CGFloat = 56
    private let rowH: CGFloat = 44
    private let hPad: CGFloat = Space.md

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - hPad * 2
            let colW = max(52, (usable - labelW) / CGFloat(max(n, 1)))

            ScrollView {
                // プレイヤー名ヘッダーは pinnedViews で常に上部固定。
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    gameHeader
                        .padding(.bottom, Space.lg)
                    Section {
                        tableBody(colW: colW)
                        Text("各回、全員の合計が 0 になるように入力してください。1人だけ空欄でEnterを押すと自動計算します。")
                            .font(AppFont.body(12))
                            .foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Space.lg)
                    } header: {
                        tableHeader(colW: colW)
                    }
                }
                .padding(.horizontal, hPad)
                .padding(.top, Space.md)
                .padding(.bottom, Space.sm)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                totalsFooter(colW: colW)
            }
        }
        .background(NotePageBackground())
        .navigationTitle(session.gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { FinalResultView(session: session) } label: {
                    Image(systemName: "flag.checkered")
                }
            }
        }
        .sheet(isPresented: $showSettings) { GameSettingsSheet(session: session) }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: rows) { _, _ in if loaded { persist() } }
        .onChange(of: chipText) { _, _ in if loaded { persist() } }
    }

    // MARK: ゲームヘッダー（係数＋タグを常時表示・タップで編集）

    private var gameHeader: some View {
        Button { showSettings = true } label: {
            NoteCard(padding: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.md) {
                        coeffPill("1000点", Int(session.pointCoefficientPer1000))
                        coeffPill("チップ1枚", Int(session.chipPointCoefficient))
                        Spacer()
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                    }
                    if !session.tags.isEmpty {
                        FlowLayout(spacing: Space.xs) {
                            ForEach(session.tags, id: \.self) { TagChip(text: $0) }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func coeffPill(_ title: String, _ pt: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).font(AppFont.body(11)).foregroundStyle(Theme.inkSecond)
            Text("\(pt)pt").font(AppFont.number(13, weight: .bold)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Space.sm).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
    }

    // MARK: スコア表（ヘッダー＋回戦行＋追加）

    /// スクロールしても上部に固定されるプレイヤー名ヘッダー。
    private func tableHeader(colW: CGFloat) -> some View {
        HStack(spacing: 0) {
            gridCell(width: labelW, showRight: true) { Color.clear }
            ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                gridCell(width: colW, showRight: idx < n - 1) {
                    VStack(spacing: 2) {
                        PlayerDot(colorHex: p.colorHex, size: 7)
                        Text(p.name)
                            .font(AppFont.body(12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .background(Theme.sunken)   // 不透明。スクロール時に下の行が透けない。
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.small, topTrailingRadius: Radius.small))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: Radius.small, topTrailingRadius: Radius.small)
                .stroke(Theme.rule, lineWidth: Theme.hairline)
        )
    }

    /// 回戦行＋追加ボタン。名前ヘッダーの下に続く本体。
    private func tableBody(colW: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                roundRow(r, colW: colW)
                gridLine()
            }

            Button { addRound() } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: "plus.circle")
                    Text("回戦を追加")
                }
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: rowH)
            }
        }
        .background(Theme.card)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Radius.small, bottomTrailingRadius: Radius.small))
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: Radius.small, bottomTrailingRadius: Radius.small)
                .stroke(Theme.rule, lineWidth: Theme.hairline)
        )
    }

    private func roundRow(_ r: Int, colW: CGFloat) -> some View {
        let sum = roundSum(r)
        let warn = rowWarnColor(r)   // nil＝OK、黄＝入力途中、赤＝全入力済みで不一致
        return HStack(spacing: 0) {
            // 回戦ラベル（タップで削除メニュー）。不一致ならズレ量を色付き表示。
            gridCell(width: labelW, showRight: true) {
                Menu {
                    Button(role: .destructive) { deleteRound(r) } label: {
                        Label("この回戦を削除", systemImage: "trash")
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("\(r + 1)回戦")
                            .font(AppFont.body(12, weight: .semibold))
                            .foregroundStyle(warn ?? Theme.inkSecond)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let warn { // ズレ量（0にすべき差）
                            Text(sum.signedPointString)
                                .font(AppFont.number(10, weight: .bold))
                                .foregroundStyle(warn)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            ForEach(Array(participants.enumerated()), id: \.element.id) { idx, _ in
                gridCell(width: colW, showRight: idx < n - 1) {
                    TextField("", text: cellBinding(r, idx))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.center)
                        .font(AppFont.number(17, weight: .semibold))
                        .foregroundStyle(Theme.pointColor(cellValue(r, idx)))
                        .frame(maxWidth: .infinity)
                        .submitLabel(.done)
                        .onSubmit { autoBalance(r) }
                }
            }
        }
        .background((warn ?? .clear).opacity(warn == nil ? 0 : 0.10))
    }

    /// 回戦行の警告色。空欄なし＆合計≠0→赤、一部入力＆合計≠0→黄、それ以外→nil。
    private func rowWarnColor(_ r: Int) -> Color? {
        let filled = rowFilledCount(r)
        guard filled > 0, roundSum(r) != 0 else { return nil }
        return filled == n ? Theme.accentRed : Theme.accentYellow
    }

    private func rowFilledCount(_ r: Int) -> Int {
        guard r < rows.count else { return 0 }
        return rows[r].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: 下部固定フッター（合計・チップ・総合計）

    private func totalsFooter(colW: CGFloat) -> some View {
        VStack(spacing: 0) {
            gridLine()
            footerRow(title: "合計", colW: colW, big: false) { idx in
                let v = playerRoundTotal(idx)
                return AnyView(Text(v.signedPointString)
                    .font(AppFont.number(15, weight: .semibold))
                    .foregroundStyle(Theme.pointColor(v)))
            }
            gridLine()
            // チップ（編集可）
            HStack(spacing: 0) {
                gridCell(width: labelW, showRight: true) {
                    Text("チップ").font(AppFont.body(12, weight: .semibold)).foregroundStyle(Theme.inkSecond)
                }
                ForEach(Array(participants.enumerated()), id: \.element.id) { idx, _ in
                    gridCell(width: colW, showRight: idx < n - 1) {
                        TextField("0", text: chipBinding(idx))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            .font(AppFont.number(15, weight: .semibold))
                            .foregroundStyle(Theme.pointColor(chipCount(idx)))
                            .submitLabel(.done)
                            .onSubmit { autoBalanceChips() }
                    }
                }
            }
            gridLine()
            footerRow(title: "総合計", colW: colW, big: true) { idx in
                let v = grandTotal(idx)
                return AnyView(Text(v.signedPointString)
                    .font(AppFont.number(19, weight: .bold))
                    .foregroundStyle(Theme.pointColor(v)))
            }
        }
        .padding(.horizontal, hPad)
        .padding(.bottom, Space.xs)
        .background(Theme.card.opacity(0.98))
        .overlay(alignment: .top) { HairlineRule() }
    }

    private func footerRow(title: String, colW: CGFloat, big: Bool,
                           value: @escaping (Int) -> AnyView) -> some View {
        HStack(spacing: 0) {
            gridCell(width: labelW, showRight: true) {
                Text(title)
                    .font(AppFont.body(big ? 13 : 12, weight: big ? .bold : .semibold))
                    .foregroundStyle(big ? Theme.ink : Theme.inkSecond)
            }
            ForEach(0..<n, id: \.self) { idx in
                gridCell(width: colW, showRight: idx < n - 1) { value(idx) }
            }
        }
    }

    // MARK: グリッド部品

    private func gridCell<V: View>(width: CGFloat, showRight: Bool,
                                   @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(width: width, height: rowH)
            .overlay(alignment: .trailing) {
                if showRight { Rectangle().fill(Theme.grid).frame(width: 0.5) }
            }
    }

    private func gridLine() -> some View {
        Rectangle().fill(Theme.grid).frame(height: 0.5)
    }

    // MARK: バインディング・計算

    private func cellBinding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { r < rows.count && c < rows[r].count ? rows[r][c] : "" },
            set: { if r < rows.count && c < rows[r].count { rows[r][c] = filter($0) } }
        )
    }
    private func chipBinding(_ c: Int) -> Binding<String> {
        Binding(
            get: { c < chipText.count ? chipText[c] : "" },
            set: { if c < chipText.count { chipText[c] = filter($0) } }
        )
    }
    /// 先頭のマイナス1つ＋数字のみ許可。
    private func filter(_ s: String) -> String {
        let neg = s.hasPrefix("-")
        let digits = s.filter { $0.isNumber }
        return (neg ? "-" : "") + digits
    }

    private func cellValue(_ r: Int, _ c: Int) -> Int {
        guard r < rows.count, c < rows[r].count else { return 0 }
        return Int(rows[r][c]) ?? 0
    }
    private func roundSum(_ r: Int) -> Int {
        guard r < rows.count else { return 0 }
        return rows[r].reduce(0) { $0 + (Int($1) ?? 0) }
    }
    private func playerRoundTotal(_ c: Int) -> Int {
        rows.reduce(0) { $0 + (c < $1.count ? (Int($1[c]) ?? 0) : 0) }
    }
    private func chipCount(_ c: Int) -> Int {
        c < chipText.count ? (Int(chipText[c]) ?? 0) : 0
    }
    private func grandTotal(_ c: Int) -> Int {
        let roundPt = ScoreCalculator.roundPoint(rawTotal: playerRoundTotal(c),
                                                 per1000: session.pointCoefficientPer1000)
        let chipPt = ScoreCalculator.chipPoint(count: chipCount(c),
                                               coefficient: session.chipPointCoefficient)
        return roundPt + chipPt
    }

    // MARK: 行操作・永続化

    private func loadIfNeeded() {
        guard !loaded else { return }
        let sorted = session.sortedRounds
        rows = sorted.map { round in
            participants.map { p in
                let v = round.point(for: p.id)
                return round.points.contains { $0.participantID == p.id } ? "\(v)" : ""
            }
        }
        if rows.isEmpty { rows = [Array(repeating: "", count: n)] }   // 最初の1回戦
        chipText = participants.map { p in
            let c = session.chipCount(for: p.id)
            return session.chips.contains { $0.participantID == p.id } && c != 0 ? "\(c)" : ""
        }
        if chipText.count != n { chipText = Array(repeating: "", count: n) }
        loaded = true
    }

    private func addRound() {
        rows.append(Array(repeating: "", count: n))
    }

    /// その回戦で空欄がちょうど1つなら、横合計が0になるよう自動補完。
    private func autoBalance(_ r: Int) {
        guard r < rows.count else { return }
        let emptyIdx = rows[r].indices.filter {
            rows[r][$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard emptyIdx.count == 1 else { return }
        let sumOthers = rows[r].reduce(0) { $0 + (Int($1) ?? 0) }
        rows[r][emptyIdx[0]] = "\(-sumOthers)"
    }

    /// チップ欄が1つだけ空欄なら、合計が0になるよう自動補完。
    private func autoBalanceChips() {
        let emptyIdx = chipText.indices.filter {
            chipText[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard emptyIdx.count == 1 else { return }
        let sumOthers = chipText.reduce(0) { $0 + (Int($1) ?? 0) }
        chipText[emptyIdx[0]] = "\(-sumOthers)"
    }

    private func deleteRound(_ r: Int) {
        guard r < rows.count else { return }
        rows.remove(at: r)
        if rows.isEmpty { rows = [Array(repeating: "", count: n)] }
    }

    /// @State から session を再構築して保存。
    private func persist() {
        // 既存回戦を全削除して作り直す（件数が少ないため単純・確実）。
        for round in session.rounds { context.delete(round) }
        session.rounds.removeAll()
        for (i, row) in rows.enumerated() {
            let points = buildPoints(row)
            let rr = RoundResult(roundNumber: i + 1, points: points)
            rr.session = session
            session.rounds.append(rr)
            context.insert(rr)
        }
        session.chips = participants.enumerated().map { idx, p in
            ChipEntry(participantID: p.id, chipCount: chipCount(idx))
        }
        session.updatedAt = Date()
        try? context.save()
    }

    /// 入力行から順位を計算して PlayerRoundPoint を構築（高い点＝上位）。
    private func buildPoints(_ row: [String]) -> [PlayerRoundPoint] {
        let vals = (0..<n).map { c -> Int in c < row.count ? (Int(row[c]) ?? 0) : 0 }
        let order = vals.indices.sorted { vals[$0] > vals[$1] }
        var rankOf = Array(repeating: 0, count: n)
        for (pos, idx) in order.enumerated() { rankOf[idx] = pos + 1 }
        return participants.indices.map { i in
            PlayerRoundPoint(participantID: participants[i].id,
                             rank: rankOf[i], point: vals[i], isAutoCalculated: false)
        }
    }
}
