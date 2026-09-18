# LootLedger — Design

**Target:** World of Warcraft: Forever (client 1.60.x, `## Interface: 16001`, Mainline 12.1.5 API surface with the Midnight addon restrictions).
**Status:** approved design, 2026-09-17.

## 1. What it is

LootLedger is a gold-per-hour and loot tracker. It runs continuously in the background from the moment you log in: every corpse you loot, every item, every coin drop is attributed to the mob it came from, valued (vendor price or an auction-house price provider, whichever is higher), and rolled into a live gold/hour rate. A window shows a persistent per-mob loot history: each mob with its kill count, total value, a portrait, and a grid of everything it has dropped.

### Goals

- Zero-setup, always-on tracking; **This Session** survives `/reload` and relog.
- Exact attribution of loot to the mob that dropped it (no guessing from your target).
- Correct behaviour in groups: your share of coin, your roll wins, other players' pickups shown but not counted.
- Pricing that starts useful with nothing installed (vendor price) and gets better when an AH addon is present, through a provider interface anyone can extend.
- A UI that looks like a native part of the modern client.
- Headless-testable core: everything that isn't a frame runs under a plain Lua 5.1 interpreter.

### Non-goals

- Counting kills you never loot (see §4.1 — a kill is an opened corpse).
- Scanning the auction house ourselves.
- Any dependency on combat log data (the client forbids it — see §2).
- Libraries. The addon is self-contained.

## 2. Platform facts this design relies on

Verified in-game on build 1.60.1.69893 with a throwaway probe addon:

| Fact | Consequence |
|---|---|
| `WOW_PROJECT_ID == 1`; `C_Item`, `C_AddOns`, `C_PartyInfo`, `C_TooltipInfo`, `C_Secrets`, `Settings`, `AddonCompartmentFrame`, `EditModeManagerFrame`, `ScrollUtil`, `MinimalScrollBar`, `WowScrollBoxList`, `BackdropTemplate`, `ItemButtonTemplate`-era templates all exist. Legacy globals `GetItemInfo`, `IsAddOnLoaded`, `GetLootMethod`, `GetCoinTextureString` are **nil**. | Use the `C_*` namespaces exclusively. |
| Registering `COMBAT_LOG_EVENT` / `COMBAT_LOG_EVENT_UNFILTERED` raises the "blocked from an action only available to the Blizzard UI" dialog and `RegisterEvent` returns `false`. | Never register them, not even inside `pcall`. |
| Secret values exist (`C_Secrets.HasSecretRestrictions()` is true) but in open-world combat `ShouldUnitIdentityBeSecret(unit)` was `false`; `UnitName`, `UnitGUID`, `UnitIsDead`, `UnitIsTapDenied`, loot-source GUIDs and chat text were all plain, including while looting mid-fight. | Guard every read with `issecretvalue`; design so a secret only loses data, never errors. |
| Loot event order with auto-loot: `LOOT_READY` → `LOOT_OPENED` → `LOOT_READY` (again) → `LOOT_SLOT_CLEARED` per slot (can repeat for the same slot) → `LOOT_CLOSED` (twice) → **then** `CHAT_MSG_LOOT` "You receive loot: …" → `PLAYER_MONEY` → `CHAT_MSG_MONEY` "You loot 16 Copper" (~1 s later). | Snapshot the window at the first `LOOT_READY`; chat receipts must be matched against a queue that outlives the window. |
| `GetLootSourceInfo(slot)` → `guid, quantity, guid2, quantity2, …`. For coin slots the quantity **is the copper amount**. `GetLootSlotType`: 1 item, 2 money, 3 currency. `GetLootSlotLink` is a full link for items, nothing for coin. After a slot is cleared, `GetLootSlotLink` returns an empty link. | Per-slot exact source; read link/name only from the snapshot. |
| Creature GUID format `Creature-0-<server>-<instance>-<zone>-<npcID>-<spawnUID>`; npcID is field 6 and is stable across spawns. | Key mob records by npcID. |
| Name resolution: `UnitTokenFromGUID(guid)` returned `target`/`nameplateN` for corpses and live mobs; `C_TooltipInfo.GetHyperlink("unit:" .. guid)` returned the name as `lines[1].leftText` for every creature and player seen. | Two independent name paths plus a persistent cache. |
| Item links: `\|cnIQ1:\|Hitem:159::::::::6:1485:::::::::\|h[Refreshing Spring Water]\|h\|r` — colour is a named-colour code; item string fields: `item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel:specID:…`. `C_Item.GetItemInfo` returns 18 values, sell price is #11; `C_Item.GetItemInfoInstant` is synchronous (itemID, type, subtype, equipLoc, icon, classID, subclassID). | Parse suffix from field 8; icons never wait on async data. |
| Quest rewards arrive as `CHAT_MSG_LOOT` "You receive item: …" (`LOOT_ITEM_PUSHED_SELF`). | Must be excluded from loot. |
| `CHAT_MSG_COMBAT_XP_GAIN` "X dies, you gain N experience." fires at death while levelling. | Not used (absent at max level); noted for future ideas only. |
| Creating an `EditBox` at load steals keyboard focus. | Create UI lazily and never with auto-focus. |

