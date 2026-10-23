import Foundation
import CryptoKit
import CoreFoundation

struct DotSubscription: Codable, Equatable {
    var id: String
    var url: String
    var secret: String
    var expires: Date
    var previousSecret: String?
    var rotationUntil: Date?
    var verifiedAt: Date?
    var refreshCount: Int?
}
struct DotDelivery: Codable, Equatable {
    var attempts = 0
    var nextAttempt = Date.distantPast
    var accepted = false
    var stopped = false
    var status: Int?
    var acceptedAt: Date?
}

/// Persistent subscriptions are stored with their grant in the existing, stable Keychain helper.
/// Only dispatch identifiers leave the Mac in events. Materials are read through claimed tools.
@MainActor final class DotEvents {
    static let name="work.task_queued"
    private let pairing: DotPairing
    private let store: WorkspaceStore
    private let transport: any DotWebhookTransport
    var allowed: () -> Bool
    var deliveryReady: () -> Bool = { true }
    var now: () -> Date
    private var pumping=false
    private var generation: [UUID:Int]=[:]
    // In-memory metadata only: no callback URL, secret, task body or identifiers.
    private(set) var diagnostic: [String:String] = [:]
    var healthSnapshot: [String:String] {
        var value=diagnostic
        let subscriptions=pairing.grants.filter{$0.expires>now()}.compactMap(\.subscription)
        value["activeSubscriptions"]=String(subscriptions.filter{$0.expires>now()}.count)
        value["refreshCount"]=String(subscriptions.reduce(0){$0+($1.refreshCount ?? 0)})
        value["refreshBefore"]=subscriptions.map(\.expires).min()?.ISO8601Format()
        return value
    }
    init(pairing: DotPairing, store: WorkspaceStore, transport: any DotWebhookTransport = DotPublicWebhook(), allowed: @escaping () -> Bool = {true}, now: @escaping () -> Date = Date.init) {
        self.pairing=pairing; self.store=store; self.transport=transport; self.allowed=allowed; self.now=now
    }
    static func identity(grant: UUID, url: String, project: String) -> String {
        let canonical=try! JSONSerialization.data(withJSONObject:["grant":grant.uuidString,"url":url,"name":name,"arguments":["project":project]],options:.sortedKeys)
        return "sub_"+SHA256.hash(data:canonical).map{String(format:"%02x",$0)}.joined()
    }
    static var definition: [String:Any] {
        ["name":name,"description":"A task explicitly delegated to Dot in this one project is ready to claim. The event contains identifiers only; read material through the scoped task tools.","delivery":["webhook"],
         "inputSchema":["type":"object","properties":["project":["type":"string"]],"required":["project"],"additionalProperties":false],
         "payloadSchema":["type":"object","properties":["task_id":["type":"string"],"dispatch_id":["type":"string"]],"required":["task_id","dispatch_id"],"additionalProperties":false]]
    }
    func rpc(_ request: [String:Any], grant: DotGrant) async -> [String:Any]? {
        guard let id=request["id"] else { return nil }
        func result(_ value: [String:Any]) -> [String:Any] { var value=value; value["resultType"]="complete"; return ["jsonrpc":"2.0","id":id,"result":value] }
        func failure(_ message: String, callback: Bool = false) -> [String:Any] {
            diagnostic["error"]=message; diagnostic["at"]=now().ISO8601Format()
            return ["jsonrpc":"2.0","id":id,"error":["code":callback ? -32015 : -32602,"message":message,"data":["reason":callback ? "challenge_failed" : "invalid_subscription"]]]
        }
        guard allowed(), request["jsonrpc"] as? String=="2.0" else { return failure("Mac is locked or invalid request") }
        let method=request["method"] as? String ?? ""
        var p=request["params"] as? [String:Any] ?? [:]; p.removeValue(forKey:"_meta")
        if method=="events/list" {
            guard p.isEmpty || (Set(p.keys)==["cursor"] && p["cursor"] is NSNull) else { return failure("No event catalog cursor") }
            return result(["events":[Self.definition],"ttlMs":0,"cacheScope":"private"])
        }
        guard ["events/subscribe","events/unsubscribe"].contains(method), p["name"] as? String==Self.name,
              let args=p["arguments"] as? [String:Any], Set(args.keys)==["project"], args["project"] as? String==grant.project,
              let delivery=p["delivery"] as? [String:Any], delivery["mode"] as? String=="webhook", let url=delivery["url"] as? String else { return failure("Event or project is outside this grant") }
        do { _=try DotPublicWebhook.destination(url) } catch { return failure("Callback must be public HTTPS") }
        let identity=Self.identity(grant:grant.id,url:url,project:grant.project)
        if method=="events/unsubscribe" {
            diagnostic["lastAction"]="unsubscribe"
            guard Set(p.keys)==["name","arguments","delivery"], Set(delivery.keys)==["mode","url"] else { return failure("Unknown unsubscribe fields") }
            generation[grant.id,default:0]+=1
            do {
                if pairing.grants.first(where:{$0.id==grant.id})?.subscription?.id==identity { try pairing.setSubscription(nil,grantID:grant.id) }
                return result([:])
            } catch { return failure("Subscription storage unavailable") }
        }
        guard Set(p.keys).isSubset(of:["name","arguments","delivery","cursor","ttlMs"]),
              p["cursor"]==nil || p["cursor"] is NSNull, Set(delivery.keys)==["mode","url","secret"], let secret=delivery["secret"] as? String,
              (try? DotWebhookSigner.key(secret)) != nil else { return failure("Invalid subscription fields or signing key") }
        var ttl=86400.0
        diagnostic=["lastAction":"subscribe","stage":"validated","at":now().ISO8601Format()]
        if let raw=p["ttlMs"], !(raw is NSNull) {
            guard let milliseconds=raw as? NSNumber, CFGetTypeID(milliseconds) != CFBooleanGetTypeID(), milliseconds.doubleValue.isFinite, milliseconds.doubleValue>=1000 else { return failure("ttlMs must be at least 1000") }
            ttl=min(ttl,milliseconds.doubleValue/1000)
        }
        generation[grant.id,default:0]+=1; let version=generation[grant.id]!
        let instant=now(), challenge=UUID().uuidString+UUID().uuidString
        let expiry=min(grant.expires,instant.addingTimeInterval(ttl))
        var subscription=DotSubscription(id:identity,url:url,secret:secret,expires:expiry)
        subscription.refreshCount=(pairing.grants.first(where:{$0.id==grant.id})?.subscription?.refreshCount ?? 0)+1
        if let old=pairing.grants.first(where:{$0.id==grant.id})?.subscription, old.id==identity, old.secret != secret {
            subscription.previousSecret=old.secret; subscription.rotationUntil=instant.addingTimeInterval(300)
        }
        do {
            let previous=pairing.grants.first(where:{$0.id==grant.id})?.subscription
            if let previous, previous.id==identity, previous.secret==secret, previous.expires>instant,
               let verified=previous.verifiedAt, (0..<60).contains(instant.timeIntervalSince(verified)) {
                subscription.verifiedAt=verified
                subscription.previousSecret=previous.previousSecret; subscription.rotationUntil=previous.rotationUntil
            } else {
                let body=try JSONSerialization.data(withJSONObject:["type":"verification","challenge":challenge],options:.sortedKeys)
                diagnostic["stage"]="callback"
                let reply=try await transport.post(url:url,headers:DotWebhookSigner.headers(id:"verify_"+UUID().uuidString,subscription:subscription,body:body,now:instant),body:body)
                diagnostic["callbackHTTP"]=String(reply.status)
                guard (200...299).contains(reply.status), reply.body.count<=16384,
                      let value=try? JSONSerialization.jsonObject(with:reply.body) as? [String:Any], let echo=value["challenge"] as? String,
                      Self.equal(challenge,echo), now().timeIntervalSince(instant)<30 else { return failure("Callback challenge failed",callback:true) }
                subscription.verifiedAt=now()
            }
            guard allowed(), generation[grant.id]==version, expiry>now() else { return failure("Subscription cancelled or expired during verification") }
            try pairing.setSubscription(subscription,grantID:grant.id)
            diagnostic["stage"]="saved"
            return result(["id":identity,"refreshBefore":expiry.ISO8601Format(),"cursor":NSNull(),"truncated":false])
        } catch {
            if let error=error as? WorkError { diagnostic["detail"]=error.localizedDescription }
            return failure("Callback verification or secure storage failed",callback:true)
        }
    }
    static func equal(_ a: String,_ b: String) -> Bool {
        let x=Array(a.utf8), y=Array(b.utf8); guard x.count==y.count else { return false }
        return zip(x,y).reduce(UInt8(0)){$0 | ($1.0 ^ $1.1)}==0
    }
    // Only transport failures are recoverable. Revoked/oversized callbacks stay stopped.
    static func transient(_ status: Int?) -> Bool {
        guard let status else { return true }
        return [408,429].contains(status) || (500...599).contains(status)
    }
    private func recoverPending(grant: DotGrant, subscription: DotSubscription) async {
        let pending=store.disk.items.filter {
            guard $0.state=="dot_waiting", $0.service=="dot", ($0.project ?? "日常工作")==grant.project,
                  let d=$0.dotDeliveries?[subscription.id] else { return false }
            return d.stopped && !d.accepted && Self.transient(d.status) && d.nextAttempt<=now()
        }
        guard !pending.isEmpty else { return }
        // Probe once per subscription after cooldown, never replay a completed/claimed task.
        for item in pending {
            if let dispatch=item.dotDispatch, var d=item.dotDeliveries?[subscription.id] {
                d.nextAttempt=now().addingTimeInterval(900)
                _=store.saveDotDelivery(taskID:item.id,dispatch:dispatch,subscription:subscription.id,value:d)
            }
        }
        do {
            let challenge=UUID().uuidString, start=now()
            let body=try JSONSerialization.data(withJSONObject:["type":"verification","challenge":challenge])
            let reply=try await transport.post(url:subscription.url,headers:DotWebhookSigner.headers(id:"recover_"+UUID().uuidString,subscription:subscription,body:body,now:start),body:body)
            guard allowed(), subscription.expires>now(), now().timeIntervalSince(start)<30,
                  pairing.grants.contains(where:{$0.id==grant.id && $0.expires>now() && $0.subscription==subscription}),
                  (200...299).contains(reply.status), reply.body.count<=16384,
                  let json=try? JSONSerialization.jsonObject(with:reply.body) as? [String:Any],
                  let echo=json["challenge"] as? String, Self.equal(echo,challenge) else { return }
            for item in pending {
                if let dispatch=item.dotDispatch { _=store.saveDotDelivery(taskID:item.id,dispatch:dispatch,subscription:subscription.id,value:DotDelivery()) }
            }
            diagnostic["recovery"]="callback_verified"
        } catch { diagnostic["recovery"]="waiting_for_connection" }
    }
    func pump() async {
        guard !pumping, allowed(), deliveryReady() else { return }
        pumping=true; defer { pumping=false }
        do { try pairing.load() } catch { return }
        // At most four deliveries per tick, yielding to Feishu and the UI throughout HTTPS I/O.
        var sent=0
        for grant in pairing.grants where grant.expires>now() {
            guard let subscription=grant.subscription, subscription.expires>now() else { continue }
            await recoverPending(grant:grant,subscription:subscription)
            for item in store.disk.items where item.service=="dot" && (item.project ?? "日常工作")==grant.project && item.state=="dot_waiting" {
                guard sent<4, allowed() else { return }
                guard let dispatch=item.dotDispatch, let occurred=item.dotQueuedAt else { continue } // No replay of legacy/manual tasks.
                guard pairing.grants.contains(where:{$0.id==grant.id && $0.expires>now() && $0.subscription==subscription}), subscription.expires>now(),
                      store.disk.items.contains(where:{$0.id==item.id && $0.dotDispatch==dispatch && $0.state=="dot_waiting"}) else { continue }
                var delivery=item.dotDeliveries?[subscription.id] ?? DotDelivery()
                guard !delivery.accepted, !delivery.stopped, delivery.nextAttempt<=now(), (item.dotDeliveries?.count ?? 0)<64 || item.dotDeliveries?[subscription.id] != nil else { continue }
                if delivery.attempts>=6 { delivery.stopped=true; _=store.saveDotDelivery(taskID:item.id,dispatch:dispatch,subscription:subscription.id,value:delivery); continue }
                delivery.attempts+=1
                // Persist before send. A crash after receipt may redeliver the same event ID, never a new task.
                delivery.nextAttempt=now().addingTimeInterval(10*pow(2,Double(delivery.attempts-1)))
                guard store.saveDotDelivery(taskID:item.id,dispatch:dispatch,subscription:subscription.id,value:delivery) else { continue }
                sent+=1
                do {
                    let event: [String:Any] = ["eventId":dispatch.uuidString,"name":Self.name,"timestamp":occurred.ISO8601Format(),"data":["task_id":item.id.uuidString,"dispatch_id":dispatch.uuidString],"cursor":NSNull()]
                    let body=try JSONSerialization.data(withJSONObject:event,options:.sortedKeys)
                    let reply=try await transport.post(url:subscription.url,headers:DotWebhookSigner.headers(id:dispatch.uuidString,subscription:subscription,body:body,now:now()),body:body)
                    delivery.status=reply.status; delivery.accepted=(200...299).contains(reply.status)
                    if delivery.accepted { delivery.acceptedAt=now() }
                    delivery.stopped = !delivery.accepted && !Self.transient(reply.status)
                } catch { delivery.status=nil }
                if delivery.attempts>=6 && !delivery.accepted { delivery.stopped=true; delivery.nextAttempt=now().addingTimeInterval(900) }
                _=store.saveDotDelivery(taskID:item.id,dispatch:dispatch,subscription:subscription.id,value:delivery)
            }
        }
    }
}
