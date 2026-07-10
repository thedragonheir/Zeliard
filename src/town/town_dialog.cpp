#include "town.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <span>
#include <vector>

#include "../mcga/mcga_draw.h"
#include "town_actors.h"

namespace
{
constexpr std::size_t TownDialogWidth = 176;
constexpr std::size_t TownDialogPositionBaseY = 0x18;
constexpr std::size_t TownDialogPositionBottomY = 0x56;
constexpr std::size_t TownDialogVerticalCenterHeight = 0x40;
constexpr std::size_t TownDialogBorderThickness = 2;
constexpr std::size_t TownDialogInnerTextLeft = TownDialogBorderThickness;
constexpr std::size_t TownDialogInnerTextTop = 2;
constexpr std::size_t TownDialogTextInset = 4;
constexpr std::size_t TownDialogLineHeight = 10;
constexpr std::size_t TownDialogTextWidth = 0xA8;
constexpr std::size_t TownDialogMaximumLines = 7;
constexpr std::size_t TownDialogMaximumBoxLines = 8;
constexpr std::size_t TownDialogContinuationCursorX = 0x54;
constexpr std::size_t TownDialogContinuationCursorY = 0x4A;
constexpr std::uint8_t TownDialogContinuationCursorGlyph = 0x7C;
constexpr std::size_t TownDialogContinuationCursorWidth = 4;
constexpr std::size_t TownDialogContinuationCursorHeight = 8;
constexpr std::size_t TownDialogScrollStepCount = 10;
constexpr std::uint8_t TownDialogControlCodeStart = 0x80;
constexpr std::uint8_t TownDialogFontColorSelector = 0x01;
constexpr std::uint8_t TownDialogContinuationCursorColorSelector = 0x02;
constexpr std::uint8_t TownDialogBorderColor = 9;
constexpr std::array<std::uint8_t, 8> TownFontColorPaletteIndices =
{
    0x00, 0x09, 0x12, 0x1B, 0x24, 0x2D, 0x36, 0x3F
};
constexpr std::array<std::uint8_t, 96> TownDialogCharXOffsets =
{
    0, 2, 2, 3, 1, 0, 0, 2, 2, 3, 1, 1,
    1, 2, 2, 0, 1, 2, 1, 1, 1, 1, 1, 1,
    1, 1, 3, 2, 1, 1, 2, 1, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0,
    2, 2, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    0, 2, 1, 0, 2, 0, 1, 1, 0, 0, 0, 1,
    1, 0, 0, 0, 1, 1, 1, 2, 0, 3, 1, 0
};
constexpr std::array<std::uint8_t, 96> TownDialogCharWidths =
{
    5, 4, 4, 4, 6, 8, 5, 3, 4, 4, 6, 6,
    6, 5, 6, 8, 7, 5, 7, 7, 7, 7, 7, 7,
    7, 7, 3, 4, 6, 6, 6, 7, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 5, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 7, 8, 8, 8, 8, 7, 5, 3,
    3, 5, 6, 7, 7, 8, 8, 7, 8, 7, 7, 8,
    8, 5, 6, 8, 5, 8, 7, 7, 8, 8, 8, 7,
    6, 8, 8, 8, 7, 7, 7, 4, 8, 4, 7, 8
};

std::uint8_t GetTownDialogCharWidth(std::uint8_t Byte)
{
    if (Byte < 0x20 || Byte >= 0x80)
    {
        return 0;
    }

    return TownDialogCharWidths[static_cast<std::size_t>(Byte - 0x20)];
}

std::uint8_t GetTownDialogCharXOffset(std::uint8_t Byte)
{
    if (Byte < 0x20 || Byte >= 0x80)
    {
        return 0;
    }

    return TownDialogCharXOffsets[static_cast<std::size_t>(Byte - 0x20)];
}

std::size_t MeasureTownDialogTextToDelimiter(const std::vector<std::uint8_t>& DialogBytes,
    std::size_t Offset)
{
    std::size_t Width = 0;
    while (Offset < DialogBytes.size())
    {
        const std::uint8_t Byte = DialogBytes[Offset++];
        if (Byte >= TownDialogControlCodeStart || Byte == ' ' || Byte == '/')
        {
            break;
        }

        if (Byte >= 0x20)
        {
            Width += GetTownDialogCharWidth(Byte);
        }
    }

    return Width;
}

std::size_t CountTownDialogLines(const std::vector<std::uint8_t>& DialogBytes)
{
    std::size_t LineCount = 0;
    std::size_t LineWidth = 0;
    for (std::size_t Offset = 0; Offset < DialogBytes.size(); ++Offset)
    {
        const std::uint8_t Byte = DialogBytes[Offset];
        if (Byte >= TownDialogControlCodeStart)
        {
            break;
        }

        if (Byte < 0x20)
        {
            continue;
        }

        if (Byte == '/')
        {
            ++LineCount;
            LineWidth = 0;
            continue;
        }

        LineWidth += GetTownDialogCharWidth(Byte);
        if (Byte == ' ')
        {
            const std::size_t WordWidth = MeasureTownDialogTextToDelimiter(DialogBytes, Offset + 1);
            if (LineWidth + WordWidth >= TownDialogTextWidth)
            {
                ++LineCount;
                LineWidth = 0;
            }
        }
    }

    if (LineWidth != 0)
    {
        ++LineCount;
    }

    return LineCount;
}
void DrawTownDialogBoldFontGlyph(SDL_Renderer* Renderer, const Main64Palette& Palette,
    const Grp::FontGroup& FontGroup, float StartX, float StartY, std::uint8_t ColorSelector, char Character)
{
    const unsigned char CharacterIndex = static_cast<unsigned char>(Character);
    if (CharacterIndex < 0x20)
    {
        return;
    }

    const std::size_t GlyphIndex = static_cast<std::size_t>(CharacterIndex - 0x20);
    if (GlyphIndex >= FontGroup.Glyphs.size())
    {
        return;
    }

    if (ColorSelector >= TownFontColorPaletteIndices.size())
    {
        return;
    }

    // Render_Font_Glyph translates AH through mul9 before drawing only the set
    // bits from the bold 8x8 glyph table; dialog text has no shadow treatment.
    SDL_SetRenderDrawBlendMode(Renderer, SDL_BLENDMODE_NONE);
    const std::uint8_t PaletteIndex = TownFontColorPaletteIndices[ColorSelector];
    const Grp::FontGlyph& Glyph = FontGroup.Glyphs[GlyphIndex];
    for (std::size_t Row = 0; Row < Glyph.Rows.size(); ++Row)
    {
        const std::uint8_t Bits = Glyph.Rows[Row];
        for (std::size_t Column = 0; Column < 8; ++Column)
        {
            if (((Bits >> (7 - Column)) & 1) != 0)
            {
                Mcga::DrawIndexedPixel(Renderer, Palette, PaletteIndex,
                    StartX + static_cast<float>(Column), StartY + static_cast<float>(Row));
            }
        }
    }
}

void FillTownDialogOverlayRect(std::vector<std::uint8_t>& Pixels, std::size_t PixelWidth,
    std::size_t PixelHeight, std::uint8_t PaletteIndex, std::size_t Left, std::size_t Top,
    std::size_t Width, std::size_t Height)
{
    const std::size_t EndX = std::min(Left + Width, PixelWidth);
    const std::size_t EndY = std::min(Top + Height, PixelHeight);
    for (std::size_t Row = Top; Row < EndY; ++Row)
    {
        for (std::size_t Column = Left; Column < EndX; ++Column)
        {
            Pixels[Row * PixelWidth + Column] = PaletteIndex;
        }
    }
}

void DrawTownDialogBorderToOverlay(std::vector<std::uint8_t>& Pixels, std::size_t Width, std::size_t Height)
{
    std::fill(Pixels.begin(), Pixels.end(), 0);

    // Draw_Bordered_Rectangle uses a two-pixel stepped frame around its black
    // interior. Keep this cached with the text so continuation never rebuilds
    // the whole dialog box.
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, 2, 0, Width - 4, 1);
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, 1, 1, Width - 2, 1);
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, 0, 2, 2, Height - 4);
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, Width - 2, 2, 2, Height - 4);
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, 1, Height - 2, Width - 2, 1);
    FillTownDialogOverlayRect(Pixels, Width, Height, TownDialogBorderColor, 2, Height - 1, Width - 4, 1);
}

