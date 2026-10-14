#include "StickerVP9.h"
#include "vpx/vpx_decoder.h"
#include "vpx/vp8dx.h"
#include <stdlib.h>
struct SBVP9 { vpx_codec_ctx_t color, alpha; };
SBVP9 *sb_vp9_create(void) {
  SBVP9 *d = calloc(1, sizeof(*d));
  if (!d) return NULL;
  vpx_codec_dec_cfg_t cfg = { 1, 512, 512 };
  if (vpx_codec_dec_init(&d->color, vpx_codec_vp9_dx(), &cfg, 0)) { free(d); return NULL; }
  if (vpx_codec_dec_init(&d->alpha, vpx_codec_vp9_dx(), &cfg, 0)) {
    vpx_codec_destroy(&d->color); free(d); return NULL;
  }
  return d;
}
void sb_vp9_destroy(SBVP9 *d) {
  if (d) { vpx_codec_destroy(&d->color); vpx_codec_destroy(&d->alpha); free(d); }
}
static uint8_t clamp(int x) { return x < 0 ? 0 : x > 255 ? 255 : x; }
int sb_vp9_decode(SBVP9 *d, const uint8_t *color, size_t n, const uint8_t *alpha,
                  size_t a, uint8_t *rgba, size_t capacity, int *width, int *height) {
  if (!d || !color || !n || n > 2097152 || a > 2097152 || !width || !height) return -1;
  if (vpx_codec_decode(&d->color, color, (unsigned int)n, NULL, 0)) return -1;
  vpx_codec_iter_t ci = NULL, ai = NULL;
  vpx_image_t *c = vpx_codec_get_frame(&d->color, &ci), *al = NULL;
  if (a) {
    if (!alpha || vpx_codec_decode(&d->alpha, alpha, (unsigned int)a, NULL, 0)) return -1;
    al = vpx_codec_get_frame(&d->alpha, &ai);
  }
  if (!c) return al ? -1 : 0;
  if (vpx_codec_get_frame(&d->color, &ci) || c->fmt != VPX_IMG_FMT_I420 ||
      c->d_w < 1 || c->d_w > 512 || c->d_h < 1 || c->d_h > 512 ||
      (rgba && capacity < (size_t)c->d_w * c->d_h * 4)) return -1;
  if (a && (!al || vpx_codec_get_frame(&d->alpha, &ai) || al->fmt != VPX_IMG_FMT_I420 ||
            al->d_w != c->d_w || al->d_h != c->d_h)) return -1;
  *width = (int)c->d_w; *height = (int)c->d_h;
  if (!rgba) return 1;
  for (unsigned y = 0; y < c->d_h; y++) for (unsigned x = 0; x < c->d_w; x++) {
    int Y = c->planes[0][y*c->stride[0]+x];
    int U = c->planes[1][(y/2)*c->stride[1]+x/2]-128;
    int V = c->planes[2][(y/2)*c->stride[2]+x/2]-128;
    int full = c->range == VPX_CR_FULL_RANGE;
    int yy = full ? 256*Y : 298*(Y-16);
    int hd = c->cs == VPX_CS_BT_709;
    int r = (yy + (full ? (hd ? 403 : 359) : (hd ? 459 : 409))*V + 128)>>8;
    int g = (yy - (full ? (hd ? 48 : 88) : (hd ? 55 : 100))*U - (full ? (hd ? 120 : 183) : (hd ? 136 : 208))*V + 128)>>8;
    int b = (yy + (full ? (hd ? 475 : 454) : (hd ? 541 : 516))*U + 128)>>8;
    unsigned av = al ? al->planes[0][y*al->stride[0]+x] : 255;
    size_t p = ((size_t)y*c->d_w+x)*4;
    rgba[p] = (clamp(r)*av+127)/255; rgba[p+1] = (clamp(g)*av+127)/255;
    rgba[p+2] = (clamp(b)*av+127)/255; rgba[p+3] = (uint8_t)av;
  }
  return 1;
}
