import Foundation

/// Where the user is typing when a dictation or transform starts.
public struct AppContext: Sendable, Equatable {
    public var bundleID: String?
    public var appName: String?
    /// Host of the active browser tab (e.g. `mail.google.com`), when the app is a browser.
    public var host: String?

    public init(bundleID: String? = nil, appName: String? = nil, host: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.host = host
    }

    /// Human readable description used in prompts and history ("Gmail in Google Chrome").
    public var displayName: String {
        switch (appName, host) {
        case let (app?, host?): "\(host) in \(app)"
        case let (app?, nil): app
        case let (nil, host?): host
        default: "Unknown app"
        }
    }
}
