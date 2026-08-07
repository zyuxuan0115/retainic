package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.Glossary
import com.retainic.app.data.GlossaryRepository
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabularyList
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Lists and glossaries that have been moved to the trash. Reached from either
 * tab, since both kinds are kept here. [onBack] pops the calling tab's stack.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrashScreen(auth: AuthService, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var lists by remember { mutableStateOf<List<VocabularyList>>(emptyList()) }
    var glossaries by remember { mutableStateOf<List<Glossary>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingPurge by remember { mutableStateOf<VocabularyList?>(null) }
    var pendingPurgeGlossary by remember { mutableStateOf<Glossary?>(null) }
    var isPurging by remember { mutableStateOf(false) }
    var showEmptyConfirm by remember { mutableStateOf(false) }

    val isEmpty = lists.isEmpty() && glossaries.isEmpty()

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            lists = VocabRepository.fetchTrashedLists(uid)
            glossaries = GlossaryRepository.fetchTrashedGlossaries(uid)
        } catch (e: Exception) {
            error = e.localizedMessage
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(auth.uid) { load() }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.trash)) },
                navigationIcon = {
                    IconButton(onClick = onBack, enabled = !isPurging) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.done))
                    }
                },
                actions = {
                    if (!isEmpty) {
                        IconButton(onClick = { showEmptyConfirm = true }, enabled = !isPurging) {
                            Icon(Icons.Filled.DeleteSweep, contentDescription = stringResource(R.string.empty_trash))
                        }
                    }
                },
            )
        },
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when {
                isLoading && isEmpty -> LoadingView(stringResource(R.string.loading))
                isEmpty -> EmptyState(
                    icon = Icons.Filled.Delete,
                    title = stringResource(R.string.trash_is_empty),
                    description = stringResource(R.string.trash_empty_desc),
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    // With both kinds in the trash the headers say which is
                    // which; with one they'd be noise.
                    if (lists.isNotEmpty() && glossaries.isNotEmpty()) {
                        item(key = "lists-header") { TrashSectionHeader(stringResource(R.string.lists)) }
                    }
                    items(lists, key = { it.id ?: it.name }) { list ->
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { value ->
                                when (value) {
                                    SwipeToDismissBoxValue.StartToEnd -> {
                                        val uid = auth.uid
                                        val id = list.id
                                        if (uid != null && id != null) scope.launch {
                                            try {
                                                VocabRepository.restoreList(uid, id)
                                                lists = lists.filterNot { it.id == id }
                                            } catch (e: Exception) { error = e.localizedMessage }
                                        }
                                    }
                                    SwipeToDismissBoxValue.EndToStart -> pendingPurge = list
                                    else -> {}
                                }
                                false
                            },
                        )
                        SwipeToDismissBox(
                            state = dismissState,
                            backgroundContent = {
                                val toEnd = dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart
                                Box(
                                    Modifier.fillMaxSize()
                                        .background(
                                            if (toEnd) MaterialTheme.colorScheme.errorContainer
                                            else MaterialTheme.colorScheme.primaryContainer
                                        )
                                        .padding(horizontal = 20.dp),
                                    contentAlignment = if (toEnd) Alignment.CenterEnd else Alignment.CenterStart,
                                ) {
                                    Icon(
                                        if (toEnd) Icons.Filled.Delete else Icons.Filled.Restore,
                                        contentDescription = null,
                                    )
                                }
                            },
                        ) {
                            Surface { ListRow(list) }
                        }
                        HorizontalDivider()
                    }
                    if (lists.isNotEmpty() && glossaries.isNotEmpty()) {
                        item(key = "glossaries-header") { TrashSectionHeader(stringResource(R.string.glossaries)) }
                    }
                    items(glossaries, key = { it.id ?: it.name }) { glossary ->
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { value ->
                                when (value) {
                                    SwipeToDismissBoxValue.StartToEnd -> {
                                        val uid = auth.uid
                                        val id = glossary.id
                                        if (uid != null && id != null) scope.launch {
                                            try {
                                                GlossaryRepository.restoreGlossary(uid, id)
                                                glossaries = glossaries.filterNot { it.id == id }
                                            } catch (e: Exception) { error = e.localizedMessage }
                                        }
                                    }
                                    SwipeToDismissBoxValue.EndToStart -> pendingPurgeGlossary = glossary
                                    else -> {}
                                }
                                false
                            },
                        )
                        SwipeToDismissBox(
                            state = dismissState,
                            backgroundContent = {
                                val toEnd = dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart
                                Box(
                                    Modifier.fillMaxSize()
                                        .background(
                                            if (toEnd) MaterialTheme.colorScheme.errorContainer
                                            else MaterialTheme.colorScheme.primaryContainer
                                        )
                                        .padding(horizontal = 20.dp),
                                    contentAlignment = if (toEnd) Alignment.CenterEnd else Alignment.CenterStart,
                                ) {
                                    Icon(
                                        if (toEnd) Icons.Filled.Delete else Icons.Filled.Restore,
                                        contentDescription = null,
                                    )
                                }
                            },
                        ) {
                            Surface { GlossaryRow(glossary) }
                        }
                        HorizontalDivider()
                    }
                }
            }

            if (isPurging) {
                Box(
                    Modifier.fillMaxSize().background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.4f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Surface(shape = MaterialTheme.shapes.large, tonalElevation = 4.dp) {
                        LoadingView(stringResource(R.string.deleting))
                    }
                }
            }
        }
    }

    pendingPurge?.let { list ->
        AlertDialog(
            onDismissRequest = { pendingPurge = null },
            title = { Text(stringResource(R.string.delete_forever)) },
            text = { Text(stringResource(R.string.delete_forever_msg, list.name)) },
            confirmButton = {
                TextButton(onClick = {
                    val uid = auth.uid
                    val id = list.id
                    pendingPurge = null
                    if (uid != null && id != null) {
                        isPurging = true
                        scope.launch {
                            delay(2000)
                            try {
                                VocabRepository.purgeList(uid, id)
                                lists = lists.filterNot { it.id == id }
                            } catch (e: Exception) { error = e.localizedMessage }
                            isPurging = false
                        }
                    }
                }) { Text(stringResource(R.string.delete_forever)) }
            },
            dismissButton = { TextButton(onClick = { pendingPurge = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    pendingPurgeGlossary?.let { glossary ->
        AlertDialog(
            onDismissRequest = { pendingPurgeGlossary = null },
            title = { Text(stringResource(R.string.delete_forever)) },
            text = { Text(stringResource(R.string.delete_forever_msg, glossary.name)) },
            confirmButton = {
                TextButton(onClick = {
                    val uid = auth.uid
                    val id = glossary.id
                    pendingPurgeGlossary = null
                    if (uid != null && id != null) {
                        isPurging = true
                        scope.launch {
                            delay(2000)
                            try {
                                GlossaryRepository.purgeGlossary(uid, id)
                                glossaries = glossaries.filterNot { it.id == id }
                            } catch (e: Exception) { error = e.localizedMessage }
                            isPurging = false
                        }
                    }
                }) { Text(stringResource(R.string.delete_forever)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingPurgeGlossary = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    if (showEmptyConfirm) {
        AlertDialog(
            onDismissRequest = { showEmptyConfirm = false },
            title = { Text(stringResource(R.string.empty_trash)) },
            text = { Text(stringResource(R.string.empty_trash_confirm)) },
            confirmButton = {
                TextButton(onClick = {
                    showEmptyConfirm = false
                    val uid = auth.uid ?: return@TextButton
                    isPurging = true
                    scope.launch {
                        for (l in lists) {
                            val id = l.id ?: continue
                            try { VocabRepository.purgeList(uid, id) }
                            catch (e: Exception) { error = e.localizedMessage }
                        }
                        lists = emptyList()
                        for (g in glossaries) {
                            val id = g.id ?: continue
                            try { GlossaryRepository.purgeGlossary(uid, id) }
                            catch (e: Exception) { error = e.localizedMessage }
                        }
                        glossaries = emptyList()
                        isPurging = false
                    }
                }) { Text(stringResource(R.string.empty_trash)) }
            },
            dismissButton = { TextButton(onClick = { showEmptyConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    ErrorDialog(error) { error = null }
}

/** Heading above a group of trashed items. */
@Composable
private fun TrashSectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}
