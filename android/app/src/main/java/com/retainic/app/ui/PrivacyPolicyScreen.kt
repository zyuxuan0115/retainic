package com.retainic.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.retainic.app.R

/**
 * The privacy policy, shown in-app from About. Mirrors `web/privacy.html` and
 * the iOS `PrivacyPolicyView`; the three are kept word-for-word in step. The
 * policy itself stays in English, like the hosted page — only the screen's
 * title is localized, so the text lives here rather than in `strings.xml`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyPolicyScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.privacy_policy)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.done))
                    }
                },
            )
        },
    ) { inner ->
        Column(
            Modifier.padding(inner).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Privacy Policy", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(
                "Applies to the Retainic apps for Android, iOS and the web.\n" +
                    "Last updated: 11 August 2026 · Effective: 11 August 2026",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            POLICY.forEach { section ->
                if (section.title.isNotEmpty()) {
                    HorizontalDivider(Modifier.padding(top = 8.dp))
                    Text(
                        section.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                section.blocks.forEach { block -> BlockView(block) { context.startActivity(it) } }
            }

            HorizontalDivider(Modifier.padding(top = 8.dp))
            Text(
                stringResource(R.string.copyright),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun BlockView(block: Block, openIntent: (Intent) -> Unit) {
    when (block) {
        is Block.Text -> Text(emphasized(block.text), style = MaterialTheme.typography.bodyMedium)

        is Block.Bullet -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("•", style = MaterialTheme.typography.bodyMedium)
            Text(emphasized(block.text), style = MaterialTheme.typography.bodyMedium)
        }

        is Block.Term -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                block.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(emphasized(block.text), style = MaterialTheme.typography.bodyMedium)
        }

        is Block.Link -> Row(
            Modifier.fillMaxWidth()
                .clickable { openIntent(Intent(Intent.ACTION_VIEW, Uri.parse(block.url))) }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val mail = block.url.startsWith("mailto:")
            Icon(
                if (mail) Icons.Filled.MailOutline else Icons.AutoMirrored.Filled.OpenInNew,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                block.label,
                Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/** Renders the `**bold**` runs the policy copy uses for its lead-ins. */
private fun emphasized(text: String): AnnotatedString = buildAnnotatedString {
    var rest = text
    while (true) {
        val open = rest.indexOf("**")
        val close = if (open < 0) -1 else rest.indexOf("**", open + 2)
        if (open < 0 || close < 0) {
            append(rest)
            return@buildAnnotatedString
        }
        append(rest.substring(0, open))
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
            append(rest.substring(open + 2, close))
        }
        rest = rest.substring(close + 2)
    }
}

private sealed interface Block {
    data class Text(val text: String) : Block
    /** A bulleted line. */
    data class Bullet(val text: String) : Block
    /** A bold lead-in on its own line, then the copy beneath it. */
    data class Term(val label: String, val text: String) : Block
    /** A tappable row opening [url] — the policy's contact address and citations. */
    data class Link(val label: String, val url: String) : Block
}

private data class PolicySection(val title: String, val blocks: List<Block>)

private const val CONTACT_EMAIL = "retainic.app@gmail.com"

