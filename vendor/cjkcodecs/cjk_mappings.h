/*
 * cjk_mappings.h: Standalone CJK codec mapping tables for Metal0
 *
 * This header extracts just the mapping data from CPython's cjkcodecs
 * without any Python dependencies.
 */

#ifndef _CJK_MAPPINGS_H_
#define _CJK_MAPPINGS_H_

#include <stdint.h>

/* Type definitions */
typedef uint16_t ucs2_t;
typedef uint32_t Py_UCS4;
typedef uint16_t DBCHAR;

/* Sentinel values */
#define UNIINV  0xFFFE  /* Unicode undefined */
#define NOCHAR  0xFFFF  /* No character mapping */
#define MULTIC  0xFFFE  /* Multi-character sequence */
#define DBCINV  0xFFFD  /* Invalid DBCS sequence */

/* Shorter macros for mapping tables */
#define U UNIINV
#define N NOCHAR
#define M MULTIC
#define D DBCINV

/* Decode map: byte pair -> Unicode */
struct dbcs_index {
    const ucs2_t *map;
    unsigned char bottom, top;
};

/* Wide decode map: byte pair -> 32-bit Unicode */
struct widedbcs_index {
    const Py_UCS4 *map;
    unsigned char bottom, top;
};

/* Encode map: Unicode -> byte pair */
struct unim_index {
    const DBCHAR *map;
    unsigned char bottom, top;
};

/* Include the actual mapping data */
#include "mappings_jp.h"
#include "mappings_kr.h"
#include "mappings_cn.h"
#include "mappings_tw.h"
#include "mappings_hk.h"
#include "mappings_jisx0213_pair.h"

#endif /* _CJK_MAPPINGS_H_ */
