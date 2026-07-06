# KidBox — Mobile App UI Kit

Click-through recreation of the KidBox iOS app (SwiftUI), grounded directly in
the source: `Features/Auth/LoginView.swift`, `Features/Home/HomeView.swift` +
`HomeCardGrid`, `Features/Settings/SettingsView/SettingsView.swift`,
`Features/Documents/{DocumentsHomeView,DocumentFolderView}.swift`. The Android
app (Jetpack Compose, `ui/theme/Theme.kt`) uses the same colors/typography and
an equivalent Home grid, so this kit doubles as its reference.

**Flow:** Login (Google/Apple/Facebook/email pills) → Home (hero + full
18-tile category grid + Ask-AI FAB) → tap a card to open Documents, or the
gear icon for Settings.

Screens compose the design system's `HomeCard`, `HeroCard`, `InviteCard`,
`SettingsCard`, `CategoryCard` and `AskAIButton` — no UI is reimplemented here.

**Icon substitution:** the real apps use SF Symbols (iOS) and Material icons
(Android), neither shippable as web assets. This kit substitutes
[Lucide](https://lucide.dev) via CDN — closest match in stroke weight/rounded
style — via the `Ic` helper in `Icons.jsx`.

Files: `index.html` (shell + screen router), `ios-frame.jsx` (device bezel),
`Icons.jsx`, `LoginScreen.jsx`, `HomeScreen.jsx`, `DocumentsScreen.jsx`,
`SettingsScreen.jsx`.
