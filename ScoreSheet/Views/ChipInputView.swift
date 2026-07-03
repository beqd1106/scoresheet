import SwiftUI
import SwiftData

struct ChipInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: TableSession
    @State private var vm: ChipInputViewModel

    init(session: TableSession) {
        self.session = session
        _vm = State(initialValue: ChipInputViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    // 係数の説明
                    NoteCard {
                        HStack {
                            Text("チップ 1枚あたり").font(AppFont.body(15)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(Int(vm.coefficient)) pt")
                                .font(AppFont.number(18, weight: .bold)).foregroundStyle(Theme.mutedBlue)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "各プレイヤーのチップ枚数")
                        VStack(spacing: Space.md) {
                            ForEach(vm.participants) { p in
                                chipRow(p)
                            }
                        }
                    }

                    // 合計目安
                    HStack {
                        Image(systemName: vm.totalCount == 0 ? "checkmark.circle" : "info.circle")
                            .foregroundStyle(vm.totalCount == 0 ? Theme.deepGreen : Theme.inkFaint)
                        Text(vm.totalCount == 0 ? "枚数の合計は 0 です" : "枚数の合計：\(vm.totalCount)")
                            .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("チップ入力")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: { Text("チップを保存") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Space.lg)
                    .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func chipRow(_ p: Participant) -> some View {
        NoteCard(padding: Space.md) {
            HStack(spacing: Space.md) {
                PlayerDot(colorHex: p.colorHex)
                Text(p.name).font(AppFont.body(16, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()

                // ステッパー
                HStack(spacing: Space.sm) {
                    stepButton("minus") { vm.adjust(-1, for: p.id) }
                    Text(vm.count(for: p.id).signedPointString)
                        .font(AppFont.number(20, weight: .bold))
                        .foregroundStyle(Theme.pointColor(vm.count(for: p.id)))
                        .frame(minWidth: 44)
                    stepButton("plus") { vm.adjust(1, for: p.id) }
                }

                // 換算ポイント
                Text(vm.chipPoint(for: p.id).signedPointString + " pt")
                    .font(AppFont.number(15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecond)
                    .frame(width: 72, alignment: .trailing)
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .foregroundStyle(Theme.accent)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
        }
    }

    private func save() {
        session.chips = vm.buildChips()
        session.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
