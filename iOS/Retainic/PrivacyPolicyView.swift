//
//  PrivacyPolicyView.swift
//  Retainic
//
//  The privacy policy, shown in-app from About. Mirrors web/privacy.html and
//  the Android PrivacyPolicyScreen; the three are kept word-for-word in step.
//  The policy itself stays in English, like the hosted page — only the screen's
//  title is localized.
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(Array(Self.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 10) {
                        if !section.title.isEmpty {
                            Text(verbatim: section.title)
                                .font(.headline)
                        }
                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                }
                Divider()
                Text(verbatim: "© 2026 Retainic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Privacy Policy")
                .font(.title.bold())
            Text(verbatim: "Applies to the Retainic apps for Android, iOS and the web.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "Last updated: 11 August 2026 · Effective: 11 August 2026")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let markdown):
            Self.styled(markdown)
        case .bullet(let markdown):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                Self.styled(markdown)
            }
        case .term(let label, let markdown):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.subheadline.bold())
                Self.styled(markdown)
            }
        }
    }

    /// Body copy rendered from inline Markdown, so `**bold**` and `[text](url)`
    /// links (including `mailto:`) work without hand-built attributed strings.
    private static func styled(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let attributed = (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)
        return Text(attributed).font(.subheadline)
    }

    private enum Block {
        case text(String)
        /// A bulleted line.
        case bullet(String)
        /// A bold lead-in on its own line, then the copy beneath it.
        case term(String, String)
    }

    private struct PolicySection {
        let title: String
        let blocks: [Block]
    }
}

// MARK: - The policy

extension PrivacyPolicyView {
    fileprivate static let contactEmail = "retainic.app@gmail.com"