void DrawTownDialogOverlay(SDL_Renderer* Renderer, const Main64Palette& Palette,
    std::span<const std::uint8_t> Pixels, std::size_t Width, std::size_t Height,
    std::size_t ScreenX, std::size_t ScreenY)
{
    if (Width < 4 || Height < 4 || Pixels.size() < Width * Height)
    {
        return;
    }

    // Draw_Bordered_Rectangle preserves the framebuffer in the stepped corner
    // gaps. Draw the cached overlay in bands so those pixels remain untouched.
    Mcga::DrawIndexedImage(Renderer, Palette, Pixels.subspan(2, Width - 4), Width - 4, 1,
        ScreenX + 2, ScreenY);
    Mcga::DrawIndexedImage(Renderer, Palette, Pixels.subspan(Width + 1, Width - 2), Width - 2, 1,
        ScreenX + 1, ScreenY + 1);
    Mcga::DrawIndexedImage(Renderer, Palette, Pixels.subspan(Width * 2, Width * (Height - 4)),
        Width, Height - 4, ScreenX, ScreenY + 2);
    Mcga::DrawIndexedImage(Renderer, Palette,
        Pixels.subspan(Width * (Height - 2) + 1, Width - 2), Width - 2, 1,
        ScreenX + 1, ScreenY + Height - 2);
    Mcga::DrawIndexedImage(Renderer, Palette,
        Pixels.subspan(Width * (Height - 1) + 2, Width - 4), Width - 4, 1,
        ScreenX + 2, ScreenY + Height - 1);
}

}

