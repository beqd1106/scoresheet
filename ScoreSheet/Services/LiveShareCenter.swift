import Foundation
import MultipeerConnectivity
import SwiftUI

/// 同じ部屋のスマホ同士で、卓の成績をリアルタイムに見せ合う仕組み。
///
/// ・記録係（ホスト）… 卓を「共有中」として近くに知らせ、入力のたびに卓の内容を丸ごと送る。
/// ・見る人（ビューア）… 近くで共有中の卓を探し、選んだ卓の最新の内容を受け取って表示する。
/// 入力できるのは記録係だけ（見る側からは何も送らない）ので、数字の食い違いが起きない。
/// 通信は MultipeerConnectivity（Wi-Fi / Bluetooth で端末同士が直接つながる）。サーバーは使わない。
@MainActor
final class LiveShareCenter: NSObject, ObservableObject {

    /// サービス種別（1〜15文字・英小文字/数字/ハイフン）。Info.plist の NSBonjourServices と一致させる。
    nonisolated static let serviceType = "scoresheet-live"
    /// 通信内容の版。中身の形式を変えたら上げ、違う版の卓は一覧に出さない。
    nonisolated static let protocolVersion = "1"

    // MARK: 記録係の状態

    @Published private(set) var hostingSessionID: UUID?
    @Published private(set) var viewerCount = 0
    private var hostedSession: TableSession?

    // MARK: 見る側の状態

    /// 近くで共有中の卓。
    struct NearbyTable: Identifiable, Equatable {
        let id: UUID            // 卓のID
        let peerID: MCPeerID
        let gameName: String
        let members: String
    }

    enum ViewerState: Equatable {
        case idle
        case searching          // 一覧から卓を選ぶ前
        case connecting         // 選んだ卓につないでいる
        case live               // 受信中
        case reconnecting       // つながりが切れ、つなぎ直している
        case ended              // 記録係が共有をやめた
    }

    @Published private(set) var nearbyTables: [NearbyTable] = []
    @Published private(set) var viewerState: ViewerState = .idle
    @Published private(set) var watchingTableID: UUID?
    @Published private(set) var latest: LiveSnapshot?
    /// 探し始められなかったとき（ローカルネットワークの許可がない等）の案内。
    @Published private(set) var browseFailed = false

    // MARK: 通信

    private let myPeerID: MCPeerID
    private var mcSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var connectedPeers: Set<MCPeerID> = []

    override init() {
        // 表示名は相手の画面には出さない（卓の情報は discoveryInfo で送る）。
        myPeerID = MCPeerID(displayName: "ScoreSheet-\(Int.random(in: 1000...9999))")
        super.init()
    }

    var isHosting: Bool { hostingSessionID != nil }

    // MARK: - 記録係

    func startHosting(_ session: TableSession) {
        stopViewing()
        teardownHost(notify: true)
        beginHosting(session)
    }

    private func beginHosting(_ session: TableSession) {
        hostedSession = session
        hostingSessionID = session.id
        mcSession = makeSession()

        let adv = MCNearbyServiceAdvertiser(peer: myPeerID,
                                            discoveryInfo: Self.discoveryInfo(for: session),
                                            serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
    }

    /// 入力のたびに呼ぶ。共有中の卓でなければ何もしない。
    func publish(_ session: TableSession) {
        guard hostingSessionID == session.id else { return }
        hostedSession = session
        send(snapshotMessage(of: session), to: Array(connectedPeers))
    }

    func stopHosting() {
        teardownHost(notify: true)
    }

    private func teardownHost(notify: Bool) {
        guard isHosting else { return }
        if notify && !connectedPeers.isEmpty {
            send(.ended, to: Array(connectedPeers))
        }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        let old = mcSession
        mcSession = nil
        // 「終了」の通知が届くよう、少し待ってから切る。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            old?.disconnect()
        }
        connectedPeers.removeAll()
        hostedSession = nil
        hostingSessionID = nil
        viewerCount = 0
    }

    // MARK: - 見る側

    func startViewing() {
        stopHosting()
        guard browser == nil else { return }
        nearbyTables = []
        browseFailed = false
        watchingTableID = nil
        latest = nil
        viewerState = .searching
        mcSession = makeSession()
        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
    }

    func watch(_ table: NearbyTable) {
        if watchingTableID != table.id { latest = nil }
        watchingTableID = table.id
        viewerState = .connecting
        invite(table.peerID)
    }

    /// 見ている卓から抜けて一覧に戻る。
    func leaveTable() {
        mcSession?.disconnect()
        connectedPeers.removeAll()
        mcSession = makeSession()
        watchingTableID = nil
        latest = nil
        viewerState = browser == nil ? .idle : .searching
    }

    func stopViewing() {
        guard browser != nil || viewerState != .idle else { return }
        browser?.stopBrowsingForPeers()
        browser = nil
        mcSession?.disconnect()
        mcSession = nil
        connectedPeers.removeAll()
        nearbyTables = []
        watchingTableID = nil
        latest = nil
        viewerState = .idle
    }

