import ScribApplication
import SwiftUI

struct LastTrialSummary: View {
    @ObservedObject var model: RecordingViewModel
    let run: AIGenerationRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(ScribDesign.success)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dernier essai validé — \(run.modelProfile.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text("\(run.usage.inputTokens) jetons entrants · \(run.usage.outputTokens) sortants · \(model.formatUSDCost(run.usage.estimatedCostUSD))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(ScribDesign.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TrialComparisonList: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        Text("Comparatif des essais").font(.headline)
        ForEach(Array(model.aiGenerationRuns.prefix(8))) { run in
            HStack(spacing: 12) {
                Image(systemName: run.usage.isSimulated ? "desktopcomputer" : "cloud.fill")
                    .foregroundStyle(ScribDesign.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.modelProfile.displayName).font(.subheadline.weight(.semibold))
                    Text("\(run.sectionCount) sections · \(run.blockCount) blocs · \(run.durationMilliseconds) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.formatUSDCost(run.usage.estimatedCostUSD)).font(.subheadline.weight(.semibold))
                    Text(run.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if run.id != model.aiGenerationRuns.prefix(8).last?.id { Divider() }
        }
    }
}
