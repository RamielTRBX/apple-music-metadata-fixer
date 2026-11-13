#!/usr/bin/env python3
"""Generate the original macOS app icon and its .icns representation."""

from __future__ import annotations

import shutil
import struct
import subprocess
import tempfile
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources" / "AppleMusicMetadataFixer" / "Resources"
SCALE = 4
SIZE = 1024
PIXELS = SIZE * SCALE


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_image(variant: str) -> Image.Image:
    y, x = np.mgrid[0:PIXELS, 0:PIXELS]
    nx = x / (PIXELS - 1)
    ny = y / (PIXELS - 1)

    if variant == "primary":
        stops = [
            (0.00, (255, 91, 122)),
            (0.42, (247, 43, 105)),
            (0.72, (218, 47, 183)),
            (1.00, (112, 73, 235)),
        ]
    else:
        stops = [
            (0.00, (255, 116, 102)),
            (0.46, (241, 55, 101)),
            (0.78, (190, 61, 203)),
            (1.00, (91, 94, 232)),
        ]

    diagonal = np.clip((nx * 0.62 + ny * 0.48), 0, 1)
    rgb = np.zeros((PIXELS, PIXELS, 3), dtype=np.float32)
    for index in range(len(stops) - 1):
        start, first = stops[index]
        end, second = stops[index + 1]
        mask = (diagonal >= start) & (diagonal <= end)
        local = np.clip((diagonal - start) / (end - start), 0, 1)
        for channel in range(3):
            rgb[..., channel] = np.where(
                mask,
                first[channel] + (second[channel] - first[channel]) * local,
                rgb[..., channel],
            )

    # A soft upper-left light source and a deeper lower-right corner give the
    # surface the polished depth typical of modern macOS app icons.
    distance = np.sqrt((nx - 0.22) ** 2 + (ny - 0.12) ** 2)
    glow = np.clip(1.0 - distance / 0.78, 0, 1) ** 2
    rgb += glow[..., None] * np.array([62, 42, 62], dtype=np.float32)
    shade = np.clip((nx + ny - 1.05) / 0.95, 0, 1)
    rgb -= shade[..., None] * np.array([26, 22, 36], dtype=np.float32)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    return Image.fromarray(rgb, "RGB").convert("RGBA")


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (PIXELS, PIXELS), 0)
    draw = ImageDraw.Draw(mask)
    inset = 100 * SCALE
    radius = 190 * SCALE
    draw.rounded_rectangle(
        (inset, inset, PIXELS - inset, PIXELS - inset),
        radius=radius,
        fill=255,
    )
    return mask


def cubic(points, samples=90):
    p0, p1, p2, p3 = points
    result = []
    for index in range(samples + 1):
        t = index / samples
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        result.append((x, y))
    return result


def scaled(value):
    return int(value * SCALE)