bool TownScene::StartTownDialogForNpc(std::size_t NpcRuntimeIndex, bool RestoreNpcState)
{
    if (NpcRuntimeIndex >= TownNpcArray.size())
    {
        return false;
    }

    TownNpcRuntimeRecord& RuntimeRecord = TownNpcArray[NpcRuntimeIndex];
    if (RuntimeRecord.NpcId >= TownMap.NpcConversations.size())
    {
        return false;
    }

    TownDialogNpcRuntimeIndex = NpcRuntimeIndex;
    TownDialogRestoreNpcState = RestoreNpcState;
    if (RestoreNpcState)
    {
        TownDialogNpcOriginalFacing = RuntimeRecord.Facing;
        TownDialogNpcOriginalSpriteSelector = RuntimeRecord.SpriteSelector;
        TownDialogNpcOriginalAiType = RuntimeRecord.NpcAiType;

        // hero_spacebar_interaction forces a normal NPC to static animation and
        // makes it face the hero only for the duration of start_npc_conversation.
        const bool HeroFacingLeft = (TownHeroState.FacingDirection & 1) != 0;
        RuntimeRecord.Facing = HeroFacingLeft ? 0 : 1;
        RuntimeRecord.NpcAiType = TownNpcAiTypeStatic;
        if (RuntimeRecord.Facing != 0)
        {
            RuntimeRecord.SpriteSelector |= 0x80;
        }
        else
        {
            RuntimeRecord.SpriteSelector &= 0x7F;
        }
    }

    // start_npc_conversation clears n_flags bit 7. Normal conversations have
    // already passed the 0xC0 flags test; special conversations need this clear
    // so the same flagged NPC does not retrigger on every town tick.
    RuntimeRecord.NpcFlags &= 0x7F;
    RuntimeRecord.AnimationPhase |= 1;
    // TODO: DOS requests soundFX_request 30 at dialog start; sound is intentionally omitted.

    TownHeroState.HeroAnimationPhase |= 1;
    SyncTownHeroRuntimeProjection();
    const std::size_t StandingActorFrameIndex =
        TownActors::GetActorFrameIndex(ActorFacingDirection, false, ActorAnimationPhase);
    (void)UpdateTownMapActorFrame(StandingActorFrameIndex);

    const std::vector<std::uint8_t>& DialogBytes = TownMap.NpcConversations[RuntimeRecord.NpcId];
    const std::size_t MeasuredLineCount = CountTownDialogLines(DialogBytes);
    const std::size_t BoxLineCount = std::min<std::size_t>(MeasuredLineCount, TownDialogMaximumBoxLines);
    TownDialogBoxLeftX = (TownHeroState.FacingDirection & 1) != 0 ? 56 : 88;
    TownDialogBoxHeight = 6 + BoxLineCount * TownDialogLineHeight;
    const std::size_t CenteredLineHeight = (BoxLineCount & 0xFE) * 8;
    const std::size_t VerticalCenterOffset = (TownDialogVerticalCenterHeight - CenteredLineHeight) / 2;
    TownDialogBoxTopY = TownDialogPositionBaseY + (TownDialogPositionBottomY - TownDialogBoxHeight)
        - VerticalCenterOffset;
    TownDialogConversationIndex = RuntimeRecord.NpcId;
    TownDialogByteOffset = 0;
    TownDialogLineCount = MeasuredLineCount;
    TownDialogOpen = true;
    TownDialogHasMorePages = false;
    TownDialogContinuationCursorVisible = false;
    TownDialogPageText.clear();
    if (BuildTownDialogPage())
    {
        InitializeTownDialogOverlay();
        return true;
    }

    TownDialogOpen = false;
    if (TownDialogRestoreNpcState)
    {
        RuntimeRecord.Facing = TownDialogNpcOriginalFacing;
        RuntimeRecord.SpriteSelector = TownDialogNpcOriginalSpriteSelector;
        RuntimeRecord.NpcAiType = TownDialogNpcOriginalAiType;
    }
    TownDialogRestoreNpcState = false;
    return false;
}

