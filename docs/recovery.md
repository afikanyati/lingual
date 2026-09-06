# Lingual recovery — September 4, 2026

The working repository is `/Users/afikanyati/Code/lingual`, outside Documents/iCloud Drive. The original folders were read and left in place.

| Source | State found | Decision |
| --- | --- | --- |
| GitHub `afikanyati/lingual` | `a33219e7bbc58293828428461813dd268bdd0cf4` | Cloned with history and the original `origin` remote. |
| `~/Documents/Diction Processor/lingual` | `07f6e463e1a07990aedc1c41c18e0ee170c6a97b`, April 22, 2021; one commit ahead of GitHub | Fetched locally and fast-forwarded the recovered checkout. This includes the newer selection, paste, and entry-list fixes. |
| Same folder, uncommitted edits | `Utils.swift`: omit silences enabled; `beethoven/PitchEngine.swift`: modern record-permission enum spelling | Preserved in the working files. Exact original patch is `.local/recovery/local-uncommitted.patch`. |
| `~/Documents/Diction Processor/diction-processor-v2` | `d3b38a1780ef6e7ce1bd6511496c3744a37b1c43`, December 15, 2020 | Older version; original retained in place. |

Recovered the untracked shared Xcode scheme. Preserved the old Podfile, lockfile and workspace under `.local/recovery/`. SwiftSVG was not imported or used anywhere in application code; the stale CocoaPods linker/build-phase references were removed so Xcode can build the app without installing unused pods. The original CocoaPods directory remains in Documents. The untracked `command/` directory contained only a nested Git repository and no working files; it is preserved under `.local/recovery/legacy-command-repository`.

Nothing has been committed, pushed, or deployed by this recovery.

## Apple Notes sources

All three are in **Verascope Design**:

- **Lingual - Master Product Document:** — the main product, debugging, and outstanding-work list.
- **Lingual 2.0:** — the concentrated reproduction notes for focus loss, headphone changes, removing selection, stopped-entry editing, fast recording, and soft speech.
- **Lingual Tests to Specify:** — the existing manual test inventory.

The separate note **• error ending note** contains no useful text body. **Common Bugs:** in Verascope Development is about the later website, not this Swift app. The original notes were not edited. Relevant local extracts are under `.local/notes/`, which is ignored by Git.
