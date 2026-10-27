// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Youzi Island contributors

import AppKit

/// Product-neutral drop content. Files take precedence over their text representation.
public enum NookDropPayload: Sendable, Equatable {
    case files([URL])
    case text(String)
    case link(URL)

    @MainActor
    public static func read(from pasteboard: NSPasteboard) -> Self? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        if let raw = pasteboard.string(forType: .URL), let url = webURL(raw) { return .link(url) }
        if let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            if let url = webURL(value) { return .link(url) }
            return .text(value)
        }
        return nil
    }

    public static func webURL(_ value: String) -> URL? {
        guard !value.contains(where: \.isWhitespace), let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        return url
    }
}