bool TownScene::TryOpenTownDialog()
{
    const std::size_t HeroAbsoluteX = GetTownHeroAbsoluteX();
    const bool FacingLeft = (TownHeroState.FacingDirection & 1) != 0;

    // This is the C++ equivalent of the DOS viewport marker scan: the runtime
    // NPC list is kept in MDT order, and the first exact X match wins.
    for (std::size_t Distance = 1; Distance <= 3; ++Distance)
    {
        if (FacingLeft && HeroAbsoluteX < Distance)
        {
            continue;
        }

        const std::size_t TargetX = FacingLeft ? HeroAbsoluteX - Distance : HeroAbsoluteX + Distance;
        for (std::size_t NpcRuntimeIndex = 0; NpcRuntimeIndex < TownNpcArray.size(); ++NpcRuntimeIndex)
        {
            const TownNpcRuntimeRecord& RuntimeRecord = TownNpcArray[NpcRuntimeIndex];
            if (RuntimeRecord.X != TargetX)
            {
                continue;
            }

            // hero_spacebar_interaction rejects both special and non-passable
            // NPCs before starting the normal conversation path.
            if ((RuntimeRecord.NpcFlags & 0xC0) != 0)
            {
                return false;
            }

            return StartTownDialogForNpc(NpcRuntimeIndex, true);
        }
    }

    return false;
}

bool TownScene::TryOpenTownSpecialDialog()
{
    const std::size_t HeroAbsoluteX = GetTownHeroAbsoluteX();
    const bool FacingLeft = (TownHeroState.FacingDirection & 1) != 0;
    if (FacingLeft && HeroAbsoluteX < 2)
    {
        return false;
    }

    const std::size_t TargetX = FacingLeft ? HeroAbsoluteX - 2 : HeroAbsoluteX + 2;
    for (std::size_t NpcRuntimeIndex = 0; NpcRuntimeIndex < TownNpcArray.size(); ++NpcRuntimeIndex)
    {
        const TownNpcRuntimeRecord& RuntimeRecord = TownNpcArray[NpcRuntimeIndex];
        if (RuntimeRecord.X != TargetX)
        {
            continue;
        }

        // check_special_npc_conversation requires the NPC to face the hero and
        // to carry n_flags bit 7. It does not alter the NPC AI or facing.
        const bool NpcFacesHero = FacingLeft ? RuntimeRecord.Facing == 0 : RuntimeRecord.Facing != 0;
        if (!NpcFacesHero || (RuntimeRecord.NpcFlags & 0x80) == 0)
        {
            return false;
        }

        return StartTownDialogForNpc(NpcRuntimeIndex, false);
    }

    return false;
}

