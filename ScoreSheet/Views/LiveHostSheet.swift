import SwiftUI

/// 記録係が卓をみんなに共有する（やめる）シート。
struct LiveHostSheet: View {
    let session: TableSession
    @EnvironmentObject private var live: LiveShareCenter
    @Environment(\.dismiss) private var dismiss

    private var isSharingThis: Bool { live.hostingSessionID == session.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("この卓をみんなに共有")
                            .font(AppFont.heading(22))
                            .foregroundStyle(Theme.ink)
                        Text("近くにいる人のスマホで、この卓の成績をリアルタイムに見られるようにします。点数を入力できるのは、このスマホだけです。")
                            .font(AppFont.body(14))
                            .foregroundStyle(Theme.inkSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statusCard

                    if isSharingThis {
                        Button(role: .destructive) {
                            live.stopHosting()
                        } label: {
                            Label("共有をやめる", systemImage: "stop.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button {
                            live.startHosting(session)
                        } label: {
                            Label("共有をはじめる", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "見る人の操作", systemImage: "iphone")
                        VStack(alignment: .leading, spacing: Space.sm) {
                            guideRow(1, "スコアシートのホームで「近くの卓を見る」を押す")
                            guideRow(2, "出てきたこの卓をタップする")
                            guideRow(3, "終わったら「自分のスマホに保存」で記録を残せる")
                        }
                    }

                    Text("Wi-Fi と Bluetooth をオンにして、同じ部屋で使ってください。はじめて使うときは「ローカルネットワーク」の許可を求められるので「許可」を選んでください。画面を離れても共有は続き、ホームに戻ると終わります。")
                        .font(AppFont.body(12))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var statusCard: some View {
        NoteCard(padding: Space.lg) {
            HStack(spacing: Space.md) {
                LiveDot(color: isSharingThis ? Theme.accent : Theme.inkFaint, pulsing: isSharingThis)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSharingThis ? "共有中" : "共有していません")
                        .font(AppFont.body(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(isSharingThis
                         ? (live.viewerCount == 0 ? "見ている人を待っています" : "\(live.viewerCount)人が見ています")
                         : "共有をはじめると、近くのスマホに卓が表示されます")
                        .font(AppFont.body(13))
                        .foregroundStyle(Theme.inkSecond)
                }
                Spacer()
                if isSharingThis {
                    Text("\(live.viewerCount)")
                        .font(AppFont.number(28, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text("人").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: live.viewerCount)
    }

    private func guideRow(_ n: Int, _ text: String) -> some View {
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
}
