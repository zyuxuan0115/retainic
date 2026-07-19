package com.retainic.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
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
import com.retainic.app.R
import com.retainic.app.data.AuthService
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

    val tabs = listOf(
        Tab(R.string.my_lists, Icons.AutoMirrored.Filled.List),
        Tab(R.string.statistics, Icons.Filled.BarChart),
        Tab(R.string.settings, Icons.Filled.Settings),
        Tab(R.string.about, Icons.Filled.Info),
    )

    val atListsRoot = listsStack.size == 1
    val showBottomBar = selectedTab != 0 || atListsRoot

    // On the Lists tab, Back walks the internal stack before leaving the app.
    BackHandler(enabled = selectedTab == 0 && !atListsRoot) { nav.pop() }

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
                            label = { Text(stringResource(tab.label)) },
                        )
                    }
                }
            }
        },
    ) { inner ->
        val contentModifier = Modifier.padding(inner)
        when (selectedTab) {
            0 -> ListsTabContent(auth, listsStack, nav, contentModifier)
            1 -> StatsScreen(auth, contentModifier)
            2 -> SettingsScreen(auth, contentModifier)
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
        ListsRoute.Trash -> TrashScreen(auth, nav, modifier)
        is ListsRoute.Detail -> ListDetailScreen(auth, route.list, nav, modifier)
        is ListsRoute.Editor -> AddWordScreen(
            auth, route.listId, route.learning, route.original, route.tts, route.word, nav, modifier
        )
        is ListsRoute.Practice -> FlashcardScreen(
            auth, route.cards, route.learning, route.tts, nav, modifier
        )
    }
}
