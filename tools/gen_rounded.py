#!/usr/bin/env python3
"""Generate the white rounded-rect textures used by Rounded.lua (stdlib only).

fill_R.tga: filled rounded rectangle, corner radius R texels, R = 1..20.
ring_R.tga: 1 texel thick ring, outer corner radius R texels, R = 1..28.
Each is a power-of-two square, uncompressed 32-bit TGA, white with an anti-aliased alpha.
The addon nine-slices them with margins = R, so the corners stay circular at any size.

Run from the addon folder:  python3 tools/gen_rounded.py
"""
import os
import struct

SS = 8  # supersampling per axis
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")


def inside(x, y, size, inset, r):
    lo, hi = inset, size - inset
    if not (lo <= x <= hi and lo <= y <= hi):
        return False
    cx = lo + r if x < lo + r else (hi - r if x > hi - r else None)
    cy = lo + r if y < lo + r else (hi - r if y > hi - r else None)
    if cx is None or cy is None:
        return True
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def pow2(n):
    p = 8
    while p < n:
        p *= 2
    return p


def write(name, size, shape):
    rows = []
    for py in range(size):  # TGA rows top to bottom (descriptor bit 5); the shapes are symmetric anyway
        row = bytearray()
        for px in range(size):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    if shape(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS):
                        hits += 1
            a = round(255 * hits / (SS * SS))
            row += bytes((255, 255, 255, a))  # B G R A
        rows.append(bytes(row))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + b"".join(rows))


def main():
    os.makedirs(OUT, exist_ok=True)
    for r in range(1, 21):
        s = pow2(2 * r + 2)
        write("fill_%d.tga" % r, s, lambda x, y, s=s, r=r: inside(x, y, s, 0, r))
    for r in range(1, 29):
        s = pow2(2 * r + 2)
        write("ring_%d.tga" % r, s,
              lambda x, y, s=s, r=r: inside(x, y, s, 0, r) and not inside(x, y, s, 1, max(r - 1, 0)))


if __name__ == "__main__":
    main()