Global strings captured (enUS) — patterns are compiled from these at runtime, never hardcoded:

```
LOOT_ITEM_SELF                    "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE           "You receive loot: %sx%d"
LOOT_ITEM                         "%s receives loot: %s."
LOOT_ITEM_MULTIPLE                "%s receives loot: %sx%d."
LOOT_ITEM_PUSHED_SELF             "You receive item: %s"            (excluded)
LOOT_ITEM_PUSHED_SELF_MULTIPLE    "You receive item: %sx%d"         (excluded)
LOOT_ROLL_YOU_WON                 "|HlootHistory:%d|h[Loot]|h: You won: %s"
LOOT_ROLL_YOU_WON_NO_SPAM_NEED    "|HlootHistory:%d|h[Loot]|h: You (Need - %d, Main-Spec) Won: %s"
LOOT_ROLL_YOU_WON_NO_SPAM_GREED   "|HlootHistory:%d|h[Loot]|h: You (Greed - %d) Won: %s"
LOOT_ROLL_WON                     "|HlootHistory:%d|h[Loot]|h: %s won: %s"
LOOT_ROLL_WON_NO_SPAM_NEED        "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Main-Spec) Won: %s"
LOOT_ROLL_WON_NO_SPAM_GREED       "|HlootHistory:%d|h[Loot]|h: %s (Greed - %d) Won: %s"
YOU_LOOT_MONEY                    "You loot %s"
YOU_LOOT_MONEY_GUILD              "You loot %s (%s deposited to guild bank)"
LOOT_MONEY_SPLIT                  "Your share of the loot is %s."
LOOT_MONEY_SPLIT_GUILD            "Your share of the loot is %s. (%s deposited to guild bank)"
GOLD_AMOUNT / SILVER_AMOUNT / COPPER_AMOUNT   "%d Gold" / "%d Silver" / "%d Copper"
```

## 3. Architecture

### 3.1 Files

All files share the addon-private namespace (`local ADDON_NAME, LL = ...`). Load order is the `.toc` order below.

