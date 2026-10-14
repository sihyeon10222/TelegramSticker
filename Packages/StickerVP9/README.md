# StickerVP9

App-only, source-built VP9 decoder. No encoder, networking, assembly, high-bit-depth,
postprocessing, or runtime CPU dispatch. libvpx v1.17.0, upstream commit
`6df3ec34557879fff673706f4a1d9fbd0f3a6f0e` from
https://github.com/webmproject/libvpx (tag object `82615ff0733cd4063838c352bc2e2ab225f37ade`).
Upstream LICENSE, PATENTS and AUTHORS are retained in Sources/CStickerVP9/vendor.
The wrapper is StickerBridge code. Do not link this package into the keyboard.

Generated headers and the 50 compiled C sources/dependent headers were selected from:

```
./configure --target=generic-gnu --disable-vp8 --disable-vp9-encoder \
 --disable-examples --disable-tools --disable-docs --disable-unit-tests \
 --disable-runtime-cpu-detect --disable-multithread --disable-webm-io \
 --disable-libyuv --disable-vp9-highbitdepth --disable-postproc \
 --disable-vp9-postproc --disable-shared --enable-static --size-limit=512x512
make -j4
```

The upstream decoder enforces 512×512 before allocating frame contexts; the wrapper
also validates actual output and buffer size. Color/alpha use separate decoder
contexts; output is premultiplied RGBA. Updates require reviewing upstream security
fixes, regenerating the source list/headers, and rerunning transparent/opaque and
malformed bitstream tests on device and Simulator. Scalar C favors portability;
conversion is sequential and time/frame/size bounded by the containing app.