bool TownScene::BuildTownDialogPage()
{
    if (!TownDialogOpen || TownDialogConversationIndex >= TownMap.NpcConversations.size())
    {
        return false;
    }

    const std::vector<std::uint8_t>& DialogBytes = TownMap.NpcConversations[TownDialogConversationIndex];
    TownDialogPageText.clear();
    TownDialogHasMorePages = false;
    TownDialogContinuationCursorVisible = false;

    std::size_t LineCount = 1;
    std::size_t LineWidth = 0;
    std::size_t Offset = TownDialogByteOffset;
    while (Offset < DialogBytes.size())
    {
        const std::uint8_t Byte = DialogBytes[Offset];
        if (Byte == 0xFF)
        {
            TownDialogByteOffset = Offset + 1;
            return true;
        }

        ++Offset;
        if (Byte >= TownDialogControlCodeStart)
        {
            if (!TownDialogControlWarningPrinted)
            {
                std::cerr << "town NPC dialog control code 0x" << std::hex
                    << static_cast<unsigned int>(Byte) << std::dec << " skipped" << '\n';
                TownDialogControlWarningPrinted = true;
            }
            continue;
        }

        if (Byte == '/')
        {
            if (LineCount >= TownDialogMaximumLines && TownDialogLineCount != TownDialogMaximumBoxLines)
            {
                // render_dialog_text subtracts the seven rendered lines before
                // it waits and starts the next page.
                TownDialogLineCount -= TownDialogMaximumLines;
                TownDialogByteOffset = Offset;
                TownDialogHasMorePages = true;
                return true;
            }

            TownDialogPageText.push_back('\n');
            ++LineCount;
            LineWidth = 0;
            continue;
        }

        if (Byte < 0x20)
        {
            continue;
        }

        TownDialogPageText.push_back(static_cast<char>(Byte));
        LineWidth += GetTownDialogCharWidth(Byte);
        if (Byte == ' ')
        {
            const std::size_t WordWidth = MeasureTownDialogTextToDelimiter(DialogBytes, Offset);
            if (LineWidth + WordWidth >= TownDialogTextWidth)
            {
                if (LineCount >= TownDialogMaximumLines && TownDialogLineCount != TownDialogMaximumBoxLines)
                {
                    TownDialogLineCount -= TownDialogMaximumLines;
                    TownDialogByteOffset = Offset;
                    TownDialogHasMorePages = true;
                    return true;
                }

                TownDialogPageText.push_back('\n');
                ++LineCount;
                LineWidth = 0;
            }
        }
    }

    TownDialogByteOffset = Offset;
    return true;
}

void TownScene::InitializeTownDialogOverlay()
{
    TownDialogOverlayPixels.assign(TownDialogWidth * TownDialogBoxHeight, 0);
    DrawTownDialogBorderToOverlay(TownDialogOverlayPixels, TownDialogWidth, TownDialogBoxHeight);
    TownDialogCharX = TownDialogTextInset;
    TownDialogCharY = 0;
    TownDialogLinesRendered = 0;
    TownDialogRenderTextOffset = 0;
    RenderTownDialogTextToOverlay();
}

void TownScene::ClearTownDialogOverlayRect(std::size_t Left, std::size_t Top, std::size_t Width,
    std::size_t Height)
{
    if (TownDialogOverlayPixels.empty())
    {
        return;
    }

    FillTownDialogOverlayRect(TownDialogOverlayPixels, TownDialogWidth, TownDialogBoxHeight, 0,
        Left, Top, Width, Height);
}

