# Rany implementation ledger

Baseline reviewed: application main `c9c02e8`, Rany 1.3.11 (39); website/server main `558a04d`.
The older interrupted work in `/workspace/Wanyapp` remains separate. This branch starts from the latest app revision and contains no Blender or pre-rendered intro movie.

## Phase A — candidate 1.3.12 (40)

Native dynamic SceneKit leaves use subdivided geometry with GPU cylindrical curvature, perspective, directional shadow, slight turn variation and restrained camera motion blur. A full cover surface remains underneath the moving leaves, avoiding uncovered edges. Eight textures at a maximum 640-pixel edge bound the decoded image pool. UV crops preserve proportions. Cached reading/library/favorite interests and cached server personalization are ranked before actual source popular results. Existing bundled story covers are the final offline fallback; no popularity numbers are synthesized. Background preparation reads `/api/personalization-state`, resolves up to 40 keys and downloads up to 12 thumbnails, scoped to the current API generation/account. No account image is written into the shared guest cache.

Typography uses the existing `RanyScript` font and established script glyphs: Read Any Time → RANY → R → `RanyMark`. Surplus glyphs are clipped; retained letters move continuously. A complementary wipe converts the retained R to the actual official component. No identity source is modified. The same `RanyMark` moves to the existing globally measured `login` or `header` frame. The native preview mounts the real RootView with a read-only account snapshot and closes on account change. Existing auth, navigation, glass, hotbar and profile components are preserved.

Preview: Settings → Update history → Play cinematic preview. Replay, duration, login destination and cover preparation controls appear after playback. iOS Reduce Motion shows a static official destination and short reveal. `CinematicConfiguration.production.playback` remains `.disabled`; only after approval set `.coldLaunch` or `.once` in a separately versioned change. The prepared runtime does not restart on resume. Lifecycle cancellation and a duration watchdog release the overlay.

Local Phase A checks: release gate against c9c02e8; four Node feed/source merge checks. Native tests added for brand gate, retained letters, phone/landscape measured destinations, interest ranking and empty texture fallback. These require macOS/Xcode; no native test success is claimed before CI. Target is 60Hz; actual device GPU/memory/energy and visual handoff still require Instruments and device review. Core Animation blur/material appearance during logo movement also needs device comparison.

## Website contracts reviewed

- Auth: POST change-password (`currentPassword`, `newPassword`, `confirmPassword`), POST security-question (`currentPassword`, `question`, `answer`), POST recovery-code (`currentPassword`), POST recover-password, POST logout-all.
- Lists: GET/POST lists, GET/PUT/DELETE lists/:id, POST lists/:id/items, DELETE lists/:id/items/:key; PUT lists/:id/reorder (`mangaId`, `beforeId`, `afterId`). List/section visibility and section order are managed through GET/PUT profile/sections, not an invented list visibility route.
- Reading: POST reading/open, reading/unread, reading/unread-work, reading/read-bulk. Opening and completion are different events. Server opening deduplicates a short window; unread-work removes library/history/progress. The existing download Select all remains a download action.
- Personalization: GET personalization-state includes followed (including custom lists) and readingWorks; source popular ordering is source-owned.

Each later phase appends actual changes, test results and limitations here. The final parity matrix must distinguish implemented, pre-existing and incomplete work. Production server/user data is not changed for tests.

## Phase B — candidate 1.3.14 (42)

Added native security and recovery forms with server-owned password/question/recovery-code verification and explicit sensitive-action confirmation. Secrets exist only in transient form/task memory, are never saved to disk/cache/logs, and clear on dismissal/background. Recovery never verifies an answer separately before the complete reset. Logout-all waits for server revocation before clearing local credentials and account attachment. Change-password now persists the server's rotated cookie to Keychain and invalidates old request generations; a new feed engine is created for the renewed session. HTTP 401 marks session recovery as required.

Executed server contract/auth checks: `node --experimental-strip-types --test tests/auth-request-safety.test.mjs tests/settings-phase9.test.mjs tests/invitation-registration.test.mjs` — 24 passed. Four native feed bridge tests also passed locally. Added URLProtocol-based native tests for cookie rotation, 401 propagation and the recovery contract; native results await CI. The first Phase A CI failed at SwiftUI type inference, not at a passing test; 1.3.13 (41) split the heavy animation expression into smaller views and reruns CI. No failed build was packaged as an IPA.

