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

## Liquid Glass (1.4.1+)

- iOS 26 device: tab bar, navigation bars, menus and sheets use system Liquid Glass. Cards, fields, the reader bar and the avatar save bar use glassEffect. iOS 17/18 device: the same surfaces use system materials with no visual regressions.
- Settings › المظهر: toggle glass off (solid surfaces everywhere), then try each strength (شفاف، خفيف، متوازن، قوي) on iOS 26 and on iOS 17/18.
- Enable Reduce Transparency: every custom glass surface becomes a solid readable surface.
- Reader bar over bright and dark pages: title, page count and buttons stay legible; every button is at least 44 pt.
- Confirm the IPA Info.plist has no UIDesignRequiresCompatibility key.

## Performance (1.4.2+)

- Scroll Discover, FYP and the profile library fast on an older iPhone: covers appear without layout jumps; the placeholder keeps the cover's exact size. Return to a visited page: covers are already there.
- Watch the animated cover wallpaper: it freezes while scrolling and during push/pop, resumes from the same place afterwards, and never runs in the reader.
- Start a multi-chapter download and open the profile and Discover tabs: they must stay smooth; the Downloads summary updates about once a second.
- Generate FYP and the New feed: the UI keeps responding to scrolling and taps while the feed is being prepared.
- Open a large downloaded chapter offline and a long story chapter list: the reader opens without a stall, and progress is still saved after killing the app from the background.
- Instruments (Time Profiler, SwiftUI): no JSON decoding, image decoding or file writes on the main thread during scrolling or reading.

## Merged 1.3.35 + 1.4.x (1.4.5+)

- Cold launch and login: identical to 1.3.35 — only the R mark appears, shines once and flies to its place, then the approved wallpaper settles. In the navigation bar the mark sits directly in the bar circle.
- Story page: each chapter row has its read/unread control beside the download control; "mark all read" and "clear progress" ask for confirmation and sync with the website.
- Statistics › reading calendar: weekdays read right to left starting with Sunday; every day is the same circle; tapping a day shows its count.
- Login: the submit button is solid gold with dark text and dims only while disabled.
- Wallpaper: only your own covers of at least 432×595 appear; with none available the background stays plain. No soft or blurry cover may appear behind content.
- Reader: the bar touches the top edge (glass under the status bar and camera, no gap), the chapter number appears once, and the slider menu offers image quality plus re-download of the current chapter in that quality.

## 1.4.6

- Open an undownloaded chapter on a normal and on a slow connection with quality set to high or original: pages appear within a few seconds (balanced if needed), then sharpen in place without the page jumping or going blank.
- While a page loads it shows a spinner and "جارٍ تحميل الصورة"; "إعادة المحاولة" appears only offline or after the page really failed.
- End of chapter: framed card with a gold "الفصل التالي" button and a secondary "العودة للفصول" button, both easy to tap.
- Settings › المظهر: turn glass off and check the profile library, FYP and story cards are separated by thin edges; turn glass on and the edges disappear.
- FYP: both columns align at the top in every row, with long and short titles and reasons.
- Reading statistics: the headline number, streak strip and three tiles fit without the large title gap; check large Dynamic Type.

- Story page over a bright, busy wallpaper with glass set to شفاف: the description, every button and the chapter tools stay clearly readable; disabled buttons dim but remain legible.

## 1.4.7

- Security page and other long pages: scroll hard to the bottom and top repeatedly; the page must settle without bouncing up and down, and the bottom bar must not flicker.
- Reader: read through a long chapter, scrolling down steadily; the position must never jump back to the top. End-of-chapter card title is fully visible at large text sizes.
- Profile › تعديل: a sheet opens; the tab bar and other pages are unreachable until حفظ or إلغاء. The badge sits next to the name; @username is readable.
- Story page: "خيارات القراءة" (⋯) in the top bar holds mark-all-read and clear progress, each with confirmation; nothing destructive sits beside the chapter list.
- Every download button asks for balanced / high / original before starting; the chosen quality is used for those chapters.
- Offline: open a currently-reading or favourite story; its description and genres are shown.
- Cold launch with a large downloads library: the first screen appears without delay.
- Tap the R mark in the top bar: a sheet explains the name (R from Read + ANY from Anytime); it closes with تمام or a swipe. The intro still lands on the mark.

## 1.4.8

- Open Settings from any tab: the bottom tab bar is hidden there and on every page opened from Settings (security, updates, avatar); it returns after going back.
- Profile › القوائم › إدارة القوائم وترتيب الأقسام: the page loads without "The data couldn't be read" and shows favourites plus each list with its name, icon and count; hide/show and reorder save and survive a refresh.
- Activity page: each event is a compact two-line row (avatar, who/what/when, then the story and chapter); long titles truncate to one line.
- Tap the R mark: the sheet's إغلاق button closes it on the first tap; swiping down still works.

