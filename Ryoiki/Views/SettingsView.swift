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
    @AppStorage("library.itemsPerRow") private var itemsPerRowPreference: Int = 6

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
        }
        .formStyle(.grouped)
    }
}
