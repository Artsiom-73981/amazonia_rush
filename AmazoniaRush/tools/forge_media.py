#!/usr/bin/env python3
"""Turns the raw art drops into everything the app ships.

  * slices every 1584x672 sheet into its four separate props
  * recompresses the vertical scenes and the two world maps
  * keys the baked checkerboard out of the wordmark
  * renders the blurred boot plates in both orientations
  * builds the asset catalogue and the obfuscated Swift name tables
  * copies the audio, de-duplicating the two drops

Run from the AmazoniaRush folder:

    uv run --with pillow python tools/forge_media.py
"""

from __future__ import annotations

import collections
import hashlib
import json
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = Path(__file__).resolve().parent.parent
RAW = HERE.parent
CATALOGUE = HERE / "App" / "Media.xcassets"
AUDIO = HERE / "App" / "Audio"
GENERATED = HERE / "App" / "Generated"

DROPS = {"a": "Egypt_1", "b": "Egypt_2"}
PROP_EDGE = 360
SCENE_QUALITY = 82
BOOT_PORTRAIT = (1290, 2796)
BOOT_LANDSCAPE = (2796, 1290)
SHEET_SIZE = (1584, 672)
PIECES_PER_SHEET = 4

# The scene whose blur becomes the boot plate. Smooth golden dunes: no hard
# silhouettes, so the blur stays clean behind the wordmark in either
# orientation.
BOOT_SOURCE = "Egypt_1_gameplay_assets/bg_location_1_asset.webp"


def sweep(folder: Path) -> None:
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True, exist_ok=True)


def catalogue_root() -> None:
    sweep(CATALOGUE)
    (CATALOGUE / "Contents.json").write_text(
        json.dumps({"info": {"author": "forge", "version": 1}}, indent=2)
    )


def enrol(name: str, image: Image.Image, suffix: str, quality: int | None = None) -> None:
    """Writes one image into the catalogue as a universal, unscaled asset."""
    slot = CATALOGUE / f"{name}.imageset"
    slot.mkdir(parents=True, exist_ok=True)
    leaf = f"{name}{suffix}"
    target = slot / leaf
    if suffix == ".jpg":
        image.convert("RGB").save(target, quality=quality or SCENE_QUALITY, optimize=True, progressive=True)
    else:
        image.save(target, optimize=True)
    (slot / "Contents.json").write_text(
        json.dumps(
            {
                "images": [{"idiom": "universal", "filename": leaf}],
                "info": {"author": "forge", "version": 1},
                "properties": {"template-rendering-intent": "original"},
            },
            indent=2,
        )
    )


def enrol_wash(name: str, rgb: tuple[int, int, int]) -> None:
    """A flat colour asset, used by the launch plist so the very first frame is
    already the right darkness instead of white."""
    slot = CATALOGUE / f"{name}.colorset"
    slot.mkdir(parents=True, exist_ok=True)
    (slot / "Contents.json").write_text(
        json.dumps(
            {
                "colors": [
                    {
                        "color": {
                            "color-space": "srgb",
                            "components": {
                                "alpha": "1.000",
                                "blue": f"{rgb[2] / 255:.3f}",
                                "green": f"{rgb[1] / 255:.3f}",
                                "red": f"{rgb[0] / 255:.3f}",
                            },
                        },
                        "idiom": "universal",
                    }
                ],
                "info": {"author": "forge", "version": 1},
            },
            indent=2,
        )
    )


def snake(stem: str) -> str:
    stem = stem.replace("_asset", "")
    stem = re.sub(r"[^0-9a-zA-Z]+", "_", stem)
    stem = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", stem)
    return re.sub(r"_+", "_", stem).strip("_").lower()


def camel(name: str) -> str:
    chunks = [chunk for chunk in name.split("_") if chunk]
    if not chunks:
        return "unnamed"
    head, *rest = chunks
    out = head + "".join(chunk.capitalize() for chunk in rest)
    if out[0].isdigit():
        out = "x" + out
    return out


# --- sheet slicing ---------------------------------------------------------


