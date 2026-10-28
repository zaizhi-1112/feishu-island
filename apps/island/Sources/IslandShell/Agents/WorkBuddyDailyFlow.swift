import Foundation

enum WorkBuddyDailyFlow {
    struct Receipt:Codable { var day:String;var account:String;var state:String;var checked:Double }
    static func run(day:String,account:String,claimed:Bool,eligible:Bool,allowClaim:Bool,records:[Receipt],save:(String)->Bool,press:()->Bool,verify:()->Bool)->String {
        if claimed{return save("already_claimed") ? "already_claimed" : "storage_error"}
        guard allowClaim else{return "not_claimed"}
        guard eligible else{return "station_changed"}
        guard !records.contains(where:{$0.day==day && $0.account==account && ["attempted","uncertain"].contains($0.state)}) else{return "uncertain"}
        guard save("attempted") else{return "storage_error"}
        guard press() else{_ = save("uncertain");return "uncertain"}
        guard verify() else{_ = save("uncertain");return "uncertain"}
        return save("claimed") ? "claimed" : "storage_error"
    }
}
