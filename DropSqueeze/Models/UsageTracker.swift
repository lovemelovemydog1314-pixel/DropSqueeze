import Foundation

enum AutomaticUsageKind: String {
    case image
    case video

    var dailyLimit: Int {
        switch self {
        case .image: return 15
        case .video: return 3
        }
    }
}

struct UsageReservation {
    let kind: AutomaticUsageKind
    let countsTowardLimit: Bool
    let id: UUID
    let date: Date
}

@MainActor
final class UsageTracker {
    private let defaults: UserDefaults
    private let now: () -> Date
    private var reservations: [UUID: UsageReservation] = [:]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var imageCountToday: Int {
        resetDailyValuesIfNeeded()
        return defaults.integer(forKey: "automaticImageCountToday")
    }

    var videoCountToday: Int {
        resetDailyValuesIfNeeded()
        return defaults.integer(forKey: "automaticVideoCountToday")
    }

    var weeklySavedBytes: Int64 {
        resetWeeklyValuesIfNeeded()
        return defaults.object(forKey: "weeklySavedBytes") as? Int64 ?? 0
    }

    func reserve(_ kind: AutomaticUsageKind, isPro: Bool) -> UsageReservation? {
        resetDailyValuesIfNeeded()
        let date = now()
        let reservation = UsageReservation(kind: kind, countsTowardLimit: !isPro, id: UUID(), date: date)
        if !isPro {
            let currentCount = kind == .image ? imageCountToday : videoCountToday
            let reservedCount = reservations.values.filter {
                $0.kind == kind && $0.countsTowardLimit && Calendar.current.isDate($0.date, inSameDayAs: date)
            }.count
            guard currentCount + reservedCount < kind.dailyLimit else { return nil }
        }
        reservations[reservation.id] = reservation
        return reservation
    }

    func complete(_ reservation: UsageReservation, succeeded: Bool, savedBytes: Int64 = 0) {
        guard let active = reservations.removeValue(forKey: reservation.id) else { return }
        resetDailyValuesIfNeeded()
        // Quota is charged on the day the work was reserved.
        if active.countsTowardLimit, succeeded, Calendar.current.isDate(active.date, inSameDayAs: now()) {
            let key = active.kind == .image ? "automaticImageCountToday" : "automaticVideoCountToday"
            defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        }
        if succeeded, savedBytes > 0 { recordSavedBytes(savedBytes) }
    }

    func recordSavedBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        resetWeeklyValuesIfNeeded()
        defaults.set(weeklySavedBytes + bytes, forKey: "weeklySavedBytes")
    }

    private func resetDailyValuesIfNeeded() {
        let today = Calendar.current.startOfDay(for: now())
        guard let storedDate = defaults.object(forKey: "automaticQuotaDate") as? Date,
              Calendar.current.isDate(storedDate, inSameDayAs: today) else {
            defaults.set(today, forKey: "automaticQuotaDate")
            defaults.set(0, forKey: "automaticImageCountToday")
            defaults.set(0, forKey: "automaticVideoCountToday")
            return
        }
    }

    private func resetWeeklyValuesIfNeeded() {
        let key = currentWeekKey
        guard defaults.integer(forKey: "weeklySavedWeekKey") != key else { return }
        defaults.set(key, forKey: "weeklySavedWeekKey")
        defaults.set(Int64(0), forKey: "weeklySavedBytes")
    }

    private var currentWeekKey: Int {
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now())
        return (components.yearForWeekOfYear ?? 0) * 100 + (components.weekOfYear ?? 0)
    }
}
