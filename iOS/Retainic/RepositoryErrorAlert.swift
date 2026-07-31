//
//  RepositoryErrorAlert.swift
//  Retainic
//
//  Shared presentation for repository-backed view-model failures.
//

import SwiftUI

extension View {
    func repositoryErrorAlert(
        _ message: Binding<String?>,
        language: String
    ) -> some View {
        alert(
            "Something went wrong".localized(language),
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK".localized(language), role: .cancel) {
                message.wrappedValue = nil
            }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
