import SwiftUI
import NookApp

struct AgentCompletionNotice: Identifiable, Sendable {
    let id = UUID()
    let profileID: String
    let name: String
    let count: Int
    let stillWorking: Bool
    var status: String { stillWorking ? "完成\(count)项 · 仍在工作" : count > 1 ? "\(count)项已完成" : "已完成" }
    var message: String { "\(name) · \(count)个任务已完成" + (stillWorking ? "，还有任务正在工作" : "") }
}

/// One soft ring, then a steady light. Never loops while the island is idle.
struct AgentStatusLight: View {
    let color: Color
    var pulse = false
    var motion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.55), radius: 3)
            .overlay {
                if pulse && motion && !reduceMotion {
                    Circle().stroke(color.opacity(settled ? 0 : 0.65), lineWidth: 1)
                        .scaleEffect(settled ? 2.8 : 1)
                }
            }
            .task {
                guard pulse && motion && !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.85).delay(0.2)) { settled = true }
            }
            .accessibilityHidden(true)
    }
}

private struct CompletionCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.20))
        return path
    }
}

struct AgentCompletionStatus: View {
    let notice: AgentCompletionNotice
    let motion: Bool
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checked = false
    var body: some View {
        HStack(spacing: 6) {
            AgentStatusLight(color: notice.stillWorking ? .red : .green, pulse: !notice.stillWorking, motion: motion)
            Text(notice.name).foregroundStyle(theme.secondaryLabel)
            Text(notice.status).foregroundStyle(notice.stillWorking ? theme.primaryLabel : .green)
            CompletionCheck().trim(from: 0, to: !motion || reduceMotion || checked ? 1 : 0)
                .stroke(.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 10).accessibilityHidden(true)
        }
        .font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize()
        .id(notice.id)
        .task(id: notice.id) {
            checked = false
            guard motion && !reduceMotion else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            withAnimation(.easeOut(duration: 0.35)) { checked = true }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(notice.message)
        .accessibilityIdentifier("island.agentCompletion")
    }
}
