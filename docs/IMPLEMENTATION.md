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