    private static let sections: [PolicySection] = [
        PolicySection(title: "", blocks: [
            .text("""
            Retainic ("the app", "we", "us") is a vocabulary-learning app that lets you build \
            word lists and glossaries, record pronunciations and practice them with \
            spaced-repetition flashcards. This policy explains what personal data the app \
            collects, why, who it is shared with, how long it is kept and how you can have it \
            deleted. It covers every version of Retainic — the Android app, the iOS app and the \
            web app — which all share one account and one backend.
            """),
        ]),

        PolicySection(title: "1. Who we are", blocks: [
            .text("""
            Retainic is an independent project developed and operated by the developer of the \
            open-source repository at [github.com/zyuxuan0115/retainic](https://github.com/zyuxuan0115/retainic), \
            who is the data controller for the personal data described here.
            """),
            .text("""
            **Privacy contact:** [\(contactEmail)](mailto:\(contactEmail)). Please use this \
            address for any question about this policy, for a copy of your data, or to have your \
            account and data deleted.
            """),
        ]),

        PolicySection(title: "2. Data we collect", blocks: [
            .text("""
            We only collect data you provide by using the app. There is no advertising, no \
            analytics or tracking SDK, no advertising identifier, and no third-party marketing. \
            We do not collect your location, contacts, calendar, photos, device identifiers or \
            browsing activity outside the app.
            """),
            .term("Account data — your email address, a username you choose, your password, and the date your account was created.", """
            To create your account, sign you in, keep your data attached to you across devices, \
            and let you reset or change your password. Passwords are handled by Firebase \
            Authentication and are stored only as salted hashes; we never see or store your \
            password ourselves.
            """),
            .term("Invitation code — the code you enter when registering.", """
            To verify that sign-up is permitted. It is checked at registration and is not \
            attached to your profile.
            """),
            .term("Learning content — the vocabulary lists, glossaries, words, terms, translations, definitions, readings, parts of speech and notes you create, plus any file you import.", """
            This is the content of the app: it is stored so it is there the next time you sign \
            in, on any device.
            """),
            .term("Audio recordings — pronunciation clips you record with your microphone.", """
            To play a word's pronunciation back to you during practice. Recording is entirely \
            optional; the microphone is used only while you are actively recording a clip, never \
            in the background, and only after you grant permission.
            """),
            .term("Practice and progress data — review history, per-word scheduling state, daily practice counts and statistics.", """
            To run the spaced-repetition schedule and to draw your statistics charts.
            """),
            .term("Custom review algorithm — the Python snippet you write, if you replace the built-in schedule.", """
            To compute when your cards are next due.
            """),
            .term("Local settings — your preferred interface language and similar preferences.", """
            Stored on your own device to remember how you like the app. Not sent to us.
            """),
            .text("""
            We do not knowingly collect personal data from children under 13 (or the equivalent \
            minimum age in your country). If you believe a child has created an account, contact \
            us and we will delete it.
            """),
        ]),

        PolicySection(title: "3. How the data is used", blocks: [
            .text("""
            Your data is used only to provide the app: to authenticate you, to store and \
            synchronise your lists, glossaries, recordings and progress across your devices, to \
            schedule your reviews, to show your statistics, and to respond to you if you contact \
            support. We do not sell or rent personal data, we do not share it with data brokers, \
            and we do not use it for advertising, profiling or automated decision-making.
            """),
        ]),

        PolicySection(title: "4. Who your data is shared with", blocks: [
            .term("Service providers", """
            Retainic has no servers of its own. All account, content and audio data is stored in \
            **Google Firebase** (Firebase Authentication, Cloud Firestore and Cloud Storage for \
            Firebase), operated by Google LLC and its affiliates, which processes the data on our \
            behalf as our sole sub-processor. Google's handling of that data is governed by the \
            [Firebase Privacy and Security](https://firebase.google.com/support/privacy) \
            documentation and the [Google Privacy Policy](https://policies.google.com/privacy).
            """),
            .term("Sharing you choose", """
            The app lets you share a vocabulary list by giving someone its share code. Anyone who \
            is signed in to Retainic and has that code can view and import a copy of that list's \
            words — so do not put anything private in a list you share. Sharing is entirely under \
            your control; nothing is shared unless you hand out the code, and your account \
            details, recordings for other lists, and progress are never exposed this way.
            """),
            .term("Text-to-speech", """
            When a word has no recording, the app can read it aloud using the speech engine built \
            into your device. In that case the word being spoken is passed to that system \
            component, which is governed by your device vendor's own privacy policy.
            """),
            .term("Legal", """
            We may disclose data if we are legally required to do so, or where it is necessary to \
            investigate abuse or protect the rights and safety of users.
            """),
        ]),

        PolicySection(title: "5. International transfers", blocks: [
            .text("""
            Firebase stores and processes data on Google's infrastructure, which may be located in \
            the United States and other countries. Where required, these transfers rely on \
            Google's standard contractual clauses and safeguards described in the Firebase \
            documentation linked above.
            """),
        ]),

        PolicySection(title: "6. How your data is protected", blocks: [
            .bullet("""
            All traffic between the app and Firebase is encrypted in transit with HTTPS/TLS, and \
            data is encrypted at rest by Google.
            """),
            .bullet("""
            Access is enforced by server-side security rules: your profile, lists, glossaries, \
            words, progress and audio files can only be read or written by your own signed-in \
            account (the one exception being a list you deliberately share, as described above).
            """),
            .bullet("""
            Passwords are never stored in plain text and are never visible to us; changing a \
            password requires re-entering your current one.
            """),
            .bullet("""
            No system is perfectly secure, so we cannot guarantee absolute security, but we will \
            inform affected users of any breach that puts their data at risk, as required by \
            applicable law.
            """),
        ]),

        PolicySection(title: "7. How long we keep data", blocks: [
            .text("""
            Your account data, content, recordings and progress are kept for as long as your \
            account exists, because the app's purpose is to preserve them between sessions. Items \
            you delete inside the app go to the Trash and are removed when you empty it. When an \
            account is deleted, its data is removed from our live systems promptly and purged \
            from Firebase's encrypted backups within 90 days.
            """),
        ]),

        PolicySection(title: "8. Your rights and choices", blocks: [
            .text("You can, at any time:"),
            .bullet("""
            **Access and correct** your content directly in the app, and export any list or \
            glossary to a CSV file.
            """),
            .bullet("""
            **Delete individual items** — words, terms, lists, glossaries and recordings — from \
            within the app.
            """),
            .bullet("**Change your password** in Settings."),
            .bullet("""
            **Withdraw microphone permission** in your device settings; the rest of the app \
            continues to work.
            """),
            .bullet("""
            **Delete your account and all associated data.** Email \
            [\(contactEmail)](mailto:\(contactEmail)) from the address your account uses, with the \
            subject "Delete my account". We will verify the request and erase your profile, \
            lists, glossaries, words, progress and audio recordings within 30 days, and confirm by \
            email when it is done. There is no charge, and you do not need to give a reason.
            """),
            .bullet("""
            **Request a copy of your data**, or ask us to restrict or object to our processing of \
            it, using the same address.
            """),
            .text("""
            Depending on where you live (for example under the GDPR in the EU/UK or the CCPA in \
            California) you may have further statutory rights, including the right to lodge a \
            complaint with your local data protection authority. Where the GDPR applies, our legal \
            basis for processing your account and content data is the performance of our contract \
            with you (providing the app), and consent for optional microphone access, which you \
            may withdraw at any time.
            """),
        ]),

        PolicySection(title: "9. Changes to this policy", blocks: [
            .text("""
            If this policy changes materially, we will update the "Last updated" date above and, \
            where the change affects how your data is used, give notice in the app before it takes \
            effect. The current version is always available on this screen and from the app's \
            About screen.
            """),
        ]),

        PolicySection(title: "10. Contact", blocks: [
            .text("""
            Questions, requests or complaints about this policy or your data: \
            [\(contactEmail)](mailto:\(contactEmail)).
            """),
        ]),
    ]
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
