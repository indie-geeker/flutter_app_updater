# Flutter App Updater Example

This example demonstrates the v3 UI-free update flow:

- build an `AppUpdater` with a static preview manifest
- call `checkAndPrepare()`
- show the recommended action
- call `performRecommended()` from app UI
- list all actions in the candidate release

Run it from the package root:

```bash
cd example
flutter run
```

The preview manifest is in `lib/main.dart`. Replace the static manifest with `AppUpdater.manifest(...)` when testing against your own remote manifest.
