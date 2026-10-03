/* Host-only independent layout/value instrumentation. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "review-types-fixture.h"
long review_types_metric(int);
long reference_types_metric(int);
int review_types_local_addresses(ReviewTypesAddressOracle);
int reference_types_local_addresses(ReviewTypesAddressOracle);
int review_types_global_addresses(ReviewTypesAddressOracle);
int reference_types_global_addresses(ReviewTypesAddressOracle);
ReviewTypesFloatingCallback review_types_forward_floating(ReviewTypesFloatingCallback);
ReviewTypesAggregateCallback review_types_forward_aggregate(ReviewTypesAggregateCallback);

static double floating_callback(double value) { return value; }
static struct ReviewTypesMixed aggregate_callback(struct ReviewTypesMixed value) { return value; }

static int global_mode;
static int inspect(float *f, double *d, long double *ld,
                   struct ReviewTypesMixed *mixed, struct ReviewTypesNested *nested,
                   union ReviewTypesUnion *value, float *fs, double *ds,
                   long double *lds) {
    void *pointers[]={f,d,ld,mixed,nested,value,fs,ds,lds};
    size_t sizes[]={sizeof(*f),sizeof(*d),sizeof(*ld),sizeof(*mixed),
        sizeof(*nested),sizeof(*value),3*sizeof(*fs),3*sizeof(*ds),3*sizeof(*lds)};
    size_t aligns[]={_Alignof(float),_Alignof(double),_Alignof(long double),
        _Alignof(struct ReviewTypesMixed),_Alignof(struct ReviewTypesNested),
        _Alignof(union ReviewTypesUnion),_Alignof(float),_Alignof(double),
        _Alignof(long double)};
    for (unsigned i=0;i<9;i++) {
        uintptr_t start=(uintptr_t)pointers[i];
        if (start%aligns[i]) return 1;
        for (unsigned j=0;j<i;j++) {
            if (global_mode && i==j+6) continue;
            uintptr_t other=(uintptr_t)pointers[j];
            if (start<other+sizes[j] && other<start+sizes[i]) return 2;
        }
    }
    memset(mixed,0xa5,sizeof(*mixed));
    memset(nested,0x5a,sizeof(*nested));
    memset(value,0x3c,sizeof(*value));
    for (unsigned i=0;i<3;i++) { fs[i]=1.25f+i; ds[i]=3.5+i; lds[i]=7.75L+i; }
    *f=11.25f; *d=13.5; *ld=17.75L;
    mixed->f=19.25f; mixed->d=23.5; mixed->ld=29.75L;
    nested->members[1].f=31.25f;
    nested->members[1].d=37.5;
    nested->members[1].ld=41.75L;
    value->ld=43.75L;
    if (*f!=11.25f || *d!=13.5 || *ld!=17.75L) return 3;
    if (mixed->f!=19.25f || mixed->d!=23.5 || mixed->ld!=29.75L) return 4;
    if (nested->members[1].f!=31.25f || nested->members[1].d!=37.5
        || nested->members[1].ld!=41.75L || value->ld!=43.75L) return 5;
    for (unsigned i=global_mode?1:0;i<3;i++)
        if (fs[i]!=1.25f+i || ds[i]!=3.5+i || lds[i]!=7.75L+i) return 6;
    return 0;
}

int main(void) {
    if (review_types_forward_floating(floating_callback)!=floating_callback
        || review_types_forward_aggregate(aggregate_callback)!=aggregate_callback) return 3;
    for (int i=0;i<31;i++) {
        long target=review_types_metric(i), reference=reference_types_metric(i);
        if (target!=reference) {
            fprintf(stderr,"metric %d: target %ld, host %ld\n",i,target,reference);
            return 1;
        }
    }
    int local=review_types_local_addresses(inspect);
    int reference_local=reference_types_local_addresses(inspect);
    global_mode=1;
    int global=review_types_global_addresses(inspect);
    int reference_global=reference_types_global_addresses(inspect);
    if (local || reference_local || global || reference_global) {
        fprintf(stderr,"addresses: target local %d global %d; host local %d global %d\n",
                local,global,reference_local,reference_global);
        return 2;
    }
    puts("PASS: 31 host layout/metadata comparisons; local/global floating addresses and writes");
    return 0;
}
