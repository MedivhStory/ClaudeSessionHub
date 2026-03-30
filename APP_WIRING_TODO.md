# App Wiring TODO

The following changes need to be added to `Sources/ClaudeSessionHub/App/ClaudeSessionHubApp.swift`:

## 1. Add Settings scene

Add a `Settings` scene to the `@main` App struct so that Cmd+, opens the settings view:

```swift
Settings {
    SettingsView()
        .environment(store)
}
```

## 2. Add scan timer modifier to ContentView

In the App body where `ContentView` is used, add the `.withScanTimers()` modifier,
or add it directly inside `ContentView`'s body on the `NavigationSplitView`.

Example in ContentView:

```swift
NavigationSplitView { ... }
    .withScanTimers()
```
