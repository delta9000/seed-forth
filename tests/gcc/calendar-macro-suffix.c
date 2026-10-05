static int one(long seconds,long status,char *zone,const char *date,const char *clock,int warning,int conversions)
{
    cpp_reader reader;
    cpp_hashnode node;
    const unsigned char *first_date,*first_time;
    chosen_seconds=seconds;chosen_status=status;chosen_zone=zone;
    time_calls=0;localtime_calls=0;allocations=0;warnings=0;
    reader.date=NULL;reader.time=NULL;
    node.value.builtin=BT_TIME;
    first_time=fixture_expand(&reader,&node);
    node.value.builtin=BT_DATE;first_date=fixture_expand(&reader,&node);
    if (strcmp((const char *)first_date,date) || strcmp((const char *)first_time,clock)) return 1;
    if (time_calls!=1 || localtime_calls!=conversions || warnings!=warning
        || allocations!=(warning?0:2)) return 2;
    /* A changed clock/zone and a later syscall failure must not alter cache. */
    chosen_seconds=0;chosen_status=-EIO;chosen_zone="unsupported";
    if (fixture_expand(&reader,&node)!=first_date) return 3;
    node.value.builtin=BT_TIME;
    if (fixture_expand(&reader,&node)!=first_time || time_calls!=1
        || localtime_calls!=conversions || warnings!=warning) return 4;
    if (!warning) {
        if (blocks[0][sizeof("\"Oct 11 1347\"")]!=85
            || blocks[1][sizeof("\"12:34:56\"")]!=85) return 5;
        free(blocks[0]);free(blocks[1]);
    }
    return 0;
}
int main(void)
{
    if (one(-1,0,"UTC0","\"Dec 31 1969\"","\"23:59:59\"",0,1)) return 1;
    if (one(0,0,"UTC0","\"Jan  1 1970\"","\"00:00:00\"",0,1)) return 2;
    if (one(951827696,0,"UTC0","\"Feb 29 2000\"","\"12:34:56\"",0,1)) return 3;
    if (one(2147483648L,0,"UTC0","\"Jan 19 2038\"","\"03:14:08\"",0,1)) return 4;
    if (one(0,-EIO,"UTC0","\"??? ?? ????\"","\"??:??:??\"",1,0)) return 5;
    if (one(0,0,"America/New_York","\"??? ?? ????\"","\"??:??:??\"",1,1)) return 6;
    if (one(9223372036854775807L,0,"UTC0","\"??? ?? ????\"","\"??:??:??\"",1,1)) return 7;
    puts("original libcpp date/time formatting and caching passed");return 0;
}
