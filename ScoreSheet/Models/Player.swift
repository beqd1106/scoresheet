import Foundation
import SwiftData

/// 名簿上のプレイヤー（メンバー管理）。
@Model
final class Player {
    // CloudKit 同期のため全プロパティにデフォルト値を持たせる（制約）。
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = Theme.playerPalette[0]
    var iconName: String = "person.fill"
    var createdAt: Date = Date()

    init(name: String,
         colorHex: String = Theme.playerPalette[0],
         iconName: String = "person.fill") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = Date()
    }

    /// 卓参加者スナップショットへ変換。
    var participant: Participant {
        Participant(id: id, name: name, colorHex: colorHex)
    }
}
