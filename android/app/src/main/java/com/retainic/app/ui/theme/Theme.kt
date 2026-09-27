package com.retainic.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Neutral surfaces let the vocabulary lead; blue consistently identifies actions.
private val LightColors = lightColorScheme(
    primary = Color(0xFF245EDB), onPrimary = Color.White,
    primaryContainer = Color(0xFFE8EFFF), onPrimaryContainer = Color(0xFF183E89),
    secondary = Color(0xFF526681), onSecondary = Color.White,
    secondaryContainer = Color(0xFFE8EFFF), onSecondaryContainer = Color(0xFF183E89),
    background = Color(0xFFF4F6FA), onBackground = Color(0xFF1C2027),
    surface = Color.White, onSurface = Color(0xFF1C2027),
    surfaceVariant = Color(0xFFEDF0F6), onSurfaceVariant = Color(0xFF626B7A),
    surfaceContainer = Color(0xFFF4F6FA), surfaceContainerLow = Color(0xFFF8F9FC),
    surfaceContainerHigh = Color(0xFFEDF0F6), surfaceContainerHighest = Color(0xFFE6EAF1),
    outline = Color(0xFF747E8E), outlineVariant = Color(0xFFE2E7EF),
    surfaceTint = Color(0xFF245EDB),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF91B7FF), onPrimary = Color(0xFF092B64),
    primaryContainer = Color(0xFF20375C), onPrimaryContainer = Color(0xFFD9E6FF),
    secondary = Color(0xFFAFBED4), onSecondary = Color(0xFF203047),
    secondaryContainer = Color(0xFF20375C), onSecondaryContainer = Color(0xFFD9E6FF),
    background = Color(0xFF101216), onBackground = Color(0xFFF3F5FA),
    surface = Color(0xFF1C2027), onSurface = Color(0xFFF3F5FA),
    surfaceVariant = Color(0xFF282E38), onSurfaceVariant = Color(0xFFA5AEBE),
    surfaceContainer = Color(0xFF181C23), surfaceContainerLow = Color(0xFF15191F),
    surfaceContainerHigh = Color(0xFF252B35), surfaceContainerHighest = Color(0xFF303744),
    outline = Color(0xFF8792A5), outlineVariant = Color(0xFF343C49),
    surfaceTint = Color(0xFF91B7FF),
)

private val AppTypography = Typography(
    headlineLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 32.sp, lineHeight = 38.sp, letterSpacing = (-0.8).sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 34.sp, letterSpacing = (-0.5).sp),
    titleLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 24.sp, lineHeight = 30.sp, letterSpacing = (-0.4).sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 24.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 21.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 20.sp),
)

@Composable
fun RetainicTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        shapes = Shapes(
            extraSmall = RoundedCornerShape(8.dp), small = RoundedCornerShape(12.dp),
            medium = RoundedCornerShape(18.dp), large = RoundedCornerShape(24.dp),
            extraLarge = RoundedCornerShape(28.dp),
        ),
        content = content,
    )
}
