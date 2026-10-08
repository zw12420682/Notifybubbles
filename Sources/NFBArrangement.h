#pragma once
#include <stddef.h>
#include <math.h>
typedef struct { double width, height, x, y; } NFBTile;

// Lay out tiles WITHOUT scaling: the first `rowCount` tiles form a horizontal
// row at the top (left-to-right), the remaining tiles stack vertically with the
// first `topCount` of them pinned just below the row and the rest bottom-aligned.
// Natural sizes are preserved. Returns 1 on success, 0 on invalid input.
static inline int NFBArrangeMixed(NFBTile *tiles, size_t count, size_t rowCount, size_t topCount, double height) {
    if (!count || height <= 0) return 1;
    for (size_t i=0; i<count; i++) {
        if (!isfinite(tiles[i].width) || !isfinite(tiles[i].height) || tiles[i].width<=0 || tiles[i].height<=0) return 0;
    }

    // Horizontal mini row at the top, left-to-right.
    double x = 0, rowHeight = 0;
    double rgap = rowCount > 1 ? 6 : 0;
    for (size_t i=0; i<count && i<rowCount; i++) {
        tiles[i].x = x; tiles[i].y = 0;
        rowHeight = fmax(rowHeight, tiles[i].height);
        x += tiles[i].width + rgap;
    }

    // Vertical group below the row: landscape prefix pinned to the row, the
    // portrait remainder bottom-aligned.
    size_t vcount = count - rowCount;
    if (vcount) {
        double vgap = vcount > 1 ? fmin(6, height / (vcount * 8.0)) : 0;
        double total = 0;
        for (size_t i=rowCount; i<count; i++) total += tiles[i].height;
        double y = height - total - vgap*(vcount-1);
        for (size_t i=rowCount; i<count; i++) { tiles[i].x = 0; tiles[i].y = y; y += tiles[i].height + vgap; }
        if (topCount) {
            double offset = tiles[rowCount].y - rowHeight;
            for (size_t i=rowCount; i<count && i<rowCount+topCount; i++) tiles[i].y -= offset;
        }
    }
    return 1;
}

// Slide the whole top group (mini row + landscape: `rowCount + topCount` tiles)
// together through the free vertical space. position 0 keeps the mini row at the
// top; position 1 puts the group's bottom at the screen bottom. This links the
// mini row's top to the landscape slider setting.
static inline void NFBPositionLandscape(NFBTile *tiles, size_t count, size_t rowCount, size_t topCount, double height, double position) {
    size_t total = rowCount + topCount;
    if (!count || !total || total > count || height <= 0) return;
    if (!isfinite(position)) position = 0;
    position = fmax(0, fmin(1, position));
    double top = tiles[0].y;
    double bottom = tiles[total - 1].y + tiles[total - 1].height;
    double offset = fmax(0, height - top - (bottom - top)) * position;
    for (size_t i=0; i<total; i++) tiles[i].y += offset;
}
