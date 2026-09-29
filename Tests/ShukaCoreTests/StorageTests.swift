import Foundation
import Testing
@testable import ShukaCore

@Suite struct HistoryStoreTests {
    @Test func insertSearchAndDelete() async throws {
        let store = try HistoryStore(url: nil)
        let first = HistoryEntry(date: Date(timeIntervalSince1970: 100), kind: .dictation,
                                 rawText: "euh bonjour", finalText: "Bonjour tout le monde", appName: "Slack", audioDuration: 3)
        let second = HistoryEntry(date: Date(timeIntervalSince1970: 200), kind: .transform,
                                  rawText: "hi", finalText: "Hello there", label: "Polish")
        try await store.insert(first)
        try await store.insert(second)

        let all = try await store.recent()
        #expect(all.map(\.id) == [second.id, first.id])
        #expect(all.last == first)

        let found = try await store.recent(matching: "bonjour")
        #expect(found.map(\.id) == [first.id])

        // Transforms don't count as dictated words.
        let samples = try await store.statsSamples()
        #expect(samples == [.init(date: first.date, words: 4, duration: 3)])

        try await store.delete(id: first.id)
        #expect(try await store.recent().map(\.id) == [second.id])
        try await store.deleteAll()
        #expect(try await store.recent().isEmpty)
    }

    @Test func survivesQuotesAndUnicode() async throws {
        let store = try HistoryStore(url: nil)
        let entry = HistoryEntry(kind: .dictation, rawText: "l'été", finalText: "C'est \"génial\" 🎉 ; DROP TABLE entries;")
        try await store.insert(entry)
        #expect(try await store.recent().first?.finalText == entry.finalText)
    }
}

@Suite struct UsageStatsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ n: Int, hour: Int = 12) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n * 86_400 + hour * 3600))
    }

    @Test func computesTotalsSpeedAndTimeSaved() {
        let samples = [
            UsageStats.Sample(date: day(10), words: 150, duration: 60),
            UsageStats.Sample(date: day(10, hour: 13), words: 150, duration: 60),
        ]
        let stats = UsageStats(samples: samples, now: day(10, hour: 18), calendar: calendar)
        #expect(stats.totalWords == 300)
        #expect(stats.sessions == 2)
        #expect(stats.wordsPerMinute == 150)
        #expect(stats.minutesSaved == 5) // 300 / 45 ≈ 6.7 min typing − 2 min speaking
        #expect(stats.wordsToday == 300)
    }

    @Test func streakCountsConsecutiveDaysAndToleratesToday() {
        let samples = [8, 9, 10].map { UsageStats.Sample(date: day($0), words: 1, duration: 1) }
        #expect(UsageStats(samples: samples, now: day(10), calendar: calendar).dayStreak == 3)
        #expect(UsageStats(samples: samples, now: day(11), calendar: calendar).dayStreak == 3)
        #expect(UsageStats(samples: samples, now: day(12), calendar: calendar).dayStreak == 0)
    }

    @Test func emptyHistory() {
        #expect(UsageStats(samples: []) == UsageStats())
    }
}

@Suite struct ConfigurationTests {
    @Test func decodesPartialFilesWithDefaults() throws {
        let json = #"{"settings": {"playSounds": false}, "dictionary": [{"id": "5A1B3A48-1E0B-4F7A-9C39-1B1C8D9E0F11", "term": "Supabase", "aliases": []}]}"#
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(configuration.settings.playSounds == false)
        #expect(configuration.settings.cleanupEnabled == true)
        #expect(configuration.categories == StyleCategory.defaults)
        #expect(configuration.dictionary.map(\.term) == ["Supabase"])
        #expect(configuration.transform(inSlot: 1)?.name == "Polish")
    }

    @Test func fallbackCategoryIsRestoredIfMissing() throws {
        let json = #"{"categories": []}"#
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(configuration.categories.count == 1)
        #expect(configuration.categories[0].isFallback)
    }

    @Test @MainActor func storeRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "shukawhisper-tests-\(UUID().uuidString)/config.json")
        let store = ConfigurationStore(fileURL: url)
        store.configuration.dictionary.append(DictionaryEntry(term: "Gemini"))
        store.saveNow()
        #expect(ConfigurationStore.load(from: url).dictionary.map(\.term) == ["Gemini"])
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func corruptFileIsBackedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "shukawhisper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "config.json")
        try Data("{not json".utf8).write(to: url)
        #expect(ConfigurationStore.load(from: url) == Configuration())
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "config.corrupt.json").path))
        try? FileManager.default.removeItem(at: dir)
    }
}