def ink_profile(alpha: Image.Image, box: tuple[int, int, int, int], axis: int) -> list[int]:
    """Alpha coverage per column (axis 0) or per row (axis 1) inside `box`."""
    left, top, right, bottom = box
    grid = alpha.load()
    if axis == 0:
        return [
            sum(grid[x, y] for y in range(top, bottom, 2)) for x in range(left, right)
        ]
    return [sum(grid[x, y] for x in range(left, right, 2)) for y in range(top, bottom)]


def quietest_cut(profile: list[int]) -> tuple[int, float]:
    """Finds the emptiest line in the middle of a profile.

    Returns the offset and how empty it is relative to the busiest line, so the
    caller can prefer a real gap over cutting through an object.
    """
    span = len(profile)
    if span < 40:
        return span // 2, 1.0
    margin = max(8, int(span * 0.22))
    window = profile[margin : span - margin]
    if not window:
        return span // 2, 1.0
    peak = max(profile) or 1
    # Smooth a little so a single bright pixel does not hide a genuine gap.
    best_at, best_val = 0, None
    for index in range(len(window)):
        low = max(0, index - 2)
        high = min(len(window), index + 3)
        local = sum(window[low:high]) / (high - low)
        if best_val is None or local < best_val:
            best_val = local
            best_at = index
    return margin + best_at, (best_val or 0) / peak


def slice_sheet(sheet: Image.Image) -> list[Image.Image]:
    """Splits a sheet into the props painted on it.

    Most sheets carry four, laid out 4-across or 2x2, but a single prop arrives
    on a sheet of its own as well. How many islands of paint there are decides
    how many cuts to look for, so a lone mug is never quartered.

    The sheet is repeatedly cut along whichever axis offers the emptiest line,
    which handles both layouts and survives props whose legs nearly touch.
    """
    alpha = sheet.split()[3]
    start = alpha.getbbox() or (0, 0, *sheet.size)
    # Counting props on a sheet is unreliable: legs and shadows bridge the
    # gaps. Telling a sheet of four from a sheet of one is not, because one
    # prop holds nearly all the paint on its sheet.
    want = 1 if lone(sheet) else PIECES_PER_SHEET
    if want == 1:
        return harvest(sheet, [start])
    pieces: list[tuple[int, int, int, int]] = [start]

    while len(pieces) < want:
        best = None
        for index, box in enumerate(pieces):
            left, top, right, bottom = box
            if right - left < 48 or bottom - top < 48:
                continue
            across = quietest_cut(ink_profile(alpha, box, 0))
            down = quietest_cut(ink_profile(alpha, box, 1))
            area = (right - left) * (bottom - top)
            for axis, (offset, emptiness) in ((0, across), (1, down)):
                # Emptier cuts win; bigger pieces break ties.
                merit = emptiness - area / (sheet.width * sheet.height) * 0.08
                if best is None or merit < best[0]:
                    best = (merit, index, axis, offset)
        if best is None:
            break
        _, index, axis, offset = best
        left, top, right, bottom = pieces.pop(index)
        if axis == 0:
            pieces.append((left, top, left + offset, bottom))
            pieces.append((left + offset, top, right, bottom))
        else:
            pieces.append((left, top, right, top + offset))
            pieces.append((left, top + offset, right, bottom))

    # Props whose limbs reach across the gap can defeat the adaptive cut, so
    # the two regular grids compete with it and the tidiest layout wins.
    left, top, right, bottom = start
    mid_x = (left + right) // 2
    mid_y = (top + bottom) // 2
    quadrants = [
        (left, top, mid_x, mid_y),
        (mid_x, top, right, mid_y),
        (left, mid_y, mid_x, bottom),
        (mid_x, mid_y, right, bottom),
    ]
    lanes = []
    for step in range(PIECES_PER_SHEET):
        lane_left = left + (right - left) * step // PIECES_PER_SHEET
        lane_right = left + (right - left) * (step + 1) // PIECES_PER_SHEET
        lanes.append((lane_left, top, lane_right, bottom))

    plans = [pieces] if want != PIECES_PER_SHEET else [pieces, quadrants, lanes]
    scored = []
    for plan in plans:
        cut = harvest(sheet, plan)
        cost = tidiness(cut, want) + bleeding(alpha, plan, start) * 70.0
        cost += sum(max(0, clumps(patch) - 1) for patch in cut) * 260.0
        scored.append((cost, plan))
    return harvest(sheet, min(scored, key=lambda pair: pair[0])[1])


