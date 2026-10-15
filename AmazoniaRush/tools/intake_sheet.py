#!/usr/bin/env python3
"""Takes a four-up art sheet that arrived as a flat JPEG and turns it into a
sheet the media forge can read.

Generated art comes back with the transparency checkerboard baked into the
pixels and at whatever size the generator felt like. This clears the
checkerboard back to alpha, tight-crops each of the four pieces, and lays them
out on the 1584x672 canvas the forge expects, with wide gaps between them so
the slicer's cuts land in empty space.

    python3 tools/intake_sheet.py ../remains_asset.jpg b

The second argument is the drop the sheet belongs to ("a" for Egypt_1, "b" for
Egypt_2); the file is written into that drop's gameplay folder as a PNG, where
forge_media.py will find it on its next run.
"""

from __future__ import annotations

import collections
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE.parent.parent
SHEET = (1584, 672)
MARGIN = 26
# The checkerboard is two near-white greys. Anything this pale and this grey,
# reachable from the border, is backdrop rather than art.
# A soft grey contact shadow is part of the backdrop too, so the sweep reaches
# well below white. Art survives it by being coloured: anything this grey and
# this pale, connected to the border, was never meant to be kept.
PALE = 198
FLAT = 13
# The looser second sweep: grey enough and bright enough to be a cast shadow
# on white paper rather than anything anyone painted on purpose.
DIM = 162
DRAB = 30
# How dead-neutral a pixel must be to count as backdrop when the art itself is
# nearly white.
FINE = 6
# Smallest enclosed patch of checkerboard worth clearing, in pixels.
POCKET = 400


def peel(plate: Image.Image, tight: bool = False) -> Image.Image:
    """Clears the baked checkerboard, keeping pale pixels inside the art.

    `tight` is for art that is itself nearly white: beer froth, linen, bone.
    The checkerboard is perfectly neutral and froth never is, so the sweep is
    narrowed to dead grey and the shadow pass is skipped rather than risk it
    walking up into the head of the beer.
    """
    plate = plate.convert("RGB")
    wide, tall = plate.size
    grid = plate.load()
    backdrop = bytearray(wide * tall)
    for y in range(tall):
        row = y * wide
        for x in range(wide):
            r, g, b = grid[x, y]
            span = FINE if tight else FLAT
            if max(r, g, b) - min(r, g, b) <= span and (r + g + b) / 3 >= PALE:
                backdrop[row + x] = 1

    seen = bytearray(wide * tall)
    queue = collections.deque()
    for x in range(wide):
        for y in (0, tall - 1):
            if backdrop[y * wide + x]:
                queue.append((x, y))
                seen[y * wide + x] = 1
    for y in range(tall):
        for x in (0, wide - 1):
            if backdrop[y * wide + x]:
                queue.append((x, y))
                seen[y * wide + x] = 1

    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= wide or ny >= tall:
                continue
            spot = ny * wide + nx
            if seen[spot] or not backdrop[spot]:
                continue
            seen[spot] = 1
            queue.append((nx, ny))

    # The contact shadow under a figure is greyer and darker than the
    # checkerboard, and the strict sweep stops at its soft edge. A second pass
    # creeps out of the cleared ground with a looser idea of what grey is, so
    # the shadow goes with the backdrop instead of travelling as a white blot.
    if tight:
        # Dead-neutral grey is the checkerboard and nothing else on a sheet
        # like this, so the pockets the flood cannot reach -- the hole in a
        # tankard handle, the gap under a bent rim -- go as well. Only the
        # roomy ones: a white speck in the froth is froth.
        for seat in range(wide * tall):
            if not backdrop[seat] or seen[seat]:
                continue
            pocket = [seat]
            seen[seat] = 1
            walk = [seat]
            while walk:
                at = walk.pop()
                x, y = at % wide, at // wide
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= wide or ny >= tall:
                        continue
                    spot = ny * wide + nx
                    if backdrop[spot] and not seen[spot]:
                        seen[spot] = 1
                        pocket.append(spot)
                        walk.append(spot)
            if len(pocket) < POCKET:
                for spot in pocket:
                    seen[spot] = 0
    else:
        queue.extend(
            (x, y)
            for y in range(tall)
            for x in range(wide)
            if seen[y * wide + x]
        )
        while queue:
            x, y = queue.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= wide or ny >= tall:
                    continue
                spot = ny * wide + nx
                if seen[spot]:
                    continue
                r, g, b = grid[nx, ny]
                if max(r, g, b) - min(r, g, b) > DRAB or (r + g + b) / 3 < DIM:
                    continue
                seen[spot] = 1
                queue.append((nx, ny))

    out = plate.convert("RGBA")
    paint = out.load()
    for y in range(tall):
        row = y * wide
        for x in range(wide):
            if seen[row + x]:
                paint[x, y] = (0, 0, 0, 0)
    return out


