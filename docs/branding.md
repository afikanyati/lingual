# Lingual branding

The React app uses the user's original assets copied from `/Users/afikanyati/Documents/Lingual/`. Copies live in `web/public/brand/` so the application does not depend on iCloud-hydrated files.

| Source asset | Web asset | Use |
| --- | --- | --- |
| `lingual-light.png` | `wordmark-light.png` | Original white wordmark on the navy sidebar |
| `lingual-dark.png` | `wordmark-dark.png` | Preserved matching wordmark for light surfaces |
| `lingual-logo-1024x1024.png` | `app-icon.png` | App icon, browser favicon, and Apple touch icon |

The PNG files are unmodified copies, displayed with their original proportions.

The six canonical colors come from `diction-processor/Utils.swift`. The original Swift values include `FF` for full opacity; the CSS values below omit that redundant alpha.

| Swift constant | Exact RGB value | Web use |
| --- | --- | --- |
| `LINGUAL_PURPLE` | `#7771C2` | Primary controls and active view buttons |
| `LINGUAL_RED` | `#D31900` | Recording indicator, Stop, and destructive buttons |
| `LINGUAL_ORANGE` | `#D87736` | Browser text selection, word highlights and unsaved indicator |
| `LINGUAL_DARK_PURPLE` | `#252533` | Background, chrome, and editor text |
| `LINGUAL_GRAY` | `#A6A9BF` | Secondary labels and supporting text |
| `LINGUAL_WHITE` | `#CACFE5` | Text and headings on dark surfaces |

The original landing page's plum (`#393346`) supplies raised panels. Pure white is retained for the writing surface and the original white wordmark; it does not replace the canonical pale-white token.

CSS variables in `web/src/styles.css` centralize the palette. Supporting tints improve text contrast and distinguish playback from selected words. The editor remains a white writing surface with navy text. The existing fonts and application behavior are unchanged.

The main Enable voice / Start entry action uses original orange `#D87736` with pure-white text and icons. Stop entry finishes recording and returns to listening only; the outlined Stop listening control turns the microphone off. Orange also remains the selection highlight. All orange backgrounds use the shared white `--on-orange` foreground, including hover, selection, and playback highlights. The editor no longer shows the decorative workspace, Thinking Room, personal-entry, headline, flow doodle, or version-tagline copy.
