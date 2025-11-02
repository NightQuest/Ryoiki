//
//  SettingsView.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

/// The app's settings view
struct SettingsView: View {

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(.settingsLibraryItemsPerRow) private var itemsPerRowPreference: Int = 6
    @AppStorage(.settingsNetworkUserAgent) private var userAgent: String = defaultUserAgent
    @AppStorage(.settingsDownloadMaxConcurrent) private var maxConcurrentDownloads: Int = 10
    @AppStorage(.settingsNetworkPerHost) private var maxConnectionsPerHost: Int = 6

    @AppStorage(.settingsVerticalPillarboxEnabled) private var verticalPillarboxEnabled: Bool = false
    @AppStorage(.settingsVerticalPillarboxWidth) private var verticalPillarboxWidth: Double = 0

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Comics per row") {
                    Stepper(String(itemsPerRowPreference),
                            value: $itemsPerRowPreference,
                            in: 2...10,
                            step: 1)
                }
            }
            Section("Network") {
                LabeledContent("User-Agent") {
                    TextField("User-Agent", text: $userAgent)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 240)
                }
                LabeledContent("Max concurrent downloads") {
                    Stepper(String(maxConcurrentDownloads), value: $maxConcurrentDownloads, in: 1...24, step: 1)
                }
                LabeledContent("Max connections per host") {
                    Stepper(String(maxConnectionsPerHost), value: $maxConnectionsPerHost, in: 1...12, step: 1)
                }
            }
            Section("Reader") {
                Toggle("Vertical mode pillarbox", isOn: $verticalPillarboxEnabled)
                HStack {
                    Text("Pillarbox width")
                    Slider(value: $verticalPillarboxWidth, in: 0...120, step: 1)
                        .frame(maxWidth: 200)
                    Text("\(Int(verticalPillarboxWidth)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .disabled(!verticalPillarboxEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
