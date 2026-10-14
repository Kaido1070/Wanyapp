# Wany release requirements

The user explicitly requires a visible, updated version number and a description of every change, both in the app and in the final chat response.

For every change committed/shipped to this repository:
1. Increase MARKETING_VERSION in project.yml (at least the patch number) and CURRENT_PROJECT_VERSION (at least +1). Never reuse a shipped version or build number.
2. Prepend the matching version/build/date and clear Arabic change notes to Wany/Resources/Releases.json. Preserve all previous release entries.
3. Show the installed version via Bundle metadata, never a hard-coded string. Settings and the offline Updates screen use the same installed bundle version.
4. Run `node scripts/check-release.mjs --base <previous-main-sha>` before publishing. CI must always run this gate; do not skip or weaken it.
5. Report the exact version/build and what changed in the final chat response. When delivering an IPA, verify its Info.plist matches that version/build and identify it clearly to the user.

These rules also apply to configuration, workflow, asset and documentation changes. A `[package-only]` build may skip previously passed behavioral tests for low-impact changes, but never skips release validation or the native iPhone build.
