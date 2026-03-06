//
//  RecordingWaveformView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI

struct AdaptiveRecordingWaveformView: View {
    let samples: [CGFloat]
    let availableWidth: CGFloat
    
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 28
    
    var body: some View {
        let slot = barWidth + spacing
        let capacity = max(1, Int(availableWidth / slot))
        let visibleSamples = Array(samples.suffix(capacity))
        
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(visibleSamples.enumerated()), id: \.offset) { _, sample in
                RoundedRectangle(cornerRadius: 2)
                    .fill(KBTheme.bubbleTint)
                    .frame(
                        width: barWidth,
                        height: max(minBarHeight, sample * maxBarHeight)
                    )
            }
        }
        .frame(width: availableWidth, height: 30, alignment: .trailing)
        .clipped()
        .animation(.linear(duration: 0.05), value: samples)
    }
}
