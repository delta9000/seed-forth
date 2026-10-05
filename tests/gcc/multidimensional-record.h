#ifndef MULTIDIMENSIONAL_RECORD_H
#define MULTIDIMENSIONAL_RECORD_H
struct cell { char tag; long value; };
typedef int int_row[3];
struct matrix {
    char lead;
    int scalar[2][3];
    struct cell records[2][3];
    char text[2][4];
    int_row alias[2];
    unsigned bits:3;
    unsigned more:5;
    char tail;
};
struct tiny { unsigned char values[2][3]; };
struct pair { long values[1][2]; };
struct nested { char tag; struct matrix matrix; long tail; };
union matrix_union { struct cell records[2][3]; long words[3][4]; };
extern struct matrix matrix_global;
long matrix_layout(int);
long matrix_read(struct matrix *, int, int);
void matrix_fill(struct matrix *);
struct tiny tiny_roundtrip(struct tiny);
struct pair pair_roundtrip(struct pair);
struct matrix matrix_roundtrip(struct matrix);
int matrix_checks(void);
#endif