| File | Responsibility |
|---|---|
| `LootLedger.toc` | `## Interface: 16001`, `## SavedVariables: LootLedgerDB`, `## SavedVariablesPerCharacter: LootLedgerCharDB`, `## OptionalDeps: Auctionator, Auctioneer`, `## AddonCompartmentFunc: LootLedger_OnCompartmentClick`, `## IconTexture: Interface\Icons\INV_Misc_Coin_02` |
| `Core.lua` | namespace, `LL.Print`, `LL.Plain` (secret guard), event bus (`LL.On`/`LL.Fire`), DB init + versioned migration, money formatting helpers |
| `Items.lua` | link parsing → `itemKey`, item-string normalisation, cached `GetItemInfoInstant`/`GetItemInfo` access with async load requests |
| `Guid.lua` | GUID parsing (`type`, `npcID`), name resolution chain, learned-name cache |
| `Session.lua` | live session lifecycle, logged-in clock, restart, history entries |
| `Ledger.lua` | per-mob records (all-time + session mirror): kills, coin, items, unclaimed; reset per mob / all; filter list |
| `Tracker.lua` | the event engine (§5) |
| `Pricing.lua` | provider registry, vendor provider, `GetBestPrice`, price memo |
| `Pricing_Auctionator.lua` | Auctionator adapter |
| `Pricing_Auctioneer.lua` | Auctioneer adapter (detection + single price function to fill in once its Forever API is known) |
| `Report.lua` | pure view model: ledger + pricing + filters → sorted sections, entries, totals, rates |
| `Widgets.lua` | small helpers for creating templated frames (tabs, icon buttons, portrait, money text) |
| `UI_MainWindow.lua` | main window, compact strip, ScrollBox element templates |
| `UI_Settings.lua` | Settings-panel canvas category |
| `UI_History.lua` | history window |
| `UI_Minimap.lua` | compartment entry + optional minimap button |
| `Commands.lua` | `/ll` |
| `tests/` | headless test suite (§9) |
| `README.md`, `CHANGELOG.md`, `LICENSE` (MIT) | docs |

No fonts or textures are bundled; everything visual comes from Blizzard templates and atlases.

### 3.2 Event bus

`LL.On(name, fn)` / `LL.Fire(name, ...)`. Events: `LEDGER_CHANGED`, `SESSION_CHANGED`, `PRICES_CHANGED`, `FILTERS_CHANGED`, `SETTINGS_CHANGED`. Data code never references UI; UI subscribes and coalesces refreshes to the next frame (`C_Timer.After(0, …)` with a dirty flag).

### 3.3 Secret-value guard

`LL.Plain(v)` returns `v` unless `issecretvalue` exists and reports it secret, in which case `nil`. Every value that originates from an event payload or a unit/loot/chat API passes through it before any comparison, string operation, or use as a table key. Table-valued results are checked with `issecrettable` where available.

## 4. Data model

### 4.1 Identity

- **Mob key:** `npcID` (number) from the creature GUID. Display name is metadata (`mobs[npcID].name`), filled from the name cache and updated in place whenever a better resolution arrives. Unresolved mobs render as `Unknown (#npcID)`.
- **Kill:** a distinct `Creature-` GUID seen as a loot source. Deduped by GUID with a 10-minute TTL.
- **Item key:** `"itemID:suffixID"` (suffix `0` when absent) parsed from the link. Random-suffix items are tracked and priced separately per suffix. The first full link seen for a key is stored for tooltips and pricing.
- **Coin:** a per-mob copper total; rendered in the grid as a coin entry valued at face.

### 4.2 SavedVariables

`LootLedgerDB` (account-wide):

```lua
{
  version   = 1,
  mobs      = { [npcID] = { name, kills, coin, items = { [itemKey] = { name, link, count } },
                            unclaimed = { [itemKey] = { name, link, count } }, lastUpdate } },
  npcNames  = { [npcID] = "Name" },
  filters   = { [itemKey] = true },
  settings  = { viewMode = "session"|"alltime", sortMode = "recent"|"value", compact = false,
                showUnclaimed = true, showPortraits = true, minimapButton = false, minimapAngle = 220,
                window = { point, x, y, width, height }, collapsed = { [npcID] = true } },
}
```

`LootLedgerCharDB` (per character):

```lua
{
  version = 1,
  session = { startTime, activeSeconds, lastResumeTime, kills, coin,
              items = { [itemKey] = { name, link, count } },
              mobs  = { [npcID] = { name, kills, coin, items = {…}, unclaimed = {…}, lastUpdate } } },
  history = { { label, startTime, endTime, activeSeconds, kills, coin, itemValue,
                topMobs = { {npcID, name, value, kills}, … ≤5 }, topItems = { {itemKey, name, count, value}, … ≤10 } }, … },  -- newest first, ≤100
}
```

