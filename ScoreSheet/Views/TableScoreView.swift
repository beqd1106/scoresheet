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
    /// busters[roundIndex][playerIndex] = その人を飛ばした人（トビ罰符の受取先）。
    @State private var busters: [[UUID?]] = []
    @State private var chipText: [String] = []
    @State private var loaded = false
    @State private var showSettings = false
    @State private var showRules = false
    @State private var ruleCache: GameRule?

    // 自動保存
    @State private var lastSavedAt: Date?
    @State private var saveFailed = false

    /// 現在入力しているマス（アプリ内テンキーの対象）。
    @State private var focus: FocusTarget?

    /// 入力欄の位置。
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
                        roundExtras
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
                VStack(spacing: 0) {
                    totalsFooter(colW: colW)
                    if focus != nil { keypad }
                }
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
        }
        .sheet(isPresented: $showSettings) { GameSettingsSheet(session: session) }
        .sheet(isPresented: $showRules) { RuleSettingsSheet(session: session) }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: session.ruleJSON) { _, _ in ruleCache = session.rule }
        .onChange(of: session.inputModeRaw) { _, _ in reloadFromSession() }
        .onChange(of: rows) { _, _ in if loaded { scheduleSave() } }
        .onChange(of: yakitori) { _, _ in if loaded { scheduleSave() } }
        .onChange(of: busters) { _, _ in if loaded { scheduleSave() } }
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
        guard isRaw else {
            return "マスをタップして、下のキーで入力します。各回、全員の合計が 0 になるように入力してください（1人だけ空欄なら杖のキーで自動補完）。"
        }
        return "マスをタップして、下のキーで終局時の持ち点を入力します。"
            + "全員の合計が \(session.expectedTotalScore) 点になるのが目安です（1人だけ空欄なら杖のキーで自動補完）。"
    }

    // MARK: アプリ内テンキー
    // システムのキーボードは使わず、この画面専用のキーを出す。
    // 麻雀の点数は桁が多いので 00 / 000 と、隣のマスへ移る「次へ」を用意する。

    private var keypad: some View {
        VStack(spacing: 0) {
            HairlineRule()
            HStack(spacing: Space.sm) {
                Text(focusTitle)
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecond)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button { focus = nil } label: {
                    HStack(spacing: 4) {
                        Text("閉じる").font(AppFont.body(14, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)

            HStack(spacing: Space.xs) {
                // 数字（3列）
                VStack(spacing: Space.xs) {
                    ForEach(digitRows, id: \.self) { row in
                        HStack(spacing: Space.xs) {
                            ForEach(row, id: \.self) { key in
                                keyButton(label: key, tint: Theme.ink) { append(key) }
                            }
                        }
                    }
                }
                // 補助（1列）
                VStack(spacing: Space.xs) {
                    keyButton(systemImage: "delete.left", tint: Theme.inkSecond) { backspace() }
                    keyButton(systemImage: "plus.forwardslash.minus", tint: Theme.inkSecond) { toggleSign() }
                    keyButton(systemImage: "wand.and.stars", tint: Theme.accent) { autoBalanceFocused() }
                    keyButton(label: "次へ", tint: .white, background: Theme.accent) { moveNext() }
                }
                .frame(width: 78)
            }
            .padding(.horizontal, Space.sm)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.sm)
        }
        .background(Theme.sunken)
    }

    private var digitRows: [[String]] {
        [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], ["0", "00", "000"]]
    }

    /// いま入力しているマスの見出し（例：2回戦　たろう　持ち点）。
    private var focusTitle: String {
        switch focus {
        case .cell(let r, let c)?:
            let name = c < n ? participants[c].name : ""
            return "\(r + 1)回戦　\(name)　" + (isRaw ? "持ち点" : "ポイント")
        case .chip(let c)?:
            let name = c < n ? participants[c].name : ""
            return "チップ　\(name)"
        case nil:
            return ""
        }
    }

    private func keyButton(label: String,
                           tint: Color,
                           background: Color = Theme.card,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.number(label.count > 2 ? 17 : 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(background))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    private func keyButton(systemImage: String,
                           tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: テンキーの操作

    /// 入力できる桁数。素点は 6 桁（-12300 など）、ポイントは 5 桁まで。
    private var maxDigits: Int { isRaw ? 6 : 5 }

    private func currentText() -> String {
        switch focus {
        case .cell(let r, let c)?:
            return r < rows.count && c < rows[r].count ? rows[r][c] : ""
        case .chip(let c)?:
            return c < chipText.count ? chipText[c] : ""
        case nil:
            return ""
        }
    }

    private func setCurrentText(_ text: String) {
        switch focus {
        case .cell(let r, let c)?:
            guard r < rows.count, c < rows[r].count else { return }
            rows[r][c] = text
        case .chip(let c)?:
            guard c < chipText.count else { return }
            chipText[c] = text
        case nil:
            break
        }
    }

    private func append(_ key: String) {
        let text = currentText()
        // 「0」だけの状態で数字を押したら置き換える（0 の連なりを防ぐ）。
        let base = text.filter { $0.isNumber } == "0" ? text.replacingOccurrences(of: "0", with: "") : text
        guard base.filter({ $0.isNumber }).count + key.count <= maxDigits else { return }
        setCurrentText(filter(base + key))
    }

    private func backspace() {
        let text = currentText()
        guard !text.isEmpty else { return }
        setCurrentText(String(text.dropLast()))
    }

    private func toggleSign() {
        let text = currentText()
        setCurrentText(text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text)
    }

    private func autoBalanceFocused() {
        switch focus {
        case .cell(let r, _)?: autoBalance(r)
        case .chip?:           autoBalanceChips()
        case nil:              break
        }
    }

    /// 次のマスへ。行の右端まで行ったら次の回戦へ、最後はチップ行へ移る。
    private func moveNext() {
        switch focus {
        case .cell(let r, let c)?:
            if c + 1 < n {
                focus = .cell(r, c + 1)
            } else if r + 1 < rows.count {
                focus = .cell(r + 1, 0)
            } else {
                focus = .chip(0)
            }
        case .chip(let c)?:
            focus = c + 1 < n ? .chip(c + 1) : nil
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
            if isRaw && rule.tobiEnabled && rule.tobiPayee == .buster {
                ForEach(tobiIndices(r), id: \.self) { c in
                    Menu("\(participants[c].name)を飛ばした人") {
                        ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                            if idx != c {
                                Button {
                                    setBuster(r, c, p.id)
                                } label: {
                                    Label(p.name, systemImage: busterAt(r, c) == p.id ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                        if busterAt(r, c) != nil {
                            Button(role: .destructive) { setBuster(r, c, nil) } label: {
                                Label("指定を外す", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
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
                inputCell(text: cellText(r, c),
                          selected: focus == .cell(r, c),
                          size: 15,
                          color: Theme.ink,
                          height: 28)
                    .onTapGesture { focus = .cell(r, c) }
                HStack(spacing: 3) {
                    if isYakitori(r, c) && rule.yakitoriEnabled {
                        Text("焼").font(AppFont.body(9, weight: .bold)).foregroundStyle(Theme.accentYellow)
                    }
                    if let s = settlement, s.isTobi {
                        // 「飛ばした人」を待っている状態は黄色で知らせる。
                        let waiting = rule.tobiPayee == .buster && busterAt(r, c) == nil
                        Text("飛").font(AppFont.body(9, weight: .bold))
                            .foregroundStyle(waiting ? Theme.accentYellow : Theme.accentRed)
                    }
                    if let s = settlement, s.isKubi {
                        Text("首").font(AppFont.body(9, weight: .bold)).foregroundStyle(Theme.accentRed)
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
            inputCell(text: cellText(r, c),
                      selected: focus == .cell(r, c),
                      size: 17,
                      color: Theme.pointColor(cellValue(r, c)),
                      height: rowH - 8)
                .onTapGesture { focus = .cell(r, c) }
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
        return RoundPersistence.settlement(row: rows[r],
                                           yakitori: yakitoriRow(r),
                                           busters: busterRow(r),
                                           session: session)
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
                        inputCell(text: idx < chipText.count ? chipText[idx] : "",
                                  selected: focus == .chip(idx),
                                  size: 15,
                                  color: Theme.pointColor(chipCount(idx)),
                                  height: 36,
                                  placeholder: "0")
                            .onTapGesture { focus = .chip(idx) }
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

    private func cellText(_ r: Int, _ c: Int) -> String {
        r < rows.count && c < rows[r].count ? rows[r][c] : ""
    }

    /// 入力マス。タップで選択し、アプリ内テンキーから入力する。
    /// 選択中は枠と薄い塗りで、どこを打っているかが分かるようにする。
    private func inputCell(text: String,
                           selected: Bool,
                           size: CGFloat,
                           color: Color,
                           height: CGFloat,
                           placeholder: String = "") -> some View {
        Text(text.isEmpty ? placeholder : text)
            .font(AppFont.number(size, weight: .semibold))
            .foregroundStyle(text.isEmpty ? Theme.inkFaint : color)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .stroke(selected ? Theme.accent : Color.clear, lineWidth: 1.5)
            )
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
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

    // MARK: トビ（飛ばした人）

    private func busterRow(_ r: Int) -> [UUID?] {
        guard r < busters.count, busters[r].count == n else { return Array(repeating: nil, count: n) }
        return busters[r]
    }
    private func busterAt(_ r: Int, _ c: Int) -> UUID? {
        r < busters.count && c < busters[r].count ? busters[r][c] : nil
    }
    private func setBuster(_ r: Int, _ c: Int, _ id: UUID?) {
        guard r < busters.count, c < busters[r].count else { return }
        busters[r][c] = id
    }

    /// その回戦でトビになっている人の列番号。
    private func tobiIndices(_ r: Int) -> [Int] {
        guard isRaw, rule.tobiEnabled, r < rows.count else { return [] }
        return rows[r].indices.filter { c in
            guard let v = Int(rows[r][c]) else { return false }
            return v < 0 || (rule.tobiIncludesZero && v == 0)
        }
    }

    /// 「飛ばした人が受け取る」設定で、まだ相手が決まっていないもの。
    private var pendingBusters: [(round: Int, player: Int)] {
        guard isRaw, rule.tobiEnabled, rule.tobiPayee == .buster else { return [] }
        var out: [(Int, Int)] = []
        for r in rows.indices {
            for c in tobiIndices(r) where busterAt(r, c) == nil { out.append((r, c)) }
        }
        return out
    }

    /// 表の下に出す回戦ごとの設定カード。
    /// 点棒を入力 → ヤキトリを1タップでON/OFF → トビがいれば飛ばした人を選ぶ、という流れ。
    @ViewBuilder
    private var roundExtras: some View {
        let targets = extraRounds
        if !targets.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(text: "回戦ごとの設定", systemImage: "hand.tap")
                ForEach(targets, id: \.self) { r in
                    NoteCard(padding: Space.md) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            HStack(spacing: Space.sm) {
                                Text("\(r + 1)回戦")
                                    .font(AppFont.body(14, weight: .bold)).foregroundStyle(Theme.ink)
                                if !pendingBusterIndices(r).isEmpty {
                                    Text("未指定")
                                        .font(AppFont.body(11, weight: .semibold))
                                        .foregroundStyle(Theme.accentYellow)
                                }
                            }

                            if rule.yakitoriEnabled {
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    Text("ヤキトリ（タップで切り替え）")
                                        .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                                    FlowLayout(spacing: Space.sm) {
                                        ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                                            Button { toggleYakitori(r, idx) } label: {
                                                nameChip(p, selected: isYakitori(r, idx), tint: Theme.accentYellow)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            if rule.tobiEnabled && rule.tobiPayee == .buster {
                                ForEach(tobiIndices(r), id: \.self) { c in
                                    VStack(alignment: .leading, spacing: Space.sm) {
                                        if c > 0 || rule.yakitoriEnabled { HairlineRule() }
                                        Text("\(participants[c].name) を飛ばしたのは？")
                                            .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                                        FlowLayout(spacing: Space.sm) {
                                            ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                                                if idx != c {
                                                    Button {
                                                        // もう一度押したら解除。
                                                        setBuster(r, c, busterAt(r, c) == p.id ? nil : p.id)
                                                    } label: {
                                                        nameChip(p, selected: busterAt(r, c) == p.id, tint: Theme.accent)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if !pendingBusters.isEmpty {
                    Text("飛ばした人を指定するまでは、トップが受け取る扱いで計算します。")
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    /// 設定カードを出す回戦（何か入力がある回戦だけ）。
    private var extraRounds: [Int] {
        guard isRaw else { return [] }
        let needsYakitori = rule.yakitoriEnabled
        let needsBuster = rule.tobiEnabled && rule.tobiPayee == .buster
        guard needsYakitori || needsBuster else { return [] }
        return rows.indices.filter { r in
            if rowFilledCount(r) == 0 { return false }
            return needsYakitori || !tobiIndices(r).isEmpty
        }
    }

    /// 指定待ちのトビ（回戦単位）。
    private func pendingBusterIndices(_ r: Int) -> [Int] {
        guard rule.tobiEnabled, rule.tobiPayee == .buster else { return [] }
        return tobiIndices(r).filter { busterAt(r, $0) == nil }
    }

    /// 名前チップ。選択中は塗りつぶす。
    private func nameChip(_ p: Participant, selected: Bool, tint: Color) -> some View {
        HStack(spacing: Space.xs) {
            if selected {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            } else {
                PlayerDot(colorHex: p.colorHex, size: 8)
            }
            Text(p.name).font(AppFont.body(14, weight: .medium))
        }
        .foregroundStyle(selected ? Color.white : Theme.inkSecond)
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: Radius.pill).fill(selected ? tint : Theme.sunken))
        .overlay(RoundedRectangle(cornerRadius: Radius.pill)
            .stroke(selected ? Color.clear : Theme.rule, lineWidth: Theme.hairline))
    }

    // MARK: 行操作

    private func loadIfNeeded() {
        guard !loaded else { return }
        let input = RoundPersistence.load(from: session)
        rows = input.rows
        yakitori = input.yakitori
        busters = input.busters
        chipText = input.chips
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
        busters.append(Array(repeating: nil, count: n))
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
        if r < busters.count { busters.remove(at: r) }
        if rows.isEmpty {
            rows = [Array(repeating: "", count: n)]
            yakitori = [Array(repeating: false, count: n)]
            busters = [Array(repeating: nil, count: n)]
        }
    }

    // MARK: 自動保存

    /// 入力のたびにすぐ保存する。
    /// キーは1タップずつの操作で書き込みも軽いため、待ち時間を置かずに保存して
    /// 万一アプリが落ちても直前の操作が残るようにしている。
    private func scheduleSave() {
        persist()
    }

    /// 画面を離れる・バックグラウンドへ移るときの保存。
    private func saveNow() {
        guard loaded else { return }
        persist()
    }

    /// @State の内容を session へ反映して保存する。
    private func persist() {
        let ok = RoundPersistence.save(currentInput, to: session, context: context)
        if ok {
            lastSavedAt = Date()
            saveFailed = false
        } else {
            saveFailed = true
        }
    }

    private var currentInput: ScoreTableInput {
        ScoreTableInput(rows: rows, yakitori: yakitori, busters: busters, chips: chipText)
    }
}

// MARK: - 安全な添字アクセス

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
