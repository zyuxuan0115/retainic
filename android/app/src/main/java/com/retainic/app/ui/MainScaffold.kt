package com.retainic.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.retainic.app.R
import com.retainic.app.data.AuthService
import com.retainic.app.data.Glossary
import com.retainic.app.data.GlossaryEntry
import com.retainic.app.data.GlossaryPracticeCard
import com.retainic.app.data.PracticeCard
import com.retainic.app.data.VocabWord
import com.retainic.app.data.VocabularyList

/** A destination within the Lists tab's own navigation stack. */
sealed interface ListsRoute {
    data object Home : ListsRoute
    data object Trash : ListsRoute
    data class Detail(val list: VocabularyList) : ListsRoute
    data class Editor(
        val listId: String,
        val learning: String,
        val original: String,
        val tts: Boolean,
        val word: VocabWord?,
    ) : ListsRoute
    data class Practice(
        val cards: List<PracticeCard>,
        val learning: String,
        val tts: Boolean,
    ) : ListsRoute
}

/** Push/pop helpers handed to each Lists-tab screen. */
class ListsNav(val push: (ListsRoute) -> Unit, val pop: () -> Unit)

/** A destination within the Glossaries tab's own navigation stack. */
sealed interface GlossariesRoute {
    data object Home : GlossariesRoute
    data object Trash : GlossariesRoute
    data class Detail(val glossary: Glossary) : GlossariesRoute
    data class Editor(
        val glossaryId: String,
        val language: String,
        val entry: GlossaryEntry?,
    ) : GlossariesRoute
    data class Practice(val cards: List<GlossaryPracticeCard>) : GlossariesRoute
}

/** Push/pop helpers handed to each Glossaries-tab screen. */
class GlossariesNav(val push: (GlossariesRoute) -> Unit, val pop: () -> Unit)

private data class Tab(val label: Int, val icon: ImageVector)

@Composable
fun MainScaffold(auth: AuthService) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val listsStack = remember { mutableStateListOf<ListsRoute>(ListsRoute.Home) }
    val nav = remember {
        ListsNav(
            push = { listsStack.add(it) },
            pop = { if (listsStack.size > 1) listsStack.removeAt(listsStack.size - 1) },
        )
    }
    // Glossaries are a separate tab with their own stack, independent of lists.
    val glossariesStack = remember { mutableStateListOf<GlossariesRoute>(GlossariesRoute.Home) }
    val glossariesNav = remember {
        GlossariesNav(
            push = { glossariesStack.add(it) },
            pop = { if (glossariesStack.size > 1) glossariesStack.removeAt(glossariesStack.size - 1) },
        )
    }

    val tabs = listOf(
        Tab(R.string.lists, Icons.AutoMirrored.Filled.List),
        Tab(R.string.glossaries, Icons.AutoMirrored.Filled.MenuBook),
        Tab(R.string.statistics, Icons.Filled.BarChart),
        Tab(R.string.settings, Icons.Filled.Settings),
        Tab(R.string.about, Icons.Filled.Info),
    )

    val atListsRoot = listsStack.size == 1
    val atGlossariesRoot = glossariesStack.size == 1
    val showBottomBar = when (selectedTab) {
        0 -> atListsRoot
        1 -> atGlossariesRoot
        else -> true
    }

    // On a stack tab, Back walks the internal stack before leaving the app.
    BackHandler(enabled = selectedTab == 0 && !atListsRoot) { nav.pop() }
    BackHandler(enabled = selectedTab == 1 && !atGlossariesRoot) { glossariesNav.pop() }

    Scaffold(
        // Each child screen has its own Scaffold/TopAppBar that consumes the
        // status-bar inset, so the outer scaffold must not add it again.
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    tabs.forEachIndexed { index, tab ->
                        NavigationBarItem(
                            selected = selectedTab == index,
                            onClick = { selectedTab = index },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            // One line, always: a label wide enough to wrap —
                            // "Glossaries" on a narrow screen, or a longer
                            // translation like "Estadísticas" — made its tab
                            // taller than the rest and knocked the row out of
                            // line. The smaller label style buys enough width
                            // for most of them to fit whole.
                            label = {
                                Text(
                                    stringResource(tab.label),
                                    style = MaterialTheme.typography.labelSmall,
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.Center,
                                )
                            },
                        )
                    }
                }
            }
        },
    ) { inner ->
        val contentModifier = Modifier.padding(inner)
        when (selectedTab) {
            0 -> ListsTabContent(auth, listsStack, nav, contentModifier)
            1 -> GlossariesTabContent(auth, glossariesStack, glossariesNav, contentModifier)
            2 -> StatsScreen(auth, contentModifier)
            3 -> SettingsScreen(auth, contentModifier)
            else -> AboutScreen(contentModifier)
        }
    }
}

@Composable
private fun ListsTabContent(
    auth: AuthService,
    stack: List<ListsRoute>,
    nav: ListsNav,
    modifier: Modifier,
) {
    when (val route = stack.last()) {
        ListsRoute.Home -> VocabListsScreen(auth, nav, modifier)
        ListsRoute.Trash -> TrashScreen(auth, nav.pop, modifier)
        is ListsRoute.Detail -> ListDetailScreen(auth, route.list, nav, modifier)
        is ListsRoute.Editor -> AddWordScreen(
            auth, route.listId, route.learning, route.original, route.tts, route.word, nav, modifier
        )
        is ListsRoute.Practice -> FlashcardScreen(
            auth, route.cards, route.learning, route.tts, nav, modifier
        )
    }
}

@Composable
private fun GlossariesTabContent(
    auth: AuthService,
    stack: List<GlossariesRoute>,
    nav: GlossariesNav,
    modifier: Modifier,
) {
    when (val route = stack.last()) {
        GlossariesRoute.Home -> GlossariesScreen(auth, nav, modifier)
        // The Trash holds both kinds, so both tabs open the same screen.
        GlossariesRoute.Trash -> TrashScreen(auth, nav.pop, modifier)
        is GlossariesRoute.Detail -> GlossaryDetailScreen(auth, route.glossary, nav, modifier)
        is GlossariesRoute.Editor -> AddEntryScreen(
            auth, route.glossaryId, route.language, route.entry, nav, modifier
        )
        is GlossariesRoute.Practice -> GlossaryFlashcardScreen(auth, route.cards, nav, modifier)
    }
}
