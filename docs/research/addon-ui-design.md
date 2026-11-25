# Addon UI design for Better AH (Forever client)

Research for [#28](https://github.com/chsko/better-ah/issues/28). This covers how to build a native-looking auction window
on World of Warcraft: Forever (interface 16001, build 1.60.1.71091).

**Main source:** Gethe's `wow-ui-source` mirror has a
[`forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever). Its
[`version.txt`](https://github.com/Gethe/wow-ui-source/blob/forever/version.txt) reads `1.60.1.71091`, the same build as
our client (commit `c01a87b`). Every FrameXML claim below was checked by grepping that branch, unless it is marked otherwise.
Links of the form `…/blob/forever/<path>` point into it. Wiki pages (warcraft.wiki.gg) mostly describe retail, so they are
flagged where Forever could differ.

**Sources that could not be reached:** wowforeverguides.com, townlong-yak.com and tradeskillmaster.github.io did not resolve
from this session. Nothing below relies on them.

## 0. Key finding: Forever is a "camelot" game type in the Mainline family

Forever's UI code calls itself `camelot`. It sets
[`WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT`](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua).
Blizzard's `.toc` files load files per game type and per family. They use `[Family]` and `[Game]` path tokens and
`AllowLoadGameType` conditions ([TOC format](https://warcraft.wiki.gg/wiki/TOC_format)).

For Forever, `[Family]` resolves to **Mainline**, not Classic. Three pieces of evidence (an inference, but a consistent one):

- [`Blizzard_AuctionHouseUI.toc`](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc)
  says `## AllowLoadGameType: mainline, cata, mists`, with no `camelot`. It loads on Forever anyway, and it has a
  `[Game]\Blizzard_AuctionData.lua [AllowLoadGameType camelot]` line. So camelot counts as `mainline` for this check.
- [`Blizzard_SharedXML.toc`](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Blizzard_SharedXML.toc)
  loads `[Family]\NineSliceLayouts.lua`. That file exists only under `Mainline/`, and the folder has no `Classic/` subfolder.
- [`Blizzard_Menu.toc`](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Menu/Blizzard_Menu.toc)
  loads `[Family]\MenuVariants.lua [AllowLoadGameType mainline]` and adds a camelot-only `Camelot\Menu.xml`.

The practical result: **read the `Mainline/` and `Shared/` files, plus any `Camelot/` overrides**. For example the SharedXML `.toc` loads
`[Game]\NineSliceLayoutOverrides.lua [AllowLoadGameType camelot]` from `Blizzard_SharedXML/Camelot/`; it does not
touch `InsetFrameTemplate` in build 71091, but check it before relying on a nine-slice layout. The `Classic/` copies
in the same addon are for Cata and Mists Classic. For example, `AuctionCategoryButtonTemplate` exists in both
[Mainline](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseCategoriesList.xml)
(atlas art) and [Classic](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Classic/Blizzard_AuctionHouseCategoriesList.xml)
(old `UI-AuctionFrame-FilterBg` file art). Forever uses the Mainline one.

The API is Mainline-style too. Forever has C APIs such as `C_GameRules.GetForeverExperiencePreset`, with
`Enum.ForeverExperiencePreset` values `Classic = 0` and `Enhanced = 1`
([GameRulesDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/GameRulesDocumentation.lua)).
Many API docs also carry `SecretArguments`, which shows that retail's secret-value system is present
([CurrencyInfoDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurrencyInfoDocumentation.lua)).

## 1. Lua vs XML

**What XML gives you.** The [XML schema page](https://warcraft.wiki.gg/wiki/XML_schema) documents these attributes:

- `virtual="true"`: defines a template instead of creating a widget. It needs a name.
- `inherits`: a comma-separated list of templates to inherit.
- `mixin` / `secureMixin`: Lua mixin tables to copy onto the widget.
- `parentKey` / `parentArray`: store a reference on the parent (`self.ScrollBox`) or add the widget to an array on the parent
  (`self.FilterButtons`).
- `<KeyValues>`: typed per-template constants.
- `atlas` / `useAtlasSize` on textures.

Blizzard's own templates use all of these together. For example, `AuctionHouseCategoriesListTemplate` has
`mixin="AuctionHouseCategoriesListMixin"`, a `KeyValue` for `layoutType`, a `Background` texture with `atlas="auctionhouse-background-categories"`, a `NineSlice` child, and
`ScrollBox`/`ScrollBar` children wired by parentKey
([source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseCategoriesList.xml)).
Inheritance lets you override any property of a template and keep the rest
([XML user interface](https://warcraft.wiki.gg/wiki/XML_user_interface)).

**Addons can define their own templates.** List `.xml` files in the `.toc` next to the `.lua` files. "Only Lua and XML files
need to be listed", and they load top to bottom ([TOC format](https://warcraft.wiki.gg/wiki/TOC_format)). An XML file can
also pull in others with `<Script file=…>` and `<Include file=…>` (same page). After that, a template is usable from Lua:
`CreateFrame("Button", nil, parent, "BetterAHRowTemplate")`. Auctionator does exactly this. Its `Source/Manifest.xml` tree
defines templates such as `AuctionatorDropDown` (`mixin="AuctionatorDropDownMixin"`, a child `DropdownButton` that inherits
`WowStyle1DropdownTemplate`) and `AuctionatorPanelTemplate`
([mirror of Auctionator's source](https://github.com/etkr/Auctionator/blob/master/Source/Components/Frames/DropDown.xml)).

**What Lua alone can do.** Everything at runtime: `CreateFrame(type, name, parent, "TemplateA, TemplateB")`, `CreateTexture`,
`CreateFontString`, `Mixin(frame, SomeMixin)`, and `SetScript`. Lua can **inherit** templates but cannot **define** new
virtual templates. Since patch 1.10, `CreateFrame` has let Lua do most of the work, and XML remains an accepted, supported
approach ([XML user interface](https://warcraft.wiki.gg/wiki/XML_user_interface)).

**Trade-offs.**

- *XML:* declarative layout, parentKeys, reusable templates that work with `ScrollView:SetElementInitializer("Template", …)`,
  and the same idiom Blizzard and Auctionator use. On the other hand, our busted specs cannot load it, a malformed file errors
  only at login or `/reload`, and it is more verbose.
- *Lua:* testable with our fake client (`spec/window_spec.lua`) and all in one language. On the other hand, every row
  "template" becomes a Lua factory function, and pooled list rows need a frame type plus an extent instead of a template
  name ([Making scrollable frames](https://warcraft.wiki.gg/wiki/Making_scrollable_frames)).

## 2. Finding and reusing Blizzard templates safely

**Where they live (Forever branch).**

| Template | File |
| --- | --- |
| `BasicFrameTemplateWithInset` | [Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml#L602](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml#L602) |
| `PortraitFrameTemplate`, `InsetFrameTemplate`, `NineSlicePanelTemplate`, `UIPanelButtonTemplate`, `PanelTabButtonTemplate`, `ButtonFrameTemplate` | [Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml) |
| `WowScrollBoxList` | [Shared/Scroll/ScrollTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml) |
| `MinimalScrollBar` | [Shared/Scroll/MinimalScrollBar.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml) |
| `WowTrimScrollBar`, `WowClassicScrollBar` | [Shared/Scroll/TrimScrollBar.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Shared/Scroll/TrimScrollBar.xml) |
| `FauxScrollFrameTemplate`, `UIPanelScrollFrameTemplate` | [SecureScrollTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/SecureScrollTemplates.xml) |
| `HybridScrollFrameTemplate` | [HybridScrollFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/HybridScrollFrame.xml) |
| `SearchBoxTemplate`, `InputBoxTemplate` | [Shared/InputBox/InputBoxTemplates.xml#L209](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml#L209) |
| `UICheckButtonTemplate` | [Shared/Button/CheckButtonTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml) |
| `WowStyle1DropdownTemplate` (new Menu system; `MenuUtil`) | [Blizzard_Menu/Mainline/MenuTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Menu/Mainline/MenuTemplates.xml) |
| `UIDropDownMenuTemplate` (legacy dropdown, still shipped) | [Mainline/UIDropDownMenuTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml) |
| `MoneyDisplayFrameTemplate` | [Blizzard_MoneyFrame/Shared/MoneyFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MoneyFrame/Shared/MoneyFrame.xml) |
| `SmallMoneyFrameTemplate`, `MoneyFrameTemplate` | [Blizzard_MoneyFrame/Mainline/MoneyFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MoneyFrame/Mainline/MoneyFrame.xml) |
| `MoneyInputFrameTemplate` | [Blizzard_MoneyFrame/Mainline/MoneyInputFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MoneyFrame/Mainline/MoneyInputFrame.xml) |
| `BackdropTemplate` (needed for `SetBackdrop`) | [Blizzard_SharedXML/Backdrop.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Backdrop.xml) |
| `ItemButton` (an intrinsic, so call `CreateFrame("ItemButton", …)`) | [Blizzard_ItemButton/Shared/ItemButtonTemplate.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ItemButton/Shared/ItemButtonTemplate.xml) |

On the Mainline path, `ItemButtonTemplate` itself shows up only in the Vanilla/Cata files. Use the `ItemButton` intrinsic, with
`SetItemButtonCount` and the mixin's quality helpers
([Mainline/ItemButtonTemplate.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua)).

**Three kinds of template home:**

1. **Always loaded.** `Blizzard_SharedXML*` and `Blizzard_UIPanelTemplates` load before addons, so their templates are safe
   at any time.
2. **Load-on-demand.** `Blizzard_AuctionHouseUI` is `## LoadOnDemand: 1`
   ([toc](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Blizzard_AuctionHouseUI.toc)).
   Its templates and their global script functions (`AuctionFrameFilter_OnLoad` and so on) only exist after the auction house
   addon has loaded. A `CreateFrame` that names one of them before then fails.
3. **Game-type specific.** A `Camelot/` file can override a Mainline one, so always check the `.toc` line that loads a file.

**How to read what a template expects.** Open the XML and then the Lua that drives it. Look for five things:

- `mixin=` (methods and their `OnLoad`).
- `<Scripts>` that call global functions.
- `parentKey`/`parentArray` children the code indexes (`self.Text`, the parent's `FilterButtons`).
- `KeyValues` the mixin reads.
- Above all, the **setup function** that the owning list calls on every row.

**The AuctionCategoryButtonTemplate pitfall, explained.** The Mainline template
([XML](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseCategoriesList.xml))
defines four textures:

- `NormalTexture`: atlas `auctionhouse-nav-button`, 136x32.
- `HighlightTexture`: atlas `auctionhouse-nav-button-highlight`, hidden, one `CENTER` anchor, **no size**.
- `SelectedTexture`: atlas `auctionhouse-nav-button-select`, `alphaMode="ADD"`, anchored to `NormalTexture`.
- `Lines`.

It also declares `parentArray="FilterButtons"` and inherits `TruncatedTooltipScriptTemplate`. Its `OnEnter` is the global
`AuctionFrameFilter_OnEnter`, which calls `TruncatedTooltipScript_OnEnter(self)` and then `self.HighlightTexture:Show()`
([Shared Lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseCategoriesList.lua)).

The real layout happens in `AuctionHouseFilterButton_SetUp(button, info)`
([Mainline Lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseCategoriesList.lua)).
For each `info.type` (`category`, `subCategory`, `subSubCategory`), it re-applies the atlases, re-anchors all three textures and
resizes them for most types (for `subSubCategory` it only re-anchors `NormalTexture` and sets its alpha to 0), sets blend modes, fonts and text offsets, and toggles `SelectedTexture`.
`AuctionHouseCategoriesListMixin:OnLoad` calls that function from a `ScrollView` element initializer. A button created
outside that list never gets the setup, which is why our prototype's highlight and selection drew at the wrong size.

The lesson: **a Blizzard row template is half of a contract; the other half is its list's initializer.** Either call the
matching setup function yourself, which ties us to private Blizzard code that can change per patch, or define our own row
template and copy only the atlas names.

## 3. Widget API essentials

- **Regions and anchoring.** Positions are in UI units, where screen height is 768 times a ratio. Effective scale is the
  product of the parent scales ([UI scaling](https://warcraft.wiki.gg/wiki/UI_scaling)). Anchor with `SetPoint`, and always
  `ClearAllPoints` before re-anchoring a pooled region (Blizzard does this in `AuctionHouseFilterButton_SetUp`, linked above).
- **Strata and levels.** Strata run WORLD, BACKGROUND, LOW, MEDIUM, HIGH, DIALOG, FULLSCREEN, FULLSCREEN_DIALOG, TOOLTIP.
  Frame levels run 0 to 10000, and a child starts one level above its parent
  ([Frame Strata](https://warcraft.wiki.gg/wiki/Frame_Strata)). Inside a frame, textures and font strings sit in draw layers:
  BACKGROUND, BORDER, ARTWORK, OVERLAY, HIGHLIGHT. A layer can also take a `textureSubLevel`, which Auctionator uses as
  `textureSubLevel="-6"`
  ([example](https://github.com/etkr/Auctionator/blob/master/Source/Components/Frames/Panel.xml)).
- **Textures.**
  - `SetTexture(path or fileID)` with `SetTexCoord` crops a sheet by hand.
  - `SetAtlas(name [, useAtlasSize [, filterMode [, resetTexCoords]]])` uses a named sub-image with its coordinates built in
    ([SetAtlas](https://warcraft.wiki.gg/wiki/API_TextureBase_SetAtlas)).
  - Prefer atlases. `C_Texture.GetAtlasInfo(atlas)` returns size and coordinates
    ([TextureUtilsDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TextureUtilsDocumentation.lua)).
  - Retail patch 12.0.0 added wrap-mode arguments to `SetAtlas` (same wiki page). That they exist on Forever is unverified.
- **Font strings.** Use the client's font objects (`GameFontNormal`, `GameFontHighlightSmall`, `NumberFontNormal`, …),
  defined in [Blizzard_Fonts_Shared/Shared/FontStyles.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Fonts_Shared/Shared/FontStyles.xml).
  Inherit them with `CreateFontString(nil, "OVERLAY", "GameFontNormal")` or `SetFontObject`, not raw `SetFont`.
- **Pixel perfection.** [PixelUtil](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/PixelUtil.lua)
  provides `SetSize`, `SetPoint`, `GetNearestPixelSize` and `SetRoundLayoutToNearestPixelRecursively`, which snap 1px lines
  and borders. Texture seams and rounding glitches come from scale, not from our math
  ([UI scaling](https://warcraft.wiki.gg/wiki/UI_scaling)).
- **Mixins.** The globals `Mixin(obj, ...)` and `CreateFromMixins(...)` copy tables of methods. Blizzard builds
  `CreateAndInitFromMixin` and the secure variants on top of them
  ([Blizzard_SharedXMLBase/Mixin.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLBase/Mixin.lua)).
  Blizzard composes them, for example `AuctionHouseItemListLineMixin = CreateFromMixins(TableBuilderRowMixin)`
  ([source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemList.lua)).
  A mixin is just a table of functions, but **XML can only name globals**: `mixin="X"` and `<OnLoad function="X"/>`
  look `X` up in `_G`. Our rule is "no new globals except saved variables", so our XML templates must carry no
  `mixin=` and no script functions. Apply behaviour in Lua instead, for example `Mixin(frame, ns.RowMixin)` in the
  ScrollBox initializer, then `frame:SetScript(...)`. Allowing a `BetterAH_*` global prefix would need an ADR first.

## 4. Native art, colors and money

**Finding art.**

- `ExportInterfaceFiles art` writes `BlizzardInterfaceArt` into the game folder
  ([Viewing Blizzard's interface code](https://warcraft.wiki.gg/wiki/Viewing_Blizzard%27s_interface_code)).
  This export holds **files** (BLP), not atlas names.
- Atlases are defined in client data. The wiki points to Townlong Yak's `Helix/AtlasInfo.lua` (file to atlas name, size
  and coordinates) and the in-game [Texture Atlas Viewer](https://www.curseforge.com/wow/addons/textureatlasviewer) addon
  ([SetAtlas page](https://warcraft.wiki.gg/wiki/API_TextureBase_SetAtlas)). That viewer's Forever support is unverified.
- In game, `/fstack` with SHIFT toggles texture info, which shows the atlas or file of the region under the mouse
  ([framestack](https://warcraft.wiki.gg/wiki/MACRO_framestack)).
- The fastest source of AH atlas names is the AH XML itself: `auctionhouse-nav-button*`, `auctionhouse-ui-row-select`,
  `auctionhouse-ui-row-highlight`, `auctionhouse-background-categories` (all in the CategoriesList files linked above).

**Quality colors.** Use `ITEM_QUALITY_COLORS[quality]` (built in
[Blizzard_Colors/Mainline/ColorConstants.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Colors/Mainline/ColorConstants.lua)
and [ColorManager.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Colors/Mainline/ColorManager.lua))
or `C_Item.GetItemQualityColor(quality)`, which returns r, g, b and more
([ItemDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)).

**Money.**

- `GetMoneyString(money, separateThousands, …)` is Lua in
  [FormattingUtil.lua#L72](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/FormattingUtil.lua#L72).
- `C_CurrencyInfo.GetCoinTextureString(amount [, fontHeight=14])` is documented in
  [CurrencyInfoDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurrencyInfoDocumentation.lua).
  No Lua global `GetCoinTextureString` alias appears in the Forever FrameXML, so use the `C_CurrencyInfo` form.
- For frames, use `MoneyDisplayFrameTemplate`, which the AH itself uses for its money display
  ([AuctionHouseFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml)),
  or `SmallMoneyFrameTemplate`.
- For tooltips, use `SetTooltipMoney(frame, money, …)`
  ([Shared/MoneyFrame.lua#L609](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MoneyFrame/Shared/MoneyFrame.lua#L609)).
- Money stays integer copper (CLAUDE.md). Format only at the edge.

**Tooltips.** Blizzard's own code calls `GameTooltip:SetItemByID(itemID)`
([GarrisonMissionUI.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_GarrisonUI/Mainline/Blizzard_GarrisonMissionUI.lua)),
and `C_TooltipInfo.GetItemByID` exists for data-only reads
([TooltipInfoDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua)).
For auction rows, `SetHyperlink(itemLink)` keeps the item's exact properties. It is a standard GameTooltip method, but I did
not check it against Forever.

## 5. Getting the exact FrameXML for this client

- **Best: the mirror.** The [`forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever) of
  [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) is already at our build. Other branches exist for `live`,
  `classic`, `classic_era`, `classic_anniversary` and more
  ([branches](https://github.com/Gethe/wow-ui-source/branches/all)). Check `version.txt` against the client build after
  each Forever patch.
- **Authoritative: export from the client.**
  1. Start the game with `-console`. In Battle.net this is Settings > Game Settings > "Additional command line arguments"
     ([Console](https://warcraft.wiki.gg/wiki/Console)).
  2. Open the console with the backtick key **at the login or character-select screen**.
  3. Run `ExportInterfaceFiles code`, which writes `BlizzardInterfaceCode` (or `ExportInterfaceFiles art` for the art).
  The command "only works from the actual console on the login and character selection screens". Typed in the world, it
  answers "Unknown Command" ([Viewing Blizzard's interface code](https://warcraft.wiki.gg/wiki/Viewing_Blizzard%27s_interface_code)).
  That matches what we saw in game. The export is the client's own files, so it is the tiebreaker if the mirror ever lags.
- **In-game API docs.** The `Blizzard_APIDocumentationGenerated` files in the mirror back the in-game `/api` command, which is
  registered as `SLASH_COMMAND.API`
  ([SlashCommands.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua)).
- **Annotations.** [Ketho's vscode-wow-api](https://github.com/Ketho/vscode-wow-api) gives LuaLS completion for API, widgets,
  events and enums for mainline, mists and vanilla builds. It has no Forever flavor, but Mainline is the closest match.

## 6. Native layout patterns, and how other AH addons build UI

**Blizzard's auction house (Forever).** `AuctionHouseFrame` inherits `PortraitFrameTemplate`, is 800x538, and has `parentKey`
children
([AuctionHouseFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.xml)):

- `BuyTab`, `SellTab` and `AuctionsTab`, which inherit `AuctionHouseFrameDisplayModeTabTemplate`, built on
  `PanelTabButtonTemplate`
  ([Tab.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseTab.xml)).
- A `SearchBar` along the top.
- A `CategoriesList` (168x438: an inset with a NineSlice, a `WowScrollBoxList` and a scroll bar) on the left.
- `BrowseResultsFrame`, `ItemBuyFrame` and `CommoditiesBuyFrame` filling the right.
- Sell frames with a list beside them.
- A `MoneyFrameInset` with a `MoneyDisplayFrameTemplate` at the bottom.
- A modal `BuyDialog` over a `DialogOverlay` at frame level 1000.

Result lists use `AuctionHouseItemListTemplate`: header container, `WowScrollBoxList` and `MinimalScrollBar`, with a
spinner and "Searching" text while loading. They are driven by `CreateScrollBoxListLinearView`,
`ScrollUtil.InitScrollBoxListWithScrollBar`, a `TableBuilder` for columns (`ScrollUtil.RegisterTableBuilder`) and
`ScrollUtil.RegisterAlternateRowBehavior` for zebra rows
([ItemList.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseItemList.xml),
[ItemList.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemList.lua)).
This is the pattern to imitate: an inset per region, gold title text, small fonts in rows, alternating rows, and
`auctionhouse-ui-row-highlight`/`-select` atlases for hover and selection.

**Scroll lists: ScrollBox vs the old frames.** ScrollBox is a scroll box plus a scroll bar plus a view plus a
`DataProvider`. It pools frames, and you must reset per-row state in the initializer
([Making scrollable frames](https://warcraft.wiki.gg/wiki/Making_scrollable_frames)). Blizzard's AH uses it throughout.
`FauxScrollFrameTemplate` and `HybridScrollFrameTemplate` still ship
([SecureScrollTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/SecureScrollTemplates.xml),
[HybridScrollFrame.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/HybridScrollFrame.xml)),
but they are the older approach: manual offsets and fixed row counts, which our current `Window.lua` imitates.

**Auctionator** builds its UI in XML templates with Lua mixins. It has hundreds of XML files, with `Source/Components/Frames/*.xml`
and `Source/Components/Mixins/*.lua`. It inherits Blizzard templates (`WowStyle1DropdownTemplate`) and uses `WowScrollBoxList`
and `CreateScrollBoxListLinearView` in its results listing. Its `.toc` files are per flavor (`Auctionator.toc`, `_Cata`,
`_Vanilla`, `_Wrath`). Sources:
[repo mirror](https://github.com/etkr/Auctionator),
[ResultsListing.xml](https://github.com/etkr/Auctionator/blob/master/Source/Components/ResultsListing/Templates/ResultsListing.xml).
The upstream is `Auctionator/Auctionator` according to [search results](https://github.com/Auctionator), but that URL
returned 404 here, so the fork is cited.

**TradeSkillMaster** uses its own skinned UI framework rather than Blizzard templates (ADR 0002 already records this). Its
GitHub organization publishes only support libraries (LibTSMClass, LibTSMCore, LibTSMUtil, LibTSMReactive, LibTSMDatabase, a
luacheck fork, wowlua-ls) under MIT and GPL ([github.com/TradeSkillMaster](https://github.com/TradeSkillMaster)). I found no
public repository for the addon itself, so its UI internals are not verified here.

## 7. Testing and inspection tools

- **`/fstack`** (`/framestack [showHidden, showRegions, showAnchors]`) lists the frames under the cursor. While it is open,
  ALT cycles through them, CTRL inspects the selection like `/tinspect`, SHIFT toggles texture info, and CTRL-C copies a
  texture path (not atlas names) ([framestack](https://warcraft.wiki.gg/wiki/MACRO_framestack)). It is ideal for checking
  anchors and parentKeys. Forever ships it: [Blizzard_FrameStack](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_FrameStack),
  with `fstack_*` CVars in
  [Blizzard_DebugTools.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_DebugTools/Blizzard_DebugTools.lua).
- **`/tinspect [GlobalName]`** opens the table inspector. With no argument, it inspects the widget under the mouse
  ([tableinspect](https://warcraft.wiki.gg/wiki/MACRO_tableinspect)).
- **`/dump expr`** prints any Lua expression, up to 30 table entries, through `DevTools_Dump`
  ([dump](https://warcraft.wiki.gg/wiki/MACRO_dump)). It is good for `/dump C_AuctionHouse.GetBrowseResults()`.
- **`/etrace`** opens the event trace. `/etrace mark text` adds a marker, and `EventTrace:TogglePause()` pauses logging
  ([eventtrace](https://warcraft.wiki.gg/wiki/MACRO_eventtrace)). Forever ships
  [Blizzard_EventTrace](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_EventTrace). Use it to
  confirm AH event order (`AUCTION_HOUSE_BROWSE_RESULTS_UPDATED` and others).
- The slash keys for these commands (`EVENTTRACE`, `TABLEINSPECT`, `DUMP`, `FRAMESTACK`, `API`, plus `/tvis`) are registered
  in Forever's
  [SlashCommands.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua).

## Recommendations for Better AH

1. **Use the `forever` branch of wow-ui-source as the reference.** Pin the build we read in commits and ADRs, and check
   `version.txt` after each client patch. Read `Mainline/`, `Shared/` and `Camelot/`, and ignore `Classic/`. Fall back to
   `ExportInterfaceFiles code` at character select only if the mirror lags.
2. **Adopt XML for templates only; keep logic in Lua.** Add a `BetterAH/UI/Templates.xml`, listed in the `.toc` before the
   UI Lua. It would define our own row, category and column-header templates with parentKeys and art only (no `mixin=` or script
   functions, see §3), and the Lua initializer mixes in `ns` tables. That lets ScrollBox
   initializers take a template name and keeps the window code thin. Pure modules stay as they are, and the fake client can
   keep testing the Lua adapters. *Alternative:* stay pure Lua and use `SetElementInitializer("Button", …)` with
   `SetElementExtent`, accepting factory functions for rows. Either works. XML is the Blizzard and Auctionator norm.
3. **Do not reuse Blizzard AH row templates** (`AuctionCategoryButtonTemplate`, `AuctionHouseItemListLineTemplate`).
   They depend on load-on-demand code and on private setup functions. Copy their **atlas names** instead
   (`auctionhouse-nav-button*`, `auctionhouse-ui-row-highlight`, `auctionhouse-ui-row-select`) into our own templates, with
   explicit sizes and anchors.
4. **Replace the hand-rolled 14-row list with ScrollBox:** `WowScrollBoxList` + `MinimalScrollBar`, using
   `CreateScrollBoxListLinearView` and `CreateDataProvider`. Add `ScrollUtil.AddSelectionBehavior` for the selected row and
   `RegisterAlternateRowBehavior`/TableBuilder if we want Blizzard-style columns. Feed it from WindowModel's pure output.
5. **Building blocks for the window:**
   - Frame: keep `BasicFrameTemplateWithInset`, or move to `PortraitFrameTemplate`/`ButtonFrameTemplate` to match the AH.
   - Regions: `InsetFrameTemplate` (or `NineSlicePanelTemplate` with `layoutType="InsetFrameTemplate"`).
   - Tabs: `PanelTabButtonTemplate`.
   - Controls: `UIPanelButtonTemplate`, `SearchBoxTemplate`, `WowStyle1DropdownTemplate` with `MenuUtil` (not
     `UIDropDownMenuTemplate`).
   - Money: `MoneyDisplayFrameTemplate`, or `GetMoneyString` for text and `MoneyInputFrameTemplate` for price entry.
   - Items: the `ItemButton` intrinsic for icons, `GameTooltip:SetHyperlink`/`SetItemByID` for tooltips, and
     `C_Item.GetItemQualityColor` for names.
   - Settings: a Settings panel through `Settings.RegisterCanvasLayoutCategory` and `RegisterAddOnCategory`
     ([Settings API](https://warcraft.wiki.gg/wiki/Settings_API),
     [Forever source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua#L134)).
6. **Add new globals to `.luacheckrc`** as they come in: `CreateScrollBoxListLinearView`, `CreateDataProvider`, `ScrollUtil`,
   `MenuUtil`, `GetMoneyString`, `C_CurrencyInfo`, `ITEM_QUALITY_COLORS`, `PixelUtil`, `Mixin`, `CreateFromMixins`,
   `Settings`, `SetTooltipMoney`, `GameTooltip`, `C_Item`, `C_Texture`. Code that reads them through the `env` table
   (as `Window.lua` does with `env.CreateFrame`) doesn't need an entry; only direct global reads do.
7. **Verify in game before relying on these, and say so in the issue:**
   - That `[Family]` really is Mainline (for example `/dump WOW_PROJECT_ID`, which should print 18, and that
     `WowStyle1DropdownTemplate` renders in Mainline style).
   - The `SetAtlas` argument list.
   - That `GameTooltip:SetHyperlink` works on an auction item link.
   - Inspect the finished window with `/fstack` and its SHIFT texture info to catch any texture that is unsized or anchored
     to the wrong frame.
