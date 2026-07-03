import Foundation
import SwiftData

/// 名簿上のプレイヤー（メンバー管理）。
@Model
final class Player {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    var createdAt: Date

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
