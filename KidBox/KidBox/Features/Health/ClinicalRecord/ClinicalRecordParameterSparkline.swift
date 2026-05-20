//
//  ClinicalRecordParameterSparkline.swift
//  KidBox
//

import SwiftUI

struct ClinicalRecordParameterSparkline: View {
    let parameter: ParameterTrend
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(parameter.name)
                    .font(.subheadline.bold())
                Spacer()
                trendArrow
                if let last = parameter.points.last {
                    Text(last.displayValue)
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                }
            }
            if parameter.points.count >= 2 {
                GeometryReader { geo in
                    let nums = parameter.points.compactMap(\.numericValue)
                    if nums.count >= 2 {
                        sparkPath(in: geo.size, values: nums)
                            .stroke(tint, lineWidth: 2)
                    }
                }
                .frame(height: 36)
                HStack {
                    Text(formatDate(parameter.points.first?.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDate(parameter.points.last?.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let note = parameter.clinicalNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.06)))
    }

    @ViewBuilder
    private var trendArrow: some View {
        switch parameter.trend {
        case .stabile:
            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        case .inAumento:
            Image(systemName: "arrow.up.right")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        case .inDiminuzione:
            Image(systemName: "arrow.down.right")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }

    private func sparkPath(in size: CGSize, values: [Double]) -> Path {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.001)
        var path = Path()
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
            let y = size.height * (1 - CGFloat((v - minV) / span))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateFormat = "MMM yy"
        return f.string(from: date)
    }
}