Both tables carry `version`; `Core.lua` runs forward migrations at `ADDON_LOADED` and fills defaults with a deep-default merge so new fields never need per-site `or {}` guards.

## 5. Tracking engine (`Tracker.lua`)

Registered events: `LOOT_READY`, `LOOT_OPENED`, `LOOT_SLOT_CLEARED`, `LOOT_CLOSED`, `CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`, `ITEM_DATA_LOAD_RESULT`.

### 5.1 Loot window snapshot

On the first `LOOT_READY` (or `LOOT_OPENED` if no snapshot exists) build:

```lua
snapshot = { openedAt = GetTime(), slots = { [slot] = {
  kind = "item"|"coin"|"currency", link, itemKey, name, qty, copper, guid, guidType, npcID, cleared = false } } }
```

from `GetNumLootItems`, `GetLootSlotType`, `GetLootSlotInfo`, `GetLootSlotLink`, `GetLootSourceInfo`. Only the first source pair of a slot is used for attribution; every distinct source GUID is considered for kills. Duplicate `LOOT_READY`s while a snapshot is open are ignored. `LOOT_CLOSED` discards the snapshot.

For each distinct `Creature-` GUID in the snapshot not present in `recentCorpses`: record `recentCorpses[guid] = now` and call `Ledger.RecordKill(npcID, name)`. `GameObject-`, `Item-`, `Vehicle-` and other sources are not kills; loot from them is credited to the session totals without a mob.

### 5.2 Slot cleared

`LOOT_SLOT_CLEARED(slot)`: if the snapshot has that slot and it isn't already `cleared`, mark it and push to a pending queue:

- items → `pendingItems`: `{ itemKey, qty, npcID, t }`
- coin → `pendingCoin`: `{ copper, npcID, t }`

Entries expire after 15 s (purged lazily on each push/pop).

### 5.3 Chat receipts

`CHAT_MSG_LOOT(text, playerName, …, playerGUID)` — `text` guarded; classified by matching compiled patterns in this order:

1. **Own receipt:** `LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_SELF`, `LOOT_ROLL_YOU_WON_NO_SPAM_NEED`, `LOOT_ROLL_YOU_WON_NO_SPAM_GREED`, `LOOT_ROLL_YOU_WON`.
   Parse link → `itemKey`, name, qty (default 1). Drop if filtered. Attribution: pop the oldest `pendingItems` entry with the same `itemKey`; else, for roll wins only, the most recently opened corpse within 5 minutes (`lastCorpse`); else unattributed. `Ledger.RecordItem(npcID?, itemKey, name, link, qty)`.
2. **Other player's:** `LOOT_ITEM_MULTIPLE`, `LOOT_ITEM`, `LOOT_ROLL_WON_NO_SPAM_*`, `LOOT_ROLL_WON`. Same attribution; `Ledger.RecordUnclaimed(npcID?, itemKey, name, link, qty)`.
3. Anything else is ignored (pushed/created/refunded items, roll participation lines, passes).

Pattern compilation: escape magic characters in the global string, replace `%s` with `(.-)` and `%d` with `(%d+)`, anchor with `^…$`. Multi-item patterns are tried before their single-item prefixes.

### 5.4 Coin receipts

`CHAT_MSG_MONEY(text)`: must match `YOU_LOOT_MONEY`, `YOU_LOOT_MONEY_GUILD`, `LOOT_MONEY_SPLIT` or `LOOT_MONEY_SPLIT_GUILD`. Copper is the sum of all `GOLD_AMOUNT`/`SILVER_AMOUNT`/`COPPER_AMOUNT` matches inside the captured money text. Attribution: pop the oldest `pendingCoin`. `Ledger.RecordCoin(npcID?, copper)`. Crediting the chat amount (not the slot amount) makes group splits correct.

