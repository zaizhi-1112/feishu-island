import Foundation
import Security
import LocalAuthentication
import CryptoKit

// Stable owner of only this application's newly created tunnel runtime key.
// No secret-returning action; run injects it into a verified bundled child environment.
let context=LAContext(); context.interactionNotAllowed=true
let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.zaizhi.feishu-island.dot-tunnel-v1",kSecAttrAccount as String:"runtime",kSecUseAuthenticationContext as String:context]
func finish(_ ok: Bool) -> Never { print(ok ? "{\"ok\":true}" : "{\"ok\":false}"); exit(ok ? 0 : 1) }
let data=FileHandle.standardInput.readDataToEndOfFile()
guard data.count<16384, let p=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { finish(false) }
switch p["action"] as? String {
case "save":
    guard let key=p["key"] as? String, key.hasPrefix("sk-"), (30...512).contains(key.count), !key.contains(where:{$0.isWhitespace}) else { finish(false) }
    let value=Data(key.utf8)
    let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:value] as CFDictionary)
    if status==errSecItemNotFound {
        var next=query; next[kSecValueData as String]=value; next[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        finish(SecItemAdd(next as CFDictionary,nil)==errSecSuccess)
    }
    finish(status==errSecSuccess)
case "available":
    var next=query; next[kSecReturnAttributes as String]=true
    finish(SecItemCopyMatching(next as CFDictionary,nil)==errSecSuccess)
case "run":
    guard let tunnel=p["tunnel"] as? String, tunnel.range(of:"^tunnel_[a-z0-9]{32}$",options:.regularExpression) != nil,
          let port=p["port"] as? Int, (1024...65535).contains(port),
          let token=p["token"] as? String, token.utf8.count<256, !token.contains(where:{$0.isWhitespace}),
          let executable=Bundle.main.executableURL else { finish(false) }
    let directory=executable.deletingLastPathComponent()
    let client=directory.appendingPathComponent("tunnel-client")
    // The build script only packages the official checksum-verified release.
    guard FileManager.default.isExecutableFile(atPath:client.path),
          let binary=try? Data(contentsOf:client,options:.mappedIfSafe),
          SHA256.hash(data:binary).map({String(format:"%02x",$0)}).joined()=="d8f165d8175fa9f813a113b6ef434aed25a384f765a69b3709228704e5347474" else { finish(false) }
    var next=query; next[kSecReturnData as String]=true
    var found: CFTypeRef?
    guard SecItemCopyMatching(next as CFDictionary,&found)==errSecSuccess, let bytes=found as? Data, let key=String(data:bytes,encoding:.utf8) else { finish(false) }
    let child=Process()
    child.executableURL=client
    child.arguments=["run","--control-plane.tunnel-id",tunnel,"--mcp.server-url","http://127.0.0.1:\(port)/mcp/dot","--mcp.extra-headers","Authorization: env:ISLAND_DOT_AUTH","--mcp.discovery-extra-headers","Authorization: env:ISLAND_DOT_AUTH","--health.listen-addr","127.0.0.1:18769","--log.level","error"]
    child.environment=["PATH":"/usr/bin:/bin","HOME":NSHomeDirectory(),"CONTROL_PLANE_API_KEY":key,"ISLAND_DOT_AUTH":"Bearer "+token]
    child.standardInput=FileHandle.nullDevice; child.standardOutput=FileHandle.nullDevice; child.standardError=FileHandle.nullDevice
    // UI exit/crash, lock or disconnect must not leave an orphan tunnel process.
    signal(SIGTERM,SIG_IGN)
    let termination=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.global())
    termination.setEventHandler { if child.isRunning { child.terminate() }; exit(0) }; termination.resume()
    let parent=getppid(), watchdog=DispatchSource.makeTimerSource(queue:.global())
    watchdog.schedule(deadline:.now()+2,repeating:2)
    watchdog.setEventHandler { if getppid() != parent { if child.isRunning { child.terminate() }; exit(0) } }; watchdog.resume()
    do { try child.run(); child.waitUntilExit(); exit(child.terminationStatus) } catch { finish(false) }
default: finish(false)
}
