@testable import IslandLegacyFixtures
import Foundation
@testable import IslandShell

@MainActor extension FusionTests {
    /// Pure synthetic boundary tests. No WebKit window, real account, credential
    /// store, default preferences or network request is touched by this test.
    func testCompanyConnectionBoundary() throws {
        let now=Date(timeIntervalSince1970:1_800_000_000)
        var sample:[String:Any]=["appId":CompanyConnection.Purpose.receive.appID,"access":"synthetic-not-a-token",
                               "scope":CompanyConnection.Purpose.receive.scopes.sorted().joined(separator:" "),"userId":"synthetic-company-user",
                               "openId":"ou_synthetic","userName":"合成账号","expires":now.addingTimeInterval(3600).timeIntervalSince1970*1000]
        let c=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now)
        XCTAssertEqual(c.checkScopes("im:chat:read")["ok"] as? Bool,true)
        XCTAssertEqual(c.checkScopes("im:chat:write")["ok"] as? Bool,false)
        try c.validateIdentity(boundUser:nil,boundOpenID:nil)
        try c.validateIdentity(boundUser:"synthetic-company-user",boundOpenID:"ou_synthetic")
        do{try c.validateIdentity(boundUser:"another-user",boundOpenID:"ou_synthetic");XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        do{try c.validateIdentity(boundUser:"synthetic-company-user",boundOpenID:"ou_another");XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.archive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        sample["scope"]="im:chat:read"
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        sample["scope"]=CompanyConnection.Purpose.receive.scopes.sorted().joined(separator:" ")+" im:message:send"
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        sample["scope"]=CompanyConnection.Purpose.receive.scopes.sorted().joined(separator:" ")
        sample["expires"]=now.addingTimeInterval(-1).timeIntervalSince1970*1000
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        sample["expires"]=Double.infinity
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        sample["expires"]=now.addingTimeInterval(3600).timeIntervalSince1970*1000;sample["access"]="bad\nheader"
        do{_=try CompanyConnection.Credential.decode(sample,purpose:.receive,now:now);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        let env=c.environment(["PATH":"synthetic-path","LARKSUITE_CLI_APP_SECRET":"synthetic-secret","LARKSUITE_CLI_TENANT_ACCESS_TOKEN":"synthetic-bot","LARKSUITE_CLI_PROXY_KEY":"synthetic-proxy","LARKSUITE_CLI_PROFILE":"old-profile","LARKSUITE_CLI_CONFIG_DIR":"old-config"])
        XCTAssertNil(env["LARKSUITE_CLI_APP_SECRET"]);XCTAssertNil(env["LARKSUITE_CLI_TENANT_ACCESS_TOKEN"])
        XCTAssertNil(env["LARKSUITE_CLI_PROXY_KEY"]);XCTAssertNil(env["LARKSUITE_CLI_PROFILE"])
        XCTAssertEqual(env["LARKSUITE_CLI_APP_ID"],CompanyConnection.Purpose.receive.appID)
        XCTAssertEqual(env["LARKSUITE_CLI_USER_ACCESS_TOKEN"],"synthetic-not-a-token")
        XCTAssertEqual(env["LARKSUITE_CLI_STRICT_MODE"],"user");XCTAssertEqual(env["PATH"],"synthetic-path")
        XCTAssertFalse(env["LARKSUITE_CLI_CONFIG_DIR"] == "old-config")
        XCTAssertTrue(CompanyConnection.allowed(CompanyConnection.connectURL))
        for url in ["http://island.example.invalid/connect.html","https://island.example.invalid.evil.test/connect.html","https://a@island.example.invalid/connect.html","https://island.example.invalid:444/connect.html"] {XCTAssertFalse(CompanyConnection.allowed(URL(string:url)))}
        let defaults=UserDefaults(suiteName:"local.company.synthetic."+UUID().uuidString)!
        let connection=CompanyConnection(defaults:defaults)
        XCTAssertFalse(connection.isEnabled(.receive));XCTAssertFalse(connection.isEnabled(.archive))
        do{_=try connection.credential(.receive);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        // Preferences are read-only in this test; no persistent suite data is created.
    }
    func testCompanyActivationIsolation() async throws {
        let suite="local.company.activation."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        func fixture(_ purpose:CompanyConnection.Purpose,user:String="synthetic-company-user") -> CompanyConnection.Credential {
            CompanyConnection.Credential(appID:purpose.appID,access:"synthetic-not-a-token",scope:purpose.scopes,userID:user,openID:"ou_"+purpose.rawValue,userName:"合成账号",expires:Date().addingTimeInterval(3600))
        }
        let connection=CompanyConnection(defaults:defaults,fetcher:{purpose,done in done(.success(fixture(purpose)))})
        let receive=try await Task.detached { try connection.prepare(.receive) }.value
        XCTAssertFalse(connection.isEnabled(.receive));XCTAssertNil(defaults.string(forKey:"island.company.user"))
        XCTAssertEqual((connection.statusJSON()["receive"] as? [String:Any])?["connected"] as? Bool,false)
        do { _=try await Task.detached {try connection.credential(.receive)}.value;XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        try connection.activate(receive,purpose:.receive)
        XCTAssertTrue(connection.isEnabled(.receive));XCTAssertFalse(connection.isEnabled(.archive))
        let active=try await Task.detached {try connection.credential(.receive)}.value
        XCTAssertEqual(active.openID,"ou_receive")
        let archive=try await Task.detached {try connection.prepare(.archive)}.value
        XCTAssertFalse(connection.isEnabled(.archive));XCTAssertNil(defaults.string(forKey:"island.company.archive.openID"))
        XCTAssertEqual((connection.statusJSON()["receive"] as? [String:Any])?["connected"] as? Bool,true)
        XCTAssertEqual((connection.statusJSON()["archive"] as? [String:Any])?["connected"] as? Bool,false)
        // A rejected activation cannot change the active receiver or bind archive.
        do{try connection.activate(fixture(.archive,user:"another-user"),purpose:.archive);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
        XCTAssertFalse(connection.isEnabled(.archive));XCTAssertEqual(defaults.string(forKey:"island.company.user"),"synthetic-company-user")
        XCTAssertEqual((connection.statusJSON()["receive"] as? [String:Any])?["connected"] as? Bool,true)
        try connection.activate(archive,purpose:.archive)
        XCTAssertTrue(connection.isEnabled(.archive))
        XCTAssertEqual((connection.statusJSON()["receive"] as? [String:Any])?["connected"] as? Bool,true)
        connection.setEnabled(.archive,false)
        XCTAssertFalse(connection.isEnabled(.archive));XCTAssertTrue(connection.isEnabled(.receive))
        XCTAssertEqual((connection.statusJSON()["receive"] as? [String:Any])?["connected"] as? Bool,true)
        do{try connection.activate(archive,purpose:.receive);XCTAssertTrue(false)}catch{XCTAssertTrue(true)}
    }

}