### 5.5 Names

`Guid.Resolve(guid, npcID)`:

1. `npcNames[npcID]`
2. `UnitTokenFromGUID(guid)` → `UnitName(token)` (guarded)
3. `C_TooltipInfo.GetHyperlink("unit:" .. guid)` → `lines[1].leftText` (guarded; wrapped in `pcall`)
4. `nil`

Any success writes `npcNames[npcID]` and, if a mob record exists without a name, fills it and fires `LEDGER_CHANGED`. `PLAYER_TARGET_CHANGED` / `UPDATE_MOUSEOVER_UNIT` (throttled to 4/s) learn `Creature-` names into the cache opportunistically.

### 5.6 Sessions (`Session.lua`)

- `Start()` creates a new session table in `LootLedgerCharDB.session` (`startTime = time()`, `activeSeconds = 0`, `lastResumeTime = time()`).
- `Resume()` at `PLAYER_LOGIN` sets `lastResumeTime = time()`; `Suspend()` at `PLAYER_LOGOUT` folds `time() - lastResumeTime` into `activeSeconds`.
- `GetActiveSeconds()` = `activeSeconds + (time() - lastResumeTime)`; every duration and rate reads this.
- `Restart()` → `Suspend()`, build a history entry (label: `GetInstanceInfo()` name when inside an instance, else the top-kills mob name, else "Session"), unshift into `history`, trim to 100, then `Start()`.
- `ResetAll()` clears `mobs`, `session`, `history`, `npcNames` stays.

### 5.7 Ledger (`Ledger.lua`)

Every record function writes both the all-time record (`LootLedgerDB.mobs[npcID]`) and the session mirror (`LootLedgerCharDB.session.mobs[npcID]`), bumps `lastUpdate`, updates session totals (`kills`, `coin`, `items`), and fires `LEDGER_CHANGED`. `ResetMob(npcID)` removes the mob from both. Filters are enforced twice: at record time (new pickups of a filtered key are dropped) and at report time (existing records with a filtered key are skipped), so filtering an item removes it from the window immediately without mutating history.

## 6. Pricing (`Pricing.lua`)

```lua
LL.Pricing.Register({ id, label, priority, IsAvailable = function() end, GetPrice = function(itemKey, link, itemID) end })
LL.Pricing.GetBestPrice(itemKey, link) --> copper|nil, label|nil
```

- Result = max over the vendor price and every available provider. Memoised per `itemKey`; memo cleared on `ITEM_DATA_LOAD_RESULT` and when a provider announces an update (`PRICES_CHANGED` fired either way).
- **Vendor provider** (built in): `C_Item.GetItemInfo(link)` sell price. On nil, `C_Item.RequestLoadItemDataByID(itemID)` once; the load event triggers the memo flush.
- **Quality 0 (grey) items are vendor-only**; providers are not consulted.
- **Auctionator adapter**: available when `C_AddOns.IsAddOnLoaded("Auctionator")` and `Auctionator.API.v1.GetAuctionPriceByItemLink` exist; price = that call with caller id `"LootLedger"`.
- **Auctioneer adapter**: available when `C_AddOns.IsAddOnLoaded("Auctioneer")` and the price function is present; the adapter file contains exactly one function to wire once the Forever build's API is known, and reports itself unavailable until then.
- Providers are re-checked at `PLAYER_LOGIN` and on `/ll debug`.

## 7. Report (`Report.lua`)

Pure function of (ledger view, pricing, filters, settings):

```lua
Report.Build(scope)  -- scope = "session" | "alltime"
--> { sections = { { npcID, name, kills, value, coin, entries = { { kind="item"|"coin", itemKey, link, name, count, unitPrice, priceLabel, value, unclaimed=bool } … } } … },
--    totals = { kills, coin, itemValue, total, activeSeconds, goldPerHour, killsPerHour }, anyUnpriced = bool }
```

