import SwiftUI

/// Panel displaying position evaluation from cloud analysis
struct AnalysisPanel: View {
    let evaluation: CloudEvalService.CloudEval?
    let isLoading: Bool
    let isBlackPerspective: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "cpu")
                Text("Analysis")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let eval = evaluation {
                // Evaluation bar
                EvaluationBar(score: CloudEvalService.normalizedScore(eval.pvs.first!, forBlack: isBlackPerspective))

                // Main score
                if let pv = eval.pvs.first {
                    HStack {
                        Text(CloudEvalService.formatScore(pv, forBlack: isBlackPerspective))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(pv))

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Depth \(eval.depth)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(eval.knodes / 1000)M nodes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Principal variations
                Text("Best Lines")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(Array(eval.pvs.prefix(3).enumerated()), id: \.offset) { index, pv in
                    PrincipalVariationRow(
                        index: index + 1,
                        pv: pv,
                        isBlackPerspective: isBlackPerspective
                    )
                }
            } else if !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Position not in cloud database")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Spacer()
        }
        .padding()
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func scoreColor(_ pv: CloudEvalService.CloudEval.PrincipalVariation) -> Color {
        let score = CloudEvalService.normalizedScore(pv, forBlack: isBlackPerspective)
        if score > 0.3 {
            return .green
        } else if score < -0.3 {
            return .red
        }
        return .primary
    }
}

/// Visual bar showing position evaluation
struct EvaluationBar: View {
    let score: Double  // -1.0 (black winning) to 1.0 (white winning)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background (black side)
                Rectangle()
                    .fill(Color.black)

                // White side
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geo.size.width * whitePercentage)
            }
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
        }
        .frame(height: 20)
    }

    private var whitePercentage: CGFloat {
        // Convert -1..1 to 0..1
        return CGFloat((score + 1) / 2)
    }
}

/// Row showing a principal variation line
struct PrincipalVariationRow: View {
    let index: Int
    let pv: CloudEvalService.CloudEval.PrincipalVariation
    let isBlackPerspective: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .trailing)

            Text(CloudEvalService.formatScore(pv, forBlack: isBlackPerspective))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(scoreColor)
                .frame(width: 40, alignment: .leading)

            Text(formattedMoves)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var scoreColor: Color {
        let score = CloudEvalService.normalizedScore(pv, forBlack: isBlackPerspective)
        if score > 0.1 {
            return .green
        } else if score < -0.1 {
            return .red
        }
        return .primary
    }

    private var formattedMoves: String {
        // Show first 4-5 moves
        let moves = pv.moves.split(separator: " ").prefix(5)
        return moves.joined(separator: " ")
    }
}

/// Compact evaluation display for inline use
struct CompactEvaluation: View {
    let evaluation: CloudEvalService.CloudEval?
    let isBlackPerspective: Bool

    var body: some View {
        if let eval = evaluation, let pv = eval.pvs.first {
            HStack(spacing: 4) {
                Text(CloudEvalService.formatScore(pv, forBlack: isBlackPerspective))
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(scoreColor(pv))

                // Mini eval bar
                EvaluationBar(score: CloudEvalService.normalizedScore(pv, forBlack: isBlackPerspective))
                    .frame(width: 40, height: 8)
            }
        }
    }

    private func scoreColor(_ pv: CloudEvalService.CloudEval.PrincipalVariation) -> Color {
        let score = CloudEvalService.normalizedScore(pv, forBlack: isBlackPerspective)
        if score > 0.2 {
            return .green
        } else if score < -0.2 {
            return .red
        }
        return .secondary
    }
}

#Preview {
    AnalysisPanel(
        evaluation: CloudEvalService.CloudEval(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            knodes: 12500000,
            depth: 36,
            pvs: [
                .init(moves: "e7e5 g1f3 b8c6 f1b5 a7a6", cp: 25, mate: nil),
                .init(moves: "c7c5 g1f3 d7d6 d2d4 c5d4", cp: 35, mate: nil),
                .init(moves: "e7e6 d2d4 d7d5 b1c3 g8f6", cp: 40, mate: nil)
            ]
        ),
        isLoading: false,
        isBlackPerspective: false,
        error: nil
    )
}