def bleeding(alpha: Image.Image, pieces: list[tuple[int, int, int, int]], outer) -> float:
    """How much art each cut runs through, 0 when every cut fell in a gap.

    A plan that halves a prop scores badly here no matter how tidy its boxes
    look, which is what keeps a four-up sheet laid out 2x2 from being read as
    four lanes.
    """
    cost = 0.0
    for left, top, right, bottom in pieces:
        walls = (
            (left, True), (right - 1, True),
            (top, False), (bottom - 1, False),
        )
        for at, upright in walls:
            low, high = (outer[0], outer[2]) if upright else (outer[1], outer[3])
            if at <= low + 1 or at >= high - 2:
                continue
            line = (
                alpha.crop((at, top, at + 1, bottom)) if upright
                else alpha.crop((left, at, right, at + 1))
            )
            lit = list(line.getdata())
            if not lit:
                continue
            cost += sum(1 for shade in lit if shade > 24) / len(lit)
    return cost


def tidiness(cut: list[Image.Image], want: int = PIECES_PER_SHEET) -> float:
    """Lower is better. Punishes missing pieces, slivers and lopsided areas."""
    if not cut:
        return 1e9
    penalty = abs(len(cut) - want) * 100.0
    areas = [patch.width * patch.height for patch in cut]
    mean = sum(areas) / len(areas)
    for patch, area in zip(cut, areas):
        slim = min(patch.width, patch.height) / max(patch.width, patch.height)
        if slim < 0.16:
            penalty += 40.0
        penalty += abs(area - mean) / mean
    return penalty


