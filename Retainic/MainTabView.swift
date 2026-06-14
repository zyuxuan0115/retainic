//
//  MainTabView.swift
//  Retainic
//
//  Top-level navigation once onboarding is complete.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    var body: some View {
        TabView {
            WordListView()
                .tabItem {
                    Label("Words", systemImage: "character.book.closed")
                }

            FlashcardView()
                .tabItem {
                    Label("Practice", systemImage: "rectangle.on.rectangle.angled")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: Word.self, inMemory: true)
}