private val POLICY: List<PolicySection> = listOf(
    PolicySection(
        "",
        listOf(
            Block.Text(
                "Retainic (\"the app\", \"we\", \"us\") is a vocabulary-learning app that lets you " +
                    "build word lists and glossaries, record pronunciations and practice them with " +
                    "spaced-repetition flashcards. This policy explains what personal data the app " +
                    "collects, why, who it is shared with, how long it is kept and how you can have " +
                    "it deleted. It covers every version of Retainic — the Android app, the iOS app " +
                    "and the web app — which all share one account and one backend."
            ),
        ),
    ),

    PolicySection(
        "1. Who we are",
        listOf(
            Block.Text(
                "Retainic is an independent project developed and operated by the developer of the " +
                    "open-source repository at github.com/zyuxuan0115/retainic, who is the data " +
                    "controller for the personal data described here."
            ),
            Block.Text(
                "**Privacy contact:** $CONTACT_EMAIL. Please use this address for any question " +
                    "about this policy, for a copy of your data, or to have your account and data " +
                    "deleted."
            ),
            Block.Link(CONTACT_EMAIL, "mailto:$CONTACT_EMAIL"),
        ),
    ),

    PolicySection(
        "2. Data we collect",
        listOf(
            Block.Text(
                "We only collect data you provide by using the app. There is no advertising, no " +
                    "analytics or tracking SDK, no advertising identifier, and no third-party " +
                    "marketing. We do not collect your location, contacts, calendar, photos, device " +
                    "identifiers or browsing activity outside the app."
            ),
            Block.Term(
                "Account data — your email address, a username you choose, your password, and the " +
                    "date your account was created.",
                "To create your account, sign you in, keep your data attached to you across " +
                    "devices, and let you reset or change your password. Passwords are handled by " +
                    "Firebase Authentication and are stored only as salted hashes; we never see or " +
                    "store your password ourselves."
            ),
            Block.Term(
                "Invitation code — the code you enter when registering.",
                "To verify that sign-up is permitted. It is checked at registration and is not " +
                    "attached to your profile."
            ),
            Block.Term(
                "Learning content — the vocabulary lists, glossaries, words, terms, translations, " +
                    "definitions, readings, parts of speech and notes you create, plus any file you " +
                    "import.",
                "This is the content of the app: it is stored so it is there the next time you " +
                    "sign in, on any device."
            ),
            Block.Term(
                "Audio recordings — pronunciation clips you record with your microphone.",
                "To play a word's pronunciation back to you during practice. Recording is entirely " +
                    "optional; the microphone is used only while you are actively recording a clip, " +
                    "never in the background, and only after you grant permission."
            ),
            Block.Term(
                "Practice and progress data — review history, per-word scheduling state, daily " +
                    "practice counts and statistics.",
                "To run the spaced-repetition schedule and to draw your statistics charts."
            ),
            Block.Term(
                "Custom review algorithm — the Python snippet you write, if you replace the " +
                    "built-in schedule.",
                "To compute when your cards are next due."
            ),
            Block.Term(
                "Local settings — your preferred interface language and similar preferences.",
                "Stored on your own device to remember how you like the app. Not sent to us."
            ),
            Block.Text(
                "We do not knowingly collect personal data from children under 13 (or the " +
                    "equivalent minimum age in your country). If you believe a child has created an " +
                    "account, contact us and we will delete it."
            ),
        ),
    ),

    PolicySection(
        "3. How the data is used",
        listOf(
            Block.Text(
                "Your data is used only to provide the app: to authenticate you, to store and " +
                    "synchronise your lists, glossaries, recordings and progress across your " +
                    "devices, to schedule your reviews, to show your statistics, and to respond to " +
                    "you if you contact support. We do not sell or rent personal data, we do not " +
                    "share it with data brokers, and we do not use it for advertising, profiling or " +
                    "automated decision-making."
            ),
        ),
    ),

    PolicySection(
        "4. Who your data is shared with",
        listOf(
            Block.Term(
                "Service providers",
                "Retainic has no servers of its own. All account, content and audio data is stored " +
                    "in **Google Firebase** (Firebase Authentication, Cloud Firestore and Cloud " +
                    "Storage for Firebase), operated by Google LLC and its affiliates, which " +
                    "processes the data on our behalf as our sole sub-processor. Google's handling " +
                    "of that data is governed by the Firebase Privacy and Security documentation " +
                    "and the Google Privacy Policy."
            ),
            Block.Link("Firebase Privacy and Security", "https://firebase.google.com/support/privacy"),
            Block.Link("Google Privacy Policy", "https://policies.google.com/privacy"),
            Block.Term(
                "Sharing you choose",
                "The app lets you share a vocabulary list by giving someone its share code. Anyone " +
                    "who is signed in to Retainic and has that code can view and import a copy of " +
                    "that list's words — so do not put anything private in a list you share. " +
                    "Sharing is entirely under your control; nothing is shared unless you hand out " +
                    "the code, and your account details, recordings for other lists, and progress " +
                    "are never exposed this way."
            ),
            Block.Term(
                "Text-to-speech",
                "When a word has no recording, the app can read it aloud using the speech engine " +
                    "built into your device. In that case the word being spoken is passed to that " +
                    "system component, which is governed by your device vendor's own privacy policy."
            ),
            Block.Term(
                "Legal",
                "We may disclose data if we are legally required to do so, or where it is " +
                    "necessary to investigate abuse or protect the rights and safety of users."
            ),
        ),
    ),

    PolicySection(
        "5. International transfers",
        listOf(
            Block.Text(
                "Firebase stores and processes data on Google's infrastructure, which may be " +
                    "located in the United States and other countries. Where required, these " +
                    "transfers rely on Google's standard contractual clauses and safeguards " +
                    "described in the Firebase documentation linked above."
            ),
        ),
    ),

    PolicySection(
        "6. How your data is protected",
        listOf(
            Block.Bullet(
                "All traffic between the app and Firebase is encrypted in transit with HTTPS/TLS, " +
                    "and data is encrypted at rest by Google."
            ),
            Block.Bullet(
                "Access is enforced by server-side security rules: your profile, lists, " +
                    "glossaries, words, progress and audio files can only be read or written by " +
                    "your own signed-in account (the one exception being a list you deliberately " +
                    "share, as described above)."
            ),
            Block.Bullet(
                "Passwords are never stored in plain text and are never visible to us; changing a " +
                    "password requires re-entering your current one."
            ),
            Block.Bullet(
                "No system is perfectly secure, so we cannot guarantee absolute security, but we " +
                    "will inform affected users of any breach that puts their data at risk, as " +
                    "required by applicable law."
            ),
        ),
    ),

    PolicySection(
        "7. How long we keep data",
        listOf(
            Block.Text(
                "Your account data, content, recordings and progress are kept for as long as your " +
                    "account exists, because the app's purpose is to preserve them between " +
                    "sessions. Items you delete inside the app go to the Trash and are removed when " +
                    "you empty it. When an account is deleted, its data is removed from our live " +
                    "systems promptly and purged from Firebase's encrypted backups within 90 days."
            ),
        ),
    ),

    PolicySection(
        "8. Your rights and choices",
        listOf(
            Block.Text("You can, at any time:"),
            Block.Bullet(
                "**Access and correct** your content directly in the app, and export any list or " +
                    "glossary to a CSV file."
            ),
            Block.Bullet(
                "**Delete individual items** — words, terms, lists, glossaries and recordings — " +
                    "from within the app."
            ),
            Block.Bullet("**Change your password** in Settings."),
            Block.Bullet(
                "**Withdraw microphone permission** in your device settings; the rest of the app " +
                    "continues to work."
            ),
            Block.Bullet(
                "**Delete your account and all associated data.** Email $CONTACT_EMAIL from the " +
                    "address your account uses, with the subject \"Delete my account\". We will " +
                    "verify the request and erase your profile, lists, glossaries, words, progress " +
                    "and audio recordings within 30 days, and confirm by email when it is done. " +
                    "There is no charge, and you do not need to give a reason."
            ),
            Block.Bullet(
                "**Request a copy of your data**, or ask us to restrict or object to our " +
                    "processing of it, using the same address."
            ),
            Block.Link(CONTACT_EMAIL, "mailto:$CONTACT_EMAIL"),
            Block.Text(
                "Depending on where you live (for example under the GDPR in the EU/UK or the CCPA " +
                    "in California) you may have further statutory rights, including the right to " +
                    "lodge a complaint with your local data protection authority. Where the GDPR " +
                    "applies, our legal basis for processing your account and content data is the " +
                    "performance of our contract with you (providing the app), and consent for " +
                    "optional microphone access, which you may withdraw at any time."
            ),
        ),
    ),

    PolicySection(
        "9. Changes to this policy",
        listOf(
            Block.Text(
                "If this policy changes materially, we will update the \"Last updated\" date above " +
                    "and, where the change affects how your data is used, give notice in the app " +
                    "before it takes effect. The current version is always available on this screen " +
                    "and from the app's About screen."
            ),
        ),
    ),

    PolicySection(
        "10. Contact",
        listOf(
            Block.Text(
                "Questions, requests or complaints about this policy or your data: $CONTACT_EMAIL."
            ),
            Block.Link(CONTACT_EMAIL, "mailto:$CONTACT_EMAIL"),
        ),
    ),
)
