#ifndef SEED_GCC_FLOAT_PRIVATE_H
#define SEED_GCC_FLOAT_PRIVATE_H
/* Private runtime interface between stdio.c and floatfmt.c; see
   ../PRINTF-FLOAT.md. Not a public header: programs must not use it. */

/* One formatted floating conversion, as pieces that stdio pads and writes:
   sign prefix lead lead_zeros [.] frac_zeros frac trail_zeros suffix.
   The digit pointers stay valid until the next conversion. Zero counts can
   be very large (huge precisions); the caller checks the total length. */
struct __seed_float_text {
    char sign;
    const char *prefix;
    const char *lead;
    int lead_len;
    int lead_zeros;
    int point;
    int frac_zeros;
    const char *frac;
    int frac_len;
    int trail_zeros;
    char suffix[16];
    int suffix_len;
    int special;
};

/* BYTES holds a binary64 (8 bytes) or, when IS_LONG, an x87 extended80
   (10 significant bytes), in AMD64 memory order. CONVERSION is one of
   eEfFgGaA; PRECISION < 0 means the default. */
void __seed_float_format(struct __seed_float_text *out, const unsigned char *bytes,
                         int is_long, int conversion, int precision,
                         int alternate, int plus, int blank);
#endif
