-- Forever's Auction House over Blizzard's own AuctionFrame (NpcKit.lua): metal portrait frame showing the auctioneer, "Auction House" as the title, the Browse / Bids / Auctions tabs under
-- the frame, and a layout of our own for each page, 832 x 462 (A.LAYOUT is the one table: the code places from it, the specs check it):
--   Browse    search row (name + history, level range, quality, usable, Search / Reset) | filter column + three toggles | sort headers over 8 result rows | pager | Bid price, Bid / Buyout / Close
--   Bids      sort headers over 9 rows | Bid price, Bid / Buyout / Close
--   Auctions  create panel (item, stack size, stacks, duration, starting and buyout price, deposit and its warning, Create / Undercut) | headers over 9 own auctions | value, Cancel / Close
-- The client's rows, item buttons, price inputs (gold / silver / copper boxes), duration radios and every script stay the client's; the text of each result row is drawn by AuctionTools.lua
-- from the client's own list API (so the columns line up with our headers and carry per-unit prices, time colours and our marks). Blizzard_AuctionUI loads on demand: skinned on its ADDON_LOADED.
-- Client facts (Gethe/wow-ui-source 2.5.3 Interface_TBC/AddOns/Blizzard_AuctionUI/Blizzard_AuctionUI.xml): AuctionFrame 832 x 447 (pages AuctionFrameBrowse / Bid / Auctions), AuctionFrameTab1..3,
-- Browse: AuctionFilterButton1..15 + BrowseFilterScrollFrame, BrowseButton1..8 + BrowseScrollFrame, the five Browse*Sort headers, BrowseName / MinLevel / MaxLevel, BrowseDropDown,
-- IsUsable / ShowOnPlayer check buttons; Bid: BidButton1..9, BidScrollFrame; Auctions: AuctionsButton1..9, AuctionsScrollFrame, AuctionsItemButton, the create / cancel buttons.
AFUI = AFUI or {}
local A = {}
AFUI.AuctionFrame = A