## 1.4.9

- Settings › الأمان: one card with three equal rows (password, security question, recovery code) and a separate full-width sign-out-everywhere card; check both glass on and glass off.
- Each row opens its own page: labelled fields, live hints (short password, mismatch, question length), the action button stays dim until valid, a confirmation explains what happens, and a green or orange result appears below.
- Wrong current password shows "كلمة المرور الحالية غير صحيحة" and changes nothing.
- رمز الاستعادة: the button is disabled until the current password is typed; the new code appears with a copy button and disappears when leaving the page.

## 1.4.10

- Hunter x Hunter from العاشق (3asq): the story page lists the same chapters as the website and they open and download.
- A story whose source announces more chapters than it returned shows every returned chapter plus a short "المصدر يعلن…" note; pull to refresh fetches the rest.
- Team-X stories with many chapter pages: the full list loads; if one page fails, the chapters already loaded stay visible.
- Discover/search: a source page containing one malformed entry still shows all other stories.
- أقرأ حاليًا: open chapter 150, accept "تعليم الفصول السابقة كمقروءة", go back; «وصلت للفصل» must still say 150 and open chapter 150.

## 1.4.11

- Browse login, sign-up, profile, lists, story, statistics, achievements, security and سجل التحديثات: no text says Wany or mentions the website; every name reads Rany.
- Achievements: the 5,000-chapter trophy reads «أسطورة Rany».

## 1.4.12

- Sign in, read a chapter, mark a chapter read, add to favourites: each saves and survives an app restart (all requests go directly to the current service origin).
- Previously downloaded chapters and cached covers still open, including ones saved before this update.

## 1.4.13

- جديد: open a chapter from the feed; the bottom tab bar is gone for the whole chapter and the last pages and end-of-chapter card are fully visible. Going back shows the tab bar again.

## 1.4.14

- Statistics page: opening it syncs local progress, then loads fresh statistics; pull to refresh and «تحديث الإحصائيات» do the same. Other syncs no longer request statistics.
- Profile › مكتبتي: scroll down inside «أقرأ حاليًا», switch to «المفضلة» and back; the page stays at the same height and does not jump to the top.

## 1.4.15

- Settings: sections appear in this order, each in its own card with an icon heading: الحساب، الخصوصية والأمان، المظهر والخلفية، القراءة والتنزيل، التخزين، المزامنة، حول التطبيق، then تسجيل الخروج. Every option is its own row separated by a divider; descriptions sit under their own option. Every option behaves as before.

## 1.4.16

- Sync: a progress record or chapter-open event the server rejects as invalid (400/413/422) is dropped and the records after it still sync; outages, 401 and 429 keep it queued as before.
- Pull to refresh or «مزامنة الآن» while the 30-second sync runs: the request waits for it and then refreshes; two refreshes at once run only one.
- A refresh with nothing to push reads the account once instead of twice.
- Download a large story: the download ledger is saved once per batch of started pages and at most every two seconds on completion; leaving the app saves at once. Pause, relaunch and resume still keep finished pages.
- An invalid cover or page link fails that image instead of closing the app.

## 1.4.17

