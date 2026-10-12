import XCTest
import SwiftData
@testable import ScoreSheet

/// 近くのスマホとの卓の共有：送る中身が落ちないこと、見る側での保存が正しいことを保証する。
final class LiveShareTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// 記録係のスマホにある卓（参加者IDは記録係の名簿のID）。
    private func makeHostSnapshot(names: [String] = ["あきら", "ばんり", "ちひろ", "だいご"]) -> SessionBackup {
        let participants = names.enumerated().map { i, name in
            Participant(name: name, colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .yonma, participants: participants, inputMode: .rawScore)
        let points = participants.enumerated().map { idx, p in
            PlayerRoundPoint(participantID: p.id, rank: idx + 1, point: [50, 10, -20, -40][idx],
                             isAutoCalculated: false, rawScore: [45000, 30000, 25000, -100][idx],
                             busterID: idx == 3 ? participants[0].id : nil)
        }
        let round = RoundResult(roundNumber: 1, points: points)
        round.session = session
        session.rounds.append(round)
        session.chips = [ChipEntry(participantID: participants[0].id, chipCount: 3),
                         ChipEntry(participantID: participants[3].id, chipCount: -3)]
        return LiveSessionStore.backup(of: session)
    }

    // MARK: 送受信

    func testSnapshotSurvivesWireRoundTrip() throws {
        let snap = LiveSnapshot(session: makeHostSnapshot(), sentAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try LiveWire.decode(LiveWire.encode(.snapshot(snap)))
        guard case .snapshot(let got) = decoded else { return XCTFail("snapshot ではない") }
        // 日時は送るときに秒単位へ丸まるので、日時以外の中身が落ちないことを確かめる。
        XCTAssertEqual(got.sentAt, snap.sentAt)
        XCTAssertEqual(got.session.id, snap.session.id)
        XCTAssertEqual(got.session.participants, snap.session.participants)
        XCTAssertEqual(got.session.chips, snap.session.chips)
        XCTAssertEqual(got.session.ruleJSON, snap.session.ruleJSON)
        XCTAssertEqual(got.session.inputModeRaw, snap.session.inputModeRaw)
        XCTAssertEqual(got.session.rounds.map(\.points), snap.session.rounds.map(\.points))
        // 受け取った内容をもう一度送っても変わらない（「保存済み」の判定に使う比較が安定する）
        guard case .snapshot(let again) = try LiveWire.decode(LiveWire.encode(.snapshot(got))) else {
            return XCTFail("snapshot ではない")
        }
        XCTAssertEqual(again, got)
    }

    func testEndedMessageRoundTrip() throws {
        let decoded = try LiveWire.decode(LiveWire.encode(.ended))
        guard case .ended = decoded else { return XCTFail("ended ではない") }
    }

    // MARK: 自分のスマホに保存

    func testSaveCopyLinksParticipantsToMyRosterByName() throws {
        let context = try makeContext()
        let mine = Player(name: "あきら", colorHex: Theme.playerPalette[5])
        context.insert(mine)
        try context.save()

        let snap = makeHostSnapshot()
        let outcome = try LiveSessionStore.saveCopy(snap, into: context)
        XCTAssertEqual(outcome, .added)

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<TableSession>()).first)
        // 同じ名前の「あきら」は自分の名簿のIDに付け替わる（プレイヤー別成績に入る）
        let akira = try XCTUnwrap(saved.participants.first { $0.name == "あきら" })
        XCTAssertEqual(akira.id, mine.id)
        XCTAssertEqual(saved.roundTotal(for: mine.id), 50)
        XCTAssertEqual(saved.chipCount(for: mine.id), 3)
        // 飛ばした人（あきら）の参照も付け替わる
        let round = try XCTUnwrap(saved.rounds.first)
        let daigo = try XCTUnwrap(saved.participants.first { $0.name == "だいご" })
        XCTAssertEqual(round.points.first { $0.participantID == daigo.id }?.busterID, mine.id)
        // 素点・ルールも落ちない
        XCTAssertEqual(saved.inputMode, .rawScore)
        XCTAssertEqual(round.points.first { $0.participantID == mine.id }?.rawScore, 45000)
    }

    func testSaveCopyAddsUnknownPlayersToRoster() throws {
        let context = try makeContext()
        let snap = makeHostSnapshot()
        try LiveSessionStore.saveCopy(snap, into: context)

        let players = try context.fetch(FetchDescriptor<Player>())
        XCTAssertEqual(Set(players.map(\.name)), ["あきら", "ばんり", "ちひろ", "だいご"])
        // 記録係側と同じIDで追加するので、次に同じ卓を保存しても同じ人として扱える
        XCTAssertEqual(Set(players.map(\.id)), Set(snap.participants.map(\.id)))
    }

    func testSavingAgainReplacesInsteadOfDuplicating() throws {
        let context = try makeContext()
        var snap = makeHostSnapshot()
        try LiveSessionStore.saveCopy(snap, into: context)

        // 記録係が2回戦目を入力した後に、もう一度保存する
        var round2 = snap.rounds[0]
        round2.id = UUID()
        round2.roundNumber = 2
        snap.rounds.append(round2)
        let outcome = try LiveSessionStore.saveCopy(snap, into: context)

        XCTAssertEqual(outcome, .updated)
        let sessions = try context.fetch(FetchDescriptor<TableSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.rounds.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RoundResult>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Player>()).count, 4)
    }

    // MARK: 一覧に出す卓の情報

    func testDiscoveryInfoIdentifiesTableAndStaysSmall() {
        let long = (0..<4).map { i in
            Participant(name: "とても長い名前のプレイヤー\(i)", colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .sanma, participants: Array(long.prefix(3)))
        let info = LiveShareCenter.discoveryInfo(for: session)
        XCTAssertEqual(info["t"], session.id.uuidString)
        XCTAssertEqual(info["v"], LiveShareCenter.protocolVersion)
        XCTAssertLessThanOrEqual(info["m"]?.count ?? 0, 40)
        // Bonjour の TXT レコードに収まる大きさ（目安 400 バイト未満）
        let bytes = info.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 2 }
        XCTAssertLessThan(bytes, 400)
    }
}