The complete website baseline initially had missing TypeScript dependencies and a pre-existing progress source-contract assertion failure. Dependencies were installed locally without changing server files; a complete rerun is being recorded separately. Production server/data are untouched.

## Phase C — candidate 1.3.16 (44)

Implemented list name/description/icon editing, confirmed deletion, native drag/drop item and managed-section ordering with accessible move alternatives, system favorites placement, hide/show and live profile reload. Changes preserve non-list section order/visibility in the complete server payload. List creation plus adding the current story shares one sheet and retains a successful created ID if the add step fails, preventing duplicate creation on retry. Current download select-all and removed status tabs are untouched. Description/icon are shown in detail and management views.

Friends now show incoming/outgoing requests, cancel/accept/reject/remove with accurate server relationship states and refreshed results, search-to-profile navigation and request counts. Public profiles render only server-permitted statistics, reading, activity, friends, favorites and lists. Accepted private friends see collections only; private reading/activity/statistics are not synthesized from other caches. Public profile/foreign list details require fresh authorization; verified own lists retain account-isolated offline caching.

Executed lists/friends/privacy server suite: 17 passed. Added native unit coverage for managed order preservation, move boundaries, path encoding, field limits and four relationship states. Native CI is still being repaired: the compiler selected ambiguous Text/View font overloads even with explicit Font; the glyph is now constrained to a Text-typed property. A real SceneKit cover-render test will exercise shader setup and attach frames.

Website full baseline after installing dependencies: 399 tests, 398 passed, 1 existing failure in d1_runtime_optimization.test.mjs expecting an outdated progress SQL no-op predicate. The newer timestamp-monotonic offline progress route and its regression tests were preserved. No server source or production data was changed.

## Phase D — candidate 1.3.17 (45)

Discovery now combines source/type/status/genres using the actual website filter aliases and predicates, exported by the reproducible feed generator. Missing metadata is fetched with at most three concurrent series requests. Filtering is client-side, as on the website; no nonexistent server filter parameters are invented. Discovery/favorites use `mergeSourceItems` from the same embedded website source as FYP/New; numeric work qualifiers and same-source identity separation have added Node regressions. Source changes await a complete chapter list before replacing the selected data; every source keeps its original progress key.

Independent chapter context actions mark one chapter read (the website progress route) or unread; work-level actions bulk-read in batches of 500 or clear all associated source variants, with destructive confirmation. Download select-all is unchanged. Manual commands drain older local progress, discard matching queued completions/positions/opens after server acknowledgment, and refetch authoritative account data. Opening a successfully loaded chapter queues a separate reading/open event; loading/repainting the same entry does not queue it twice. Reader navigation creates a fresh opening entry. Opening alone does not manufacture a percent or a completion. Prior-chapter confirmation follows the website's complete-archive/entry-from-outside-reader conditions. Chapter rows show partial percentage and literal source publication date only when supplied.

Account-scoped optional event/snapshot queues extend the existing offline ledger without dropping old data. Metadata snapshots synchronize real title/source/url/chapter and upload a <=640px JPEG through the actual authenticated binary endpoint. Archived metadata is restored before slow source resolution. Optional cover archival runs separately, with retry backoff, so an R2 failure cannot block progress uploads. Generation and owner are rechecked before uploads. Automatic offline reading remains supported; manual destructive server commands require online authorization.

Executed Phase D server reading/identity/pagination suite: 13 passed; local embedded feed/filter/group suite: 6 passed. Native ledger/opening/MIME tests added; native results await CI. CI also identified a mixed CGFloat/Double expression in the R-to-logo mask; those mask coordinates now have explicit CGFloat types.

Known server contract constraint: reading/open stamps server receipt time and deduplicates a five-minute window. Original offline event times cannot be represented by this endpoint, and a lost acknowledgment retried after that window cannot offer indefinite exactly-once delivery without server idempotency support. No claim of stronger delivery semantics is made. This is tracked for the final compatibility review.
