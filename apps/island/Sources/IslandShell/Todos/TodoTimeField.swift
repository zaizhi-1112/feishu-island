import SwiftUI
import NookApp

enum TodoTimeValue {
    static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    static func applying(_ text: String, to date: Date, calendar: Calendar = .current) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute),
              let result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date, matchingPolicy: .strict),
              calendar.isDate(result, inSameDayAs: date) else { return nil }
        return result
    }
}

/// A regular text editor works in the nonactivating island panel. Keep its draft
/// while focused so a parent refresh cannot reset partially typed hour/minute text.
struct TodoTimeField: View {
    let title: String
    @Binding var selection: Date
    var validityChanged: (Bool) -> Void = { _ in }
    @State private var draft = ""
    @State private var valid = true
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("HH:mm", text: $draft)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                .frame(width: 104).focused($focused)
                .accessibilityLabel(title).accessibilityIdentifier("todo.time." + title)
                .onSubmit { commit() }
            if !valid { Text("请输入 00:00–23:59").islandFont(size: 10).foregroundStyle(.red) }
        }
        .nookKeepsExpanded(whileFocused: $focused)
        .onAppear { draft = TodoTimeValue.text(selection); validityChanged(true) }
        .onChange(of: draft) { _, value in
            let next = TodoTimeValue.applying(value, to: selection)
            valid = next != nil; validityChanged(valid)
            if let next, next != selection { selection = next }
        }
        .onChange(of: selection) { _, value in if !focused { draft = TodoTimeValue.text(value) } }
        .onChange(of: focused) { _, value in if !value { commit() } }
        .onDisappear { validityChanged(true) }
    }
    private func commit() {
        guard let value = TodoTimeValue.applying(draft, to: selection) else { valid = false; validityChanged(false); return }
        selection = value; draft = TodoTimeValue.text(value); valid = true; validityChanged(true)
    }
}
