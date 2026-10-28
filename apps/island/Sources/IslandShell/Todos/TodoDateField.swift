import SwiftUI

/// A compact month/day entry; the stored value remains a full Date. The calendar
/// popover still lets a person deliberately choose another year.
struct TodoDateField: View {
    let title: String
    @Binding var selection: Date
    @State private var showingCalendar = false
    var body: some View {
        Button { showingCalendar = true } label: {
            HStack(spacing: 6) {
                Text(selection.formatted(.dateTime.month().day()))
                Image(systemName: "calendar").foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }.buttonStyle(.bordered)
            .accessibilityLabel(title)
            .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showingCalendar) {
                DatePicker(title, selection: $selection, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().padding(12)
            }
    }
}
