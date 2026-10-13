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
