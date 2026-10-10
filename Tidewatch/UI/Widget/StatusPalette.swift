import SwiftUI
import TidewatchCore

enum StatusPalette {
    /// nil = the dim lamp shown when there are no sessions.
    static func lamp(_ status: SessionStatus?) -> Color {
        switch status {
        case .working: return GlassColor.success
        case .needsApproval, .awaitingReview: return GlassColor.attention
        case .idle: return GlassColor.idleLamp
        case nil: return GlassColor.idleLamp.opacity(0.6)
        }
    }

    static func text(_ status: SessionStatus) -> Color {
        switch status {
        case .needsApproval: return GlassColor.attention
        case .idle: return GlassColor.textTertiary
        case .working, .awaitingReview: return GlassColor.textSecondary
        }
    }

    static func glows(_ status: SessionStatus?) -> Bool {
        status == .working || status == .needsApproval || status == .awaitingReview
    }
}
