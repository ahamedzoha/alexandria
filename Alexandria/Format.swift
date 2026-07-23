import Foundation

/// Shared formatting helpers so durations, timestamps, and relative dates read
/// identically everywhere in the app.
enum Format {
    /// Compact duration for rows and cards: "3h 12m", "45m", "<1m".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Playback timestamp: "h:mm:ss", or "m:ss" under an hour.
    static func timestamp(_ seconds: Double) -> String {
        let x = Int(seconds.isFinite ? seconds : 0)
        let h = x / 3600, m = (x % 3600) / 60, s = x % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "3d ago" style; one shared formatter (creation isn't cheap).
    @MainActor
    static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// Long-form duration for detail metadata: "3 hr 12 min". Optional in/out so
/// call sites can feed raw model fields and hide empty rows.
func durationString(_ seconds: Double?) -> String? {
    guard let seconds, seconds > 0 else { return nil }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 && minutes > 0 { return "\(hours) hr \(minutes) min" }
    if hours > 0 { return "\(hours) hr" }
    return "\(minutes) min"
}

func sizeString(_ bytes: Double?) -> String? {
    guard let bytes, bytes > 0 else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