def bleed_only(plate: Image.Image) -> Image.Image:
    """Keeps the blood and throws the floor away.

    The blood decals arrive painted onto a slab of sandstone, which would land
    on our floor as a floating tile. Sandstone is barely red; blood is nothing
    but. So a pixel is kept in proportion to how much its red beats its green
    and blue, which leaves the spatter with soft edges and no slab.
    """
    plate = plate.convert("RGBA")
    wide, tall = plate.size
    paint = plate.load()
    for y in range(tall):
        for x in range(wide):
            r, g, b, a = paint[x, y]
            if a == 0:
                continue
            lean = min(r / max(g, 1), r / max(b, 1))
            keep = int(max(0.0, min(1.0, (lean - 1.22) * 3.4)) * 255)
            paint[x, y] = (r, g, b, min(a, keep))
    return plate


def quarters(plate: Image.Image) -> list[Image.Image]:
    """The four pieces, tight-cropped, in reading order."""
    wide, tall = plate.size
    mid_x, mid_y = wide // 2, tall // 2
    boxes = [
        (0, 0, mid_x, mid_y),
        (mid_x, 0, wide, mid_y),
        (0, mid_y, mid_x, tall),
        (mid_x, mid_y, wide, tall),
    ]
    cut = []
    for box in boxes:
        piece = plate.crop(box)
        tight = piece.split()[3].getbbox()
        cut.append(piece.crop(tight) if tight else piece)
    return cut


def lay(pieces: list[Image.Image]) -> Image.Image:
    """Drops the four pieces into the canvas the forge slices."""
    sheet = Image.new("RGBA", SHEET, (0, 0, 0, 0))
    cell = (SHEET[0] // 2 - MARGIN * 2, SHEET[1] // 2 - MARGIN * 2)
    for index, piece in enumerate(pieces):
        fit = min(cell[0] / piece.width, cell[1] / piece.height, 1.0)
        if fit < 1.0:
            piece = piece.resize(
                (max(1, round(piece.width * fit)), max(1, round(piece.height * fit))),
                Image.LANCZOS,
            )
        home_x = (index % 2) * SHEET[0] // 2
        home_y = (index // 2) * SHEET[1] // 2
        sheet.paste(
            piece,
            (
                home_x + (SHEET[0] // 2 - piece.width) // 2,
                home_y + (SHEET[1] // 2 - piece.height) // 2,
            ),
            piece,
        )
    return sheet


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    source = Path(sys.argv[1]).resolve()
    drop = sys.argv[2] if len(sys.argv) > 2 else "b"
    folder = RAW / f"{'Egypt_1' if drop == 'a' else 'Egypt_2'}_gameplay_assets"
    target = folder / f"{source.stem}.png"

    plate = peel(Image.open(source), tight="--tight" in sys.argv)
    if "--blood" in sys.argv:
        plate = bleed_only(plate)
    if "--one" in sys.argv:
        # A lone prop still travels on a sheet, because that is the only thing
        # the forge reads. The other three quarters stay empty and the slicer
        # throws them away.
        tight = plate.split()[3].getbbox()
        sheet = lay([plate.crop(tight) if tight else plate])
    else:
        sheet = lay(quarters(plate))
    sheet.save(target)
    held = sum(1 for piece in quarters(sheet) if piece.width > 16)
    print(f"{source.name} -> {target.relative_to(RAW)}  ({held} pieces, {SHEET[0]}x{SHEET[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
