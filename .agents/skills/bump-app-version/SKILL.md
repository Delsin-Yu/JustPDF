---
name: bump-app-version
description: 'Bump JustPDF HarmonyOS app versionName and versionCode in AppScope/app.json5. Use when: bump version, bump app version, raise versionName/versionCode, prepare a release version, ship next version.'
argument-hint: 'Target versionName (e.g. 1.3.0). Optionally say whether to commit. versionCode increments by 1 unless a value is specified.'
user-invocable: true
---

# Bump App Version

Update the shipped HarmonyOS app version in `AppScope/app.json5`.

## Source of truth

- File: `AppScope/app.json5`
- Fields: `app.versionName` (semver string) and `app.versionCode` (integer, must increase for store uploads)
- Do **not** treat `entry/oh-package.json5`, `entry/patch.json`, or lockfile package versions as the app release version

## Procedure

1. Read current `versionName` and `versionCode` from `AppScope/app.json5`.
2. Resolve the target:
   - If the user gave a version (e.g. `1.3.0` / `130` / `v1.3.0`), normalize to `X.Y.Z`.
   - If omitted, ask which part to bump: `major` / `minor` / `patch` (default suggestion: `minor`).
   - `versionCode`: increment by `1` unless the user specifies an exact integer.
3. Prefer the script (keeps JSON5 shape stable):

```bash
node ".agents/skills/bump-app-version/scripts/bump-app-version.mjs" --version-name "X.Y.Z"
```

Optional flags:

- `--version-code <int>` — set an exact `versionCode` instead of +1
- `--dry-run` — print the planned change without writing

4. Re-read `AppScope/app.json5` and confirm both fields match the plan.
5. Report old → new for `versionName` and `versionCode`.
6. **Do not commit** unless the user explicitly asks. If committing, prefer a short English message like `Bump version` (match prior release commits), and only stage `AppScope/app.json5`.

## Rules

- Always bump `versionCode` together with a release `versionName` change.
- Never decrease `versionCode`.
- Do not edit unrelated module/package `version` fields.
- Do not create tags, push, or open a PR unless asked.
