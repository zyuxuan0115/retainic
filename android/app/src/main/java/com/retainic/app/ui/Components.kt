package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.retainic.app.R

/** Centered empty-state placeholder, mirroring iOS ContentUnavailableView. */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    description: String? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            if (description != null) {
                Text(description, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
            if (actionLabel != null && onAction != null) {
                Button(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}

/** Centered progress spinner with a label. */
@Composable
fun LoadingView(label: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CircularProgressIndicator()
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Compact part-of-speech badge shared by list rows and flashcards. */
@Composable
fun PosChip(label: String) {
    Text(
        label,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/** Shared error alert used across repository-backed screens. */
@Composable
fun ErrorDialog(message: String?, onDismiss: () -> Unit) {
    if (message != null) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.something_wrong)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.ok)) } },
        )
    }
}
