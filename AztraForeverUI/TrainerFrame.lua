-- Forever's class / profession trainer window over Blizzard's own ClassTrainerFrame (NpcKit.lua): metal portrait frame showing the trainer, dark plates behind the skill
-- list and the skill details, red Train / Cancel buttons, the filter dropdown, minimal scroll bars and Forever's row glow on the 11 skill rows. Every script stays the
-- client's (selecting a skill, expanding a header, Train, the cost and requirement texts, the money). Blizzard_TrainerUI is load on demand: skinned on its ADDON_LOADED.
-- Client facts (Gethe/wow-ui-source 2.5.3 Interface/AddOns/Blizzard_TrainerUI/Blizzard_TrainerUI.xml): ClassTrainerFrame 384 x 512 (old art, no ButtonFrameTemplate), title
-- ClassTrainerNameText, ClassTrainerGreetingText, ClassTrainerFrameFilterDropDown, ClassTrainerSkill1..11, ClassTrainerListScrollFrame 296 x 184, ClassTrainerDetailScrollFrame
-- 296 x 135, ClassTrainerMoneyFrame, ClassTrainerTrainButton / CancelButton 80 x 22, ClassTrainerFrameCloseButton. TBC has no "Train All" button (a later client added it).
AFUI = AFUI or {}
local T = {}
AFUI.TrainerFrame = T

T.SKILLS = 11 -- CLASS_TRAINER_SKILLS_DISPLAYED
T.SPEC = {
  frame = "ClassTrainerFrame", title = "ClassTrainerNameText", close = "ClassTrainerFrameCloseButton", move = "trainer", npc = true,
  icon = "Interface\\Icons\\INV_Misc_Book_09",
  size = { w = 384, h = 512, cut = 76 }, -- the widgets stop 76 px above the old frame's bottom (Train / Cancel at y -419)
  bare = { "ClassTrainerExpandButtonFrame" },
  buttons = { "ClassTrainerTrainButton", "ClassTrainerCancelButton" },
  dropdowns = { "ClassTrainerFrameFilterDropDown" },
  scrolls = { "ClassTrainerListScrollFrameScrollBar", "ClassTrainerDetailScrollFrameScrollBar" },
  rows = {}, -- ClassTrainerSkill1..11, filled below
}
for i = 1, T.SKILLS do T.SPEC.rows[i] = "ClassTrainerSkill" .. i end
T.PLATES = { { "ClassTrainerListScrollFrame", 4, 4, 4, 4 }, { "ClassTrainerDetailScrollFrame", 4, 4, 4, 4 } } -- { frame, l, t, r, b }

T.SPEC.after = function(f)
  for _, p in ipairs(T.PLATES) do local a = _G[p[1]]; if a then AFUI.NpcKit.Plate(f, a, p[2], p[3], p[4], p[5]) end end
end

function T.Setup()
  if T.done or not _G.ClassTrainerFrame then return end
  T.done = true
  AFUI.RunOutOfCombat(function() AFUI.NpcKit.Skin(T.SPEC) end)
end

AFUI.On("ADDON_LOADED", function(_, name) if name == "Blizzard_TrainerUI" then T.Setup() end end)
AFUI.RegisterModule("TrainerFrame", { OnLogin = T.Setup })
