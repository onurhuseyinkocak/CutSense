import Foundation
import Observation

/// Reduced-price Pro windows: one welcome offer (24 h from the first save) and one 15-minute flash offer
/// (≥ 7 days after the welcome ended, ≥ 3 saves). End times are absolute and survive relaunch.
@MainActor @Observable
final class OfferCenter {
    enum Kind: String { case welcome, flash }
    struct Active: Equatable { let kind: Kind; let endsAt: Date }

    static let shared = OfferCenter()

    private(set) var active: Active?

    enum Key {
        static let kind = "offer_kind"
        static let endsAt = "offer_ends_at"
        static let welcomeDone = "offer_welcome_done"
        static let flashDone = "offer_flash_done"
        static let autoShown = "offer_auto_shown"
        static let lastEndedAt = "offer_last_ended_at"
        static let clockHigh = "offer_clock_high"
        static let saves = "stat_saves"
        static let all = [kind, endsAt, welcomeDone, flashDone, autoShown, lastEndedAt, clockHigh, saves]
    }

    nonisolated static let welcomeSeconds: TimeInterval = 86_400
    nonisolated static let flashSeconds: TimeInterval = 900
    static let flashGap: TimeInterval = 7 * 86_400
    static let flashMinSaves = 3
    /// Tolerated backwards clock drift before an active offer is treated as gamed.
    static let rollbackTolerance: TimeInterval = 120

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let canOffer: @MainActor () -> Bool

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         canOffer: @escaping @MainActor () -> Bool = { ProStore.shared.offerPrices != nil && !ProStore.shared.isPro }) {
        self.defaults = defaults
        self.now = now
        self.canOffer = canOffer
        if let raw = defaults.string(forKey: Key.kind), let kind = Kind(rawValue: raw),
           defaults.object(forKey: Key.endsAt) != nil {
            active = Active(kind: kind, endsAt: Date(timeIntervalSince1970: defaults.double(forKey: Key.endsAt)))
        }
        refresh()
    }

    func refresh() {
        let t = now().timeIntervalSince1970
        let high = defaults.double(forKey: Key.clockHigh)
        if t < high - Self.rollbackTolerance {
            if active != nil { end(at: high) }
            return
        }
        defaults.set(max(high, t), forKey: Key.clockHigh)
        if let active, t >= active.endsAt.timeIntervalSince1970 || ProEntitlement.isPro {
            end(at: min(t, active.endsAt.timeIntervalSince1970))
        }
    }

    func noteSave() {
        refresh()
        let saves = defaults.integer(forKey: Key.saves) + 1
        defaults.set(saves, forKey: Key.saves)
        let t = now().timeIntervalSince1970
        let high = defaults.double(forKey: Key.clockHigh)
        // Offline / no products / Pro: nothing starts and no right is spent. A rolled-back clock would end it at once.
        guard active == nil, canOffer(), t >= high - Self.rollbackTolerance else { return }
        if !defaults.bool(forKey: Key.welcomeDone) {
            defaults.set(true, forKey: Key.welcomeDone)
            start(.welcome, endsAt: t + Self.duration(Self.welcomeSeconds))
        } else if !defaults.bool(forKey: Key.flashDone), saves >= Self.flashMinSaves,
                  max(t, high) >= defaults.double(forKey: Key.lastEndedAt) + Self.flashGap {
            defaults.set(true, forKey: Key.flashDone)
            start(.flash, endsAt: t + Self.duration(Self.flashSeconds))
        }
    }

    /// True exactly once per install: the welcome offer is live and the sheet has not opened on its own yet.
    func takeAutoPresent() -> Bool {
        refresh()
        guard active?.kind == .welcome, !defaults.bool(forKey: Key.autoShown), canOffer() else { return false }
        defaults.set(true, forKey: Key.autoShown)
        return true
    }

    private func start(_ kind: Kind, endsAt: TimeInterval) {
        defaults.set(kind.rawValue, forKey: Key.kind)
        defaults.set(endsAt, forKey: Key.endsAt)
        active = Active(kind: kind, endsAt: Date(timeIntervalSince1970: endsAt))
    }

    private func end(at time: TimeInterval) {
        defaults.removeObject(forKey: Key.kind)
        defaults.removeObject(forKey: Key.endsAt)
        defaults.set(time, forKey: Key.lastEndedAt)
        active = nil
    }

    nonisolated static func duration(_ standard: TimeInterval) -> TimeInterval {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CUTSENSE_OFFER_SECONDS"], let seconds = TimeInterval(raw), seconds > 0 {
            return seconds
        }
        #endif
        return standard
    }
}

enum OnboardingGate {
    static let key = "onboarding_done_v1"

    /// Unit-test hosts and DEBUG automation skip onboarding; `CUTSENSE_RESET_ONBOARDING=1` overrides all of it.
    static var bypass: Bool {
        let env = ProcessInfo.processInfo.environment
        #if DEBUG
        if env["CUTSENSE_RESET_ONBOARDING"] == "1" { return false }
        if env["CUTSENSE_SKIP_ONBOARDING"] == "1" || env["CUTSENSE_AUTORUN_VIDEO_URL"] != nil
            || env["CUTSENSE_SHOW_PAYWALL"] != nil { return true }
        #endif
        return env["XCTestConfigurationFilePath"] != nil
    }

    /// Call from the App init, before `OfferCenter.shared` is first touched.
    static func applyDebugHooks() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        if env["CUTSENSE_RESET_ONBOARDING"] == "1" {
            defaults.removeObject(forKey: key)
            OfferCenter.Key.all.forEach(defaults.removeObject(forKey:))
        }
        let forced: (OfferCenter.Kind, TimeInterval)?
        if env["CUTSENSE_FORCE_FLASH_OFFER"] == "1" {
            forced = (.flash, OfferCenter.flashSeconds)
        } else if env["CUTSENSE_FORCE_WELCOME_OFFER"] == "1" {
            forced = (.welcome, OfferCenter.welcomeSeconds)
        } else {
            forced = nil
        }
        if let forced {
            let (kind, seconds) = forced
            let t = Date().timeIntervalSince1970
            defaults.set(kind.rawValue, forKey: OfferCenter.Key.kind)
            defaults.set(t + OfferCenter.duration(seconds), forKey: OfferCenter.Key.endsAt)
            defaults.set(true, forKey: kind == .welcome ? OfferCenter.Key.welcomeDone : OfferCenter.Key.flashDone)
            defaults.set(t, forKey: OfferCenter.Key.clockHigh)
        }
        #endif
    }
}
