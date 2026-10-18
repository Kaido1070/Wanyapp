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

## Phase E — candidate 1.3.18 (46)

Activity uses the server's real 20-event maximum per page, appends older events with stable event IDs, keeps prior content during page failures and offers retry. New/friends tab resets cannot append an old response into a different feed. Personal activity is cached by owner; friend activity requires authorization. Titles resolve in batches with a snapshot-first path. Unknown upstream titles show an honest unavailable message.

Stats now include the exact chapter/story/streak trophy thresholds from the website source, current earned rank, next goal, achievements and a calendar aligned to the site's UTC+3 day boundary for the last 30 days. Milestone configuration is generated alongside embedded client algorithms. No new point system or achievement thresholds are introduced. Public profile statistics remain constrained by the server's public-profile payload, not by this private dashboard.

New pagination now appends groups/chapters, merges variants that share existing source keys, retains the first group's rendering identity and prior order, deduplicates source+chapter identity and preserves legitimate simultaneous source editions. Duplicate/out-of-order pages are rejected; a failed next-page request keeps the displayed feed and can retry. Server hasMore=false stops requests. First-page refresh replaces only after a successful response. The actual New selection algorithm is unchanged.

Executed activity/New website suite: 22 passed; six embedded client checks passed. Added native pagination overlap, source-variant merge, UTC+3/30-day calendar and real milestone-boundary tests. Native CI remains authoritative for compilation/runtime. Device performance, actual interaction tests against an account and privacy changes made by a second device still require device/account acceptance testing.

## Review refinements — candidates 1.3.19 (47), 1.3.20 (48)

Candidate 46 compiled and passed all 76 native iOS tests, including the real SceneKit shader snapshots and new Phase E cases. The recording step then failed because xcodebuild tested on a cloned device while the selected recording device remained shut down; no iPhone Release build or IPA from that run is claimed. Candidate 47 explicitly boots and installs the test-built application before recording guest and signed-in read-only fixtures. It also resets the RootView identity only when account identity changes, clears CachedPage ownership on switch/logout, cancels dismissed list-editor saves and uses route-conditional pop for late list deletion. Same-account refreshes preserve navigation.

Candidate 48 gives the complete RANY word a 0.4-second hold and the centered R a 0.24-second hold before the official mark wipe; these are distinct stages within the same 4.8-second sequence. Added geometric hold checks. Once production playback is approved/enabled, cover preparation runs after the optional intro rather than delaying entry, and first-account arrival is completed. Normal production playback remains disabled.

Full native recording/Release results are reported through the PR checks/artifacts and final review report after CI completes; these notes do not predeclare success. Physical-device interaction, live-account interoperability, GPU/FPS/memory and strict offline opening idempotency remain the acceptance limits described above.

## Verified continuation — 1.3.29 (57), commit 87344b4

Run 39050496956 completed successfully: all 86 native tests passed, iPhone Release compilation succeeded, and the unsigned IPA's Info.plist was verified as 1.3.29 (57). Both real simulator recordings were inspected: full title, clipped/gathered RANY, retained R, official mark, then the measured login/header destination. These are read-only fixtures, not a live-account end-to-end test. Recordings include simulator launch/preparation before the 4.8-second sequence; 60 FPS, physical-device memory/energy and production-network behavior are not certified.

Later refinements preserve lazy startup, wait for the first textured GPU frame before starting the clock, keep outgoing page poses continuous when recycling leaves, clear preview data on account switches and test Reduced Motion without writing a read-only environment property. Official branding remains unchanged and automatic production playback remains disabled.

### Parity review

| Area | Implemented on this branch | Existing behavior preserved / remaining verification |
| --- | --- | --- |
| Cinematic | Dynamic personalized cover pages; complete four-stage typography; measured logo handoff; replay and reduced-motion preview | Original font/logo, auth entry and normal startup; physical-device performance and user visual approval pending |
| Security | Password/question/recovery-code management; account recovery; logout-all and cookie rotation | Existing server verification and Keychain/session flow; live account/device revocation acceptance pending |
| Lists/social | Edit/delete/order/visibility/icons/descriptions; same-sheet create/add; outgoing requests, cancellation/removal, relationship refresh; permitted public profile sections | Existing layouts/favorites/friends and server privacy; two-account live acceptance pending |
| Discovery/reading | Combined filters; existing shared source grouping; source switching; manual chapter/work read/unread; separate opening event; snapshots/offline queues; partial percentage and available publication date | Existing offline reader and download Select all; server's five-minute opening deduplication cannot guarantee indefinite exactly-once delivery after a lost acknowledgment |
| Activity/statistics/New | Append older activity; batched title recovery; real rank/trophies/next goal/achievements/calendar; append/deduplicate New pagination | Existing server ranking and chronology; remote source availability may limit metadata |

