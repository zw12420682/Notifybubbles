#pragma once
#include <stddef.h>
#include <math.h>
typedef struct { double width, height, x, y; } NFBTile;
// Input is ordered top-to-bottom. Keep natural sizes unless either axis overflows.
static inline double NFBArrange(NFBTile *tiles, size_t count, double width, double height) {
    if (!count || width <= 0 || height <= 0) return 1;
    double total = 0, widest = 0;
    for (size_t i=0; i<count; i++) {
        if (!isfinite(tiles[i].width) || !isfinite(tiles[i].height) || tiles[i].width<=0 || tiles[i].height<=0) return 0;
        total += tiles[i].height; widest = fmax(widest, tiles[i].width);
    }
    double gap = count > 1 ? fmin(6, height / (count * 8.0)) : 0;
    double factor = fmin(1, fmin(width / widest, (height-gap*(count-1))/total));
    double y = height - total*factor - gap*(count-1);
    for (size_t i=0; i<count; i++) {
        tiles[i].width *= factor; tiles[i].height *= factor;
        tiles[i].x=0; tiles[i].y=y; y += tiles[i].height+gap;
    }
    return factor;
}

// Compute one scale factor so the first `rowCount` tiles (a horizontal row) fit
// the width, and the remaining vertical tiles fit below the row's natural
// height. Does not mutate tiles.
static inline double NFBScaleFactor(NFBTile *tiles, size_t count, size_t rowCount, double width, double height) {
    if (!count || width <= 0 || height <= 0) return 1;
    double rowWidth = 0, rowHeight = 0;
    for (size_t i=0; i<count && i<rowCount; i++) {
        rowWidth += tiles[i].width + (i ? 6 : 0);
        rowHeight = fmax(rowHeight, tiles[i].height);
    }
    size_t vcount = count - rowCount;
    double total = 0, widest = 0;
    for (size_t i=rowCount; i<count; i++) {
        total += tiles[i].height; widest = fmax(widest, tiles[i].width);
    }
    double vgap = vcount > 1 ? fmin(6, height / (vcount * 8.0)) : 0;
    double factor = 1;
    if (rowCount) factor = fmin(factor, width / rowWidth);
    if (vcount) factor = fmin(factor, fmin(width / widest, (height - rowHeight - vgap*(vcount-1)) / total));
    return factor > 0 ? factor : 0;
}

// Scale every tile, lay the first `rowCount` tiles out left-to-right at the top,
// then stack the rest vertically with the first `topCount` of them pinned just
// below the row and the remainder bottom-aligned. Returns the factor.
static inline double NFBArrangeMixed(NFBTile *tiles, size_t count, size_t rowCount, size_t topCount, double width, double height) {
    if (!count || width <= 0 || height <= 0) return 1;
    for (size_t i=0; i<count; i++) {
        if (!isfinite(tiles[i].width) || !isfinite(tiles[i].height) || tiles[i].width<=0 || tiles[i].height<=0) return 0;
    }
    double factor = NFBScaleFactor(tiles, count, rowCount, width, height);
    if (factor <= 0) return 0;

    // Horizontal mini row at the top, left-to-right.
    double x = 0, rowHeight = 0;
    double rgap = rowCount > 1 ? 6 : 0;
    for (size_t i=0; i<count && i<rowCount; i++) {
        tiles[i].width *= factor; tiles[i].height *= factor;
        tiles[i].x = x; tiles[i].y = 0;
        rowHeight = fmax(rowHeight, tiles[i].height);
        x += tiles[i].width + rgap;
    }

    // Vertical group below the row: landscape prefix pinned to the row, the
    // portrait remainder bottom-aligned.
    size_t vcount = count - rowCount;
    for (size_t i=rowCount; i<count; i++) { tiles[i].width *= factor; tiles[i].height *= factor; }
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
    return factor;
}

// Slide the vertical top group (landscape: `topCount` tiles starting after the
// row) through the free space below the row. position 0 keeps it just below the
// row; position 1 puts its bottom at the screen bottom.
static inline void NFBPositionLandscape(NFBTile *tiles, size_t count, size_t rowCount, size_t topCount, double height, double position) {
    if (!count || !topCount || rowCount + topCount > count || height <= 0) return;
    if (!isfinite(position)) position = 0;
    position = fmax(0, fmin(1, position));
    size_t start = rowCount;
    double top = tiles[start].y;
    double bottom = tiles[start + topCount - 1].y + tiles[start + topCount - 1].height;
    double offset = fmax(0, height - top - (bottom - top)) * position;
    for (size_t i=start; i<start+topCount; i++) tiles[i].y += offset;
}
