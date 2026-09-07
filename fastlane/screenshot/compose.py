#!/usr/bin/env python3
"""Frame a raw simulator screenshot in the device bezel over the marketing background.

The Mist Blue iPhone 17 bezel has a screen aperture of exactly 1206x2622 at offset (72, 69),
which is the native iPhone 17 / 17 Pro screenshot size, so the capture drops in 1:1 with no
resampling. The framed phone is then scaled once to sit on the background with a margin.

Apple rejects screenshots carrying an alpha channel, so the result is flattened.
"""
import argparse, os, sys
from PIL import Image, ImageDraw

APERTURE = (72, 69, 1206, 2622)   # x, y, w, h — measured from the bezel's alpha channel


def compose(shot_path, bezel_path, background_path, out_path, phone_width_frac, top_frac):
    shot = Image.open(shot_path).convert("RGB")
    bezel = Image.open(bezel_path).convert("RGBA")
    bg = Image.open(background_path).convert("RGB")

    ax, ay, aw, ah = APERTURE
    if shot.size != (aw, ah):
        # Cover the aperture and centre-crop rather than stretch, so nothing skews.
        s = max(aw / shot.width, ah / shot.height)
        shot = shot.resize((round(shot.width * s), round(shot.height * s)), Image.LANCZOS)
        left, top = (shot.width - aw) // 2, (shot.height - ah) // 2
        shot = shot.crop((left, top, left + aw, top + ah))

    # The aperture is a bounding box, but the screen itself is a rounded rectangle, so pasting the
    # capture as a plain rectangle leaves its square corners sticking out past the bezel. Mask the
    # paste with the screen's real shape: flood the transparent region that touches the image edge
    # (everything outside the phone), and whatever transparency is left is the screen.
    alpha = bezel.split()[-1]
    region = alpha.point(lambda v: 0 if v < 8 else 255).convert("L")
    ImageDraw.floodfill(region, (0, 0), 128, thresh=0)
    screen_mask = region.point(lambda v: 255 if v == 0 else 0).convert("L")

    framed = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    framed.paste(shot, (ax, ay), screen_mask.crop((ax, ay, ax + aw, ay + ah)))
    framed.alpha_composite(bezel)

    target_w = round(bg.width * phone_width_frac)
    target_h = round(framed.height * target_w / framed.width)
    framed = framed.resize((target_w, target_h), Image.LANCZOS)

    x = (bg.width - target_w) // 2
    y = (bg.height - target_h) // 2 if top_frac < 0 else round(bg.height * top_frac)
    canvas = bg.copy()
    canvas.paste(framed, (x, y), framed)          # alpha as the mask
    canvas.save(out_path, "PNG", optimize=True)
    return canvas.size, (x, y, target_w, target_h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", required=True)
    ap.add_argument("--bezel", required=True)
    ap.add_argument("--background", required=True)
    ap.add_argument("--out", required=True)
    # Defaults leave a margin either side and a little more headroom at the top than the bottom,
    # which is where a caption would go if one is ever added.
    ap.add_argument("--phone-width", type=float, default=0.82)
    ap.add_argument("--top", type=float, default=-1.0, help="fraction from top; <0 centres")
    a = ap.parse_args()
    for f in (a.shot, a.bezel, a.background):
        if not os.path.isfile(f):
            sys.exit(f"missing input: {f}")
    size, placed = compose(a.shot, a.bezel, a.background, a.out, a.phone_width, a.top)
    print(f"  {os.path.basename(a.out)}  {size[0]}x{size[1]}  phone {placed[2]}x{placed[3]} at {placed[0]},{placed[1]}")


if __name__ == "__main__":
    main()
