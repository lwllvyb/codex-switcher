//
//  DiagnosticsLogStore.swift
//  multi-codex-limit-viewer
//

import Foundation

final class DiagnosticsLogStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "multi_codex_limit_viewer.diagnostics")
    private let directoryURL: URL
    let logURL: URL

    nonisolated init(rootURL: URL) {
        directoryURL = rootURL.appendingPathComponent("logs", isDirectory: true)
        logURL = directoryURL.appendingPathComponent("viewer.log")
        prepareStorageIfNeeded()
    }

    nonisolated func append(_ message: String) {
        let line = "[\(Self.timestampFormatter.string(from: Date()))] \(message)\n"

        queue.sync {
            prepareStorageIfNeeded()
            guard let data = line.data(using: .utf8) else {
                return
            }

            if let handle = FileHandle(forWritingAtPath: logURL.path) {
                defer {
                    try? handle.close()
                }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    nonisolated func readContents(maxCharacters: Int? = nil) -> String {
        queue.sync {
            prepareStorageIfNeeded()
            let contents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""

            guard let maxCharacters, contents.count > maxCharacters else {
                return contents
            }

            return String(contents.suffix(maxCharacters))
        }
    }

    nonisolated private func prepareStorageIfNeeded() {
        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
    }

    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
