//
//  ReaderPillarboxControls.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-05.
//

import SwiftUI

struct ReaderPillarboxControls: View {
    @Binding var enabled: Bool
    @Binding var width: Double

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Pillarbox", isOn: $enabled)
                .labelsHidden()
            Slider(value: $width, in: 0...120, step: 1)
                .frame(width: 160)
            Text("\(Int(width)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