local function seq(prefix, n) return AFUI.NpcKit.Numbered(prefix, n) end
local function join(...)
  local out = {}
  for _, l in ipairs({ ... }) do for _, v in ipairs(l) do out[#out + 1] = v end end
  return out
end

A.W, A.H = 832, 462
A.PAGES = { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" }
A.PAGE_TITLES = { "BrowseTitle", "BidTitle", "AuctionsTitle" } -- the page headings: the window title says it
A.SORTS = { "BrowseQualitySort", "BrowseLevelSort", "BrowseDurationSort", "BrowseHighBidderSort", "BrowseCurrentBidSort", "BidQualitySort", "BidLevelSort", "BidDurationSort",
  "BidBuyoutSort", "BidStatusSort", "BidBidSort", "AuctionsQualitySort", "AuctionsDurationSort", "AuctionsHighBidderSort", "AuctionsBidSort" }
A.LISTS = { { "BrowseButton1", "BrowseButton8" }, { "BidButton1", "BidButton9" }, { "AuctionsButton1", "AuctionsButton9" } }

---------------------------------------------------------------- layout
-- { name, x, y, w, h }: offsets (y down) from the top left of the page frame. "plate:" = a dark panel of ours; "~" = the client sizes it (anchor only).
local function rows(prefix, n, x, y, w)
  local out = {}
  for i = 1, n do out[i] = { prefix .. i, x, y + (i - 1) * 37, w, 37 } end
  return out
end
local function filters()
  local out = {}
  for i = 1, 15 do out[i] = { "AuctionFilterButton" .. i, 14, 64 + (i - 1) * 20, 134, 20 } end
  return out
end
A.LAYOUT = {
  window = { { "~AuctionFrameMoneyFrame", 14, 444, 160, 14 } },
  browse = join({
    { "BrowseName", 70, 32, 150, 22 }, { "AFUI_AHHistory", 230, 32, 22, 22 },
    { "AFUI_AHLvlLabel", 262, 36, 22, 14 }, { "BrowseMinLevel", 288, 32, 30, 22 }, { "AFUI_AHDash", 322, 36, 8, 14 }, { "BrowseMaxLevel", 334, 32, 30, 22 },
    { "~BrowseDropDown", 358, 30, 120, 32 }, { "IsUsableCheckButton", 520, 34, 20, 20 },
    { "BrowseSearchButton", 640, 31, 86, 24 }, { "BrowseResetButton", 734, 31, 88, 24 },
    { "plate:AFUI_AHFilterPlate", 10, 60, 168, 310 }, { "BrowseFilterScrollFrame", 14, 64, 134, 300 },
  }, filters(), {
    { "AFUI_AHPerUnit", 12, 376, 20, 20 }, { "AFUI_AHHideOwn", 12, 398, 20, 20 }, { "ShowOnPlayerCheckButton", 12, 420, 20, 20 },
    { "plate:AFUI_AHBrowsePlate", 186, 60, 636, 324 },
    { "BrowseQualitySort", 190, 62, 226, 18 }, { "BrowseLevelSort", 416, 62, 36, 18 }, { "BrowseDurationSort", 452, 62, 62, 18 },
    { "BrowseHighBidderSort", 514, 62, 94, 18 }, { "BrowseCurrentBidSort", 608, 62, 92, 18 }, { "AFUI_AHBuyoutHeader", 700, 62, 90, 18 },
  }, rows("BrowseButton", 8, 190, 84, 600), {
    { "BrowseScrollFrame", 190, 84, 600, 296 }, { "~BrowseNoResultsText", 190, 220, 600, 20 },
    { "BrowsePrevPageButton", 186, 390, 28, 24 }, { "AFUI_AHPage", 218, 394, 200, 16 }, { "BrowseNextPageButton", 422, 390, 28, 24 },
    { "AFUI_AHBidLabel", 186, 430, 34, 16 }, { "~BrowseBidPrice", 224, 424, 250, 24 },
    { "BrowseBidButton", 574, 424, 80, 26 }, { "BrowseBuyoutButton", 658, 424, 80, 26 }, { "BrowseCloseButton", 742, 424, 80, 26 },
  }),
  bid = join({
    { "plate:AFUI_AHBidPlate", 10, 60, 812, 358 },
    { "BidQualitySort", 14, 62, 284, 18 }, { "BidLevelSort", 298, 62, 40, 18 }, { "BidDurationSort", 338, 62, 70, 18 },
    { "BidBuyoutSort", 408, 62, 150, 18 }, { "BidStatusSort", 558, 62, 100, 18 }, { "BidBidSort", 658, 62, 126, 18 },
  }, rows("BidButton", 9, 14, 84, 770), {
    { "BidScrollFrame", 14, 84, 770, 333 },
    { "BidBidButton", 574, 424, 80, 26 }, { "BidBuyoutButton", 658, 424, 80, 26 }, { "BidCloseButton", 742, 424, 80, 26 },
  }),
  auctions = join({
    { "plate:AFUI_AHSellPlate", 10, 60, 212, 358 }, { "plate:AFUI_AHMinePlate", 230, 60, 592, 358 },
    { "AFUI_AHItemLabel", 14, 62, 60, 12 }, { "AuctionsItemButton", 14, 76, 37, 37 }, { "~AuctionsItemText", 58, 80, 160, 30 },
    { "AFUI_AHStackLabel", 14, 120, 70, 14 }, { "AuctionsStackSizeEntry", 88, 116, 44, 22 }, { "AuctionsStackSizeMaxButton", 138, 116, 52, 22 },
    { "AFUI_AHStacksLabel", 14, 146, 70, 14 }, { "AuctionsNumStacksEntry", 88, 142, 44, 22 }, { "AuctionsNumStacksMaxButton", 138, 142, 52, 22 },
    { "AFUI_AHDurationLabel", 14, 172, 100, 12 },
    { "AuctionsShortAuctionButton", 14, 186, 20, 20 }, { "AuctionsMediumAuctionButton", 14, 206, 20, 20 }, { "AuctionsLongAuctionButton", 14, 226, 20, 20 },
    { "AFUI_AHStartLabel", 14, 250, 120, 12 }, { "~StartPrice", 14, 270, 190, 22 },
    { "AFUI_AHBuyoutLabel", 14, 298, 120, 12 }, { "~BuyoutPrice", 14, 316, 190, 22 },
    { "AFUI_AHDepositLabel", 14, 348, 48, 14 }, { "~AuctionsDepositMoneyFrame", 66, 348, 130, 14 }, { "AFUI_AHDepositWarn", 14, 366, 196, 22 },
    { "AuctionsCreateAuctionButton", 14, 390, 124, 26 }, { "AFUI_AHUndercut", 142, 390, 76, 26 },
    { "AuctionsQualitySort", 234, 62, 232, 18 }, { "AuctionsDurationSort", 466, 62, 68, 18 }, { "AuctionsHighBidderSort", 534, 62, 120, 18 }, { "AuctionsBidSort", 654, 62, 136, 18 },
  }, rows("AuctionsButton", 9, 234, 84, 556), {
    { "AuctionsScrollFrame", 234, 84, 556, 333 },
    { "AFUI_AHSummary", 234, 430, 360, 16 }, { "AuctionsCancelAuctionButton", 606, 424, 132, 26 }, { "AuctionsCloseButton", 742, 424, 80, 26 },
  }),
}
-- the Bids page has its own bid box and label (same place as Browse's)
A.LAYOUT.bid[#A.LAYOUT.bid + 1] = { "~BidBidPrice", 224, 424, 250, 24 }

local function place(f, host, r, keepSize)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", host, "TOPLEFT", r[2], -r[3])
  if not keepSize then f:SetWidth(r[4]); f:SetHeight(r[5]) end
end

local plates = {}
local function plate(host, name, r)
  local p = plates[name]
  if not p then
    p = CreateFrame("Frame", name, host)
    p:SetFrameLevel(host:GetFrameLevel()); p.afOwn = true
    if AFUI.WinKit and AFUI.WinKit.panel then AFUI.WinKit.panel(p) end
    plates[name] = p
  end
  place(p, host, r)
end

function A.Apply(page, host)
  host = host or ({ browse = _G.AuctionFrameBrowse, bid = _G.AuctionFrameBid, auctions = _G.AuctionFrameAuctions, window = _G.AuctionFrame })[page]
  if not host then return end
  for _, r in ipairs(A.LAYOUT[page]) do
    local name = r[1]
    if name:sub(1, 6) == "plate:" then plate(host, name:sub(7), r)
    else
      local keep = name:sub(1, 1) == "~"
      local f = _G[keep and name:sub(2) or name]
      if f then place(f, host, r, keep) end
    end
  end
end

-- Every FontString the client draws straight on a page goes (its labels sit where the old layout had them); `keep` lists the dynamic ones that stay.
-- Structural now (NpcKit.Sweep): every FontString / texture of a page and every child frame that is not listed in its layout and holds no control goes, whatever the client calls it; an
-- unlisted button / edit box / scroll frame stays so the page keeps working. `keep` = the dynamic FontStrings that stay.
local PAGE_HOST = { browse = "AuctionFrameBrowse", bid = "AuctionFrameBid", auctions = "AuctionFrameAuctions" }
local function quiet(page, keep, name)
  local N = AFUI.NpcKit
  if not (page and N and N.Sweep) then return end
  local names = {}
  for _, r in ipairs(A.LAYOUT[name] or {}) do local n = r[1]:gsub("^plate:", ""):gsub("^~", ""); names[n] = true end
  for k in pairs(keep) do names[k] = true end
  return N.Sweep(page, { keep = names, keepText = names, textures = true, interactive = true })
end

function A.Sweep()
  quiet(_G.AuctionFrameBrowse, { BrowseNoResultsText = true, BrowseSearchDotsText = true, BrowseSearchCountText = true }, "browse")
  quiet(_G.AuctionFrameBid, {}, "bid")
  quiet(_G.AuctionFrameAuctions, { AuctionsItemText = true }, "auctions")
end

function A.Spec()
  return {
    frame = "AuctionFrame", close = "AuctionFrameCloseButton", move = "auction", npc = true, icon = "Interface\\Icons\\INV_Hammer_20",
    size = { w = A.W, h = A.H, cut = 0 },
    bare = A.PAGES,
    tabs = seq("AuctionFrameTab", 3),
    headers = A.SORTS,
    buttons = { "BrowseSearchButton", "BrowseResetButton", "BrowseCloseButton", "BrowseBuyoutButton", "BrowseBidButton", "BidCloseButton", "BidBuyoutButton", "BidBidButton",
      "AuctionsCreateAuctionButton", "AuctionsCancelAuctionButton", "AuctionsCloseButton", "AuctionsStackSizeMaxButton", "AuctionsNumStacksMaxButton" },
    edits = { "BrowseName", "BrowseMinLevel", "BrowseMaxLevel", "AuctionsStackSizeEntry", "AuctionsNumStacksEntry", "BrowseBidPriceGold", "BrowseBidPriceSilver", "BrowseBidPriceCopper",
      "BidBidPriceGold", "BidBidPriceSilver", "BidBidPriceCopper", "StartPriceGold", "StartPriceSilver", "StartPriceCopper", "BuyoutPriceGold", "BuyoutPriceSilver", "BuyoutPriceCopper" },
    checks = { "IsUsableCheckButton", "ShowOnPlayerCheckButton" },
    slots = { "AuctionsItemButton" }, -- the item to sell: the bags' empty slot behind it
    dropdowns = { "BrowseDropDown" },
    rows = join(seq("BrowseButton", 8), seq("BidButton", 9), seq("AuctionsButton", 9), seq("AuctionFilterButton", 15)),
    strip = join(seq("BrowseButton", 8), seq("BidButton", 9), seq("AuctionsButton", 9)), -- the name bar art of each result row
    scrolls = { { "BrowseFilterScrollFrameScrollBar", 4 }, { "BrowseScrollFrameScrollBar", 6 }, { "BidScrollFrameScrollBar", 6 }, { "AuctionsScrollFrameScrollBar", 6 } },
    before = A.Before,
    after = A.After,
  }
end

-- Layout first (the scroll bars read their lists' final size), then the helper controls.
function A.Before(f)
  for _, n in ipairs(A.PAGE_TITLES) do local t = _G[n]; if t and t.SetAlpha then t:SetAlpha(0) end end
  AFUI.NpcKit.Title(f, _G.BUTTON_LAG_AUCTIONHOUSE or "Auction House")
  -- the filter column's own bars (AuctionFilterButton*: a brown tab art in the normal texture) go; the row glow marks the hover / selection
  for i = 1, 15 do
    local b = _G["AuctionFilterButton" .. i]
    if b then local nt = b.GetNormalTexture and b:GetNormalTexture(); if nt then nt:SetAlpha(0) end end
  end
  if AFUI.AuctionTools then AFUI.AuctionTools.Setup() end
  for _, p in ipairs({ "window", "browse", "bid", "auctions" }) do A.Apply(p) end
  A.Sweep()
  local n = _G.BrowseNoResultsText; if n and n.SetJustifyH then n:SetJustifyH("CENTER") end
  local it = _G.AuctionsItemText; if it and it.SetJustifyH then it:SetJustifyH("LEFT") end
end

function A.After()
  for _, p in ipairs({ "window", "browse", "bid", "auctions" }) do A.Apply(p) end -- WinKit.button sets its own height: the sizes of our layout go back on
  for _, n in ipairs(A.PAGES) do local p = _G[n]; if p and not p.afSweepHook then p.afSweepHook = true; p:HookScript("OnShow", A.Sweep) end end -- the client may show its own pieces again
end

-- /afui ahreport: what the sweep hid or kept on each Auction House page (paste it when a page looks wrong on a real client).
function A.Report()
  local lines = AFUI.NpcKit.ReportLines({ "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" })
  if AFUI.Print then for _, l in ipairs(lines) do AFUI.Print(l) end end
  return lines
end
if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("ahreport", A.Report, "what the Auction House skin hid or kept (paste it when a page looks wrong)", "/afui ahreport")
end

function A.Enabled() return AFUI.ModuleEnabled("auction") end -- Settings > Windows (useAuction; the old auctionRestyle setting still counts)

function A.Setup()
  if A.done or not A.Enabled() or not _G.AuctionFrame then return end
  A.done = true
  AFUI.RunOutOfCombat(function() AFUI.NpcKit.Skin(A.Spec()) end)
end

AFUI.On("ADDON_LOADED", function(_, name) if name == "Blizzard_AuctionUI" then A.Setup() end end)
AFUI.RegisterModule("AuctionFrame", { OnLogin = A.Setup })
