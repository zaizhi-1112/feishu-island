import Foundation
@main struct AppearanceMCPTests {
 static func main() {
  let agent = AppearanceMCP()
  var id = 0
  func call(_ method:String,_ params:[String:Any] = [:]) -> [String:Any] { id += 1; return agent.rpc(["jsonrpc":"2.0","id":id,"method":method,"params":params])! }
  assert((call("initialize")["result"] as? [String:Any])?["protocolVersion"] as? String == "2025-03-26")
  let listed = (call("tools/list")["result"] as! [String:Any])["tools"] as! [[String:Any]]
  assert(Set(listed.compactMap { $0["name"] as? String }) == ["read_appearance","update_appearance"])
  assert(agent.rpc(["jsonrpc":"2.0","method":"notifications/initialized"]) == nil)
  assert(!agent.active); _ = agent.authorize(); assert(agent.active)
  for patch: [String:Any] in [["poll":1],["fontSize":true],["showHistory":1],["background":"#ffffff","foreground":"#eeeeee"],["name":""],["fontSize":44.5],["source":"evil()"]] {
   assert(call("tools/call",["name":"update_appearance","arguments":["patch":patch]])["error"] != nil)
   assert(agent.revision == 0)
  }
  var applied = false; agent.onChange = { _ in applied = true }
  assert(call("tools/call",["name":"update_appearance","arguments":["patch":["fontSize":36,"background":"#111111","foreground":"#ffffff"]]])["result"] != nil)
  assert(applied && agent.revision == 1 && !((agent.state()["saved"] as? Bool)!))
  assert(agent.appearance["fontSize"] as? Int == 36)
  assert(call("tools/call",["name":"read_messages"])["error"] != nil)
  agent.savedRevision = 1; assert(agent.state()["saved"] as? Bool == true)
  agent.expires = 0; assert(!agent.active); agent.revoke(); assert(agent.token == nil)
  print("Appearance MCP: protocol, capability lifetime, restricted tools, validation and save acknowledgement passed")
 }
}
