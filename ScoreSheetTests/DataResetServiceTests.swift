import XCTest
import SwiftData
@testable import ScoreSheet

/// 記録の削除（プレイヤーごと・一括）。消える範囲と、消す前のバックアップを固定する。
final class DataResetServiceTests: XCTestCase {

    private var dir: URL!
    private var defaults: UserDefaults!
    private let suiteName = "DataResetServiceTests"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataResetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// A・B・C・D の4人と、ABCD の四麻・ABC の三麻・BCD の三麻を作る。
    private func seed(_ context: ModelContext) throws -> [Player] {
        let players = ["A", "B", "C", "D"].map { Player(name: $0) }
        players.forEach(context.insert)
        func add(_ who: [Int], _ type: GameType) {
            let session = TableSession(gameType: type, participants: who.map { players[$0].participant })
            let points = session.participants.enumerated().map { i, p in
                PlayerRoundPoint(participantID: p.id, rank: i + 1, point: 0, isAutoCalculated: false)
            }
            let round = RoundResult(roundNumber: 1, points: points)
            round.session = session
            session.rounds.append(round)
            context.insert(session)
        }
        add([0, 1, 2, 3], .yonma)
        add([0, 1, 2], .sanma)
        add([1, 2, 3], .sanma)
        try context.save()
        return players
    }

    private func counts(_ context: ModelContext) throws -> (sessions: Int, players: Int, rounds: Int) {
        (try context.fetchCount(FetchDescriptor<TableSession>()),
         try context.fetchCount(FetchDescriptor<Player>()),
         try context.fetchCount(FetchDescriptor<RoundResult>()))
    }

    // MARK: プレイヤーごと

    func testRosterOnlyKeepsGames() throws {
        let context = try makeContext()
        let players = try seed(context)
        let summary = try DataResetService.deletePlayer(players[0], scope: .rosterOnly,
                                                        context: context, backupDirectory: dir)
        XCTAssertEqual(summary, .init(deletedSessions: 0, deletedPlayers: 1))
        let c = try counts(context)
        XCTAssertEqual(c.sessions, 3)
        XCTAssertEqual(c.players, 3)
    }

    func testGamesOnlyDeletesThatPlayersGamesButKeepsRoster() throws {
        let context = try makeContext()
        let players = try seed(context)
        let summary = try DataResetService.deletePlayer(players[0], scope: .gamesOnly,
                                                        context: context, backupDirectory: dir)
        XCTAssertEqual(summary.deletedSessions, 2)          // A が入った四麻と三麻
        let c = try counts(context)
        XCTAssertEqual(c.sessions, 1)                       // BCD の三麻だけ残る
        XCTAssertEqual(c.players, 4)
        XCTAssertEqual(c.rounds, 1)                         // 回戦も一緒に消える
        let left = try context.fetch(FetchDescriptor<TableSession>())
        XCTAssertFalse(left[0].participants.contains { $0.id == players[0].id })
    }

    func testGamesAndRosterDeletesBoth() throws {
        let context = try makeContext()
        let players = try seed(context)
        try DataResetService.deletePlayer(players[3], scope: .gamesAndRoster,
                                          context: context, backupDirectory: dir)
        let c = try counts(context)
        XCTAssertEqual(c.sessions, 1)                       // D がいない ABC の三麻だけ
        XCTAssertEqual(c.players, 3)
    }

    // MARK: 一括

    func testResetGamesOnlyKeepsPlayersAndRules() throws {
        let context = try makeContext()
        _ = try seed(context)
        let rule = SavedRule(name: "いつもの", gameType: .yonma, inputMode: .point,
                             rule: GameRule(), pointCoefficientPer1000: 50, chipPointCoefficient: 100)
        SavedRuleStore.save([rule], defaults)
        defaults.set(UUID().uuidString, forKey: AppSettingsKey.resumeSessionID)

        let summary = try DataResetService.resetAll(scope: .gamesOnly, context: context,
                                                    defaults: defaults, backupDirectory: dir)
        XCTAssertEqual(summary.deletedSessions, 3)
        let c = try counts(context)
        XCTAssertEqual(c.sessions, 0)
        XCTAssertEqual(c.rounds, 0)
        XCTAssertEqual(c.players, 4)
        XCTAssertEqual(SavedRuleStore.load(defaults).count, 1)
        XCTAssertNil(defaults.string(forKey: AppSettingsKey.resumeSessionID))
    }

    func testResetEverythingClearsRulesAndDefaultRule() throws {
        let context = try makeContext()
        _ = try seed(context)
        let rule = SavedRule(name: "いつもの", gameType: .yonma, inputMode: .point,
                             rule: GameRule(), pointCoefficientPer1000: 50, chipPointCoefficient: 100)
        SavedRuleStore.save([rule], defaults)
        defaults.set(rule.id.uuidString, forKey: AppSettingsKey.defaultSavedRuleID)

        let summary = try DataResetService.resetAll(scope: .everything, context: context,
                                                    defaults: defaults, backupDirectory: dir)
        XCTAssertEqual(summary, .init(deletedSessions: 3, deletedPlayers: 4, deletedRules: 1))
        let c = try counts(context)
        XCTAssertEqual(c.sessions + c.players + c.rounds, 0)
        XCTAssertTrue(SavedRuleStore.load(defaults).isEmpty)
        XCTAssertNil(defaults.string(forKey: AppSettingsKey.defaultSavedRuleID))
    }

    // MARK: 消す前のバックアップ

    func testBackupIsTakenBeforeResetAndCanRestore() throws {
        let context = try makeContext()
        _ = try seed(context)
        let rule = SavedRule(name: "いつもの", gameType: .yonma, inputMode: .point,
                             rule: GameRule(), pointCoefficientPer1000: 50, chipPointCoefficient: 100)
        SavedRuleStore.save([rule], defaults)

        try DataResetService.resetAll(scope: .everything, context: context,
                                      defaults: defaults, backupDirectory: dir)

        let snap = try XCTUnwrap(AutoBackupService.list(in: dir).first)
        XCTAssertEqual(snap.sessionCount, 3)
        XCTAssertEqual(snap.playerCount, 4)
        let file = try BackupService.decode(Data(contentsOf: snap.url))
        XCTAssertEqual(file.savedRules?.map(\.name), ["いつもの"])   // 消す前のルールも入っている

        try BackupService.restore(file, into: context, defaults: defaults)
        let c = try counts(context)
        XCTAssertEqual(c.sessions, 3)
        XCTAssertEqual(c.players, 4)
    }
}