void TownScene::ScrollTownDialogTextAreaOnePixel()
{
    if (TownDialogOverlayPixels.empty() || TownDialogBoxHeight <= 8)
    {
        return;
    }

    // render_dialog_text adds 4 to BL and subtracts 8 from CL before the call.
    // The resulting CH is 22 tiles; Scroll_Screen_Rect_Down expands that to
    // 88 words, or this full 176-pixel dialog width. It copies one source row
    // below each destination row, top-to-bottom. The top and bottom border
    // rows remain outside the rectangle, while the vertical frame copies onto
    // identical frame pixels and therefore stays visually stable.
    const std::size_t ScrollLeft = 0;
    const std::size_t ScrollWidth = TownDialogWidth;
    const std::size_t ScrollTop = TownDialogTextInset;
    const std::size_t ScrollHeight = TownDialogBoxHeight - TownDialogTextInset * 2;
    if (ScrollWidth == 0 || ScrollLeft + ScrollWidth > TownDialogWidth
        || ScrollTop + ScrollHeight >= TownDialogBoxHeight)
    {
        return;
    }

    for (std::size_t Row = 0; Row < ScrollHeight; ++Row)
    {
        const auto SourceBegin = TownDialogOverlayPixels.begin()
            + static_cast<std::ptrdiff_t>((ScrollTop + Row + 1) * TownDialogWidth + ScrollLeft);
        const auto DestinationBegin = TownDialogOverlayPixels.begin()
            + static_cast<std::ptrdiff_t>((ScrollTop + Row) * TownDialogWidth + ScrollLeft);
        std::copy_n(SourceBegin, ScrollWidth, DestinationBegin);
    }
}

void TownScene::DrawTownDialogGlyphToOverlay(std::size_t StartX, std::size_t StartY,
    std::uint8_t ColorSelector, char Character)
{
    if (!TownHudFontsLoaded || TownBoldFontGroup.Glyphs.empty() || ColorSelector >= TownFontColorPaletteIndices.size())
    {
        return;
    }

    const std::uint8_t CharacterIndex = static_cast<std::uint8_t>(static_cast<unsigned char>(Character));
    if (CharacterIndex < 0x20 || CharacterIndex >= 0x80)
    {
        return;
    }

    const std::size_t GlyphIndex = static_cast<std::size_t>(CharacterIndex - 0x20);
    if (GlyphIndex >= TownBoldFontGroup.Glyphs.size())
    {
        return;
    }

    const std::uint8_t PaletteIndex = TownFontColorPaletteIndices[ColorSelector];
    const Grp::FontGlyph& Glyph = TownBoldFontGroup.Glyphs[GlyphIndex];
    const std::size_t InnerTextRight = TownDialogWidth - TownDialogBorderThickness;
    const std::size_t InnerTextBottom = TownDialogBoxHeight - TownDialogBorderThickness;
    for (std::size_t Row = 0; Row < Glyph.Rows.size() && Row + StartY < TownDialogBoxHeight; ++Row)
    {
        const std::uint8_t Bits = Glyph.Rows[Row];
        for (std::size_t Column = 0; Column < 8 && Column + StartX < TownDialogWidth; ++Column)
        {
            const std::size_t PixelX = StartX + Column;
            const std::size_t PixelY = StartY + Row;
            if (PixelX < TownDialogInnerTextLeft || PixelX >= InnerTextRight
                || PixelY < TownDialogInnerTextTop || PixelY >= InnerTextBottom)
            {
                continue;
            }

            if (((Bits >> (7 - Column)) & 1) != 0)
            {
                TownDialogOverlayPixels[PixelY * TownDialogWidth + PixelX] = PaletteIndex;
            }
        }
    }
}

