#ifndef SHIM_ENDIAN_H
#define SHIM_ENDIAN_H
#include "common/scummsys.h"
static inline uint16 READ_LE_UINT16(const void *p) { const byte *b = (const byte *)p; return b[0] | (b[1] << 8); }
static inline uint32 READ_LE_UINT32(const void *p) { const byte *b = (const byte *)p; return b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32)b[3] << 24); }
static inline uint16 READ_BE_UINT16(const void *p) { const byte *b = (const byte *)p; return (b[0] << 8) | b[1]; }
static inline uint32 READ_BE_UINT32(const void *p) { const byte *b = (const byte *)p; return ((uint32)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; }
#endif
