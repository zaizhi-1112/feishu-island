import Foundation

enum HubCardPresentation {
    static func displayText(_ text:String) -> String {
        let useful = text.components(separatedBy: .newlines).filter {
            $0.range(of: #"^\s*(?:[-*]\s*)?(?:创建人|创建者|创建时间|创建日期|提交时间|createdAt|created_at|createdBy|creator)\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) == nil
        }.map {
            $0.replacingOccurrences(of: #"\s*·\s*(?:提交于|创建于)\s+[^·]+$"#, with: "", options: .regularExpression)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return useful.replacingOccurrences(of:#"(?<=[。；;])\s*(?=[0-9]{1,2}[.、](?![0-9]))"#,with:"\n\n",options:.regularExpression)
    }
}
