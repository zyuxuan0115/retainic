---
type: "query"
date: "2026-07-31T21:09:11.028056+00:00"
question: "Improve modularity by splitting source files over 600 lines and reduce code duplication."
contributor: "graphify"
outcome: "useful"
source_nodes: ["web/js/app.js", "web/js/ui.js", "web/js/screens/list-detail-screen.js", "web/js/translations.js", "iOS/Retainic/ListDetailView.swift", "iOS/Retainic/WordsViewModel.swift", "iOS/Retainic/RepositoryErrorAlert.swift", "android/app/src/main/java/com/retainic/app/ui/ListDetailScreen.kt", "android/app/src/main/java/com/retainic/app/ui/ListDetailComponents.kt", "android/app/src/main/java/com/retainic/app/ui/Components.kt"]
---

# Q: Improve modularity by splitting source files over 600 lines and reduce code duplication.

## Answer

Split all five oversized executable source files into feature-focused modules across web, iOS, and Android. Reduced app.js from 1,881 to 113 lines, translations.js from 1,263 to a 15-line index, ListDetailView.swift from 695 to 308, VocabListsView.swift from 687 to 171, and ListDetailScreen.kt from 605 to 369. Consolidated iOS repository error alerts, Android error dialogs and POS chips, removed an unused Swift bulk-delete method, and added a repository-wide 600-line regression guard plus translation parity tests. Final maximum source size is 541 lines; web tests and iOS target compilation pass.

## Outcome

- Signal: useful

## Source Nodes

- web/js/app.js
- web/js/ui.js
- web/js/screens/list-detail-screen.js
- web/js/translations.js
- iOS/Retainic/ListDetailView.swift
- iOS/Retainic/WordsViewModel.swift
- iOS/Retainic/RepositoryErrorAlert.swift
- android/app/src/main/java/com/retainic/app/ui/ListDetailScreen.kt
- android/app/src/main/java/com/retainic/app/ui/ListDetailComponents.kt
- android/app/src/main/java/com/retainic/app/ui/Components.kt
- web/tests/modularity.test.mjs