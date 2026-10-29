import Foundation

enum HubBuiltinDestination: String, CaseIterable {
    case home, okr, library, data, exceptions, apps, skills, approval
    var title: String {
        switch self { case .home: "首页"; case .okr: "OKR"; case .library: "资料"; case .data: "数据"; case .exceptions: "异常项"; case .apps: "应用"; case .skills: "Skill"; case .approval: "审批" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .okr: "target"; case .library: "books.vertical"; case .data: "chart.bar"; case .exceptions: "exclamationmark.triangle"; case .apps: "square.grid.2x2"; case .skills: "sparkles"; case .approval: "checkmark.seal" }
    }
    var url: URL {
        if self == .approval { return URL(string: "https://applink.feishu.cn/client/mini_program/open?appId=cli_9cb844403dbb9108&mode=appCenter")! }
        return URL(string: "https://virxact.net/" + (self == .home ? "" : rawValue))!
    }
}

struct HubShortcutChoice: Identifiable {
    var id: String
    var title: String
    var group: String
    var symbol: String
    var shortcut: HubPingShortcut

    static func catalog(cards: [HubCard], applications: [HubHomeApplication]) -> [Self] {
        var result = HubBuiltinDestination.allCases.map { Self(id: "builtin:" + $0.rawValue, title: $0.title, group: "中台入口", symbol: $0.symbol, shortcut: .init(source:.builtin,cardID:$0.rawValue)) }
        result.append(Self(id:"settings",title:"灵动岛设置",group:"本机",symbol:"gearshape",shortcut:.init(source:.settings)))
        result += applications.filter { HubPingGeometry.safeURL($0.url) != nil }.map { Self(id:"app:" + $0.id,title:$0.name,group:$0.frequent ? "常用应用" : "全部应用",symbol:"app",shortcut:.init(source:.application,cardID:$0.id)) }
        result += cards.filter { $0.href.flatMap(HubPingGeometry.safeURL) != nil }.map { Self(id:"card:" + $0.id,title:HubCardPresentation.title($0),group:"我的卡片",symbol:"rectangle",shortcut:.init(source:.card,cardID:$0.id)) }
        return result
    }
}