The existing app already supplied authentication/session restoration, reading/download flows, account/profile layout, glass, hotbar, basic favorites/lists/friends, and FYP/New grouping. They were extended where specified rather than replaced. Cancelled Completed/Paused/Later tabs were not restored. Website/server sources were reviewed and their targeted suites passed (security 24; lists/social/privacy 17; reading 13; activity/New 22; suites may overlap). Its broad baseline had 398/399 passing with one existing SQL progress-contract assertion failure; no server code was changed to conceal it.

### Incremental CI and release identity

Development commits may retain this unshipped candidate's version. `--development` allows identical version/build while preserving historical notes; it rejects rollback, mismatched version/build changes and an explicit missing baseline. Five regression cases exercise these rules. Strict candidate validation against the production baseline remains mandatory before IPA packaging. A new candidate increments version and build together when it is actually prepared; version changes are no longer required for every experimental commit.

CI now compiles application/tests first, then runs mandatory tests using that build, then validates and builds/packages the iPhone app. Commit-message test bypasses were removed. IPA upload precedes independent recording. The separate capture job downloads the already tested simulator application; if recording fails, rerun only that failed job from GitHub Actions. The capture failure remains visible and cannot prevent the existing IPA artifact from being produced. Optional screenshot export reports its own step failure. Automatic cancellation is disabled; wait for a relevant run before pushing another change. This workflow change requires one integration run; its result must be reported against its actual new commit, not attributed to 87344b4.

Preview remains Settings → Update history → Play cinematic preview. After explicit approval, change `CinematicConfiguration.production.playback` from `.disabled` to the chosen supported policy in a separate reviewed release. No merge to main, production deployment, live-user writes or physical iPhone test has been performed.

Integration run 39065504078 at commit 702951c completed successfully: separate build-for-testing, all 86 native tests, iPhone Release/IPA and the independent guest/signed-in capture job passed. A final capture-only policy refinement sets upload-artifact's documented `overwrite: true`, allowing a failed recording's partial artifact to be replaced when that job is rerun. It does not alter runtime sources or the candidate version; actionlint validates its workflow syntax. Its own CI result is reported separately rather than borrowing the prior run's result.

Run 39066559554 at 90765ac compiled but failed one of 86 tests: RanyPresentationTests.swift:183 (preview owner change); no IPA was produced. The test switched accounts upon UIView creation, before its first GPU frame, and used a fixed 300ms cleanup sleep. Its focused correction waits for actual rendered playback, observes removal across bounded render transactions, retains the no-PageStage assertion and captures an owner-change diagnostic screenshot. Runtime privacy guards are unchanged. This correction must pass native CI before it is reported as resolved; a repeated failure requires renewed diagnosis, not another timing increase.

## Golden opening readability — candidate 1.3.33 (61)

Continues PR #2 at 30a4787, retaining the exact approved RanyApprovedBackground.html and existing identity assets. Before-frame inspection showed the full title over the preparation curtain, weak gold-on-sepia contrast and a separate sleep-driven native sequence. The normal golden opening now samples the canvas's first-frame timestamp, with explicit 4.3-second beats matching its 1.08–1.85 pullback and 3.1-second settled layout. Shared native clipping typography retains the full-name → RANY → R → official mark sequence, stronger local contrast and measured destination; account-transition navigation and the experimental cinematic production flag are unchanged.

Local checks: 13 Node cases passed, including exact approved-drawing fidelity and release-policy checks. Added native timeline/bright-artwork contrast regressions and subsecond production screenshots (0.12, 0.25, 0.5, 0.8, 1.08, 1.3, 1.65, 2.05 seconds plus later stages). Native compilation, rendering and visual results must be verified in CI; these notes do not predeclare success.

The first candidate passed 92 native tests, but cold-launch video revealed that initial display preparation could still consume the full-name phase. The follow-up keeps the approved canvas at its static first page until the native title has rendered/warmed and completed a deliberate 0.4-second readable opening hold. Only then do both clocks start. The complete name remains visible during this hold and the first motion phase; total presentation is about 4.7 seconds. Added isolated JS lifecycle and real WKWebView readiness regressions. The approved drawing body and 1.3.32 base remain unchanged; version/build stay 1.3.33 (61) while this candidate is corrected.
