import SwiftUI
import SwiftData

struct FinalResultView: View {
    let session: TableSession
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context

    @State private var vm: FinalResultViewModel
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    init(session: TableSession, path: Binding<NavigationPath>) {
        self.session = session
        self._path = path
        _vm = State(initialValue: FinalResultViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // ランキング（総合ポイント順）
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "最終ランキング", systemImage: "flag.checkered")
                    VStack(spacing: Space.md) {
                        ForEach(vm.results) { r in
                            resultCard(r)
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("最終結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StatsView(session: session)
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { copyText() } label: { Label("結果をコピー", systemImage: "doc.on.doc") }
                    Button { exportCSV() } label: { Label("CSVで書き出す", systemImage: "tablecells") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Space.md) {
                Button { startRematch() } label: {
                    Label("同じ設定で再戦", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button { shareText() } label: {
                    Label("結果を共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Space.lg)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    private func resultCard(_ r: FinalResult) -> some View {
        NoteCard {
            VStack(spacing: Space.md) {
                HStack(spacing: Space.md) {
                    RankBadge(rank: r.rank, size: 34)
                    PlayerDot(colorHex: r.colorHex, size: 12)
                    Text(r.name).font(AppFont.body(18, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(r.grandTotal.signedPointString)
                        .font(AppFont.number(30, weight: .bold))
                        .foregroundStyle(Theme.pointColor(r.grandTotal))
                }
                HairlineRule()
                HStack {
                    let roundPt = ScoreCalculator.roundPoint(rawTotal: r.roundPointTotal,
                                                             per1000: session.pointCoefficientPer1000)
                    statCell("対局", roundPt.signedPointString, Theme.pointColor(roundPt))
                    divider
                    statCell("チップ", r.chipPointTotal.signedPointString, Theme.pointColor(r.chipPointTotal))
                    divider
                    statCell("トップ", "\(r.topCount)回", Theme.ink)
                    divider
                    statCell("平均順位", String(format: "%.2f", r.averageRank), Theme.ink)
                }
            }
        }
    }

    private func statCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(AppFont.body(11)).foregroundStyle(Theme.inkFaint)
            Text(value).font(AppFont.number(15, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.rule).frame(width: Theme.hairline, height: 28)
    }

    // MARK: 操作

    private func copyText() {
        UIPasteboard.general.string = vm.shareText
    }

    private func shareText() {
        shareItems = [vm.shareText]
        showShare = true
    }

    private func exportCSV() {
        if let url = CSVExporter.writeTempFile(for: session) {
            shareItems = [url]
            showShare = true
        }
    }

    /// 同じメンバー・同じルールで新しいゲームを作成して開く。
    private func startRematch() {
        let next = TableSession(gameType: session.gameType,
                                participants: session.participants,
                                pointCoefficientPer1000: session.pointCoefficientPer1000,
                                chipPointCoefficient: session.chipPointCoefficient,
                                tags: session.tags,
                                memo: "",
                                inputMode: session.inputMode,
                                rule: session.rule)
        context.insert(next)
        try? context.save()
        path = NavigationPath()      // ホームまで戻してから新しいゲームを開く
        path.append(next)
    }
}

/// UIActivityViewController ラッパー（共有シート）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
