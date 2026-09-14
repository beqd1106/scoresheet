import SwiftUI
import SwiftData

/// 表形式スコア入力画面。
/// 行＝回戦、列＝プレイヤー。
/// ・ポイント入力モード：計算済みのポイントを直接入力（合計 0 が目安）
/// ・素点入力モード：終局時の持ち点を入力し、ウマ・オカ・罰符込みのポイントを自動計算
/// 合計・チップ・総合計は常に画面下部に固定表示。入力は自動保存される。
struct TableScoreView: View {
    @Bindable var session: TableSession
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// rows[roundIndex][playerIndex] = 入力テキスト（ポイント or 素点）。
    @State private var rows: [[String]] = []
    /// yakitori[roundIndex][playerIndex] = ヤキトリ該当フラグ。
    @State private var yakitori: [[Bool]] = []
    @State private var chipText: [String] = []
    @State private var loaded = false
    @State private var showSettings = false
    @State private var showRules = false
    @State private var ruleCache: GameRule?

    // 自動保存
    @State private var saveTask: Task<Void, Never>?
    @State private var lastSavedAt: Date?
    @State private var saveFailed = false

    @FocusState private var focus: FocusTarget?

    /// 入力欄のフォーカス位置。
    private enum FocusTarget: Hashable {
        case cell(Int, Int)
        case chip(Int)
    }

    private var participants: [Participant] { session.participants }
    private var n: Int { participants.count }
    private var isRaw: Bool { session.inputMode == .rawScore }
    /// ルールは JSON から復元するため、描画のたびに解析しないようキャッシュする。
    private var rule: GameRule { ruleCache ?? session.rule }

