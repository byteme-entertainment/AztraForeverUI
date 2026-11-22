# Changelog

## 0.93 Beta (latest)

- **Bank in one window.** The bank now opens as a single window in the combined-bags style (28 main slots, then your bank bags, bag slot row and money), instead of Blizzard's separate bank bag windows. It has a search bar and a **Clean Up** button that merges partial stacks and sorts the bank. Setting **Combine bank bags** (default on) brings the old look back when off. The bags' own Clean Up also merges partial stacks now.

## 0.92 Beta

- **Outfitter compatibility.** Outfitter's panel, button and tabs now sit in front of the character window and beside its mode tabs (they used to be drawn behind them), and are re-placed when the window opens, collapses or the scale changes. `/afui compat` prints the state of Outfitter's frames (and other known addons) so problems can be reported.

## 0.91 Beta

Fixes from the first round of tester reports, plus credits.

- **Bags open in combat.** The bag windows are now prepared outside combat, so opening them in combat just shows them.
- **Upgrade arrows (green) fixed.** They only appear for gear you can actually equip, that beats what you are wearing. They no longer show for everything when worn gear has not loaded, and they update when you equip something or level up.
- **Junk and unusable items.** Grey items with a vendor price are greyed out with a coin on top, as in Forever. Items you cannot use get a red tint. Both can be switched off in the settings.
- **Spellbook.** Hiding passive spells now re-flows the book with no empty gaps and re-counts the pages.
- **Stance, pet and possess bars can be hidden** (Edit Mode, "Hide Bar", or `/afui hidebar stance|pet|possess`).
- **Action bars can show 1 to 12 icons** (was 6 to 12). Icon padding can be 0, icon size and the generic Size slider go down to 25%, and the chat frame can be smaller.
- **Settings window.** The tab column no longer runs out of the window.
- **Mailbox and Auction House skins are off by default** (testers found them rough). You can turn them on from General, they are marked beta.
- **Quest Log key (L)** opens the map with the quest panel and closes it again with a second press. `/afui qlog` prints a short report if it still misbehaves.
- **Mounts tab** has a horse icon.
- **Credits and About.** The addon says it was specifically designed for Crusader-Storm. Rights now read 2026 ByteMe Entertainment and personal links were removed.
- **Game menu logo** has a new light sweep, a glow that follows the mouse and a smooth hover zoom.
- Many smaller robustness fixes from an audit (minimap addon buttons, map panning, quest log taint in combat, fonts on Korean and Chinese clients, saved-settings edge cases).

## 0.90 Beta

First public beta, made specifically for **Crusader-Storm**. Forever style unit frames, action bars, bags, character sheet, spellbook with a Mounts tab, talents, professions, map and quest log, social and guild windows, Group Finder, chat, tooltips with item comparison, dialogs and loot roll, vendor and trainer windows, Edit Mode with layouts, profiles, floating combat text, and a first-run wizard.
