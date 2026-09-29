import Testing
@testable import ShukaCore

@Suite struct StyleResolverTests {
    let categories = StyleCategory.defaults

    @Test func matchesAppByBundleID() {
        let context = AppContext(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack")
        #expect(StyleResolver.category(for: context, in: categories).id == "work")
    }

    @Test func websiteWinsOverBrowserApp() {
        let context = AppContext(bundleID: "com.google.Chrome", appName: "Google Chrome", host: "mail.google.com")
        #expect(StyleResolver.category(for: context, in: categories).id == "email")
    }

    @Test func subdomainsMatchButLookalikesDoNot() {
        #expect(StyleResolver.matches(host: "app.slack.com", domain: "slack.com"))
        #expect(StyleResolver.matches(host: "slack.com", domain: "slack.com"))
        #expect(!StyleResolver.matches(host: "notslack.com", domain: "slack.com"))
        #expect(!StyleResolver.matches(host: "slack.com", domain: " "))
    }

    @Test func wildcardBundleIDs() {
        let context = AppContext(bundleID: "com.jetbrains.WebStorm")
        #expect(StyleResolver.category(for: context, in: categories).id == "ai")
        #expect(!StyleResolver.matches(bundleID: "com.jetbrainsx", pattern: "com.jetbrains.*"))
    }

    @Test func unknownAppFallsBackToOther() {
        let context = AppContext(bundleID: "com.example.unknown", host: "example.com")
        #expect(StyleResolver.category(for: context, in: categories).id == "other")
    }

    @Test func userCategoriesAreRespected() {
        var custom = categories
        custom.insert(StyleCategory(id: "notes", name: "Notes", apps: ["com.apple.Notes"]), at: 0)
        let context = AppContext(bundleID: "com.apple.Notes")
        #expect(StyleResolver.category(for: context, in: custom).id == "notes")
    }
}