    private let labelW: CGFloat = 56
    private let hPad: CGFloat = Space.md
    private var rowH: CGFloat { isRaw ? 58 : 44 }

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
                        Text(hintText)
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
                NavigationLink { FinalResultView(session: session, path: $path) } label: {
                    Image(systemName: "flag.checkered")
                }
            }
            ToolbarItemGroup(placement: .keyboard) { keyboardBar }
        }
        .sheet(isPresented: $showSettings) { GameSettingsSheet(session: session) }
        .sheet(isPresented: $showRules) { RuleSettingsSheet(session: session) }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: session.ruleJSON) { _, _ in ruleCache = session.rule }
        .onChange(of: session.inputModeRaw) { _, _ in reloadFromSession() }
        .onChange(of: rows) { _, _ in if loaded { scheduleSave() } }
        .onChange(of: yakitori) { _, _ in if loaded { scheduleSave() } }
        .onChange(of: chipText) { _, _ in if loaded { scheduleSave() } }
        // アプリが背面に回る・画面を離れるタイミングでは待たずに保存する。
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveNow() } }
        .onDisappear { saveNow() }
    }

    // MARK: ゲームヘッダー（モード・ルール・係数・タグ）

    private var gameHeader: some View {
        VStack(spacing: Space.sm) {
            NoteCard(padding: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        modePill
                        Spacer()
                        saveIndicator
                    }
                    if isRaw {
                        Button { showRules = true } label: {
                            HStack(spacing: Space.sm) {
                                rulePill
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showSettings = true } label: {
                        HStack(spacing: Space.md) {
                            coeffPill("1000点", Int(session.pointCoefficientPer1000))
                            coeffPill("チップ1枚", Int(session.chipPointCoefficient))
                            Spacer()
                            Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    if !session.tags.isEmpty {
                        FlowLayout(spacing: Space.xs) {
                            ForEach(session.tags, id: \.self) { TagChip(text: $0) }
                        }
                    }
                }
            }
        }
    }

    private var modePill: some View {
        HStack(spacing: 5) {
            Image(systemName: isRaw ? "function" : "square.and.pencil")
                .font(.system(size: 11, weight: .semibold))
            Text(session.inputMode.displayName)
                .font(AppFont.body(12, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Space.sm).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.pill).fill(Theme.accent.opacity(0.10)))
    }

    /// 自動保存の状態表示。保存できていれば時刻、失敗していれば赤で警告。
    @ViewBuilder
    private var saveIndicator: some View {
        if saveFailed {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("保存できませんでした").font(AppFont.body(11, weight: .semibold))
            }
            .foregroundStyle(Theme.accentRed)
        } else if let lastSavedAt {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle").font(.system(size: 10))
                Text("自動保存 \(lastSavedAt, format: .dateTime.hour().minute())")
                    .font(AppFont.body(11))
            }
            .foregroundStyle(Theme.inkFaint)
        }
    }

    private var rulePill: some View {
        let uma = rule.normalizedUma(playerCount: n)
        let umaText = uma.map { $0.signedPointString }.joined(separator: "/")
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(rule.startingPoints / 1000)000持ち \(rule.returnPoints / 1000)000返し")
                .font(AppFont.body(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("ウマ \(umaText)\(penaltySummary)")
                .font(AppFont.body(11))
                .foregroundStyle(Theme.inkSecond)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var penaltySummary: String {
        var parts: [String] = []
        if rule.tobiEnabled { parts.append("トビ\(rule.tobiPenalty)") }
        if rule.yakitoriEnabled { parts.append("ヤキトリ\(rule.yakitoriPenalty)") }
        if rule.kubiEnabled { parts.append("クビ\(rule.kubiPenalty)") }
        return parts.isEmpty ? "" : "・" + parts.joined(separator: "・")
    }

    private func coeffPill(_ title: String, _ pt: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).font(AppFont.body(11)).foregroundStyle(Theme.inkSecond)
            Text("\(pt)pt").font(AppFont.number(13, weight: .bold)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Space.sm).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
    }

    private var hintText: String {
        isRaw
        ? "終局時の持ち点を入力すると、ウマ・オカ・罰符を含めたポイントを自動計算します。1人だけ空欄でEnterを押すと残りを自動補完します。"
        : "各回、全員の合計が 0 になるように入力してください。1人だけ空欄でEnterを押すと自動計算します。"
    }

    // MARK: キーボード補助バー

    @ViewBuilder
    private var keyboardBar: some View {
        if focus != nil {
            Button { appendToFocused("00") } label: { Text("00").font(AppFont.number(15, weight: .bold)) }
            Button { toggleSignOfFocused() } label: { Image(systemName: "plus.forwardslash.minus") }
            Spacer()
            if case .cell(let r, _)? = focus {
                Button { autoBalance(r) } label: { Label("自動補完", systemImage: "wand.and.stars") }
                    .font(AppFont.body(14, weight: .semibold))
            }
            Button("完了") { focus = nil }
                .font(AppFont.body(15, weight: .semibold))
        }
    }

    private func appendToFocused(_ suffix: String) {
        switch focus {
        case .cell(let r, let c)?:
            guard r < rows.count, c < rows[r].count else { return }
            guard !rows[r][c].isEmpty, rows[r][c] != "-" else { return }
            rows[r][c] = filter(rows[r][c] + suffix)
        case .chip(let c)?:
            guard c < chipText.count, !chipText[c].isEmpty, chipText[c] != "-" else { return }
            chipText[c] = filter(chipText[c] + suffix)
        case nil:
            break
        }
    }

    private func toggleSignOfFocused() {
        func flipped(_ s: String) -> String {
            s.hasPrefix("-") ? String(s.dropFirst()) : (s.isEmpty ? "-" : "-" + s)
        }
        switch focus {
        case .cell(let r, let c)?:
            guard r < rows.count, c < rows[r].count else { return }
            rows[r][c] = flipped(rows[r][c])
        case .chip(let c)?:
            guard c < chipText.count else { return }
            chipText[c] = flipped(chipText[c])
        case nil:
            break
        }
    }

    // MARK: スコア表（ヘッダー＋回戦行＋追加）

    /// スクロールしても上部に固定されるプレイヤー名ヘッダー。
    private func tableHeader(colW: CGFloat) -> some View {
        HStack(spacing: 0) {
            gridCell(width: labelW, height: 44, showRight: true) { Color.clear }
            ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                gridCell(width: colW, height: 44, showRight: idx < n - 1) {
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
                .frame(height: 44)
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
        let warn = rowWarnColor(r)   // nil＝OK、黄＝入力途中、赤＝全入力済みで不一致
        let settlements = settlements(for: r)
        return HStack(spacing: 0) {
            gridCell(width: labelW, height: rowH, showRight: true) {
                roundLabel(r, warn: warn)
            }
            ForEach(Array(participants.enumerated()), id: \.element.id) { idx, _ in
                gridCell(width: colW, height: rowH, showRight: idx < n - 1) {
                    cellContent(r, idx, settlement: settlements?[safe: idx])
                }
            }
        }
        .background((warn ?? .clear).opacity(warn == nil ? 0 : 0.10))
    }

    /// 回戦ラベル。タップで削除・ヤキトリ指定のメニュー。
    private func roundLabel(_ r: Int, warn: Color?) -> some View {
        Menu {
            if isRaw && rule.yakitoriEnabled {
                Section("ヤキトリ（和了なし）") {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                        Button {
                            toggleYakitori(r, idx)
                        } label: {
                            Label(p.name, systemImage: isYakitori(r, idx) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
            Button(role: .destructive) { deleteRound(r) } label: {
                Label("この回戦を削除", systemImage: "trash")
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(r + 1)回戦")
                    .font(AppFont.body(12, weight: .semibold))
                    .foregroundStyle(warn ?? Theme.inkSecond)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let warn {
                    Text(rowDiff(r).signedPointString)
                        .font(AppFont.number(10, weight: .bold))
                        .foregroundStyle(warn)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }

    /// セル中身。素点モードは「素点（入力）＋算出ポイント」の2段。
    @ViewBuilder
    private func cellContent(_ r: Int, _ c: Int, settlement: RoundSettlement?) -> some View {
        if isRaw {
            VStack(spacing: 1) {
                TextField("", text: cellBinding(r, c))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.center)
                    .font(AppFont.number(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .cell(r, c))
                    .submitLabel(.done)
                    .onSubmit { autoBalance(r) }
                HStack(spacing: 3) {
                    if isYakitori(r, c) && rule.yakitoriEnabled {
                        Text("焼").font(AppFont.body(9, weight: .bold)).foregroundStyle(Theme.accentYellow)
                    }
                    if let s = settlement, s.isTobi {
                        Text("飛").font(AppFont.body(9, weight: .bold)).foregroundStyle(Theme.accentRed)
                    }
                    if let s = settlement {
                        Text(s.total.signedPointString)
                            .font(AppFont.number(13, weight: .bold))
                            .foregroundStyle(Theme.pointColor(s.total))
                    } else {
                        Text("–").font(AppFont.number(13)).foregroundStyle(Theme.inkFaint)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 4)
        } else {
            TextField("", text: cellBinding(r, c))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.center)
                .font(AppFont.number(17, weight: .semibold))
                .foregroundStyle(Theme.pointColor(cellValue(r, c)))
                .frame(maxWidth: .infinity)
                .focused($focus, equals: .cell(r, c))
                .submitLabel(.done)
                .onSubmit { autoBalance(r) }
        }
    }

    /// 回戦行の警告色。合計が想定どおりなら nil。
    private func rowWarnColor(_ r: Int) -> Color? {
        let filled = rowFilledCount(r)
        guard filled > 0, rowDiff(r) != 0 else { return nil }
        return filled == n ? Theme.accentRed : Theme.accentYellow
    }

    /// 想定合計とのズレ。ポイントモードは 0、素点モードは 配給原点×人数 が基準。
    private func rowDiff(_ r: Int) -> Int {
        guard r < rows.count else { return 0 }
        let sum = rows[r].reduce(0) { $0 + (Int($1) ?? 0) }
        return isRaw ? sum - session.expectedTotalScore : sum
    }

    private func rowFilledCount(_ r: Int) -> Int {
        guard r < rows.count else { return 0 }
        return rows[r].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: 計算

    /// その回戦の精算結果。素点が全員そろっていて合計が合うときだけ算出する。
    private func settlements(for r: Int) -> [RoundSettlement]? {
        guard isRaw, r < rows.count else { return nil }
        let values = rows[r].map { Int($0) }
        guard ScoreCalculator.isRawRoundComplete(values) else { return nil }
        let scores = values.compactMap { $0 }
        guard scores.count == n else { return nil }
        guard ScoreCalculator.isRawRoundBalanced(scores, rule: rule, playerCount: n) else { return nil }
        return ScoreCalculator.settle(participantIDs: participants.map(\.id),
                                      rawScores: scores,
                                      yakitoriFlags: yakitoriRow(r),
                                      rule: rule)
    }

    /// その回戦・そのプレイヤーの確定ポイント（未確定なら 0）。
    private func pointValue(_ r: Int, _ c: Int) -> Int {
        if isRaw {
            return settlements(for: r)?[safe: c]?.total ?? 0
        }
        return cellValue(r, c)
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
                gridCell(width: labelW, height: 44, showRight: true) {
                    Text("チップ").font(AppFont.body(12, weight: .semibold)).foregroundStyle(Theme.inkSecond)
                }
                ForEach(Array(participants.enumerated()), id: \.element.id) { idx, _ in
                    gridCell(width: colW, height: 44, showRight: idx < n - 1) {
                        TextField("0", text: chipBinding(idx))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            .font(AppFont.number(15, weight: .semibold))
                            .foregroundStyle(Theme.pointColor(chipCount(idx)))
                            .focused($focus, equals: .chip(idx))
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
            gridCell(width: labelW, height: 44, showRight: true) {
                Text(title)
                    .font(AppFont.body(big ? 13 : 12, weight: big ? .bold : .semibold))
                    .foregroundStyle(big ? Theme.ink : Theme.inkSecond)
            }
            ForEach(0..<n, id: \.self) { idx in
                gridCell(width: colW, height: 44, showRight: idx < n - 1) { value(idx) }
            }
        }
    }

    // MARK: グリッド部品

    private func gridCell<V: View>(width: CGFloat, height: CGFloat, showRight: Bool,
                                   @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(width: width, height: height)
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
    private func playerRoundTotal(_ c: Int) -> Int {
        rows.indices.reduce(0) { $0 + pointValue($1, c) }
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

    // MARK: ヤキトリ

    private func yakitoriRow(_ r: Int) -> [Bool] {
        guard r < yakitori.count, yakitori[r].count == n else { return Array(repeating: false, count: n) }
        return yakitori[r]
    }
    private func isYakitori(_ r: Int, _ c: Int) -> Bool {
        r < yakitori.count && c < yakitori[r].count ? yakitori[r][c] : false
    }
    private func toggleYakitori(_ r: Int, _ c: Int) {
        guard r < yakitori.count, c < yakitori[r].count else { return }
        yakitori[r][c].toggle()
    }

    // MARK: 行操作

    private func loadIfNeeded() {
        guard !loaded else { return }
        let sorted = session.sortedRounds
        rows = sorted.map { round in
            participants.map { p in
                guard let entry = round.points.first(where: { $0.participantID == p.id }) else { return "" }
                if isRaw {
                    guard let raw = entry.rawScore else { return "" }
                    return "\(raw)"
                }
                return "\(entry.point)"
            }
        }
        yakitori = sorted.map { round in
            participants.map { p in
                round.points.first { $0.participantID == p.id }?.isYakitori ?? false
            }
        }
        if rows.isEmpty {
            rows = [Array(repeating: "", count: n)]   // 最初の1回戦
            yakitori = [Array(repeating: false, count: n)]
        }
        chipText = participants.map { p in
            let c = session.chipCount(for: p.id)
            return session.chips.contains { $0.participantID == p.id } && c != 0 ? "\(c)" : ""
        }
        if chipText.count != n { chipText = Array(repeating: "", count: n) }
        ruleCache = session.rule
        loaded = true
    }

    /// 入力方式が変わったときに、保存済みの内容から表を作り直す。
    private func reloadFromSession() {
        loaded = false
        loadIfNeeded()
    }

    private func addRound() {
        rows.append(Array(repeating: "", count: n))
        yakitori.append(Array(repeating: false, count: n))
    }

    /// その回戦で空欄がちょうど1つなら、想定合計になるよう自動補完。
    private func autoBalance(_ r: Int) {
        guard r < rows.count else { return }
        let emptyIdx = rows[r].indices.filter {
            rows[r][$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard emptyIdx.count == 1 else { return }
        let sumOthers = rows[r].reduce(0) { $0 + (Int($1) ?? 0) }
        let target = isRaw ? session.expectedTotalScore : 0
        rows[r][emptyIdx[0]] = "\(target - sumOthers)"
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
        if r < yakitori.count { yakitori.remove(at: r) }
        if rows.isEmpty {
            rows = [Array(repeating: "", count: n)]
            yakitori = [Array(repeating: false, count: n)]
        }
    }

    // MARK: 自動保存

    /// 入力のたびに走らせると重いので、少し待ってからまとめて保存する。
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    /// 待たずに保存（画面離脱・バックグラウンド移行時）。
    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard loaded else { return }
        persist()
    }

    /// @State の内容を session へ反映して保存する。
    /// 回戦は作り直さず既存レコードを更新する（毎入力での削除・再作成を避けるため）。
    private func persist() {
        let existing = session.sortedRounds

        for (i, row) in rows.enumerated() {
            let points = buildPoints(i, row)
            if i < existing.count {
                let round = existing[i]
                if round.roundNumber != i + 1 { round.roundNumber = i + 1 }
                if round.points != points { round.points = points }
            } else {
                let rr = RoundResult(roundNumber: i + 1, points: points)
                rr.session = session
                session.rounds.append(rr)
                context.insert(rr)
            }
        }

        // 行が減った分は削除する。
        if existing.count > rows.count {
            for extra in existing[rows.count...] {
                session.rounds.removeAll { $0.id == extra.id }
                context.delete(extra)
            }
        }

        session.chips = participants.enumerated().map { idx, p in
            ChipEntry(participantID: p.id, chipCount: chipCount(idx))
        }
        session.updatedAt = Date()

        do {
            try context.save()
            lastSavedAt = Date()
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    /// 入力行から保存用の PlayerRoundPoint を構築する。
    /// 素点モードは算出ポイントと素点の両方を、ポイントモードは従来どおり入力値を保存する。
    private func buildPoints(_ r: Int, _ row: [String]) -> [PlayerRoundPoint] {
        if isRaw {
            let settled = settlements(for: r)
            return participants.indices.map { i in
                let raw = i < row.count ? Int(row[i]) : nil
                let s = settled?[safe: i]
                return PlayerRoundPoint(participantID: participants[i].id,
                                        rank: s?.rank ?? 0,
                                        point: s?.total ?? 0,
                                        isAutoCalculated: s != nil,
                                        rawScore: raw,
                                        isYakitori: isYakitori(r, i))
            }
        }

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

// MARK: - 安全な添字アクセス

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
