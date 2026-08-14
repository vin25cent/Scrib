import SwiftUI

struct TrialMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(ScribDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ScribDesign.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}