    private var wentBackground = false

    /// アプリの前面・背面の切り替え。背面にいる間に切れた通信を、前面に戻ったときに張り直す。
    /// （コントロールセンターを開いた程度の一時的な切り替えでは張り直さない）
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wentBackground = true
        case .active where wentBackground:
            wentBackground = false
            resume()
        default:
            break
        }
    }

    private func resume() {
        if let session = hostedSession {
            teardownHost(notify: false)
            beginHosting(session)
        } else if browser != nil {
            let watching = watchingTableID
            let keep = latest
            let state = viewerState
            browser?.stopBrowsingForPeers()
            browser = nil
            startViewing()
            // 見ていた卓は、見つかりしだい自動でつなぎ直す。
            if let watching {
                watchingTableID = watching
                latest = keep
                viewerState = state == .ended ? .ended : .reconnecting
            }
        }
    }

    // MARK: - 内部

    private func makeSession() -> MCSession {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }

    private func invite(_ peer: MCPeerID) {
        guard let s = mcSession else { return }
        browser?.invitePeer(peer, to: s, withContext: nil, timeout: 15)
    }

    private func snapshotMessage(of session: TableSession) -> LiveMessage {
        .snapshot(LiveSnapshot(session: LiveSessionStore.backup(of: session), sentAt: Date()))
    }

    private func send(_ message: LiveMessage, to peers: [MCPeerID]) {
        guard !peers.isEmpty, let s = mcSession, let data = try? LiveWire.encode(message) else { return }
        try? s.send(data, toPeers: peers, with: .reliable)
    }

    /// 一覧に出す卓の情報。discoveryInfo は小さく保つ必要があるため名前は短く切る。
    nonisolated static func discoveryInfo(for session: TableSession) -> [String: String] {
        let members = session.participants.map(\.name).joined(separator: "・")
        return [
            "v": protocolVersion,
            "t": session.id.uuidString,
            "g": session.gameType.displayName,
            "m": String(members.prefix(40)),
        ]
    }

    // MARK: イベント処理（MainActor）

    private func handleStateChange(_ peer: MCPeerID, _ state: MCSessionState, in session: MCSession) {
        guard session === mcSession else { return }   // 古いセッションからの通知は無視
        switch state {
        case .connected:
            connectedPeers.insert(peer)
            if let hosted = hostedSession {
                viewerCount = connectedPeers.count
                send(snapshotMessage(of: hosted), to: [peer])
            }
        case .notConnected:
            connectedPeers.remove(peer)
            if isHosting {
                viewerCount = connectedPeers.count
            } else if let watching = watchingTableID, viewerState != .ended {
                viewerState = latest == nil ? .connecting : .reconnecting
                // 相手がまだ近くにいれば、少し待ってつなぎ直す。
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard self.watchingTableID == watching,
                          self.viewerState == .connecting || self.viewerState == .reconnecting,
                          let table = self.nearbyTables.first(where: { $0.id == watching }) else { return }
                    self.invite(table.peerID)
                }
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    private func handleReceive(_ data: Data, in session: MCSession) {
        guard session === mcSession, !isHosting, let message = try? LiveWire.decode(data) else { return }
        switch message {
        case .snapshot(let snap):
            guard snap.session.id == watchingTableID else { return }
            latest = snap
            viewerState = .live
        case .ended:
            viewerState = .ended
        }
    }

    private func handleFound(_ peer: MCPeerID, info: [String: String]?) {
        guard let info, info["v"] == Self.protocolVersion,
              let raw = info["t"], let tableID = UUID(uuidString: raw) else { return }
        let table = NearbyTable(id: tableID, peerID: peer,
                                gameName: info["g"] ?? "",
                                members: info["m"] ?? "")
        nearbyTables.removeAll { $0.id == tableID || $0.peerID == peer }
        nearbyTables.append(table)

        // 見ていた卓がまた見つかった（記録係が共有を再開した等）なら自動でつなぐ。
        if watchingTableID == tableID, viewerState != .live {
            viewerState = latest == nil ? .connecting : .reconnecting
            invite(peer)
        }
    }

    private func handleLost(_ peer: MCPeerID) {
        nearbyTables.removeAll { $0.peerID == peer }
    }
}

// MARK: - MCSessionDelegate（別スレッドで呼ばれるので MainActor へ移す）

extension LiveShareCenter: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.handleStateChange(peerID, state, in: session) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.handleReceive(data, in: session) }
    }

    nonisolated func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at url: URL?, withError e: Error?) {}
}

// MARK: - 記録係：見る人からの接続を受け入れる

extension LiveShareCenter: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 同じ部屋にいる前提なので誰でも見られる（見る側からは入力できない）。
        Task { @MainActor in
            invitationHandler(self.mcSession != nil, self.mcSession)
        }
    }
}

// MARK: - 見る側：近くの卓を探す

extension LiveShareCenter: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.handleFound(peerID, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.handleLost(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.browseFailed = true }
    }
}
