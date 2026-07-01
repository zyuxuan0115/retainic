//
//  MainTabView.swift
//  Retainic
//
//  Top-level navigation once signed in.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            VocabListsView()
                .tabItem {
                    Label("My Lists", systemImage: "rectangle.stack")
                }

            StatsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
