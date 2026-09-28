import XCTest
import SwiftData
@testable import ScoreSheet

/// 他アプリの成績CSVの取り込み。実際に書き出されたファイルの一部をそのまま使って確認する。
final class CSVImportServiceTests: XCTestCase {

    /// 実ファイルの抜粋（見出しの「スコア 」末尾の空白も実物どおり）。
    /// ・2026/08/13：チップは1回戦目の行だけ／1000点=100・チップ1枚=500
    /// ・2025/06/08：1回戦目が全員0点の空行（チップだけ入っている）／チップ1枚=200
    /// ・2024/08/27：同じ部屋名・日付で「1回戦」が2回続く → 別ゲーム
    private let sample = """
    部屋名,日付,回戦数,いずみ 点数,いずみ スコア ,いずみ チップ,いずみ 収支,えんどう 点数,えんどう スコア ,えんどう チップ,えんどう 収支,おーいし 点数,おーいし スコア ,おーいし チップ,おーいし 収支
    ,2026/08/13,1,22000,-48.0,8,-800,49000,54.0,-16,-2600,34000,-6.0,8,3400
    ,2026/08/13,2,35000,25.0,-,2500,71000,76.0,-,7600,-1000,-101.0,-,-10100
    ,2026/08/13,3,10000,-60.0,-,-6000,28000,-12.0,-,-1200,67000,72.0,-,7200
    ,2025/06/08,1,0,0.0,22,4400,0,0.0,-29,-5800,0,0.0,7,1400
    ,2025/06/08,2,27000,-33.0,-,-3300,-2000,-122.0,-,-12200,80000,155.0,-,15500
    ,2025/06/08,3,-10000,-150.0,-,-15000,79000,134.0,-,13400,36000,16.0,-,1600
    2024/08/27,2024/08/27,1,76000,81.0,-20,4050,31000,21.0,-20,1050,-2000,-102.0,-20,-5100
    2024/08/27,2024/08/27,1,79000,84.0,-20,4200,13000,-57.0,-20,-2850,13000,-27.0,-20,-1350
    """

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: 解析

    func testParsesGamesPlayersAndRounds() throws {
        let preview = try CSVImportService.parse(text: sample)
        XCTAssertEqual(preview.playerNames, ["いずみ", "えんどう", "おーいし"])
        XCTAssertEqual(preview.games.count, 4)
        XCTAssertEqual(preview.games.map(\.rounds.count), [3, 2, 1, 1])
        XCTAssertEqual(preview.skippedEmptyRounds, 1)
        XCTAssertEqual(preview.roundedPointCount, 0)
        XCTAssertTrue(preview.games.allSatisfy { $0.gameType == .sanma })

        let first = preview.games[0].rounds[0]
        XCTAssertEqual(first.points, [-48, 54, -6])
        XCTAssertEqual(first.rawScores, [22000, 49000, 34000])
    }

    func testChipsAreSummedIncludingEmptyRound() throws {
        let preview = try CSVImportService.parse(text: sample)
        XCTAssertEqual(preview.games[0].chips, [8, -16, 8])
        // 空行（全員0点）の回戦は数えないが、そこに入っていたチップは反映する。
        XCTAssertEqual(preview.games[1].chips, [22, -29, 7])
    }

    func testCoefficientsAreEstimatedFromBalanceColumn() throws {
        let preview = try CSVImportService.parse(text: sample)
        XCTAssertEqual(preview.games[0].pointCoefficientPer1000, 100)
        XCTAssertEqual(preview.games[0].chipPointCoefficient, 500)
        XCTAssertEqual(preview.games[1].pointCoefficientPer1000, 100)
        XCTAssertEqual(preview.games[1].chipPointCoefficient, 200)
        XCTAssertEqual(preview.games[2].pointCoefficientPer1000, 50)
    }

    func testRankUsesRawScore() {
        let round = ImportedRound(rawScores: [22000, 49000, 34000], points: [-48, 54, -6])
        XCTAssertEqual(CSVImportService.rankOrder(round), [3, 1, 2])
    }

