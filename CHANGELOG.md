# Changelog

## 0.97 Beta (latest)

- **Trainer window fixed.** The skill list, its scroll bar and the skill texts were drawn outside the window. Every part is now placed inside the window and re-placed whenever the client reorders the list; the cost no longer collides with the coins. `/afui trainerreport` prints where each part is for bug reports. The vendor window also gets a guard so names and prices cannot drift out of their row.

## 0.96 Beta

- **Possession and override bars (e.g. Teron Gorefiend's ghost).** The main action bar now follows the client's override, possess, vehicle and shapeshift pages, so those abilities show on your main bar with your normal keys. The possess bar and its cancel button appear when the client provides them. `/afui bars` prints the page and slot diagnostic.

## 0.95 Beta

- **Aura filters for the raid-style party frames.** Choose what auras show: all, only mine, only a list, all except a list, or mine plus a list; only dispellable debuffs; hide permanent buffs; max icons and sorting. Built-in starter lists (healer HoTs, raid defensive cooldowns, utility buffs, TBC raid debuffs), a spell picker with spellbook suggestions, recently seen auras and target auras, export and import. Open it with /afui filters.
- **Windows page.** Settings > Windows has one switch for every window we draw, so you can keep Blizzard's own version of just that window. Off means completely native. Changes apply after a reload.
- **Chat switch fixed.** The Chat switch now honours your saved choice (it was read before saved data was loaded).
- **Nameplates.** Plates stay put (no sliding), a compact layout, and a new Organized mode that arranges crowds in a neat screen-aligned grid. Every level is shown by default. The error "Can't measure restricted regions" is fixed.
- **Bank and bags.** The bank opens as one combined window with a search bar and Clean Up. Choose the columns, slot size and spacing (gear button), a proper footer with the money inside the frame, red buttons, and the layout panel closes when you click outside it.
- **Mailbox and Auction House** have a full redesign with quality-of-life tools (Open All, Collect All, recent recipients, price per unit, undercut...). They are off by default: turn them on in Settings > Windows. The Send Mail tab was redone (real attachment count, thin boxes, bag-style empty slots, one Postage label, autocomplete left alone).
- **Bank and bags icons** redrawn: a broom (Clean Up), a cog (Layout), a proper key for the keyring (no longer stretched) and a magnifier, all centred inside the red buttons. Empty bank slots now show the same dark wing art as the bags.
- **Send Mail:** attachments are spread evenly in one row with a live count (Attachments 3/7), and the money controls are protected from being hidden (use /afui mailreport if anything is missing).
- Settings side tabs fit the window (the window is taller and the tab column scrolls if more pages are added).

## 0.94 Beta

- **Compatibility page.** Settings > Compatibility has one switch per part (Bags & Bank, Action bars, Unit frames, Party frames, Chat, Nameplates, Map & quest log, Tooltips) saying whether Aztra's Forever UI draws it. A part gives way by default to a known addon that draws the same thing (Bagnon, ElvUI, Bartender4, Grid2, Prat, TipTac ...), with one chat notice per character. Changes apply after /reload. Nothing is disabled behind your back.
- **Other addons keep their anchors.** Blizzard frames that other addons anchor to (PlayerFrame, TargetFrame, Minimap, ActionButton1, ChatFrame1 and many more) stay alive with the size and place of our frames. `/afui anchors` reports any mismatch.
- **Integrations:** ItemRack (minimap button above our ring), Pawn (tooltip lines in order, no duplicates), Questie, OmniCC (numbers not doubled), Masque / ButtonFacade; DBM, BigWigs, Details, Recount, Skada and WeakAuras are report-only.
- `/afui compat` prints a report you can paste into a bug report; `/afui compat notice` shows the clash notice again.
- Settings side tabs now squeeze to stay inside the window.

## 0.93 Beta

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
