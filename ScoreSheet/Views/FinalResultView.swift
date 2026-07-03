import SwiftUI

struct FinalResultView: View {
    let session: TableSession
    @State private var vm: FinalResultViewModel
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    init(session: TableSession) {
        self.session = session
        _vm = State(initialValue: FinalResultViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // 並び替え
                Picker("並び替え", selection: $vm.sortKey) {
                    ForEach(FinalResultViewModel.SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                // ランキング
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
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Space.md) {
                Button { copyText() } label: { Label("コピー", systemImage: "doc.on.doc") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { exportCSV() } label: { Label("CSV出力", systemImage: "square.and.arrow.up") }
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
                    statCell("対局", r.roundPointTotal.signedPointString, Theme.pointColor(r.roundPointTotal))
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

    private func copyText() {
        UIPasteboard.general.string = vm.shareText
        shareItems = [vm.shareText]
        showShare = true
    }

    private func exportCSV() {
        if let url = CSVExporter.writeTempFile(for: session) {
            shareItems = [url]
            showShare = true
        }
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
