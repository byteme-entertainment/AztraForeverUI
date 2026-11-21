-- Forever's Auction House over Blizzard's own AuctionFrame (NpcKit.lua): metal portrait frame showing the auctioneer, "Auction House" as the title, the Browse / Bids / Auctions
-- tabs under the frame, dark plates behind the filter column and the three result lists, gold sort headers, red Search / Reset / Bid / Buyout / Create / Cancel buttons, search-box art on
-- the name and level boxes, Forever check boxes and minimal scroll bars. The page art is hidden; rows, item buttons, the price inputs (gold / silver / copper boxes), the duration radio
-- buttons and every script stay the client's. Blizzard_AuctionUI is load on demand: skinned on its ADDON_LOADED.
-- Client facts (Gethe/wow-ui-source 2.5.3 Interface_TBC/AddOns/Blizzard_AuctionUI/Blizzard_AuctionUI.xml): AuctionFrame 832 x 447 (pages AuctionFrameBrowse / Bid / Auctions, 758 x 447), AuctionFrameTab1..3,
-- AuctionFrameCloseButton, Browse: AuctionFilterButton1..15 + BrowseFilterScrollFrame, BrowseButton1..8 + BrowseScrollFrame, the five Browse*Sort headers, BrowseName / MinLevel / MaxLevel,
-- BrowseDropDown, IsUsable / ShowOnPlayer check buttons; Bid: BidButton1..9, BidScrollFrame; Auctions: AuctionsButton1..9, AuctionsScrollFrame, AuctionsItemButton, the create / cancel buttons.
AFUI = AFUI or {}
local A = {}
AFUI.AuctionFrame = A

local function seq(prefix, n) return AFUI.NpcKit.Numbered(prefix, n) end
local function join(...)
  local out = {}
  for _, l in ipairs({ ... }) do for _, v in ipairs(l) do out[#out + 1] = v end end
  return out
end

A.PAGES = { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" }
A.PAGE_TITLES = { "BrowseTitle", "BidTitle", "AuctionsTitle" } -- the page headings: the window title says it
A.SORTS = { "BrowseQualitySort", "BrowseLevelSort", "BrowseDurationSort", "BrowseHighBidderSort", "BrowseCurrentBidSort", "BidQualitySort", "BidLevelSort", "BidDurationSort",
  "BidBuyoutSort", "BidStatusSort", "BidBidSort", "AuctionsQualitySort", "AuctionsDurationSort", "AuctionsHighBidderSort", "AuctionsBidSort" }
-- result rows by page: { first row, last row, extra left, extra right } of the plate behind each list
A.LISTS = { { "BrowseButton1", "BrowseButton8" }, { "BidButton1", "BidButton9" }, { "AuctionsButton1", "AuctionsButton9" } }

function A.Spec()
  return {
    frame = "AuctionFrame", close = "AuctionFrameCloseButton", move = "auction", npc = true, icon = "Interface\\Icons\\INV_Hammer_20",
    size = { w = 832, h = 447, cut = 0 },
    bare = A.PAGES,
    tabs = seq("AuctionFrameTab", 3),
    headers = A.SORTS,
    buttons = { "BrowseSearchButton", "BrowseResetButton", "BrowseCloseButton", "BrowseBuyoutButton", "BrowseBidButton", "BidCloseButton", "BidBuyoutButton", "BidBidButton",
      "AuctionsCreateAuctionButton", "AuctionsCancelAuctionButton", "AuctionsCloseButton", "AuctionsStackSizeMaxButton", "AuctionsNumStacksMaxButton" },
    edits = { "BrowseName", "BrowseMinLevel", "BrowseMaxLevel", "AuctionsStackSizeEntry", "AuctionsNumStacksEntry" },
    checks = { "IsUsableCheckButton", "ShowOnPlayerCheckButton" },
    dropdowns = { "BrowseDropDown" },
    rows = join(seq("BrowseButton", 8), seq("BidButton", 9), seq("AuctionsButton", 9), seq("AuctionFilterButton", 15)),
    strip = join(seq("BrowseButton", 8), seq("BidButton", 9), seq("AuctionsButton", 9)), -- the name bar art of each result row
    scrolls = { { "BrowseFilterScrollFrameScrollBar", -18 }, "BrowseScrollFrameScrollBar", "BidScrollFrameScrollBar", "AuctionsScrollFrameScrollBar" }, -- the filter bar sits inside its list: results start 6 px right of it
    after = A.After,
  }
end

function A.After(f)
  for _, n in ipairs(A.PAGE_TITLES) do local t = _G[n]; if t and t.SetAlpha then t:SetAlpha(0) end end
  AFUI.NpcKit.Title(f, _G.BUTTON_LAG_AUCTIONHOUSE or "Auction House")
  -- the filter column's own bars (AuctionFilterButton*: a brown tab art in the normal texture) go; the row glow marks the hover / selection
  for i = 1, 15 do
    local b = _G["AuctionFilterButton" .. i]
    if b then
      local nt = b.GetNormalTexture and b:GetNormalTexture()
      if nt then nt:SetAlpha(0) end
    end
  end
  local browse, bid, mine = _G.AuctionFrameBrowse, _G.AuctionFrameBid, _G.AuctionFrameAuctions
  if browse and _G.BrowseFilterScrollFrame then AFUI.NpcKit.Plate(browse, _G.AuctionFilterButton1 or _G.BrowseFilterScrollFrame, 4, 4, 22, 4, _G.AuctionFilterButton15 or _G.BrowseFilterScrollFrame) end
  local pages = { browse, bid, mine }
  for i, l in ipairs(A.LISTS) do
    local first, last = _G[l[1]], _G[l[2]]
    if pages[i] and first and last then AFUI.NpcKit.Plate(pages[i], first, 4, 4, 4, 4, last) end
  end
end

function A.Enabled() return AFUI.GetSetting("auctionRestyle", false) and true or false end -- off by default: testers found the beta skin rough

function A.Setup()
  if A.done or not A.Enabled() or not _G.AuctionFrame then return end
  A.done = true
  AFUI.RunOutOfCombat(function() AFUI.NpcKit.Skin(A.Spec()) end)
end

if AFUI.Settings and AFUI.Settings.Register then
  AFUI.Settings.Register{ category = "general", key = "auctionRestyle", type = "check", default = false, label = "Forever auction house window (beta)",
    tooltip = "Draws the auction house in the Forever look. Still rough, so it is off by default and the client's own auction house stays untouched. Takes effect after /reload." }
end
AFUI.On("ADDON_LOADED", function(_, name) if name == "Blizzard_AuctionUI" then A.Setup() end end)
AFUI.RegisterModule("AuctionFrame", { OnLogin = A.Setup })
