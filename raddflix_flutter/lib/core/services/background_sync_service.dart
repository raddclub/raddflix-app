// BackgroundSyncService — intentionally empty.
//
// Catalog sync is version-gated via SyncService.sync() which calls
// /api/catalog/version first (~200 bytes). If Oracle MAX(updated_at) hasn't
// changed, sync returns immediately — zero download, zero work.
//
// Triggers (in CatalogNotifier):
//   1. Cold / warm start
//   2. App foreground (WidgetsBindingObserver.didChangeAppLifecycleState)
//   3. Internet restored (Connectivity().onConnectivityChanged)
//
// No periodic timers, no WorkManager background tasks — sync only does real
// work when the admin has actually updated the database.
