# LootLedger

![LootLedger](https://raw.githubusercontent.com/dayightt/LootLedger---An-OSRS-Style-Loot-Tracker-for-WoWForever/main/docs/art/screenshot.png)

A gold-per-hour and loot tracker for **World of Warcraft: Forever**. It runs from the moment you log in: every corpse you loot, every item and every coin drop is attributed to the mob it came from, valued, and rolled into a live gold/hour rate - alongside a persistent per-mob loot history with a portrait of each mob and a grid of everything it has dropped.

## Install

1. Copy the `LootLedger` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
2. Enable it on the AddOns list.

That's it. Nothing to configure. If **Auctionator** is installed, auction prices are used automatically; without it, items are valued at their vendor price.

## Using it

- `/ll` opens the ledger. It's also in the minimap's addon menu, and an optional classic minimap button can be turned on in Settings.
- **This Session** and **All Time** tabs at the bottom. The session keeps running across `/reload` and relogs and is per character; All Time is shared across your characters.
- Each mob shows its kill count, total value, and a grid of drops. Hover an icon for the price breakdown; **right-click an icon** to filter that item out of tracking for good; **click a mob's header** to collapse it; **right-click a header** to reset just that mob.
- The clock/coin button switches between **most recently active** and **highest value** ordering.
- **Restart Session** archives the current stretch into **History** (auto-labelled with the instance you were in or your most-killed mob) and starts a new clock.
- The collapse button shrinks the window to a one-line strip: `time · gold/hr · kills/hr · total`.
- **Reset All** wipes everything, after asking.

Settings (Esc → Options → AddOns → LootLedger, or the gear button): minimap button, whether to show items other players picked up, mob portraits, and the list of filtered items.

## How it works

- **Kills and attribution** come from the loot window itself. When you open a corpse the client tells the addon exactly which creature each slot came from, so loot is never guessed from your target. A kill is a corpse you opened - one you never loot doesn't count, which is the right definition for gold per hour.
- **Groups:** the coin you're credited is your share, not the corpse total; items you win on a roll count for you; items other players pick up are shown dimmed under the mob and never counted toward your total.
- **Pricing:** the higher of vendor price and any available auction-house price. Grey items are always vendor price. Price providers are pluggable - `Pricing_Auctionator.lua` is one; add another file that calls `LL.Pricing.Register` and list it in the `.toc`.
- **No combat-log dependence.** The addon never reads the combat log, so it works under the client's addon restrictions and keeps working inside instances.

## Commands

| Command | |
|---|---|
| `/ll` | toggle the window |
| `/ll loot` | print this session's loot |
| `/ll alltime` | print the all-time ledger |
| `/ll status` | one-line status |
| `/ll restart` | archive this session and start a new one |
| `/ll reset` | wipe everything (asks first) |
| `/ll history` | open the session history |
| `/ll settings` | open the settings panel |
| `/ll filter` | list filtered items |
| `/ll debug` | price provider status; toggles event tracing |
| `/ll debugprice <itemID or link>` | show how an item is priced |

## Development

The non-UI code runs headless. From the addon folder:

```
luajit tests/run.lua
```

`tests/wow_stub.lua` fakes the small slice of the client API the addon uses; `tests/fixtures/probe_session.lua` is a real recorded loot session the engine is replayed through.

## License

MIT - see [LICENSE](LICENSE).
