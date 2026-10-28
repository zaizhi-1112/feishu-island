import Foundation
import AppKit
import SwiftUI
import WebKit
@testable import IslandShell

@MainActor
func runAuthorizationExperienceChecks(check: (Bool, String) -> Void, renderTo: URL? = nil) async throws {
    @MainActor func capture(_ connection: CompanyConnection, _ name: String) async throws {
        guard let renderTo else { return }
        try FileManager.default.createDirectory(at: renderTo, withIntermediateDirectories: true)
        for width in [620.0, 480.0] {
        let view = NSHostingView(rootView: CompanyAuthorizationView(connection: connection).preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: width == 480 ? 580 : 660), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = view
        view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(120))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: renderTo.appendingPathComponent(name + (width == 480 ? "-narrow" : "") + ".png"))
        if view.fittingSize.width > width { print("Authorization layout: \(name) proposed=\(width), bounds=\(view.bounds), fitting=\(view.fittingSize)") }
        check(!window.isVisible && view.fittingSize.width <= width, "native authorization state fits: " + name)
        window.close()
        }
    }
    // Exercise the real WebKit completion bridge, not the injected transport.
    // This failed in build67 even for a successful server response.
    let webConfig = WKWebViewConfiguration()
    webConfig.websiteDataStore = .nonPersistent()
    let bridgeWeb = WKWebView(frame: .zero, configuration: webConfig)
    let bridged = try await CompanyConnection.evaluateAuthorizationObject(
        "await new Promise(resolve => setTimeout(resolve, 50)); return {receive:{configured:true,authorized:true},route,payloadIsNull:payload===null};",
        arguments: ["route": "status", "payload": NSNull()], web: bridgeWeb)
    check((bridged["receive"] as? [String: Any])?["authorized"] as? Bool == true,
          "real WebKit asynchronous result reaches authorization decoding")
    check(bridged["payloadIsNull"] as? Bool == true && bridged["route"] as? String == "status", "WebKit arguments preserve null GET payload")
    let denied = try await CompanyConnection.evaluateAuthorizationObject("return {authorizationFailure:403};", arguments: [:], web: bridgeWeb)
    check(denied["authorizationFailure"] as? Int == 403, "real WebKit preserves HTTP failure status")
    do {
        _ = try await CompanyConnection.evaluateAuthorizationObject("throw new Error('synthetic failure');", arguments: [:], web: bridgeWeb)
        check(false, "JavaScript failure must propagate")
    } catch { check(true, "JavaScript failure propagates instead of reporting success") }
    do {
        _ = try await CompanyConnection.evaluateAuthorizationObject("return 'not an object';", arguments: [:], web: bridgeWeb)
        check(false, "malformed result must reject")
    } catch { check(true, "malformed WebKit result rejected") }

    var calendarStarts = 0, calendarPurpose = ""
    let calendar = CompanyConnection(defaults: UserDefaults(suiteName: "authorization-calendar-" + UUID().uuidString)!, authorizationTransport: { route, payload in
        switch route {
        case "status": return ["schedule": ["configured": true, "authorized": false], "calendar": ["configured": true, "authorized": true]]
        case "start":
            calendarPurpose = payload?["purpose"] ?? ""
            calendarStarts += 1
            return ["flow": "synthetic-calendar", "url": "https://accounts.feishu.cn/synthetic-calendar", "interval": 5]
        case "cancel": return ["cancelled": true]
        default: return ["state": "pending"]
        }
    })
    calendar.authorizationPurpose = .calendar
    calendar.authorizationOpenURL = { $0.host == "accounts.feishu.cn" }
    await calendar.refreshAuthorizationStatus()
    check(calendar.authorizationConfigured && !calendar.authorizationGranted, "legacy broad calendar grant does not count as a readonly grant")
    calendar.beginAuthorization()
    try await Task.sleep(for: .milliseconds(80))
    check(calendarStarts == 1 && calendar.authorizationBusy, "calendar starts directly without a local profile")
    check(calendarPurpose == "schedule", "calendar button starts only the readonly schedule purpose")
    try await capture(calendar, "calendar-readonly")
    calendar.cancelAuthorization()
    try await Task.sleep(for: .milliseconds(80))

    var authorized = false, starts = 0, opened = 0, cancelled = 0
    let defaults = UserDefaults(suiteName: "authorization-experience-" + UUID().uuidString)!
    let connection = CompanyConnection(defaults: defaults, authorizationTransport: { route, _ in
        switch route {
        case "status": return ["receive": ["configured": true, "authorized": authorized]]
        case "start": starts += 1; return ["flow": "synthetic-flow", "url": "https://accounts.feishu.cn/synthetic", "interval": 5]
        case "poll": authorized = true; return ["state": "authorized"]
        case "cancel": cancelled += 1; return ["cancelled": true]
        default: throw WorkError.message("Unsupported fixture request")
        }
    })
    connection.authorizationOpenURL = { url in opened += 1; return url.host == "accounts.feishu.cn" }
    await connection.refreshAuthorizationStatus()
    check(connection.authorizationConfigured && !connection.authorizationGranted, "configured service does not imply authorization")
    check(starts == 0, "checking status never starts OAuth")
    try await capture(connection, "01-ready")
    connection.beginAuthorization(); connection.beginAuthorization()
    try await Task.sleep(for: .milliseconds(60))
    check(starts == 1 && opened == 1, "one explicit click opens one validated OAuth flow")
    try await capture(connection, "02-waiting")
    connection.checkAuthorizationProgress()
    try await Task.sleep(for: .milliseconds(60))
    check(connection.authorizationGranted && !connection.authorizationBusy, "authorized response updates the native result")
    check(!connection.authorizationConnected && !connection.isEnabled(.receive), "server authorization does not falsely claim desktop activation")
    try await capture(connection, "03-authorized")
    let credential = CompanyConnection.Credential(appID: CompanyConnection.Purpose.receive.appID, access: "synthetic", scope: CompanyConnection.Purpose.receive.scopes,
        userID: "fixture", openID: "ou_fixture", userName: "合成账号", expires: Date().addingTimeInterval(3600))
    try connection.activate(credential, purpose: .receive)
    check(connection.authorizationConnected, "desktop success follows verified credential activation")
    check(connection.isEnabled(.receive), "verified activation persists the existing purpose")
    try await capture(connection, "04-connected")
    connection.authorizationPurpose = .calendar
    check(!connection.authorizationGranted && !connection.authorizationConnected && !connection.authorizationConfigured, "switching purposes clears the other purpose's success state")
    await connection.refreshAuthorizationStatus()
    check(!connection.authorizationGranted && !connection.authorizationConnected, "missing calendar status cannot inherit receive authorization")

    var expired = true
    var flowCount = 0
    let retry = CompanyConnection(defaults: UserDefaults(suiteName: "authorization-retry-" + UUID().uuidString)!, authorizationTransport: { route, _ in
        switch route {
        case "status": return ["receive": ["configured": true, "authorized": false]]
        case "start": flowCount += 1; return ["flow": "retry-flow-\(flowCount)", "url": "https://accounts.feishu.cn/synthetic", "interval": 5]
        case "poll":
            if expired { throw CompanyConnection.AuthorizationFailure.expired }
            throw CompanyConnection.AuthorizationFailure.unavailable
        case "cancel": return ["cancelled": true]
        default: return [:]
        }
    })
    retry.authorizationOpenURL = { _ in true }
    await retry.refreshAuthorizationStatus(); retry.beginAuthorization()
    try await Task.sleep(for: .milliseconds(40)); retry.checkAuthorizationProgress()
    try await Task.sleep(for: .milliseconds(40))
    check(!retry.authorizationBusy && !retry.authorizationGranted && retry.authorizationFeedback.contains("过期"), "expired flow allows a fresh authorization without false success")
    try await capture(retry, "05-expired")
    expired = false; retry.beginAuthorization()
    try await Task.sleep(for: .milliseconds(40)); retry.checkAuthorizationProgress()
    try await Task.sleep(for: .milliseconds(40))
    check(flowCount == 2 && retry.authorizationBusy && !retry.authorizationGranted, "network failure retains a retryable pending flow")
    try await capture(retry, "06-network-retry")
    retry.cancelAuthorization(); try await Task.sleep(for: .milliseconds(40))
    check(!retry.authorizationBusy && !retry.authorizationGranted, "pending retry can be cancelled without granting access")

    let forbidden = CompanyConnection(defaults: UserDefaults(suiteName: "authorization-forbidden-" + UUID().uuidString)!, authorizationTransport: { _, _ in
        throw CompanyConnection.AuthorizationFailure.forbidden
    })
    await forbidden.refreshAuthorizationStatus()
    check(!forbidden.authorizationConfigured && forbidden.authorizationFeedback.contains("403") && forbidden.loginError == nil,
          "403 remains an access rejection, not a fabricated expired login")

    var unsafeOpens = 0
    let unsafe = CompanyConnection(defaults: UserDefaults(suiteName: "authorization-invalid-" + UUID().uuidString)!, authorizationTransport: { route, _ in
        route == "status" ? ["receive": ["configured": true, "authorized": false]]
            : ["flow": "invalid", "url": "https://example.org/", "interval": 5]
    })
    unsafe.authorizationOpenURL = { _ in unsafeOpens += 1; return true }
    await unsafe.refreshAuthorizationStatus(); unsafe.beginAuthorization()
    try await Task.sleep(for: .milliseconds(40))
    check(unsafeOpens == 0 && !unsafe.authorizationGranted && !unsafe.authorizationBusy, "unexpected authorization destination never opens or reports success")

    var lateOpens = 0, lateCancellations = 0
    let late = CompanyConnection(defaults: UserDefaults(suiteName: "authorization-cancel-" + UUID().uuidString)!, authorizationTransport: { route, _ in
        if route == "status" { return ["receive": ["configured": true, "authorized": false]] }
        if route == "start" {
            try? await Task.sleep(for: .milliseconds(80)) // A transport may complete after cancellation.
            return ["flow": "late-synthetic-flow", "url": "https://accounts.feishu.cn/synthetic", "interval": 5]
        }
        if route == "cancel" { lateCancellations += 1; return ["cancelled": true] }
        return [:]
    })
    late.authorizationOpenURL = { _ in lateOpens += 1; return true }
    await late.refreshAuthorizationStatus(); late.beginAuthorization()
    try await Task.sleep(for: .milliseconds(10)); late.cancelAuthorization()
    try await Task.sleep(for: .milliseconds(100))
    check(lateOpens == 0 && !late.authorizationBusy, "closing or cancelling never opens a late authorization page")
    check(lateCancellations == 1, "a late-created flow is cancelled without revoking existing grants")
}
