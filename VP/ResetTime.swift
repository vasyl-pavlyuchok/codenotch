// audience: machine
// Spanish reset-time wording for the tooltip card rows: "Se reinicia a las
// 8:20" when the reset lands today, "Se reinicia mar 14:00" otherwise.
import Foundation

enum ResetTime {
    static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "H:mm"
            return "Se reinicia a las \(f.string(from: date))"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE HH:mm"
        let text = f.string(from: date).replacingOccurrences(of: ".", with: "")
        return "Se reinicia \(text)"
    }
}
