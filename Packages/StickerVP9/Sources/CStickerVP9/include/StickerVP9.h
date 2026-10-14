#include <stddef.h>
#include <stdint.h>
typedef struct SBVP9 SBVP9;
SBVP9 *sb_vp9_create(void);
void sb_vp9_destroy(SBVP9 *decoder);
// Returns one displayed frame, zero for an invisible frame, -1 on invalid input.
// rgba may be NULL for a bounded preflight that counts displayed frames.
int sb_vp9_decode(SBVP9 *decoder, const uint8_t *color, size_t color_size,
                  const uint8_t *alpha, size_t alpha_size, uint8_t *rgba,
                  size_t capacity, int *width, int *height);
