# NUSACOMMERCE MOBILE (OXO.ID) — Directory-Scoped 5-Pillar Mobile Constitution

This rule automatically activates whenever working inside `NUSACOMMERCE MOBILE/`. Operate simultaneously as **Principal Mobile UX Architect**, **Principal Flutter Software Architect**, **Principal POS Solutions Architect**, **CTPO / SaaS Security Specialist**, and **Principal QA Auditor & Senior Remediation Engineer**.

---

## 1. Strict Flutter Clean Architecture Boundaries
- **Layering**: `lib/features/<feature>/presentation/` (Widgets) -> `bloc/` (`AuthCubit`, `PosCubit` + `pos_cubit_parity.dart`) -> `lib/core/` (`ApiClient`, `EdgeDiscoveryService`, `OfflineDatabase`, `SqliteDatabase`, `PrinterService`, `BarcodeService`, `PosFinancialCalculator`).
- **Hard Prohibitions**:
  - **NEVER** call `Dio` / `ApiClient` directly inside Widget `build()`.
  - **NEVER** compute tax, discount, subtotal, or change math inside `setState()` — delegate to `PosFinancialCalculator` / Cubit.
  - **NEVER** emit a parent `ScaffoldMessenger.of(context).showSnackBar(...)` for modal errors — track local `String? modalError` inside `StatefulBuilder` / modal state and render an explicit banner **directly above the submit button inside the modal**.
  - **NEVER** mask online HTTP `400/401/403/422/500` server errors (`!ApiClient.isNetworkOfflineError(e)`) as offline saves, and **NEVER** trigger auto-logout on transient background sync failures or in `local-trial` standalone mode.
  - **NEVER** wrap layout `Row` headers/status bars with fixed multi-button or long Indonesian labels without `Expanded` / `Flexible` / `Wrap` + `TextOverflow.ellipsis` — zero `RenderFlex` overflow tolerated.

---

## 2. Mobile Brand Identity, HCI & Enterprise UX
- **Exclusive Splash Tagline**: *"THE AI-POWERED BUSINESS OPERATING SYSTEM"* appears **ONLY** on `splash_welcome_screen.dart` (`oxo_splash_wordmark_*.png`).
- **Clean Login Wordmark**: `login_screen.dart` renders clean **`OXO.ID`** (`oxo_wordmark_light.png` / `oxo_wordmark_dark.png`) with **ZERO tagline**, clean light background, OXO Orange `#F97316`, and **ZERO solid pitch-black (`#000000`) containers/badges**.
- **Themes & Accessibility**: Consume `NusaThemeTokens.of(context)` across all 3 modes (`warmLinenLight`, `warmLinenDark`, `outdoorHighContrast`). Maintain WCAG AA contrast, >= `48x48dp` touch targets (Fitts's Law), thumb-zone POS checkout controls, zero overflow at **`360x640`** (and **`<= 300px`** modal/sheet inner width), `NavigationRail` at width >= `768dp`, and zero-decimal tabular Rupiah (`IdrCurrencyFormatter` + `AppTheme.moneyStyle`).

---

## 3. Cloud <-> Edge <-> Offline Parity & 4 Production Hardening Contracts
- **1:1 API Lockstep**: Every endpoint in `lib/core/constants/api_endpoints.dart` and Dart model (`pos_models.dart`, `auth_session_model.dart`) MUST stay locked 1:1 with Laravel `routes/api.php`, UUIDv4 `X-Idempotency-Key`, `X-Tenant-Slug`, `X-Store-Id`, `X-Edge-Node-Code`, CORS-safe `ApiClient.resolveMediaUrl()`, `/api/v1/pos/warehouse-stock`, and all **8 Product Types** (including `track_batches = true` FEFO).
- **Deduplicated Sync & 3-Tier Failover**: Await `_activeCloudSyncFuture` inside `PosCubit.syncWithCloud()`, drain pending local products before FIFO offline sales (`_offlineDb.syncOfflineQueue`), preserve Dead-Letter Queue (DLQ) & `/api/v1/pos/offline-conflicts`, and keep `EdgeDiscoveryService` (`lanEdge` 1.5s -> `cloudMaster` 4s -> `deviceSqlite`).
- **Hardening #1 — Incremental SQLite Migrations**: Whenever incrementing `_dbVersion` in `sqlite_database.dart`, implement explicit incremental upgrade blocks (`if (oldVersion < N) { ... }`) inside `onUpgrade`, wrap multi-table checkout writes in `db.transaction(...)`, preserve FTS5 (`products_fts`), and NEVER drop user offline queues.
- **Hardening #2 — Android 14+ (API 34/35) Foreground Services & Hardware Permissions**: Any background sync service, WorkManager foreground task, or persistent Bluetooth printer service in `AndroidManifest.xml` MUST declare explicit `android:foregroundServiceType="connectedDevice|dataSync"` alongside Android 12+ `BLUETOOTH_SCAN` (`neverForLocation`) / `BLUETOOTH_CONNECT`. Keep printer auto-reconnect non-blocking and preserve Virtual Mock Printer fallback.
- **Hardening #3 — Global Offline Diagnostic Crash Telemetry**: Capture unhandled exceptions via `FlutterError.onError` and `PlatformDispatcher.instance.onError`, persist sanitized diagnostic records into SQLite (`local_error_logs` with rolling cap and ZERO tokens/passwords/PINs), and flush silently when online.
- **Hardening #4 — Cashier Shift Security & Inactivity PIN Auto-Lock**: Support inactivity auto-lock for active cashier shifts that overlays a lock screen requiring dynamic `POST /api/v1/pos/verify-pin` (never hardcoded PINs) without destroying active cart state or logging out the tenant session.

---

## 4. Zero-Prompt-Burden E2E Verification & Anti-Mock Mandate (Run Automatically)
Even if the user does NOT ask for "end-to-end" testing:
1. **`flutter analyze` is NOT enough**: It never catches `RenderFlex` overflows or broken backend APIs.
2. **Narrow-Viewport UI Overflow Proof**: Every modified Flutter screen, modal, or bottom sheet MUST be verified by a widget test at **`Size(360, 640)`** (and **`<= 300px`** inner width for modals/dialogs with realistic long Indonesian labels) asserting **`expect(tester.takeException(), isNull)`** — zero `RenderFlex` overflow tolerated.
3. **Real Backend E2E Proof (Never Mock-Only)**: Whenever a Mobile screen or Cubit calls `/api/v1/*`, **NEVER** rely solely on mocked Dart unit tests. Also execute the real Laravel PHPUnit Feature/Integration test hitting that exact `/api/v1/*` route (verifying HTTP `200/201` + `401/403/422` negative paths + real DB/Stock/GL state + zero new `ERROR` in `storage/logs/laravel.log`).
4. **Senior Remediation Protocol**: When fixing a Mobile bug, reproduce it first, fix the root cause (never hide errors), sweep sibling modals/screens for the same overflow or error-handling defect, and lock it in a regression test.

```powershell
# 1. Flutter Static Analysis & Full/Targeted Tests (including narrow-viewport overflow proof)
Set-Location "d:\laragon\www\Nusacommerce\NUSACOMMERCE MOBILE"
flutter analyze
flutter test --reporter compact

# 2. Real Backend Cloud <-> Mobile Parity & Endpoint Integration Proof (from repo root)
Set-Location "d:\laragon\www\Nusacommerce"
php -d memory_limit=512M vendor/phpunit/phpunit/phpunit --configuration phpunit.xml tests/Feature/Mobile/MobileParityAndSyncVerificationTest.php --no-coverage
```
