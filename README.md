# patchCache

A small Mac app for documenting studio patchbays: what's patched where, how each pair is normalled, and what gear it belongs to.

- Blueprint-style front panel for the **Samson S-Patch Plus** and **ART P48** (24 pairs / 48 points)
- Editable label above and below every jack; matching neighbours merge automatically (stereo pairs, `RME 5 – 6`, `Phoenix L / R`)
- Normal / Half Normal / Thru per pair (Thru isn't offered on the P48, which doesn't have it)
- Patch Points table that edits in both directions, plus CSV import/export
- Versions per patchbay (update, save as new, duplicate, delete)
- Gear list with nicknames, a local manual library (Repo Man…: one folder per brand, `Brand-Name-OM.pdf`), sortable columns and type-ahead; category colors carry through to labels, jack rings and the table
- Everything is stored locally — no accounts, no cloud

## Build (macOS 11+)

1. Download or clone this repo.
2. In Terminal: `bash build.sh`
   - If prompted, install Apple's free Command Line Tools, then run it again.
3. Drag `build/patchCache.app` into Applications.

To update, replace `PatchCache.html` with a newer copy and run `bash build.sh` again. Your data isn't affected.

## Where data lives

`~/Library/Application Support/PatchCache/patchcache-data.json` (the app menu has **Show Data File in Finder**).
Use **Back Up…** / **Restore…** from the patchbay title menu for portable copies.

## Without building

`PatchCache.html` also runs on its own in any desktop browser. In that case data is kept in the browser, so back up regularly.

## Files

| File | What it is |
| --- | --- |
| `PatchCache.html` | The whole app (UI + logic) in one file |
| `main.swift` | Native Mac window around the page; saves data to a file |
| `build.sh` | Compiles the app and packages `patchCache.app` |
| `AppIcon.iconset/` | App icon |
