import Foundation
import Security
import LocalAuthentication

// Dedicated stable signed owner for project grants. Only private stdin/stdout IPC, no sockets/logs.
let context=LAContext(); context.interactionNotAllowed=true
let service=CommandLine.arguments.contains("--sandbox") ? "local.zaizhi.feishu-island.dot-sandbox.pairing-v1" : "local.zaizhi.feishu-island.dot.pairing-v1"
let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"project-grants",kSecUseAuthenticationContext as String:context]
func reply(_ value: [String:Any]) {
    guard let data=try? JSONSerialization.data(withJSONObject:value) else { exit(1) }
    try? FileHandle.standardOutput.write(contentsOf:data)
}
let input=FileHandle.standardInput.readDataToEndOfFile()
guard input.count<=200_000, let object=try? JSONSerialization.jsonObject(with:input) as? [String:Any] else { reply(["ok":false]); exit(1) }
switch object["action"] as? String {
case "load":
    var q=query; q[kSecReturnData as String]=true
    var result: CFTypeRef?
    let status=SecItemCopyMatching(q as CFDictionary,&result)
    if status==errSecItemNotFound { reply(["ok":true,"grants":[]]); exit(0) }
    guard status==errSecSuccess, let data=result as? Data, let grants=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { reply(["ok":false]); exit(1) }
    reply(["ok":true,"grants":grants])
case "save":
    guard let grants=object["grants"] as? [[String:Any]], grants.count<=20,
          let data=try? JSONSerialization.data(withJSONObject:grants) else { reply(["ok":false]); exit(1) }
    let updated=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
    if updated==errSecItemNotFound {
        var q=query; q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else { reply(["ok":false]); exit(1) }
    } else if updated != errSecSuccess { reply(["ok":false]); exit(1) }
    reply(["ok":true])
default: reply(["ok":false]); exit(1)
}
