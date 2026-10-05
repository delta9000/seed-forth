/* The ten significant bytes (little endian) of each test value. */
#define LD_VALUES 7
static const unsigned char ld_bytes[LD_VALUES][10] = {
  /* 1.0L/3 */ {0xab,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xfd,0x3f},
  /* LDBL_MAX */ {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xfe,0x7f},
  /* -0.0L */ {0,0,0,0,0,0,0,0,0x00,0x80},
  /* LDBL_MIN/4, subnormal */ {0,0,0,0,0,0,0,0x20,0x00,0x00},
  /* -Inf */ {0,0,0,0,0,0,0,0x80,0xff,0xff},
  /* quiet NaN with payload */ {0x21,0x43,0x65,0x87,0xa9,0xcb,0xed,0xc0,0xff,0x7f},
  /* signaling NaN (quiet bit clear) */ {0x01,0,0,0,0,0,0,0x80,0xff,0x7f},
};
/* Padding bytes are deliberately nonzero: only ten bytes are significant. */
static void ld_values(long double *v)
{
  int i, j;
  for (i = 0; i < LD_VALUES; i++) {
    unsigned char *b = (unsigned char *) &v[i];
    for (j = 0; j < 16; j++) b[j] = j < 10 ? ld_bytes[i][j] : 0xa5;
  }
}
