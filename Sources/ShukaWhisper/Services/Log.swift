import Foundation

/// Writes diagnostics to `~/Library/Logs/ShukaWhisper.log` (and the system log).
/// Handy for bug reports: the file never contains audio or dictated text.
enum Log {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/ShukaWhisper.log")

    private static let queue = DispatchQueue(label: "dev.shukawhisper.log")

    static func info(_ message: String) {
        NSLog("ShukaWhisper: %@", message)
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
