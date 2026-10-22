#ifndef SHIM_SCUMMSYS_H
#define SHIM_SCUMMSYS_H
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef unsigned char byte;
typedef uint8_t uint8; typedef uint16_t uint16; typedef uint32_t uint32;
typedef int8_t int8; typedef int16_t int16; typedef int32_t int32;
#define ARRAYSIZE(x) ((int)(sizeof(x) / sizeof(x[0])))

#include <stdarg.h>
static inline void error(const char *fmt, ...) { va_list a; va_start(a, fmt); fprintf(stderr, "ERROR: "); vfprintf(stderr, fmt, a); fprintf(stderr, "\n"); va_end(a); exit(1); }
static inline void warning(const char *fmt, ...) { va_list a; va_start(a, fmt); fprintf(stderr, "WARNING: "); vfprintf(stderr, fmt, a); fprintf(stderr, "\n"); va_end(a); }
#endif
