import Combine
import Foundation

struct RiskNotice: Equatable, Sendable {
    let title: String
    let message: String
    let confirmationTitle: String

    static let firstUse = Self(
        title: "使用前請先了解風險",
        message:
            "位置模擬可能受第三方服務條款限制，並可能影響帳號。請先自行確認你使用之服務的規則。",
        confirmationTitle: "我已了解"
    )

    static let simulationStart = Self(
        title: "確認開始位置模擬？",
        message:
            "這會改變已連接 iPhone 的模擬位置。第三方服務可能限制此行為，請自行承擔相關帳號風險。",
        confirmationTitle: "了解風險並開始"
    )
}

@MainActor
final class RiskNoticeStore: ObservableObject {
    static let acknowledgedKey =
        "hasAcknowledgedThirdPartyLocationSimulationRisk"

    @Published private(set) var needsFirstUseAcknowledgement: Bool
    let firstUseNotice = RiskNotice.firstUse

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsFirstUseAcknowledgement = !defaults.bool(
            forKey: Self.acknowledgedKey
        )
    }

    func acknowledgeFirstUse() {
        defaults.set(true, forKey: Self.acknowledgedKey)
        needsFirstUseAcknowledgement = false
    }

    func noticeForSimulationStart() -> RiskNotice {
        RiskNotice.simulationStart
    }
}
