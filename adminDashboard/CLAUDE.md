# Golden Gift Admin Dashboard

Flutter **web-only** admin panel. Package `golden_gift_admin`. English only. Riverpod + GoRouter, same conventions as `../mobile`.

Scope: SRS §9 (`../docs/GOLDENGIFT_SRS.md`). Built alongside the customer features: **Phase 5** = core (access, catalogue, settings); Phases 6–9 each add the modules for that phase's features (SRS §10).

Rules:
- Depends on the customer app package (`golden_gift: path: ../mobile`): use its models (`package:golden_gift/models/...`), `FirestoreParse`, `SearchTokenizer`, `ProductDerived`, `AppColors` tokens. `lib/core/constants/{admin_constants,firestore_paths}.dart` re-export the app's enums and paths — never redefine them.
- Gate every page with `AdminScaffold` (signed-out → login, non-admin → refused). Every write goes through a batch that also calls `AuditLog.add` (lib/core/data/audit_log.dart).
- Admin access is gated by the `admins/{uid}` document + custom claim `admin: true` (role in the doc: super / ops / content / finance). Partners (Phase 8) sign in with the custom claim `seller == storeId` instead — never `admin` — and see only the seller view (own store's products, order lines, KPIs, store profile); a store that isn't `active` shows the pending / suspended page.
- Callables are injected as a `CallableInvoker` (see `features/notifications/data/broadcast_repository.dart`) so tests fake them; `not-found` with a generic message, `unavailable`, `internal`, `unimplemented` mean "function not deployed yet".
- Browser APIs only through `lib/core/web/browser.dart` (tests run on the VM). Dates: `DateFormat(..., 'en_US')` or `AppDates` — never `'en'`.
- Every destructive or financial action (order status change, wallet adjustment, refund, promo creation) writes an `admin_audit_log` entry.