def harvest(sheet: Image.Image, pieces: list[tuple[int, int, int, int]]) -> list[Image.Image]:
    # Reading order: top to bottom, then left to right.
    pieces = sorted(pieces, key=lambda box: (box[1] // 64, box[0]))
    cut: list[Image.Image] = []
    for box in pieces:
        patch = sheet.crop(box)
        tight = patch.split()[3].getbbox()
        if tight:
            patch = patch.crop(tight)
        if patch.width < 16 or patch.height < 16:
            continue
        scale = PROP_EDGE / max(patch.width, patch.height)
        if scale < 1.0:
            patch = patch.resize(
                (max(1, round(patch.width * scale)), max(1, round(patch.height * scale))),
                Image.LANCZOS,
            )
        cut.append(patch)
    return cut


def lone(sheet: Image.Image) -> bool:
    """True when there is one prop on the sheet rather than four."""
    shoals = islands(sheet, 300)
    if not shoals:
        return False
    return max(shoals) >= sum(shoals) * 0.9


def clumps(patch: Image.Image, span: int = 72) -> int:
    """How many separate things ended up in one piece.

    A cut that reads a 2x2 sheet as four columns leaves two props stacked in
    every piece, and both the gaps and the box shapes look perfectly innocent.
    Counting the islands of paint is what catches it.
    """
    shoals = islands(patch, span)
    if not shoals:
        return 0
    # Measured against the biggest island, not the whole piece: a second prop
    # is roughly as large as the first, while a chip of stone that broke off a
    # neighbour is not worth refusing a cut over.
    floor = max(4, shoals[0] // 6)
    return sum(1 for size in shoals if size >= floor)


def islands(patch: Image.Image, span: int) -> list[int]:
    """The size of every connected patch of paint, biggest first."""
    mask = patch.split()[3]
    fit = span / max(mask.size)
    if fit < 1.0:
        mask = mask.resize((max(1, round(mask.width * fit)), max(1, round(mask.height * fit))))
    wide, tall = mask.size
    lit = [1 if shade > 24 else 0 for shade in mask.getdata()]
    seen = bytearray(wide * tall)
    found: list[int] = []
    for seat in range(wide * tall):
        if not lit[seat] or seen[seat]:
            continue
        seen[seat] = 1
        shoal = [seat]
        size = 0
        while shoal:
            at = shoal.pop()
            size += 1
            x, y = at % wide, at // wide
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= wide or ny >= tall:
                        continue
                    step = ny * wide + nx
                    if lit[step] and not seen[step]:
                        seen[step] = 1
                        shoal.append(step)
        found.append(size)
    found.sort(reverse=True)
    return found


# --- wordmark --------------------------------------------------------------


def strip_checker(plate: Image.Image) -> Image.Image:
    """Removes the checkerboard that was flattened into the wordmark JPEG.

    Only background-coloured pixels reachable from the border are cleared, so
    the white highlights inside the letters survive.
    """
    plate = plate.convert("RGB")
    width, height = plate.size
    grid = plate.load()
    backdrop = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            r, g, b = grid[x, y]
            flat = max(r, g, b) - min(r, g, b)
            if flat <= 16 and (r + g + b) / 3 >= 206:
                backdrop[y * width + x] = 1

    seen = bytearray(width * height)
    queue = collections.deque()
    for x in range(width):
        for y in (0, height - 1):
            if backdrop[y * width + x] and not seen[y * width + x]:
                seen[y * width + x] = 1
                queue.append((x, y))
    for y in range(height):
        for x in (0, width - 1):
            if backdrop[y * width + x] and not seen[y * width + x]:
                seen[y * width + x] = 1
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                seat = ny * width + nx
                if backdrop[seat] and not seen[seat]:
                    seen[seat] = 1
                    queue.append((nx, ny))

    mask = Image.frombytes("L", (width, height), bytes(255 - 255 * bit for bit in seen))
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    out = plate.convert("RGBA")
    out.putalpha(mask)
    box = out.split()[3].getbbox()
    if box:
        out = out.crop(box)
    return out


# --- boot plates -----------------------------------------------------------


def boot_plate(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    want_w, want_h = size
    scale = max(want_w / source.width, want_h / source.height)
    grown = source.resize(
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
        Image.LANCZOS,
    )
    left = (grown.width - want_w) // 2
    top = (grown.height - want_h) // 2
    plate = grown.crop((left, top, left + want_w, top + want_h)).convert("RGB")
    plate = plate.filter(ImageFilter.GaussianBlur(radius=max(want_w, want_h) / 72))
    plate = ImageEnhance.Brightness(plate).enhance(0.84)
    plate = ImageEnhance.Color(plate).enhance(1.04)

    # A soft dark frame so the wordmark and the bar always have contrast.
    veil = Image.new("L", plate.size, 0)
    brush = ImageDraw.Draw(veil)
    span = min(plate.size) // 2
    for step in range(span):
        shade = int(132 * (1.0 - step / span) ** 2.6)
        brush.rectangle(
            [step, step, plate.width - step - 1, plate.height - step - 1], outline=shade
        )
    plate = Image.composite(Image.new("RGB", plate.size, (8, 16, 11)), plate, veil)
    return plate


# --- main ------------------------------------------------------------------


def main() -> None:
    catalogue_root()
    sweep(AUDIO)
    GENERATED.mkdir(parents=True, exist_ok=True)

    scenes: list[str] = []
    prop_groups: dict[str, list[str]] = {}

    for tag, drop in DROPS.items():
        gameplay = RAW / f"{drop}_gameplay_assets"
        if not gameplay.is_dir():
            continue
        for art in sorted(gameplay.iterdir()):
            if art.suffix.lower() not in {".webp", ".jpg", ".png"}:
                continue
            key = f"{tag}_{snake(art.stem)}"
            image = Image.open(art)
            if image.mode == "RGBA" and image.size == (1584, 672):
                parts = slice_sheet(image)
                names = []
                for index, patch in enumerate(parts):
                    leaf = f"{key}_{index}"
                    enrol(leaf, patch, ".png")
                    names.append(leaf)
                if names:
                    prop_groups[key] = names
                print(f"  sliced {art.name} -> {len(names)}")
            else:
                enrol(key, image, ".jpg")
                scenes.append(key)
                print(f"  scene  {art.name}")

    enrol_wash("BootWash", (14, 22, 16))

    # Boot plates from a real in-game scene.
    source = Image.open(RAW / BOOT_SOURCE)
    enrol("boot_upright", boot_plate(source, BOOT_PORTRAIT), ".jpg", quality=76)
    enrol("boot_wide", boot_plate(source, BOOT_LANDSCAPE), ".jpg", quality=76)
    print("  boot plates rendered")

    # Wordmark and icon come from the project root.
    wordmark = strip_checker(Image.open(RAW / "game_name.jpg"))
    scale = 1400 / max(wordmark.size)
    if scale < 1.0:
        wordmark = wordmark.resize(
            (round(wordmark.width * scale), round(wordmark.height * scale)), Image.LANCZOS
        )
    enrol("brand_wordmark", wordmark, ".png")

    icon = Image.open(RAW / "Icon.png").convert("RGB")
    icon = icon.resize((1024, 1024), Image.LANCZOS)
    appicon = CATALOGUE / "AppIcon.appiconset"
    appicon.mkdir(parents=True, exist_ok=True)
    icon.save(appicon / "mark_1024.png", optimize=True)
    (appicon / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "filename": "mark_1024.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "forge", "version": 1},
            },
            indent=2,
        )
    )
    print("  wordmark keyed, icon rendered")

    # Audio: both drops, newest wins, de-duplicated by content.
    seen: dict[str, str] = {}
    cues: list[str] = []
    for drop in DROPS.values():
        folder = RAW / f"{drop}_sounds_assets"
        if not folder.is_dir():
            continue
        for clip in sorted(folder.glob("*.mp3")):
            digest = hashlib.sha1(clip.read_bytes()).hexdigest()
            if digest in seen:
                continue
            name = snake(clip.stem)
            if name in cues:
                continue
            seen[digest] = name
            shutil.copy2(clip, AUDIO / f"{name}.mp3")
            cues.append(name)
    print(f"  audio cues: {len(cues)}")

    write_swift(scenes, prop_groups, cues)


def cloak(text: str, salt: int) -> list[int]:
    """Light obfuscation so no asset or cue name sits in the binary as text."""
    out = []
    drum = (salt * 131 + 7) & 0xFF
    for index, byte in enumerate(text.encode()):
        drum = (drum * 31 + index * 17 + 91) & 0xFF
        out.append(byte ^ drum)
    return out


def swift_table(name: str, values: list[str], salt_base: int) -> str:
    rows = []
    for index, value in enumerate(values):
        payload = ", ".join(str(byte) for byte in cloak(value, salt_base + index))
        rows.append(f"        [{payload}]")
    body = ",\n".join(rows)
    return f"    static let {name}: [[UInt8]] = [\n{body}\n    ]\n"


def write_swift(scenes: list[str], groups: dict[str, list[str]], cues: list[str]) -> None:
    props: list[str] = []
    group_index: dict[str, list[int]] = {}
    for key, names in groups.items():
        group_index[key] = []
        for name in names:
            group_index[key].append(len(props))
            props.append(name)

    lines = [
        "// @generated by tools/forge_media.py. Do not edit.",
        "//",
        "// Asset and cue names are stored cloaked and decoded on demand, so the",
        "// Swift sources carry no plain string literals for them either.",
        "",
        "enum Canvas {",
        swift_table("sceneNames", scenes, 0x11),
        swift_table("propNames", props, 0x53),
        swift_table("cueNames", cues, 0x97),
        swift_table("plateNames", ["boot_upright", "boot_wide", "brand_wordmark"], 0xC1),
    ]

    for key, seats in sorted(group_index.items()):
        listing = ", ".join(str(seat) for seat in seats)
        lines.append(f"    static let {camel(key)}: [Int] = [{listing}]")
    lines.append("")
    for index, name in enumerate(scenes):
        lines.append(f"    static let {camel(name)}Scene = {index}")
    lines.append("")
    for index, name in enumerate(cues):
        lines.append(f"    static let {camel(name)}Cue = {index}")
    lines.append("}")

    GENERATED.joinpath("Canvas.swift").write_text("\n".join(lines) + "\n")
    print(f"  swift tables: {len(scenes)} scenes, {len(props)} props, {len(cues)} cues")


if __name__ == "__main__":
    main()
