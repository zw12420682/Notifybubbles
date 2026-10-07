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

// Landscape prefix is pinned to the top; remaining portrait group stays bottom-aligned.
static inline double NFBArrangeGroups(NFBTile *tiles, size_t count, size_t landscapes, double width, double height) {
    double factor = NFBArrange(tiles,count,width,height);
    if (factor > 0 && count && landscapes) {
        double offset = tiles[0].y;
        for (size_t i=0; i<count && i<landscapes; i++) tiles[i].y -= offset;
    }
    return factor;
}

// Slide the landscape group only through the remaining free vertical space.
static inline void NFBPositionLandscape(NFBTile *tiles, size_t count, size_t landscapes, double height, double position) {
    if (!count || !landscapes || landscapes > count || height <= 0) return;
    if (!isfinite(position)) position = 0;
    position = fmax(0, fmin(1, position));
    double bottom = tiles[landscapes-1].y + tiles[landscapes-1].height;
    double gap = landscapes < count ? fmin(6, height / (count * 8.0)) : 0;
    double limit = landscapes < count ? tiles[landscapes].y - gap : height;
    double offset = fmax(0, limit - bottom) * position;
    for (size_t i=0; i<landscapes; i++) tiles[i].y += offset;
}