def draw_music_mark(canvas: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    white = (255, 255, 255, 244)
    outline = (255, 255, 255, 224)

    # Left note
    draw.ellipse(
        (
            scaled(330),
            scaled(620),
            scaled(472),
            scaled(728),
        ),
        fill=white,
    )
    stem = cubic(
        [
            (scaled(438), scaled(670)),
            (scaled(458), scaled(515)),
            (scaled(490), scaled(385)),
            (scaled(535), scaled(344)),
        ]
    )
    draw.line(stem, fill=white, width=scaled(42), joint="curve")

    # Right note
    draw.ellipse(
        (
            scaled(588),
            scaled(584),
            scaled(716),
            scaled(684),
        ),
        fill=white,
    )
    stem = cubic(
        [
            (scaled(686), scaled(622)),
            (scaled(690), scaled(520)),
            (scaled(685), scaled(438)),
            (scaled(673), scaled(382)),
        ]
    )
    draw.line(stem, fill=white, width=scaled(42), joint="curve")

    # A rounded, slightly lifted beam connects the two stems.
    beam = cubic(
        [
            (scaled(500), scaled(328)),
            (scaled(570), scaled(326)),
            (scaled(650), scaled(345)),
            (scaled(688), scaled(376)),
        ]
    )
    draw.line(beam, fill=white, width=scaled(58), joint="curve")
    draw.ellipse(
        (
            scaled(484),
            scaled(300),
            scaled(548),
            scaled(357),
        ),
        fill=white,
    )
    draw.ellipse(
        (
            scaled(646),
            scaled(350),
            scaled(716),
            scaled(404),
        ),
        fill=white,
    )

    # A restrained "metadata corrected" sparkle adds the tool's identity
    # without introducing text or another trademark.
    center_x, center_y = scaled(724), scaled(260)
    long_radius, short_radius = scaled(62), scaled(15)
    sparkle = [
        (center_x, center_y - long_radius),
        (center_x + short_radius, center_y - short_radius),
        (center_x + long_radius, center_y),
        (center_x + short_radius, center_y + short_radius),
        (center_x, center_y + long_radius),
        (center_x - short_radius, center_y + short_radius),
        (center_x - long_radius, center_y),
        (center_x - short_radius, center_y - short_radius),
    ]
    draw.polygon(sparkle, fill=(225, 250, 255, 244))
    draw.ellipse(
        (
            scaled(770),
            scaled(310),
            scaled(792),
            scaled(332),
        ),
        fill=(220, 251, 255, 220),
    )

    shadow = layer.filter(ImageFilter.GaussianBlur(scaled(13)))
    shadow_alpha = shadow.getchannel("A").point(lambda value: value * 0.25)
    shadow.putalpha(shadow_alpha)
    shadow = Image.composite(
        Image.new("RGBA", layer.size, (54, 17, 72, 0)),
        Image.new("RGBA", layer.size, (54, 17, 72, 0)),
        Image.new("L", layer.size, 0),
    )
    shifted = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shifted.alpha_composite(shadow, (0, scaled(18)))
    shifted.alpha_composite(layer)
    return shifted


def create_icon(variant: str) -> Image.Image:
    canvas = Image.new("RGBA", (PIXELS, PIXELS), (0, 0, 0, 0))
    mask = rounded_mask()

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(scaled(30)))
    shadow.putalpha(shadow_mask.point(lambda value: int(value * 0.32)))
    shadow = Image.new("RGBA", canvas.size, (37, 6, 51, 0))
    shadow.putalpha(
        mask.filter(ImageFilter.GaussianBlur(scaled(30))).point(
            lambda value: int(value * 0.34)
        )
    )
    canvas.alpha_composite(shadow, (0, scaled(24)))

    body = gradient_image(variant)
    body.putalpha(mask)
    canvas.alpha_composite(body)

    gloss = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gloss_draw = ImageDraw.Draw(gloss)
    gloss_draw.rounded_rectangle(
        (
            scaled(112),
            scaled(112),
            scaled(912),
            scaled(912),
        ),
        radius=scaled(178),
        outline=(255, 255, 255, 54),
        width=scaled(5),
    )
    highlight = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    hdraw.ellipse(
        (
            scaled(-240),
            scaled(-360),
            scaled(840),
            scaled(680),
        ),
        fill=(255, 255, 255, 32),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(scaled(100)))
    gloss.alpha_composite(highlight)
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", canvas.size, 0), mask))
    canvas.alpha_composite(gloss)
    canvas.alpha_composite(draw_music_mark(canvas))
    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def make_icns(primary: Image.Image) -> None:
    chunks = {
        16: b"icp4",
        32: b"icp5",
        64: b"icp6",
        128: b"ic07",
        256: b"ic08",
        512: b"ic09",
        1024: b"ic10",
    }
    payloads = []
    for size, icon_type in chunks.items():
        buffer = BytesIO()
        primary.resize((size, size), Image.Resampling.LANCZOS).save(
            buffer,
            format="PNG",
        )
        payload = buffer.getvalue()
        payloads.append(icon_type + struct.pack(">I", len(payload) + 8) + payload)
    body = b"".join(payloads)
    (RESOURCES / "AppIcon.icns").write_bytes(
        b"icns" + struct.pack(">I", len(body) + 8) + body
    )


def main() -> None:
    source = RESOURCES / "AppIcon.svg"
    preview = ROOT / "AppIcon-preview.png"
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(
            [
                "qlmanage",
                "-t",
                "-s",
                "1024",
                "-o",
                directory,
                str(source),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        rendered = next(Path(directory).glob("*.png"))
        primary = Image.open(rendered).convert("RGBA")

    # Quick Look supplies a white preview backing. Reapply the macOS icon
    # silhouette so the outer corners remain genuinely transparent.
    icon_mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(icon_mask).rounded_rectangle(
        (100, 100, 924, 924),
        radius=190,
        fill=255,
    )
    alpha = primary.getchannel("A")
    alpha = Image.composite(alpha, Image.new("L", primary.size, 0), icon_mask)
    primary.putalpha(alpha)
    primary.save(preview)
    primary.save(RESOURCES / "AppIcon.png")
    make_icns(primary)
    print(RESOURCES / "AppIcon.icns")


if __name__ == "__main__":
    main()
