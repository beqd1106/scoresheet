import XCTest
import SwiftData
@testable import ScoreSheet

/// 以前のバージョンが入れたサンプルだけを消し、利用者のデータは残すことを保証する。
final class SampleDataServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suite = "SampleDataServiceTests"

    override func setUpWithError() throws {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// 旧バージョンの seed と同じ内容を入れる。
    private func seedLegacy(_ context: ModelContext) -> [Player] {
        let names = ["あきら", "ばんり", "ちひろ", "だいご"]
        let players = names.enumerated().map { Player(name: $1, colorHex: Theme.playerPalette[$0]) }
        players.forEach { context.insert($0) }
        context.insert(SampleDataService.makeYonmaSample(players[0], players[1], players[2], players[3]))
        context.insert(SampleDataService.makeSanmaSample(players[0], players[1], players[2]))
        try? context.save()
        return players
    }

    func testRemovesUntouchedSamples() throws {
        let context = ModelContext(container)
        _ = seedLegacy(context)

        SampleDataService.removeLegacySamplesIfNeeded(context, defaults: defaults)

        XCTAssertEqual(try context.fetch(FetchDescriptor<TableSession>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Player>()).count, 0)
        XCTAssertTrue(defaults.bool(forKey: SampleDataService.legacyCleanupKey))
    }

    func testKeepsUserDataAndSamplePlayersUsedElsewhere() throws {
        let context = ModelContext(container)
        let players = seedLegacy(context)
        let mine = Player(name: "たろう", colorHex: Theme.playerPalette[4])
        context.insert(mine)
        // サンプルの「あきら」を自分の卓でも使っている
        let own = TableSession(gameType: .sanma,
                               participants: [players[0].participant, mine.participant,
                                              Participant(name: "ゲスト", colorHex: Theme.playerPalette[5])])
        context.insert(own)
        try context.save()

        SampleDataService.removeLegacySamplesIfNeeded(context, defaults: defaults)

        let sessions = try context.fetch(FetchDescriptor<TableSession>())
        XCTAssertEqual(sessions.map(\.id), [own.id])
        let names = Set(try context.fetch(FetchDescriptor<Player>()).map(\.name))
        XCTAssertEqual(names, ["あきら", "たろう"])
    }

    func testKeepsSampleSessionThatWasEdited() throws {
        let context = ModelContext(container)
        _ = seedLegacy(context)
        let yonma = try context.fetch(FetchDescriptor<TableSession>()).first { $0.memo == "四麻サンプル" }!
        yonma.rounds.append(RoundResult(roundNumber: 4, points: []))
        try context.save()

        SampleDataService.removeLegacySamplesIfNeeded(context, defaults: defaults)

        let memos = try context.fetch(FetchDescriptor<TableSession>()).map(\.memo)
        XCTAssertEqual(memos, ["四麻サンプル"])
        // 残った卓の参加者（4人）は名簿からも消さない
        XCTAssertEqual(try context.fetch(FetchDescriptor<Player>()).count, 4)
    }

    func testRunsOnlyOnce() throws {
        let context = ModelContext(container)
        defaults.set(true, forKey: SampleDataService.legacyCleanupKey)
        _ = seedLegacy(context)

        SampleDataService.removeLegacySamplesIfNeeded(context, defaults: defaults)

        XCTAssertEqual(try context.fetch(FetchDescriptor<TableSession>()).count, 2)
    }
}
