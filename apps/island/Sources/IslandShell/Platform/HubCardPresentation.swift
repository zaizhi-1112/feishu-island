import Foundation

enum HubCardPresentation {
    static func displayText(_ text:String) -> String {
        text.replacingOccurrences(of:#"(?<=[。；;])\s*(?=[0-9]{1,2}[.、](?![0-9]))"#,with:"\n\n",options:.regularExpression)
    }
}
