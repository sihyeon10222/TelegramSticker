"""Own CC0 moving-circle fixtures. Dev tools: Pillow, PyAV 19.0.1 (not shipped)."""
from pathlib import Path
from fractions import Fraction
import gzip
import json
import av
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parents[1] / "TelegramStickerTests" / "Fixtures"
folder.mkdir(parents=True, exist_ok=True)
fixed = lambda value: {"a": 0, "k": value}
animation = {
    "v": "5.7.4", "fr": 30, "ip": 0, "op": 30, "w": 512, "h": 512,
    "nm": "Own moving circle fixture", "ddd": 0, "assets": [], "layers": [{
        "ty": 4, "ind": 1, "nm": "Circle", "ip": 0, "op": 30, "st": 0, "bm": 0,
        "ks": {"o": fixed(100), "r": fixed(0), "a": fixed([0, 0, 0]), "s": fixed([100, 100, 100]),
               "p": {"a": 1, "k": [
                   {"t": 0, "s": [160, 256, 0], "e": [352, 256, 0], "i": {"x": 1, "y": 1}, "o": {"x": 0, "y": 0}},
                   {"t": 29, "s": [352, 256, 0]}]}},
        "shapes": [{"ty": "el", "p": fixed([0, 0]), "s": fixed([160, 160]), "d": 1},
                   {"ty": "fl", "c": fixed([1, 0.3, 0.2, 1]), "o": fixed(100), "r": 1}]
    }]
}
(folder / "moving-circle.tgs").write_bytes(gzip.compress(json.dumps(animation).encode(), mtime=0))
with av.open(str(folder / "moving-circle.webm"), "w", format="webm") as output:
    stream = output.add_stream("libvpx-vp9", rate=30)
    stream.width = stream.height = 512
    stream.pix_fmt = "yuva420p"
    stream.options = {"lossless": "1", "auto-alt-ref": "0", "deadline": "good", "cpu-used": "4"}
    for index in range(30):
        image = Image.new("RGBA", (512, 512))
        x = 160 + round(192 * index / 29)
        ImageDraw.Draw(image).ellipse((x-80, 176, x+80, 336), fill=(255, 77, 51, 255))
        frame = av.VideoFrame(512, 512, "rgba")
        frame.planes[0].update(image.tobytes())
        frame.pts, frame.time_base = index, Fraction(1, 30)
        for packet in stream.encode(frame): output.mux(packet)
    for packet in stream.encode(): output.mux(packet)
print("Generated own TGS and VP9 alpha WebM fixtures")

# The container advertises 512px but the VP9 bitstream is 768px: native limit test.
oversized = folder / "oversized-bitstream.webm"
with av.open(str(oversized), "w", format="webm") as output:
    stream = output.add_stream("libvpx-vp9", rate=30)
    stream.width, stream.height, stream.pix_fmt = 768, 512, "yuv420p"
    stream.options = {"lossless": "1", "auto-alt-ref": "0", "cpu-used": "4"}
    for index in range(2):
        frame = av.VideoFrame(768, 512, "rgb24")
        frame.planes[0].update(Image.new("RGB", (768, 512), (255, 77, 51)).tobytes())
        frame.pts, frame.time_base = index, Fraction(1, 30)
        for packet in stream.encode(frame): output.mux(packet)
    for packet in stream.encode(): output.mux(packet)
raw = oversized.read_bytes()
assert raw.count(b"\xb0\x82\x03\x00") == 1
oversized.write_bytes(raw.replace(b"\xb0\x82\x03\x00", b"\xb0\x82\x02\x00", 1))

import shutil
app_samples = folder.parents[1] / "TelegramSticker" / "AnimationSamples"
app_samples.mkdir(parents=True, exist_ok=True)
for ext in ["tgs", "webm"]:
    shutil.copyfile(folder / ("moving-circle." + ext), app_samples / ("moving-circle." + ext))

# Older official packs contain >3-second clips. Preserve duration while sampling
# 94 source frames down to the fixed 90-frame GIF budget.
with av.open(str(folder / "long-circle.webm"), "w", format="webm") as output:
    stream = output.add_stream("libvpx-vp9", rate=24)
    stream.width = stream.height = 512
    stream.pix_fmt = "yuva420p"
    stream.options = {"lossless": "1", "auto-alt-ref": "0", "cpu-used": "4"}
    for index in range(94):
        image = Image.new("RGBA", (512, 512))
        x = 160 + round(192 * index / 93)
        ImageDraw.Draw(image).ellipse((x-80, 176, x+80, 336), fill=(255, 77, 51, 255))
        frame = av.VideoFrame(512, 512, "rgba")
        frame.planes[0].update(image.tobytes())
        frame.pts, frame.time_base = index, Fraction(1, 24)
        for packet in stream.encode(frame): output.mux(packet)
    for packet in stream.encode(): output.mux(packet)

# Regression inputs for Telegram videos with one visible frame or a 10ms frame duration.
for name, rate, count in [("single-frame", 30, 1), ("hundred-fps", 100, 20)]:
    side = 512 if count == 1 else 128
    with av.open(str(folder / (name + ".webm")), "w", format="webm") as output:
        stream = output.add_stream("libvpx-vp9", rate=rate)
        stream.width = stream.height = side
        stream.pix_fmt = "yuv420p"
        stream.options = {"lossless": "1", "auto-alt-ref": "0", "cpu-used": "4"}
        for index in range(count):
            frame = av.VideoFrame(side, side, "rgb24")
            color = (100, 150, 200) if count == 1 else (index * 10, 150, 200)
            frame.planes[0].update(Image.new("RGB", (side, side), color).tobytes())
            frame.pts, frame.time_base = index, Fraction(1, rate)
            for packet in stream.encode(frame): output.mux(packet)
        for packet in stream.encode(): output.mux(packet)
