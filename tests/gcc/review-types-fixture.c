/* Forth produces the target; compiling this with GCC is an oracle only. */
#include "review-types-fixture.h"
float review_types_floats[3];
double review_types_doubles[3];
long double review_types_long_doubles[3];
struct ReviewTypesMixed review_types_mixed[2];
struct ReviewTypesNested review_types_nested;
union ReviewTypesUnion review_types_union;
double *review_types_double_pointer = review_types_doubles + 2;
long double *review_types_long_double_pointer = &review_types_long_doubles[1];

ReviewTypesFloatingCallback review_types_forward_floating(ReviewTypesFloatingCallback callback) {
    return callback;
}
ReviewTypesAggregateCallback review_types_forward_aggregate(ReviewTypesAggregateCallback callback) {
    return callback;
}

long review_types_metric(int which) {
    struct ReviewTypesMixed mixed;
    struct ReviewTypesNested nested;
    ReviewTypesFloatingCallback floating;
    ReviewTypesAggregateCallback aggregate;
    switch (which) {
    case 0: return sizeof(float);
    case 1: return sizeof(double);
    case 2: return sizeof(long double);
    case 3: return sizeof(struct ReviewTypesMixed);
    case 4: return sizeof(struct ReviewTypesNested);
    case 5: return sizeof(union ReviewTypesUnion);
    case 6: return sizeof(ReviewTypesDoubles);
    case 7: return sizeof(ReviewTypesLongDoubles);
    case 8: return sizeof(floating);
    case 9: return sizeof(aggregate);
    case 10: return sizeof(review_types_unevaluated_float());
    case 11: return sizeof(review_types_unevaluated_aggregate());
    case 12: return sizeof(floating(0));
    case 13: return sizeof(aggregate(mixed));
    case 14: return (char *)&mixed.f - (char *)&mixed;
    case 15: return (char *)&mixed.d - (char *)&mixed;
    case 16: return (char *)&mixed.ld - (char *)&mixed;
    case 17: return (char *)&mixed.suffix - (char *)&mixed;
    case 18: return (char *)&nested.members - (char *)&nested;
    case 19: return (char *)&nested.members[1] - (char *)&nested;
    case 20: return (char *)&nested.suffix - (char *)&nested;
    case 21: return sizeof(review_types_floats);
    case 22: return sizeof(review_types_doubles);
    case 23: return sizeof(review_types_long_doubles);
    case 24: return sizeof(review_types_mixed);
    case 25: return (char *)(review_types_floats+2) - (char *)review_types_floats;
    case 26: return (char *)(review_types_doubles+2) - (char *)review_types_doubles;
    case 27: return (char *)(review_types_long_doubles+2) - (char *)review_types_long_doubles;
    case 28: return (char *)(review_types_mixed+1) - (char *)review_types_mixed;
    case 29: return review_types_double_pointer - review_types_doubles;
    case 30: return review_types_long_double_pointer - review_types_long_doubles;
    default: return -1;
    }
}

int review_types_local_addresses(ReviewTypesAddressOracle inspect) {
    long before;
    float f;
    double d;
    long double ld;
    struct ReviewTypesMixed mixed;
    struct ReviewTypesNested nested;
    union ReviewTypesUnion value;
    float fs[3];
    ReviewTypesDoubles ds;
    ReviewTypesLongDoubles lds;
    long after;
    int result;
    float *fp;
    double *dp;
    long double *lp;
    before=1234567;
    after=7654321;
    fp=fs; dp=ds; lp=lds;
    fp++; dp=dp+2; lp++;
    if (fp-fs!=1 || dp-ds!=2 || lp-lds!=1) return 20;
    if (sizeof(*fp)!=4 || sizeof(*dp)!=8 || sizeof(*lp)!=16) return 21;
    if (sizeof(f)!=4 || sizeof(d)!=8 || sizeof(ld)!=16) return 22;
    result=inspect(&f,&d,&ld,&mixed,&nested,&value,fs,ds,lds);
    if (before!=1234567 || after!=7654321) return 23;
    return result;
}

int review_types_global_addresses(ReviewTypesAddressOracle inspect) {
    return inspect(&review_types_floats[0],&review_types_doubles[0],
        &review_types_long_doubles[0],&review_types_mixed[0],
        &review_types_nested,&review_types_union,
        review_types_floats,review_types_doubles,review_types_long_doubles);
}
