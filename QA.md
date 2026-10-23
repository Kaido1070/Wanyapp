# Device acceptance checklist

Use a test account and a real iPhone before calling this a production-ready release.

1. Sign in using the website account. Confirm badge, library, favorites, statistics and avatar match. Relaunch: profile cards render from disk before requests finish.
2. Open a story with paginated chapters (particularly Team-X). Download whole story. The count must match the complete source archive, including decimal chapters. Failed/incomplete chapter lists must show an error, never success.
3. Verify bytes and speed while multiple images transfer. An unknown total must read “جارٍ حساب الحجم الإجمالي”; no estimated value is labeled exact.
4. Disconnect during a download. Completed images remain; reconnect and retry missing images. Inspect traffic to confirm completed files are not fetched again. Pause, relaunch, resume.
5. Open a downloaded chapter in airplane mode; scroll, terminate, relaunch and verify local position. Read several chapters; reconnect with app active and verify website progress and completion counts.
6. Read something newer on the website while the phone is offline. Reconnect and verify old phone records do not replace the newer last-opened chapter. Verify older completed chapters still sync.
7. Read to 98–100% while the last image is missing: chapter must not be marked completed. Retry and reach the actual end: it may complete.
8. Switch accounts while a transfer/sync is active. No progress, covers, feed snapshots or downloads from the first account appear in the second. Sign back in and verify pending progress survives.
9. Revoke the session on the website. Reopen online: request login while preserving offline reading; signing into the same account restores sync.
10. Low disk space, invalid image response, expired session, 429, slow source and failed chapter manifest: each must remain recoverable and must not become a completed download.
11. Scroll down/up and use VoiceOver, Dynamic Type, landscape, large chapters and decimal chapter numbers. Verify native navigation and reader page restore.
12. Compare FYP ordering and New feed mirrored chapters with the same source snapshot on the website. No synthetic chapter may be advertised as a new release.

Automated checks cover download accounting, persistent account separation, progress persistence, correct native API headers, and shared algorithm fixtures. Network/device/background behavior remains a required manual gate.

## Rany identity and ambience acceptance

- Cold launch: READ ANYTIME retains its actual R/A/N/Y elements through RANY, then R. Login uses a short R transition; verify no duplicate intro or interactive content before completion.
- Confirm the bundled Script font works offline, English labels use it, Arabic remains legible, and VoiceOver reads ordinary text rather than mathematical character names.
- New accounts show bundled covers. Current reading/favorites with valid cached images replace them only at a hidden boundary or the next launch. Missing, invalid and tiny images are excluded.
- Follow/unfollow while visible: artwork must stay stable. Background and return quickly: an unfinished decode must not change artwork after returning. Switch accounts: no preceding account artwork may flash.
- Profile on a physical older iPhone with Instruments: idle login, long scrolling, chapter reading, Low Power Mode, Reduce Motion and Reduce Transparency. Confirm no backdrop rendering during reading/background and no repeated image decoding on the main thread. The 24 Hz ceiling and eight thumbnails bound work; they are not a measured device performance guarantee.
- Native build, simulator tests and physical-device performance remain required before release. A browser motion preview does not validate native compilation.


## Registration and premium arrival

- Toggle sign-in/registration repeatedly, with keyboard and Reduce Motion enabled. All five registration fields remain reachable at large Dynamic Type sizes.
- Confirm local validation agrees with the existing backend: username 3–32 ASCII letters/digits/underscore starting alphanumeric; password 8–128; matching confirmation; security question 6–200 and answer 1–128.
- Mock success and errors: registration 409, registration 429, failed login after successful creation, and offline submission. The new-account arrival plays only after an authenticated login succeeds. A login retry after successful registration must not send a second registration request.
- Confirm eight cover slots remain stable. Rejected/small/flat/invalid responses use reviewed offline fallbacks; older ambience manifests must be rebuilt under the new quality policy. Inspect real source art manually: numeric quality checks cannot establish artistic quality or detect every possible placeholder.
- Verify the approved R silhouette, one metallic rim and a single sheen before docking, with a quiet first-account greeting; no repeated welcome on later launches.


## Fourteen-story circuit and glass identity

- Check all fourteen bundled fallback signatures are distinct. Personal art is prioritised, then reviewed popular art fills the pool. No duplicate pool entry may be drawn in both columns.
- Track a visible story: right goes up; left goes down. Each crosses to the other column outside the viewport, never across a visible row. Pause/resume must preserve elapsed position rather than jump back to the initial arrangement.
- Test foreground/background, reader entry/exit, Low Power Mode, Reduce Motion and Reduce Transparency. The suspended circuit must not keep ticking. Measure the fourteen-entry pool on a real phone; only visible entries should draw and decode stays outside the animation loop.
- Compare the intro mark with the docked mark: same transparent monogram, same shared glass component, letter 20% smaller. One sheen at formation, none looping afterward. Inspect all card, field and selection surfaces for consistent tint and contrast.
- DESIGN_BRIEF.md is the canonical current design handoff; newer user instructions supersede it.


## Native navigation (1.4.0+)

- Switch between all five tabs while each is several pages deep: every tab returns exactly where it was left.
- Tap the selected tab while deep in a stack: it pops to the tab's first page. Tap again: the page scrolls to the top and the large title expands.
- Push and pop rapidly (double taps, tapping during the push animation, back then forward): touches must respond during transitions; no frozen screen, duplicated page or blank page.
- Edge-swipe back on every destination, including the reader (navigation bar hidden), story, settings, avatar picker and list detail. Start a swipe and cancel it half-way: the page must stay usable.
- Scroll down on a tab root and on a destination: the bottom bar slides away; a deliberate scroll up brings it back. Content must not jump when it hides or returns.
- Large titles collapse on scroll and expand at the top. The R mark and the settings button stay in the navigation bar; cold launch and login intro still dock the mark there.
- Save an avatar and leave the picker before the request ends: no other page may be closed by the late response.
- Sign out and in with another account while deep in several tabs: every stack starts at its first page.
