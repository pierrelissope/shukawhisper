import Foundation

/// Aggregated numbers shown on the Home screen.
public struct UsageStats: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public var date: Date
        public var words: Int
        /// Seconds of speech.
        public var duration: TimeInterval

        public init(date: Date, words: Int, duration: TimeInterval) {
            self.date = date
            self.words = words
            self.duration = duration
        }
    }

    /// Typing speed used to estimate time saved (average typist).
    public static let typingWordsPerMinute: Double = 45

    public var totalWords = 0
    public var sessions = 0
    /// Average speaking speed, words per minute.
    public var wordsPerMinute = 0
    /// Minutes saved compared with typing the same words.
    public var minutesSaved = 0
    /// Consecutive days (ending today or yesterday) with at least one dictation.
    public var dayStreak = 0
    public var wordsToday = 0

    public init() {}

    public init(samples: [Sample], now: Date = Date(), calendar: Calendar = .current) {
        totalWords = samples.reduce(0) { $0 + $1.words }
        sessions = samples.count

        let spokenMinutes = samples.reduce(0) { $0 + $1.duration } / 60
        if spokenMinutes > 0 {
            wordsPerMinute = Int((Double(totalWords) / spokenMinutes).rounded())
        }
        let typingMinutes = Double(totalWords) / Self.typingWordsPerMinute
        minutesSaved = max(0, Int((typingMinutes - spokenMinutes).rounded()))

        wordsToday = samples
            .filter { calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(0) { $0 + $1.words }

        let activeDays = Set(samples.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !activeDays.contains(day) {
            // A streak isn't broken until a full day passes without dictating.
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        while activeDays.contains(day) {
            dayStreak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
    }
}
