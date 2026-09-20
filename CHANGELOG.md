# Changelog

## [1.1.2] - 2026-09-20

- Mobs whose name could not be read when looted (common in dungeons) are named later from nameplates, from your target after combat, or from the "X dies, you gain N experience" line when it is unambiguous
- Right-click a mob header to rename it yourself; the name sticks across sessions and history
- Loot other players pick up is now ignored by default; turn on "Track loot other players pick up" in Settings to see it dimmed under the mob again

## [1.1.1] - 2026-09-19

- Quality borders in the flat style are now a proper full-size frame around the icon (the template's overlay was collapsing into a tiny stamp)
- Narrow windows no longer overlap: tool icons live in the title bar, tabs and Restart Session share row two, and the summary wraps instead of clipping

## [1.1.0] - 2026-09-18

- New default look: flat dark panels with a purple accent, logo in the title bar; the classic Blizzard window style stays available in Settings
- Party members' pickups are attributed to the corpse they are looting and shown dimmed; coin splits are credited to that mob too
- Loot with no mob behind it is listed under "Other loot" instead of being dropped
- Rates show real coin icons; the summary line no longer wraps
- Escape closes the full window (not the compact strip); the close button works in combat
- Zero vendor prices count as known prices
- Login line reports what was loaded from disk

## [1.0.0] - 2026-09-18

Initial release for World of Warcraft: Forever.

- Always-on kill, loot and coin tracking with exact per-corpse attribution from the loot window
- This Session (per character, survives reload/relog) and All Time (account-wide) views
- Live gold/hour and kills/hour, compact strip mode
- Per-mob sections with 3D portraits, collapsible, resettable
- Right-click item filtering, sort by recent activity or value
- Group-aware: your coin share, roll wins, other players' pickups shown dimmed
- Vendor pricing with pluggable auction-house providers (Auctionator adapter included)
- Session history with auto-labels
- Settings panel integration, addon compartment entry, optional minimap button
- Headless test suite