- Entries sorted by value desc (coin included), unclaimed entries after claimed ones and never valued; filtered keys skipped; unclaimed entries omitted entirely when `settings.showUnclaimed` is false.
- Sections sorted by `sortMode`: `recent` = `lastUpdate` desc, `value` = value desc then kills.
- Rates use `Session.GetActiveSeconds()`; below 60 s of activity rates show as "—".

Consumers: the main window, the compact strip, `/ll loot`, `/ll status`, history entry creation.

## 8. UI

Native modern look only: `PortraitFrameTemplate`, `ButtonFrameTemplate`, `UIPanelButtonTemplate`, Blizzard tab templates, `ItemButtonTemplate`, `ScrollBox` + `MinimalScrollBar`, `MenuUtil.CreateContextMenu`, `StaticPopupDialogs`, `C_CurrencyInfo.GetCoinTextureString`, default `GameFont*` fonts. Frames are created lazily on first use and never with keyboard focus.

### 8.1 Main window

`PortraitFrameTemplate`, portrait set to a coin icon, title "Loot Ledger". Movable by the title bar, resizable from a bottom-right grip (min 320×240), position/size persisted. Not in `UISpecialFrames`.

1. **Tab row:** This Session | All Time (Blizzard tabs). Right side, icon buttons with tooltips: Sort (recent/value), History, Settings, Reset All (confirm popup), Collapse.
2. **Summary line:** session — `Time · gold/hr · kills/hr · Total` with a Restart Session button (confirm); all-time — `Kills · Total value`.
3. **Body:** `ScrollBox` with a linear view over a flat element list produced from the report:
   - **Mob header element:** portrait (§8.2), collapse arrow, name, `×kills`, value right-aligned. Left-click toggles collapse (persisted per npcID); right-click → context menu *Reset this mob* (confirm).
   - **Icon-row element:** up to N `ItemButtonTemplate` buttons per row (N from the current width, recomputed on resize). Quality border via `SetItemButtonQuality`, count via `SetItemButtonCount`; coin entry uses the coin icon with the amount as count text; unclaimed entries desaturated at 50% alpha. Hover → `GameTooltip:SetHyperlink(link)` plus lines `Looted ×N`, `Unit price (label)`, `Total`. Right-click → context menu *Filter this item* (confirm).
   - Collapsed mobs contribute only their header element.

Refresh: on `LEDGER_CHANGED`/`PRICES_CHANGED`/`FILTERS_CHANGED`/`SETTINGS_CHANGED` set dirty; next frame rebuild the report, rebuild the element list, `ScrollBox:SetDataProvider` preserving scroll offset.

### 8.2 Mob portrait

A `PlayerModel` (`SetCreature(npcID)`, `SetPortraitZoom(1)`, static) inside a circular portrait ring atlas at the left of the header. If the model fails to load, a skull icon is shown and the model is retried when the mob's name resolves. Toggle `showPortraits`. The compact strip never shows portraits. Existence of `PlayerModel:SetCreature` is verified at first launch; absence degrades to the skull icon.

### 8.3 Compact strip

A single-row flat panel anchored at the window's saved point: `Time · Gold/hr · Kills/hr · Session gold`, an expand button, draggable. Toggling compact swaps which frame is shown; both persist to the same anchor.

### 8.4 Settings

`Settings.RegisterCanvasLayoutCategory` under AddOns → LootLedger: checkboxes for minimap button, show unclaimed loot, show mob portraits; the filtered-items list (icon, name, Remove) with Clear All; a button to open the window. The main window's Settings button calls `Settings.OpenToCategory`.

### 8.5 History window

`ButtonFrameTemplate`, in `UISpecialFrames`. `ScrollBox` list of history entries: `label · duration · total · gold/hr`; click prints the stored breakdown to chat; per-row × deletes (no confirm); Clear All (confirm).

### 8.6 Minimap

