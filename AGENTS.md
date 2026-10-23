# Wany development and release requirements

The user requires efficient incremental development and accurate release identity.

1. Logical development commits may retain the current unshipped version/build. Run `node scripts/check-release.mjs --development --base <previous-development-sha>`; never reduce either number or rewrite historical release notes.
2. When preparing a new testable release candidate, increase MARKETING_VERSION and CURRENT_PROJECT_VERSION together and prepend matching clear Arabic notes in Wany/Resources/Releases.json. Never reuse a shipped version/build.
3. The strict gate `node scripts/check-release.mjs --base <production-baseline-sha>` remains mandatory before IPA packaging. Application tests and native iPhone compilation cannot be skipped, including through commit-message flags.
4. Show installed version via Bundle metadata, never a hard-coded string. Verify delivered IPA metadata and identify its tested commit, version and build.
5. Test the affected area first. Batch related fixes before expensive integration CI. Do not push over a running validation whose result is needed. Diagnose an actual failure before retrying.
6. Recording uses the already tested simulator artifact in a separate job after IPA upload. If capture alone fails, rerun that job only; retain its failure visibly. Screenshot export is optional and reports its own failure.
7. Keep the cinematic production flag disabled until user approval. Do not merge main or alter production servers/user data without approval.

8. Sequential numbering (user requirement): each delivered release increases MARKETING_VERSION by exactly one patch step and CURRENT_PROJECT_VERSION by exactly one. Fix and retry commits before delivery keep the candidate's numbers (`--development`); never skip numbers because of extra attempts.
