import Foundation

enum HubCardPresentation {
    static func isWorkPlan(_ card: HubCard) -> Bool { card.kind == "report" && card.title.contains("工作计划") }
    static func title(_ card: HubCard) -> String { isWorkPlan(card) ? "工作计划" : card.title }
    static func text(_ card: HubCard) -> String {
        let text = displayText(card.text)
        guard isWorkPlan(card) else { return text }
        let headings: Set<String> = ["工作周报", "周报", "工作计划", "下周工作计划", "本周工作计划"]
        var lines = text.components(separatedBy: .newlines)
        while let first = lines.first {
            let heading = first.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#*：:")))
            guard heading.isEmpty || headings.contains(heading) else { break }
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }
    static func displayText(_ text:String) -> String {
        let useful = text.components(separatedBy: .newlines).filter {
            $0.range(of: #"^\s*(?:[-*]\s*)?(?:创建人|创建者|创建时间|创建日期|提交时间|createdAt|created_at|createdBy|creator)\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) == nil
        }.map {
            $0.replacingOccurrences(of: #"\s*·\s*(?:提交于|创建于)\s+[^·]+$"#, with: "", options: .regularExpression)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return useful.replacingOccurrences(of:#"(?<=[。；;])\s*(?=[0-9]{1,2}[.、](?![0-9]))"#,with:"\n\n",options:.regularExpression)
    }
}
