import SwiftUI
import SwiftData

/// 「近くの卓を見る」画面。
/// 近くで共有中の卓を一覧し、選んだ卓の成績をリアルタイムで表示する（見るだけ・入力不可）。
/// 終わったら自分のスマホにも記録として保存できる。
struct LiveViewerView: View {
    @EnvironmentObject private var live: LiveShareCenter
    @Environment(\.modelContext) private var context

    /// 受信した卓を表示用に組み立てる置き場（端末には保存しないメモリ内の入れ物）。
    @State private var preview = LivePreviewStore()
    @State private var shown: TableSession?

    @State private var savedSnapshot: LiveSnapshot?
    @State private var saveError: String?

    var body: some View {
        Group {
            if live.watchingTableID == nil {
                nearbyList
            } else {
                liveTable
            }
        }
        .background(NotePageBackground())
        .navigationTitle(live.watchingTableID == nil ? "近くの卓を見る" : "ライブ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if live.watchingTableID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ほかの卓") {
                        live.leaveTable()
                        shown = nil
                        savedSnapshot = nil
                        saveError = nil
                    }
                }
            }
        }
        .onAppear { live.startViewing() }
        .onDisappear { live.stopViewing() }
        .onChange(of: live.latest) { _, snap in
            shown = snap.flatMap { preview.load($0.session) }
        }
    }

    // MARK: - 卓の一覧

    private var nearbyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("近くで共有中の卓")
                        .font(AppFont.heading(22))
                        .foregroundStyle(Theme.ink)
                    Text("記録係のスマホで入力された点数が、この画面にリアルタイムで反映されます。")
                        .font(AppFont.body(14))
                        .foregroundStyle(Theme.inkSecond)
                }

                if live.nearbyTables.isEmpty {
                    searchingCard
                } else {
                    VStack(spacing: Space.md) {
                        ForEach(live.nearbyTables) { table in
                            Button { live.watch(table) } label: { tableRow(table) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                troubleshooting
            }
            .padding(Space.lg)
        }
    }

    private var searchingCard: some View {
        NoteCard(padding: Space.xl) {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.md) {
                    ProgressView()
                    Text("近くの卓を探しています")
                        .font(AppFont.body(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    stepRow(1, "記録係のスマホで、点数を入力している卓の画面を開く")
                    stepRow(2, "右上の共有ボタンから「共有をはじめる」を押す")
                    stepRow(3, "ここに卓が出てきたら、タップして見る")
                }
            }
        }
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text("\(n)")
                .font(AppFont.number(12, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent.opacity(0.10)))
            Text(text)
                .font(AppFont.body(14))
                .foregroundStyle(Theme.inkSecond)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tableRow(_ table: LiveShareCenter.NearbyTable) -> some View {
        NoteCard(padding: Space.lg) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        Text(table.gameName)
                            .font(AppFont.label(12))
                            .foregroundStyle(Theme.mutedBlue)
                            .padding(.horizontal, Space.sm).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
                        LiveDot(color: Theme.accent)
                        Text("共有中").font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                    }
                    Text(table.members.isEmpty ? "メンバー未設定" : table.members)
                        .font(AppFont.body(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: Space.sm)
                HStack(spacing: 4) {
                    Text("見る").font(AppFont.body(14, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: live.browseFailed ? "exclamationmark.triangle.fill" : "questionmark.circle")
                    .foregroundStyle(live.browseFailed ? Theme.accentRed : Theme.inkFaint)
                Text(live.browseFailed ? "近くの卓を探せませんでした" : "見つからないときは")
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(live.browseFailed ? Theme.accentRed : Theme.inkSecond)
            }
            Text("・両方のスマホで Wi-Fi と Bluetooth をオンにしてください（同じWi-Fiにつながっていなくても大丈夫です）\n"
                 + "・「設定」アプリ → スコアシート →「ローカルネットワーク」をオンにしてください\n"
                 + "・両方のスコアシートを最新版にしてください")
                .font(AppFont.body(12))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 見ている卓

    @ViewBuilder
    private var liveTable: some View {
        if let session = shown {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    statusBar
                    standings(session)
                    roundsTable(session)
                }
                .padding(Space.lg)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        } else {
            VStack(spacing: Space.lg) {
                if live.viewerState == .ended {
                    EmptyNote(title: "共有は終了しました",
                              message: "記録係が共有をやめました。「ほかの卓」から探し直せます。",
                              systemImage: "antenna.radiowaves.left.and.right.slash")
                } else {
                    ProgressView()
                    Text("卓につないでいます…")
                        .font(AppFont.body(15, weight: .semibold))
                        .foregroundStyle(Theme.inkSecond)
                    Text("つながらないときは、記録係のスマホに近づいてください。")
                        .font(AppFont.body(13))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// つながり具合と最終更新時刻。
    private var statusBar: some View {
        let sentAt = live.latest?.sentAt
        let (color, text): (Color, String) = {
            switch live.viewerState {
            case .live:
                return (Theme.accent, "ライブで表示中")
            case .reconnecting, .connecting:
                return (Theme.accentYellow, "つなぎ直しています")
            case .ended:
                return (Theme.inkFaint, "共有は終了しました")
            case .idle, .searching:
                return (Theme.inkFaint, "")
            }
        }()
        return HStack(spacing: Space.sm) {
            LiveDot(color: color, pulsing: live.viewerState == .live)
            Text(text).font(AppFont.body(13, weight: .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            if let sentAt {
                Text("\(sentAt, format: .dateTime.hour().minute().second()) 更新")
                    .font(AppFont.number(12, weight: .regular))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.sunken))
    }

    /// 今の順位（主役）。
    private func standings(_ session: TableSession) -> some View {
        let results = ScoreCalculator.finalResults(for: session)
        let played = ScoreCalculator.countedRounds(session).count
        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "現在の順位", systemImage: "list.number")
                Spacer()
                Text("\(session.gameType.displayName)・\(played)回戦終了")
                    .font(AppFont.body(12))
                    .foregroundStyle(Theme.inkFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { HairlineRule().padding(.leading, Space.lg) }
                    HStack(spacing: Space.md) {
                        RankBadge(rank: r.rank, size: 30)
                        PlayerDot(colorHex: r.colorHex, size: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .font(AppFont.body(16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            let roundPt = ScoreCalculator.roundPoint(rawTotal: r.roundPointTotal,
                                                                     per1000: session.pointCoefficientPer1000)
                            Text("対局 \(roundPt.signedPointString)・チップ \(r.chipPointTotal.signedPointString)")
                                .font(AppFont.number(12, weight: .regular))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        Spacer(minLength: Space.sm)
                        Text(r.grandTotal.signedPointString)
                            .font(AppFont.number(24, weight: .bold))
                            .foregroundStyle(Theme.pointColor(r.grandTotal))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.rule, lineWidth: Theme.hairline))
            .animation(.easeOut(duration: 0.25), value: results.map(\.grandTotal))
        }
    }

    /// 回戦ごとの表（記録係の画面と同じ並び）。
    private func roundsTable(_ session: TableSession) -> some View {
        let ps = session.participants
        let rounds = session.sortedRounds.filter { round in
            !round.points.allSatisfy { $0.point == 0 && $0.rawScore == nil }
        }
        let labelW: CGFloat = 48
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "回戦ごとの成績", systemImage: "tablecells")
            GeometryReader { geo in
                let colW = max(48, (geo.size.width - labelW) / CGFloat(max(ps.count, 1)))
                VStack(spacing: 0) {
                    tableRowView(label: "", labelW: labelW, colW: colW, height: 40, background: Theme.sunken) { p in
                        VStack(spacing: 2) {
                            PlayerDot(colorHex: p.colorHex, size: 7)
                            Text(p.name).font(AppFont.body(12, weight: .semibold)).foregroundStyle(Theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    if rounds.isEmpty {
                        Text("まだ点数が入力されていません")
                            .font(AppFont.body(13))
                            .foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    ForEach(Array(rounds.enumerated()), id: \.element.id) { i, round in
                        gridLine
                        tableRowView(label: "\(i + 1)", labelW: labelW, colW: colW, height: 40) { p in
                            let v = round.point(for: p.id)
                            Text(v.signedPointString)
                                .font(AppFont.number(15, weight: .semibold))
                                .foregroundStyle(Theme.pointColor(v))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    gridLine
                    tableRowView(label: "合計", labelW: labelW, colW: colW, height: 40, background: Theme.sunken) { p in
                        let v = session.roundTotal(for: p.id)
                        Text(v.signedPointString)
                            .font(AppFont.number(15, weight: .bold))
                            .foregroundStyle(Theme.pointColor(v))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    gridLine
                    tableRowView(label: "チップ", labelW: labelW, colW: colW, height: 40, background: Theme.sunken) { p in
                        let v = session.chipCount(for: p.id)
                        Text(v.signedPointString)
                            .font(AppFont.number(15, weight: .semibold))
                            .foregroundStyle(Theme.pointColor(v))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline))
            }
            .frame(height: tableHeight(rounds: rounds.count))
        }
    }

    private func tableHeight(rounds: Int) -> CGFloat {
        // 見出し + 回戦 + 合計 + チップ（各40）＋区切り線。空のときは案内の高さ。
        let body = rounds == 0 ? 56 : CGFloat(rounds) * 40.5
        return 40 + body + 81
    }

    private func tableRowView<V: View>(label: String, labelW: CGFloat, colW: CGFloat, height: CGFloat,
                                       background: Color = .clear,
                                       @ViewBuilder cell: @escaping (Participant) -> V) -> some View {
        let ps = shown?.participants ?? []
        return HStack(spacing: 0) {
            Text(label)
                .font(AppFont.body(12, weight: .semibold))
                .foregroundStyle(Theme.inkSecond)
                .frame(width: labelW, height: height)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.grid).frame(width: 0.5) }
            ForEach(Array(ps.enumerated()), id: \.element.id) { idx, p in
                cell(p)
                    .frame(width: colW, height: height)
                    .overlay(alignment: .trailing) {
                        if idx < ps.count - 1 { Rectangle().fill(Theme.grid).frame(width: 0.5) }
                    }
            }
        }
        .background(background)
    }

    private var gridLine: some View {
        Rectangle().fill(Theme.grid).frame(height: 0.5)
    }

    // MARK: - 自分のスマホに保存

    private var saveBar: some View {
        VStack(spacing: Space.sm) {
            if let saveError {
                Text(saveError).font(AppFont.body(12)).foregroundStyle(Theme.accentRed)
            }
            if let latest = live.latest, latest == savedSnapshot {
                HStack(spacing: Space.sm) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("保存しました（過去のゲーム・プレイヤー別成績に入ります）")
                        .font(AppFont.body(13, weight: .semibold))
                        .foregroundStyle(Theme.inkSecond)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            } else {
                Button { save() } label: {
                    Label(savedSnapshot == nil ? "自分のスマホに保存" : "最新の内容で保存し直す",
                          systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle())
                if savedSnapshot == nil && live.viewerState != .ended {
                    Text("途中で保存しても、あとで最新の内容に保存し直せます")
                        .font(AppFont.body(11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .background(.ultraThinMaterial)
    }

    private func save() {
        guard let snap = live.latest else { return }
        do {
            try LiveSessionStore.saveCopy(snap.session, into: context)
            savedSnapshot = snap
            saveError = nil
        } catch {
            saveError = "保存できませんでした。もう一度お試しください。"
        }
    }
}

// MARK: - 表示用の置き場

/// 受信した卓を TableSession に組み立てて、計算・表示に使えるようにする。
/// 本物のデータベースとは別のメモリ内の入れ物なので、自分の記録には混ざらない。
@MainActor
final class LivePreviewStore {
    private let container: ModelContainer?
    /// 直前に表示していた卓。画面の切り替え中に消えた卓を参照しないよう、1つ前の分まで残す。
    private var shownSessions: [TableSession] = []

    init() {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        container = try? ModelContainer(for: schema,
                                        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func load(_ backup: SessionBackup) -> TableSession? {
        guard let context = container?.mainContext else { return nil }
        while shownSessions.count > 1 { context.delete(shownSessions.removeFirst()) }
        let session = LiveSessionStore.insert(backup, into: context)
        try? context.save()
        shownSessions.append(session)
        return session
    }
}

// MARK: - 共有中のしるし

/// 共有中・受信中を表す小さな丸。
struct LiveDot: View {
    var color: Color
    var pulsing: Bool = false
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(on ? 2.0 : 1)
                    .opacity(pulsing ? (on ? 0 : 0.8) : 0)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}
