package com.retainic.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import com.retainic.app.data.VocabRepository
import com.retainic.app.data.VocabularyList
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrashScreen(auth: AuthService, nav: ListsNav, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var lists by remember { mutableStateOf<List<VocabularyList>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingPurge by remember { mutableStateOf<VocabularyList?>(null) }
    var isPurging by remember { mutableStateOf(false) }
    var showEmptyConfirm by remember { mutableStateOf(false) }

    suspend fun load() {
        val uid = auth.uid ?: return
        isLoading = true
        try {
            lists = VocabRepository.fetchTrashedLists(uid)
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
                    IconButton(onClick = { nav.pop() }, enabled = !isPurging) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.done))
                    }
                },
                actions = {
                    if (lists.isNotEmpty()) {
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
                isLoading && lists.isEmpty() -> LoadingView(stringResource(R.string.loading))
                lists.isEmpty() -> EmptyState(
                    icon = Icons.Filled.Delete,
                    title = stringResource(R.string.trash_is_empty),
                    description = stringResource(R.string.trash_empty_desc),
                )
                else -> LazyColumn(Modifier.fillMaxSize()) {
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
                        isPurging = false
                    }
                }) { Text(stringResource(R.string.empty_trash)) }
            },
            dismissButton = { TextButton(onClick = { showEmptyConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    ErrorDialog(error) { error = null }
}
