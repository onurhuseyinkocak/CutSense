import Foundation
import Observation
import UIKit

/// One flash offer per install: it becomes due `flashDelay` after onboarding finishes without a purchase, opens the
/// first time the app is in the foreground after that, and lasts `flashSeconds` from that moment. Times are absolute
/// and survive relaunch; Pro or a rolled-back clock cancels it for good.
@MainActor @Observable
final class OfferCenter {
    enum Kind: String { case welcome, flash }
    struct Active: Equatable { let kind: Kind; let endsAt: Date }

    static let shared = OfferCenter()

    /// Non-nil only inside the flash window; nil while pending.
    private(set) var active: Active?
    /// Scheduled flash start while it is still in the future.
    private(set) var pendingStart: Date?

    enum Key {
        static let armed = "offer_flash_armed"
        static let startsAt = "offer_flash_starts_at"
        static let endsAt = "offer_flash_ends_at"
        static let autoShown = "offer_auto_shown"
        static let clockHigh = "offer_clock_high"
        static let saves = "stat_saves"
        static let opened = "offer_flash_opened"
        static let all = [armed, startsAt, endsAt, autoShown, clockHigh, saves, opened]
    }

    nonisolated static let flashDelaySeconds: TimeInterval = 600
    nonisolated static let flashSeconds: TimeInterval = 900
    /// Tolerated backwards clock drift before the offer is treated as gamed.
    static let rollbackTolerance: TimeInterval = 120

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let canOffer: @MainActor () -> Bool
    @ObservationIgnored private let isForeground: @MainActor () -> Bool
    @ObservationIgnored private var wake: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         canOffer: @escaping @MainActor () -> Bool = { ProStore.shared.offerPrices != nil && !ProStore.shared.isPro },
         isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.defaults = defaults
        self.now = now
        self.canOffer = canOffer
        self.isForeground = isForeground
        refresh()
    }

    func refresh() {
        let t = now().timeIntervalSince1970
        let high = defaults.double(forKey: Key.clockHigh)
        if t < high - Self.rollbackTolerance {
            cancel()
            return
        }
        defaults.set(max(high, t), forKey: Key.clockHigh)
        guard defaults.object(forKey: Key.startsAt) != nil else { return publish(nil, nil) }
        var start = defaults.double(forKey: Key.startsAt)
        var end = defaults.double(forKey: Key.endsAt)
        if t >= start, !defaults.bool(forKey: Key.opened), !ProEntitlement.isPro {
            // Due but never seen: wait for the first foreground, then run the full window from that moment.
            // Also wait for prices: opening without a price would burn the 15 minutes unseen.
            guard isForeground(), canOffer() else { return publish(nil, nil) }
            start = t
            end = t + Self.duration(Self.flashSeconds)
            defaults.set(true, forKey: Key.opened)
            defaults.set(start, forKey: Key.startsAt)
            defaults.set(end, forKey: Key.endsAt)
        }
        if t >= end || ProEntitlement.isPro { return cancel() }
        if t < start {
            publish(nil, Date(timeIntervalSince1970: start))
            schedule(after: start - t)
        } else {
            publish(Active(kind: .flash, endsAt: Date(timeIntervalSince1970: end)), nil)
            schedule(after: end - t)
        }
    }

    /// Call once when onboarding closes. Arms the flash exactly once per install; a purchase or Pro arms nothing.
    func noteOnboardingFinished(purchased: Bool) {
        refresh()
        guard !defaults.bool(forKey: Key.armed) else { return }
        defaults.set(true, forKey: Key.armed)
        guard !purchased, !ProEntitlement.isPro else { return }
        // Time-based on purpose: it starts even if products are offline; the UI only shows it once prices load.
        let start = now().timeIntervalSince1970 + Self.flashDelay()
        defaults.set(start, forKey: Key.startsAt)
        defaults.set(start + Self.duration(Self.flashSeconds), forKey: Key.endsAt)
        refresh()
    }

    /// Save counter only; offers no longer key off saves.
    func noteSave() {
        refresh()
        defaults.set(defaults.integer(forKey: Key.saves) + 1, forKey: Key.saves)
    }

    /// True exactly once per install while the flash is live. Burns the flag, so call it only when the panel can open.
    func takeAutoPresent() -> Bool {
        refresh()
        guard active?.kind == .flash, !defaults.bool(forKey: Key.autoShown), canOffer() else { return false }
        defaults.set(true, forKey: Key.autoShown)
        return true
    }

    private func publish(_ newActive: Active?, _ newPending: Date?) {
        if active != newActive { active = newActive }
        if pendingStart != newPending { pendingStart = newPending }
        if newActive == nil, newPending == nil { wake?.cancel(); wake = nil }
    }

    private func cancel() {
        defaults.removeObject(forKey: Key.startsAt)
        defaults.removeObject(forKey: Key.endsAt)
        publish(nil, nil)
    }

    /// Wakes at the next boundary so the pill appears (and disappears) mid-session without a scene change.
    private func schedule(after seconds: TimeInterval) {
        wake?.cancel()
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, seconds) + 0.05))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    nonisolated static func duration(_ standard: TimeInterval) -> TimeInterval {
        debugSeconds("CUTSENSE_OFFER_SECONDS") ?? standard
    }

    nonisolated static func flashDelay() -> TimeInterval {
        debugSeconds("CUTSENSE_FLASH_DELAY_SECONDS") ?? flashDelaySeconds
    }

    private nonisolated static func debugSeconds(_ name: String) -> TimeInterval? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[name], let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }
        #endif
        return nil
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
        if env["CUTSENSE_FORCE_FLASH_OFFER"] == "1" {
            let t = Date().timeIntervalSince1970
            defaults.set(true, forKey: OfferCenter.Key.armed)
            defaults.set(true, forKey: OfferCenter.Key.opened)
            defaults.set(t, forKey: OfferCenter.Key.startsAt)
            defaults.set(t + OfferCenter.duration(OfferCenter.flashSeconds), forKey: OfferCenter.Key.endsAt)
            defaults.set(t, forKey: OfferCenter.Key.clockHigh)
        }
        #endif
    }
}
