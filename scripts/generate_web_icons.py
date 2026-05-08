#!/usr/bin/env python3
"""Generate Flutter web icons from assets/icon.png using only stdlib.

GitHub Pages builds call this script so the repository does not need to add
binary web icon files. The source artwork is assets/icon.png.
"""

from __future__ import annotations

import os
import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SOURCE_ICON = Path("assets/icon.png")
TARGETS = {
    Path("web/favicon.png"): 32,
    Path("web/icons/Icon-192.png"): 192,
    Path("web/icons/Icon-512.png"): 512,
    Path("web/icons/Icon-maskable-192.png"): 192,
    Path("web/icons/Icon-maskable-512.png"): 512,
}


def _read_png(path: Path) -> tuple[int, int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path} is not a PNG file")

    pos = len(PNG_SIGNATURE)
    width = height = bytes_per_pixel = 0
    idat = bytearray()

    while pos < len(data):
        chunk_len = struct.unpack(">I", data[pos : pos + 4])[0]
        pos += 4
        chunk_type = data[pos : pos + 4]
        pos += 4
        chunk_data = data[pos : pos + chunk_len]
        pos += chunk_len + 4  # Skip data and CRC.

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, png_filter, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if bit_depth != 8 or color_type not in (2, 6) or compression or png_filter or interlace:
                raise ValueError("Only non-interlaced 8-bit truecolor PNG files are supported")
            bytes_per_pixel = 3 if color_type == 2 else 4
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    raw = zlib.decompress(bytes(idat))
    stride = width * bytes_per_pixel
    pixels = bytearray(height * stride)
    prev = bytearray(stride)
    raw_pos = 0

    for y in range(height):
        filter_type = raw[raw_pos]
        raw_pos += 1
        scanline = raw[raw_pos : raw_pos + stride]
        raw_pos += stride
        reconstructed = bytearray(stride)

        for x, value in enumerate(scanline):
            left = reconstructed[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
            up = prev[x]
            up_left = prev[x - bytes_per_pixel] if x >= bytes_per_pixel else 0

            if filter_type == 0:
                reconstructed[x] = value
            elif filter_type == 1:
                reconstructed[x] = (value + left) & 0xFF
            elif filter_type == 2:
                reconstructed[x] = (value + up) & 0xFF
            elif filter_type == 3:
                reconstructed[x] = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                predictor = left + up - up_left
                distances = (abs(predictor - left), abs(predictor - up), abs(predictor - up_left))
                paeth = (left, up, up_left)[distances.index(min(distances))]
                reconstructed[x] = (value + paeth) & 0xFF
            else:
                raise ValueError(f"Unsupported PNG filter type: {filter_type}")

        pixels[y * stride : (y + 1) * stride] = reconstructed
        prev = reconstructed

    return width, height, bytes_per_pixel, bytes(pixels)


def _resize_nearest(width: int, height: int, bytes_per_pixel: int, pixels: bytes, size: int) -> bytes:
    resized = bytearray(size * size * bytes_per_pixel)
    for y in range(size):
        source_y = min(height - 1, y * height // size)
        for x in range(size):
            source_x = min(width - 1, x * width // size)
            source_offset = (source_y * width + source_x) * bytes_per_pixel
            target_offset = (y * size + x) * bytes_per_pixel
            resized[target_offset : target_offset + bytes_per_pixel] = pixels[
                source_offset : source_offset + bytes_per_pixel
            ]
    return bytes(resized)


def _png_chunk(chunk_type: bytes, chunk_data: bytes) -> bytes:
    return (
        struct.pack(">I", len(chunk_data))
        + chunk_type
        + chunk_data
        + struct.pack(">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF)
    )


def _write_png(path: Path, size: int, bytes_per_pixel: int, pixels: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    color_type = 2 if bytes_per_pixel == 3 else 6
    stride = size * bytes_per_pixel
    filtered_rows = b"".join(b"\x00" + pixels[y * stride : (y + 1) * stride] for y in range(size))
    png = (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, color_type, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(filtered_rows, 9))
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def main() -> None:
    os.chdir(Path(__file__).resolve().parents[1])
    width, height, bytes_per_pixel, pixels = _read_png(SOURCE_ICON)
    for target, size in TARGETS.items():
        resized = _resize_nearest(width, height, bytes_per_pixel, pixels, size)
        _write_png(target, size, bytes_per_pixel, resized)
        print(f"Generated {target} from {SOURCE_ICON} ({size}x{size})")


if __name__ == "__main__":
    main()