- Automatic syncs (launch, return, reconnect) that fail show «تعذرت المزامنة · اضغط لإعادة المحاولة» in the top banner, never an alert; tapping it or pulling to refresh shows errors as before. A later successful sync hides it.
- Two messages at once (an error and a download notice) appear one after the other.
- Chapter read/unread buttons and «تحديد الكل كمقروء» stay enabled while syncing; a tap waits for the sync and then applies.
- Double-tap «أضف للمفضلة»: the story is added once.
- Sign out and straight into another account while a sync runs: the new account refreshes.
- Reader: a damaged local page (main or fallback file) downloads again at once; scrolling a 100+ page chapter stays smooth; retry buttons update right after a retry.
- Story page with 1000+ chapters: scrolling the list is smooth; download checkmarks still match.
- Opening a story, a chapter and going back reuses the chapter list fetched within five minutes; pull to refresh and «إعادة جلب قائمة الفصول» always fetch it. Library chapter lists refresh in the background at most every six hours, across launches.
- Friend requests are checked every two minutes. Temporary-image cleanup saves only when it removed something.
- Story descriptions show plain text (no &amp; or &#39;). The avatar does not blink when the connection changes.

## 1.4.18

- An error and a download notice at the same time: tap «حسنًا» on the first; the second appears next.
- Pull to refresh right after returning to the app while the automatic refresh fails: the failure appears as a message, not only in the banner.
- A page that downloads but cannot be opened is downloaded again once; if it fails again it shows «إعادة المحاولة» instead of downloading repeatedly. The retry buttons reset it. Only the file that failed is removed (a lighter fallback stays when the main file failed).
- Tap «مقروء» during a sync whose result is an expired session or lost connection: the tap is refused with the connection message. A second quick tap while the first runs shows nothing.
- Switching story source or leaving the page while the chapter list loads never shows a cancellation error.
- Background library pass saves its timestamps once per burst.

## 1.4.19

- Heavy history (thousands of completed chapters): opening a chapter of a long story, scrolling its chapter list and the profile cards stay smooth; «مقروء», percentages and «وصلت للفصل» match 1.4.18.
- Download a whole long story while reading another: saved downloads start at most 1000 images per 5 minutes; reading pages keep loading. If the server answers 429 to a saved download, it pauses for five minutes and resumes by itself without counting the attempt.
- While the reader is open, account saves are gathered every four seconds; leaving the reader or the app saves at once.

## 1.4.20

- Changes-only sync: after the first refresh, /api/data is requested with `since` and returns only changed progress; progress, «مقروء» marks, favorites and the library match a fresh install of the same account. Marking a chapter unread forces one full read. Accounts saved by 1.4.19 load and do a full read first.
- Messages: حسابي › الرسائل lists conversations (unread count, last message) and friends to start one; the account tab shows the unread count. A conversation opens at the newest message, the writing box stays at the bottom and above the keyboard, «عرض رسائل أقدم» keeps the place, day separators and grouped bubbles show, a shared story or chapter card opens it.
- Sharing: «مشاركة» beside «الفصول» on a story page (actions wrap under the heading on narrow phones) and «مشاركة الفصل مع صديق» in the reader menu send to a chosen friend with an optional note.
- The screen does not sleep while the reader is open and sleeps normally after leaving it.
- When the server reports the reduced-image allowance used up, one notice appears per month; pages keep loading at full size.
- An archived cover is uploaded only when the saved image came from the exact cover address being archived.

## 1.4.21

- Conversation: holding a message shows «نسخ» and copies its text; a message of up to three emoji shows large without a bubble; a shared story or chapter is a slim one-line card (36×50 cover, one-line title). The back button leaves the conversation and the messages page.

## 1.4.22

- Conversation: holding a message shows «رد», «نسخ» and, on your own, «حذف». Reply shows «الرد على …» above the writing box (× cancels) and the sent message carries a quote; tapping it scrolls to the original. Delete asks to confirm and removes the message for both friends; a reply to it then shows «رسالة محذوفة». Tapping the messages closes the keyboard; links and buttons inside messages still work.

## 1.4.23

- Friend page in Rany's own layout (not the website's): glass identity card like «حسابي» (54 pt avatar, name + badge, @username in the accent) with one trailing action — «إضافة», «مرسل» (menu: إلغاء الطلب), «طلب» (menu: قبول / رفض) or «صديق» (menu: إزالة with confirmation); details card with «مراسلة» for friends and قصة · فصل مقروء · صديق; «مكتبته» card with أقرأ حاليًا / المفضلة / القوائم tabs (list chips + «عرض القائمة كاملة»); آخر النشاط and أصدقاؤه cards only when they have entries. A private account shows «حساب خاص» only. No visible text mentions the website.

## 1.4.24

- Conversation: the send button sits on the right of the writing box (it leads the row, which is the right edge in Arabic); it keeps its 44 pt circle, dims while the box is empty, and the box still grows to five lines.

## 1.4.25

- «جديد» reloads on the first visit of a launch, whenever the saved copy is empty, and when it is older than 15 minutes; the saved copy shows at once while the fresh one loads. Pull-to-refresh and the toolbar button still reload on demand.
- Feed engine regenerated from the current algorithms (stored story summaries for FYP and «جديد», `rany:` cache keys); the bridge gained `summaries` and passes `refresh` to `recent`.

## 1.4.26

- After a snapshot save the server may answer `archived: true` (it saved a fresh copy of the cover). The app then reloads that story's snapshot and replaces the cover kept on the phone at once, instead of waiting for the next library refresh. Stories with a reviewed replacement cover also get a new saved-cover address from the server, so phones that kept the old picture fetch the new one.
- «جديد»: the toolbar refresh button and pull-to-refresh pass `refresh` to the feed engine, which sends `refresh=1` to `/api/source/recent` so the server rebuilds its shared copy (same rule as the website's تحديث; a copy rebuilt moments ago is reused). Opening the page and «تحميل المزيد» do not force a rebuild.
- Reader: the end-of-chapter card shows «الفصل التالي», «مشاركة» (opens the friend picker for this chapter; disabled offline) and «العودة للفصول».

## 1.4.27

- «جديد · أتابعها»: a chapter you read stays listed with its ✓ (the engine no longer drops read chapters; the unread count still ignores them). Feed engine regenerated from the current algorithms: chapters ordered by number, the manual refresh waits up to 40 s per source, and a followed story is also recognised by its saved name within the same source when the source changed its address.