    func testQuotedFieldsAndCRLF() {
        let rows = CSVImportService.parseCSV("a,\"b,c\",\"d\"\"e\"\r\n1,2,3\r\n")
        XCTAssertEqual(rows, [["a", "b,c", "d\"e"], ["1", "2", "3"]])
    }

    func testUTF8WithBOMAndShiftJIS() throws {
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(sample.data(using: .utf8)!)
        XCTAssertEqual(try CSVImportService.parse(bom).games.count, 4)

        let sjis = try XCTUnwrap(sample.data(using: .shiftJIS))
        XCTAssertEqual(try CSVImportService.parse(sjis).games.count, 4)
    }

    func testRejectsUnknownFormat() {
        XCTAssertThrowsError(try CSVImportService.parse(text: "名前,点数\nA,1\n")) { error in
            XCTAssertEqual(error as? CSVImportError, .unsupportedFormat)
        }
    }

    // MARK: 保存

    func testApplyReproducesOriginalTotals() throws {
        let context = try makeContext()
        let preview = try CSVImportService.parse(text: sample)
        let summary = try CSVImportService.apply(preview, tag: "前のアプリ", into: context)

        XCTAssertEqual(summary.addedSessions, 4)
        XCTAssertEqual(summary.addedPlayers, 3)
        XCTAssertEqual(summary.skippedDuplicates, 0)

        let sessions = try context.fetch(FetchDescriptor<TableSession>())
        let aug = try XCTUnwrap(sessions.first {
            Calendar.current.dateComponents([.year, .month, .day], from: $0.date) == DateComponents(year: 2026, month: 8, day: 13)
        })
        XCTAssertEqual(aug.inputMode, .point)
        XCTAssertEqual(aug.tags, ["前のアプリ"])
        XCTAssertEqual(aug.rounds.count, 3)

        // 元アプリの「収支」合計と同じ総合ポイントになる。
        // いずみ -800+2500-6000 / えんどう -2600+7600-1200 / おーいし 3400-10100+7200
        let totals = Dictionary(uniqueKeysWithValues:
            ScoreCalculator.finalResults(for: aug).map { ($0.name, $0.grandTotal) })
        XCTAssertEqual(totals["いずみ"], -4300)
        XCTAssertEqual(totals["えんどう"], 3800)
        XCTAssertEqual(totals["おーいし"], 500)

        // 素点も残る（通算成績のトビ率に使う）。
        let round2 = try XCTUnwrap(aug.sortedRounds.dropFirst().first)
        XCTAssertEqual(round2.points.map(\.rawScore), [35000, 71000, -1000])
    }

    func testApplyTwiceSkipsDuplicates() throws {
        let context = try makeContext()
        let preview = try CSVImportService.parse(text: sample)
        try CSVImportService.apply(preview, tag: nil, into: context)
        let second = try CSVImportService.apply(preview, tag: nil, into: context)

        XCTAssertEqual(second.addedSessions, 0)
        XCTAssertEqual(second.skippedDuplicates, 4)
        XCTAssertEqual(second.addedPlayers, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TableSession>()).count, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Player>()).count, 3)
    }

    func testApplyLinksExistingRosterPlayer() throws {
        let context = try makeContext()
        let izumi = Player(name: "いずみ")
        context.insert(izumi)
        try context.save()

        let preview = try CSVImportService.parse(text: sample)
        let summary = try CSVImportService.apply(preview, tag: nil, into: context)
        XCTAssertEqual(summary.addedPlayers, 2)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<TableSession>()).first)
        XCTAssertTrue(session.participants.contains { $0.id == izumi.id })
    }

    func testPointModeEditKeepsImportedRawScore() throws {
        let context = try makeContext()
        let preview = try CSVImportService.parse(text: sample)
        try CSVImportService.apply(preview, tag: nil, into: context)
        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<TableSession>())
            .first { $0.rounds.count == 3 })

        // チップだけ直して保存しても、ポイントが同じ回戦の素点は消えない。
        var input = RoundPersistence.load(from: session)
        input.chips = ["9", "-17", "8"]
        XCTAssertTrue(RoundPersistence.save(input, to: session, context: context))
        XCTAssertEqual(session.sortedRounds[0].points.map(\.rawScore), [22000, 49000, 34000])
    }
}
