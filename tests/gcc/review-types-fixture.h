/* Declaration-only floating and aggregate metadata, shared with the oracle. */
struct ReviewTypesMixed {
    char prefix;
    float f;
    double d;
    long double ld;
    char suffix;
};
struct ReviewTypesNested {
    char prefix;
    struct ReviewTypesMixed members[2];
    char suffix;
};
union ReviewTypesUnion { char c; float f; double d; long double ld; };
typedef double ReviewTypesDoubles[3];
typedef long double ReviewTypesLongDoubles[3];
typedef double (*ReviewTypesFloatingCallback)(double);
typedef struct ReviewTypesMixed (*ReviewTypesAggregateCallback)(struct ReviewTypesMixed);
typedef int (*ReviewTypesAddressOracle)(float *, double *, long double *,
    struct ReviewTypesMixed *, struct ReviewTypesNested *, union ReviewTypesUnion *,
    float *, double *, long double *);
extern double review_types_unevaluated_float(void);
extern struct ReviewTypesMixed review_types_unevaluated_aggregate(void);
