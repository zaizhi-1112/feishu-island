#!/usr/bin/env swift
import AppKit

// Finder aliases track the installed app; never copy a second executable to the desktop.
// Usage: swift scripts/install-desktop-shortcut.swift [installed-app] [desktop-alias]
let args = Array(CommandLine.arguments.dropFirst())
let home = FileManager.default.homeDirectoryForCurrentUser
let app = URL(fileURLWithPath: args.first ?? home.appendingPathComponent("Applications/柚子岛.app").path)
let shortcut = URL(fileURLWithPath: args.count > 1 ? args[1] : home.appendingPathComponent("Desktop/柚子岛.app").path)
guard Bundle(url: app)?.bundleIdentifier == "local.youzi.island" else {
    fatalError("Expected the installed 柚子岛 app at \(app.path)")
}
if FileManager.default.fileExists(atPath: shortcut.path) {
    let target = try URL(resolvingAliasFileAt: shortcut, options: [.withoutUI, .withoutMounting])
    guard target.standardizedFileURL == app.standardizedFileURL else {
        fatalError("Existing desktop item points elsewhere; left untouched: \(shortcut.path)")
    }
} else {
    let bookmark = try app.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(bookmark, to: shortcut)
}
let icon = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
guard let image = NSImage(contentsOf: icon), NSWorkspace.shared.setIcon(image, forFile: shortcut.path, options: []) else {
    fatalError("Couldn't apply the desktop icon")
}
let resolved = try URL(resolvingAliasFileAt: shortcut, options: [.withoutUI, .withoutMounting])
guard resolved.standardizedFileURL == app.standardizedFileURL,
      try shortcut.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else {
    fatalError("Desktop alias verification failed")
}
NSWorkspace.shared.noteFileSystemChanged(shortcut.deletingLastPathComponent().path)
print("Verified Finder alias: \(shortcut.path) → \(resolved.path)")