void TownScene::RenderTownDialogTextToOverlay()
{
    while (TownDialogRenderTextOffset < TownDialogPageText.size())
    {
        const char Character = TownDialogPageText[TownDialogRenderTextOffset++];
        if (Character == '\n')
        {
            TownDialogCharX = TownDialogTextInset;
            ++TownDialogCharY;
            ++TownDialogLinesRendered;
            if (TownDialogCharY == TownDialogMaximumBoxLines)
            {
                --TownDialogCharY;
                // loc_64FD performs all ten VRAM row copies synchronously
                // before loc_6516 continues rendering the dialog stream.
                // There is no frame wait in that assembly loop.
                for (std::size_t Step = 0; Step < TownDialogScrollStepCount; ++Step)
                {
                    ScrollTownDialogTextAreaOnePixel();
                }
            }
            continue;
        }

        const std::uint8_t Byte = static_cast<std::uint8_t>(static_cast<unsigned char>(Character));
        if (Byte < 0x20 || Byte >= 0x80)
        {
            continue;
        }

        const std::size_t GlyphX = TownDialogCharX - GetTownDialogCharXOffset(Byte);
        const std::size_t GlyphY = TownDialogTextInset + TownDialogCharY * TownDialogLineHeight;
        DrawTownDialogGlyphToOverlay(GlyphX, GlyphY, TownDialogFontColorSelector, Character);
        TownDialogCharX += GetTownDialogCharWidth(Byte);
    }

    if (TownDialogHasMorePages)
    {
        // The slash after the seventh line takes the assembly path through
        // loc_64E6 before it waits on the red continuation cursor.
        TownDialogCharX = TownDialogTextInset;
        TownDialogCharY = TownDialogMaximumLines;
        TownDialogLinesRendered = TownDialogMaximumLines;
        TownDialogContinuationCursorVisible = true;
    }
}

void TownScene::AdvanceTownDialog()
{
    if (!TownDialogOpen)
    {
        return;
    }

    if (TownDialogHasMorePages)
    {
        // loc_652E clears only the 0x7C cursor rectangle, clears the space
        // latch, resets dialog_lines_rendered, and resumes at dialog_text_ptr.
        TownDialogContinuationCursorVisible = false;
        ClearTownDialogOverlayRect(TownDialogContinuationCursorX, TownDialogContinuationCursorY,
            TownDialogContinuationCursorWidth, TownDialogContinuationCursorHeight);
        TownDialogLinesRendered = 0;
        TownDialogCharX = TownDialogTextInset;
        TownDialogRenderTextOffset = 0;

        if (BuildTownDialogPage())
        {
            RenderTownDialogTextToOverlay();
            return;
        }
    }

    if (TownDialogRestoreNpcState && TownDialogNpcRuntimeIndex < TownNpcArray.size())
    {
        TownNpcRuntimeRecord& RuntimeRecord = TownNpcArray[TownDialogNpcRuntimeIndex];
        RuntimeRecord.Facing = TownDialogNpcOriginalFacing;
        RuntimeRecord.SpriteSelector = TownDialogNpcOriginalSpriteSelector;
        RuntimeRecord.NpcAiType = TownDialogNpcOriginalAiType;
    }

    TownDialogOpen = false;
    TownDialogHasMorePages = false;
    TownDialogContinuationCursorVisible = false;
    TownDialogRestoreNpcState = false;
    TownDialogPageText.clear();
    TownDialogOverlayPixels.clear();
    TownDialogCharX = 0;
    TownDialogCharY = 0;
    TownDialogLinesRendered = 0;
    TownDialogRenderTextOffset = 0;
}

void TownScene::UpdateTownDialogTownFrame()
{
    // wait_for_dialog_input calls update_npcs_and_render, so dialog input blocks
    // hero movement while NPC AI and animated town tiles continue to advance.
    UpdateTownNpcRuntimeRecords();
    UpdateTownPatternAnimations();
}

void TownScene::DrawTownDialog(SDL_Renderer* Renderer) const
{
    if (!TownDialogOverlayPixels.empty())
    {
        DrawTownDialogOverlay(Renderer, Palette, TownDialogOverlayPixels, TownDialogWidth,
            TownDialogBoxHeight, TownDialogBoxLeftX, TownDialogBoxTopY);
    }

    if (TownHudFontsLoaded && !TownBoldFontGroup.Glyphs.empty())
    {
        if (TownDialogContinuationCursorVisible)
        {
            DrawTownDialogBoldFontGlyph(Renderer, Palette, TownBoldFontGroup,
                static_cast<float>(TownDialogBoxLeftX + TownDialogContinuationCursorX),
                static_cast<float>(TownDialogBoxTopY + TownDialogContinuationCursorY),
                TownDialogContinuationCursorColorSelector,
                static_cast<char>(TownDialogContinuationCursorGlyph));
        }
    }
}