`LootLedger_OnCompartmentClick` toggles the window; the compartment tooltip shows session time, gold/hr and total. Optional classic minimap button (off by default): drag around the ring, angle persisted, same click behaviour.

## 9. Commands

`/ll`, `/lootledger`:

| Command | Effect |
|---|---|
| (none) | toggle window |
| `loot` | print session report |
| `status` | one-line status |
| `restart` | Restart Session (confirm) |
| `reset` | Reset All (confirm) |
| `history` | open history window |
| `filter` | print filtered items |
| `debug` | provider status + toggle event tracing (echoes each loot event the engine consumes) |
| `debugprice <id\|link>` | every provider's answer and the winner |
| `help` | list |

## 10. Testing

`tests/run.lua` (run with `luajit tests/run.lua` from the addon folder; the interpreter lives at `C:\Users\dillo\AppData\Local\Programs\LuaJIT\bin\luajit.exe`) loads `tests/wow_stub.lua`, then each addon file in `.toc` order with a fake `...` vararg, then every `tests/test_*.lua`. Minimal assertion helpers; non-zero exit on failure.

`wow_stub.lua` provides: `CreateFrame` (records registrations, `stub.FireEvent(name, ...)` dispatches), `C_Item.GetItemInfo`/`GetItemInfoInstant` from a fixture table (with a "not loaded yet" mode), loot APIs driven by `stub.SetLootWindow({...})`, the global strings from §2, `issecretvalue`/`issecrettable` with `stub.MakeSecret(v)`, `strsplit`, `time`/`GetTime` under test control, `C_Timer.After` (queued, `stub.RunTimers()`), `UnitTokenFromGUID`/`UnitName`/`C_TooltipInfo.GetHyperlink` from a unit fixture, `GetInstanceInfo`, `C_AddOns.IsAddOnLoaded`.

Test files:

- `test_items.lua` — link parsing, suffix, itemKey, normalisation.
- `test_chat.lua` — every pattern class incl. no-spam variants, pushed/created/refund/roll-lines ignored, locale-independence (patterns built from swapped strings).
- `test_money.lua` — copper parsing for gold/silver/copper combinations, guild-bank variants, non-matching text ignored.
- `test_guid.lua` — npcID extraction, non-creature types, resolution chain order and caching.
- `test_tracker.lua` — snapshot/dedupe, duplicate READY/CLEARED, pending queue FIFO + TTL, attribution fallbacks, unattributed loot, non-creature sources, secret-value inputs cause no error and no record.
- `test_session.lua` — clock across suspend/resume, restart, history label/cap.
- `test_ledger.lua` — record/reset/filter semantics, all-time vs session mirror.
- `test_pricing.lua` — max across providers, grey vendor-only, unavailable providers, memo flush.
- `test_report.lua` — sorting, coin entry, unclaimed ordering, rates threshold.
- `test_db.lua` — defaults, migration from `version` 0 → 1, per-character vs account split.
- `test_replay.lua` — drives the engine through the recorded probe session (`tests/fixtures/probe_session.lua`) and asserts the exact resulting ledger.

UI is verified in-game with `/ll debug` tracing and screenshots.

## 11. Repository and process

- Repository root is the addon folder. `.gitignore` excludes editor/OS noise. MIT `LICENSE`.
- No commits or pushes without an explicit request.
- The `LootLedgerProbe` folder is deleted once the tracker is verified in-game.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Instanced/encounter content makes loot GUIDs or chat text secret | Guards drop the value; loot counts toward totals unattributed; kills may be missed — acceptable degradation, no errors. |
| `PlayerModel:SetCreature` missing or creature not cached | Skull icon fallback, retry on name resolution. |
| Group-loot behaviour untested on this client | Roll patterns compiled from live strings; 5-minute `lastCorpse` fallback; tracing command to diagnose. |
| Auctioneer API unknown for Forever | Adapter reports unavailable until its single function is wired. |
| Chat receipt arrives with no matching pending entry (e.g. window never observed) | Counted in session totals, unattributed. |
