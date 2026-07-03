import SwiftUI
import SwiftData

struct RoundInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: TableSession
    @State private var vm: RoundInputViewModel

    @AppStorage(AppSettingsKey.quickPoints) private var quickPointsRaw = "5,10,15,20,30"

    init(session: TableSession, editing round: RoundResult?, previousOrder: [UUID]?) {
        self.session = session
        _vm = State(initialValue: RoundInputViewModel(
            gameType: session.gameType,
            participants: session.participants,
            roundNumber: session.nextRoundNumber,
            previousOrder: previousOrder,
            editing: round
        ))
    }

    private var quickPoints: [Int] {
        quickPointsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {

                    // ① 順位を並べる
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "① 順位を並べる")
                        VStack(spacing: Space.sm) {
                            ForEach(vm.ranks, id: \.self) { rank in
                                seatRow(rank: rank)
                            }
                        }
                    }

                    // ② トップ自動計算 + 合計チェック
                    topAutoCard

                    // メモ
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel(text: "メモ（任意）")
                        TextField("役満・トビなど", text: $vm.memo, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(Space.md)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("\(vm.roundNumber)回戦")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { saveBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    // MARK: 順位席の行

    @ViewBuilder
    private func seatRow(rank: Int) -> some View {
        let participant = vm.participant(atRank: rank)
        NoteCard(padding: Space.md) {
            VStack(spacing: Space.md) {
                HStack(spacing: Space.md) {
                    RankBadge(rank: rank, size: 30)

                    // プレイヤー選択メニュー
                    Menu {
                        ForEach(vm.participants) { p in
                            Button {
                                vm.assign(p.id, toRank: rank)
                            } label: {
                                Label(p.name, systemImage: vm.rankedIDs[rank - 1] == p.id ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: Space.sm) {
                            if let participant {
                                PlayerDot(colorHex: participant.colorHex)
                                Text(participant.name).font(AppFont.body(17, weight: .medium)).foregroundStyle(Theme.ink)
                            } else {
                                Text("プレイヤーを選択").font(AppFont.body(17)).foregroundStyle(Theme.inkFaint)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                        }
                    }

                    Spacer()

                    if rank == 1 {
                        // トップは自動
                        PointText(value: vm.topPoint, size: 22, weight: .bold)
                    }
                }

                // 2着以下：ポイント入力
                if rank >= 2 {
                    pointInput(rank: rank)
                }
            }
        }
    }

    // MARK: ポイント入力（テンキー風 + クイック + 符号反転）

    private func pointInput(rank: Int) -> some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Button { vm.flipSign(atRank: rank) } label: {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Theme.mutedBlue)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                }

                TextField("0", text: Binding(
                    get: { vm.pointsText[rank] ?? "" },
                    set: { vm.pointsText[rank] = $0 }
                ))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(AppFont.number(22, weight: .semibold))
                .foregroundStyle(Theme.pointColor(vm.point(atRank: rank)))
                .padding(.horizontal, Space.md)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(Theme.rule, lineWidth: Theme.hairline))

                Text("pt").font(AppFont.body(14)).foregroundStyle(Theme.inkFaint)
            }
            // クイックポイント
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(quickPoints, id: \.self) { q in
                        quickChip("+\(q)") { vm.adjustPoint(byQuick: q, atRank: rank) }
                        quickChip("-\(q)") { vm.adjustPoint(byQuick: -q, atRank: rank) }
                    }
                    quickChip("C") { vm.setPoint(0, atRank: rank) }
                }
            }
        }
    }

    private func quickChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.number(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Space.md).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Radius.pill).fill(Theme.sunken))
        }
    }

    // MARK: トップ自動 + 合計チェックカード

    private var topAutoCard: some View {
        NoteCard {
            VStack(spacing: Space.md) {
                HStack {
                    Text("③ トップ自動計算").font(AppFont.label(13)).foregroundStyle(Theme.inkSecond)
                    Spacer()
                    if let top = vm.participant(atRank: 1) {
                        HStack(spacing: Space.sm) {
                            PlayerDot(colorHex: top.colorHex)
                            Text(top.name).font(AppFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                    }
                }
                Text(vm.topPoint.signedPointString)
                    .font(AppFont.number(40, weight: .bold))
                    .foregroundStyle(Theme.pointColor(vm.topPoint))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: vm.topPoint)

                HairlineRule()

                // ④ 合計チェック
                HStack(spacing: Space.sm) {
                    Image(systemName: vm.isBalanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(vm.isBalanced ? Theme.deepGreen : Theme.negative)
                    Text(vm.isBalanced ? "全員の合計は 0（釣り合っています）" : "合計が \(vm.totalCheck) です")
                        .font(AppFont.body(14, weight: .medium))
                        .foregroundStyle(vm.isBalanced ? Theme.deepGreen : Theme.negative)
                    Spacer()
                }
            }
        }
    }

    // MARK: 保存バー

    private var saveBar: some View {
        VStack(spacing: Space.sm) {
            if let msg = vm.validationMessage {
                Text(msg).font(AppFont.body(13)).foregroundStyle(Theme.negative)
            }
            Button { save() } label: { Text("この回戦を保存") }
                .buttonStyle(PrimaryButtonStyle(enabled: vm.canSave))
                .disabled(!vm.canSave)
        }
        .padding(Space.lg)
        .background(.ultraThinMaterial)
    }

    private func save() {
        guard let points = vm.buildPoints() else { return }
        if let editingID = vm.editingRoundID,
           let round = session.rounds.first(where: { $0.id == editingID }) {
            round.points = points
            round.memo = vm.memo
        } else {
            let round = RoundResult(roundNumber: vm.roundNumber, points: points, memo: vm.memo)
            round.session = session
            session.rounds.append(round)
            context.insert(round)
        }
        session.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
