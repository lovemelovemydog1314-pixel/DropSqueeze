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
}

@MainActor
final class UsageTracker {
    private let defaults = UserDefaults.standard
    private var reservedImageCount = 0
    private var reservedVideoCount = 0

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
        guard !isPro else { return UsageReservation(kind: kind, countsTowardLimit: false) }

        let currentCount = kind == .image ? imageCountToday : videoCountToday
        let reservedCount = kind == .image ? reservedImageCount : reservedVideoCount
        guard currentCount + reservedCount < kind.dailyLimit else { return nil }

        if kind == .image { reservedImageCount += 1 } else { reservedVideoCount += 1 }
        return UsageReservation(kind: kind, countsTowardLimit: true)
    }

    func complete(_ reservation: UsageReservation, succeeded: Bool, savedBytes: Int64 = 0) {
        if reservation.countsTowardLimit {
            if reservation.kind == .image {
                reservedImageCount = max(0, reservedImageCount - 1)
                if succeeded { defaults.set(imageCountToday + 1, forKey: "automaticImageCountToday") }
            } else {
                reservedVideoCount = max(0, reservedVideoCount - 1)
                if succeeded { defaults.set(videoCountToday + 1, forKey: "automaticVideoCountToday") }
            }
        }

        if succeeded, savedBytes > 0 { recordSavedBytes(savedBytes) }
    }

    func recordSavedBytes(_ bytes: Int64) {
        guard bytes > 0 else { return }
        resetWeeklyValuesIfNeeded()
        defaults.set(weeklySavedBytes + bytes, forKey: "weeklySavedBytes")
    }

    private func resetDailyValuesIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let storedDate = defaults.object(forKey: "automaticQuotaDate") as? Date,
              Calendar.current.isDate(storedDate, inSameDayAs: today) else {
            defaults.set(today, forKey: "automaticQuotaDate")
            defaults.set(0, forKey: "automaticImageCountToday")
            defaults.set(0, forKey: "automaticVideoCountToday")
            reservedImageCount = 0
            reservedVideoCount = 0
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
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return (components.yearForWeekOfYear ?? 0) * 100 + (components.weekOfYear ?? 0)
    }
}
