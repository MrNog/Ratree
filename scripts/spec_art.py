"""Spec art for Ratree: a 2:1 picture -> two 1024x1024 BLP2 DXT1 halves, <name>-l.blp and
<name>-r.blp, drawn side by side (2048x1024 in all). The client cannot load a texture wider than
1024, and one 1024x512 picture stretched over the window looks soft.

    python scripts/spec_art.py <picture.png> <Media/Art/name>

DXT1: the art has no transparency, and the colour is the same as DXT5's at half the size.
Needs Pillow 11.2 or later (DDS DXT1 writing).
"""
import io
import struct
import sys

from PIL import Image

HALF = 1024


def dxt1(img):
    buf = io.BytesIO()
    img.save(buf, format="DDS", pixel_format="DXT1")
    return buf.getvalue()[128:]          # drop the DDS header, keep the blocks


def blp(img, path):
    w, h = img.size
    mips, mw, mh = [], w, h
    while True:
        level = img.resize((max(4, mw), max(4, mh)), Image.LANCZOS)
        mips.append(dxt1(level))
        if mw == 1 and mh == 1:
            break
        mw, mh = max(1, mw // 2), max(1, mh // 2)
    mips = mips[:16]
    offsets, sizes, pos = [], [], 148
    for m in mips:
        offsets.append(pos)
        sizes.append(len(m))
        pos += len(m)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    # type 1, colorEncoding 2 (DXT), alphaDepth 0, alphaEncoding 0 (DXT1), hasMips 1
    header = b"BLP2" + struct.pack("<I4B2I", 1, 2, 0, 0, 1, w, h)
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    with open(path, "wb") as f:
        f.write(header)
        for m in mips:
            f.write(m)
    print(path, f"{w}x{h}", pos, "bytes")


def main():
    src, base = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGB")
    sw, sh = img.size
    if sw / sh > 2:                      # wider than 2:1: trim the sides
        cw = sh * 2
        img = img.crop(((sw - cw) // 2, 0, (sw - cw) // 2 + cw, sh))
    elif sw / sh < 2:                    # taller: trim top and bottom
        ch = sw // 2
        img = img.crop((0, (sh - ch) // 2, sw, (sh - ch) // 2 + ch))
    img = img.resize((HALF * 2, HALF), Image.LANCZOS).convert("RGBA")
    blp(img.crop((0, 0, HALF, HALF)), base + "-l.blp")
    blp(img.crop((HALF, 0, HALF * 2, HALF)), base + "-r.blp")


if __name__ == "__main__":
    main()
