/* Original seed-forth test; see LICENSE and runtime/gcc-seed/CALENDAR.md.
   Differential calendar fixture: the Forth-built program and a host GCC
   build against glibc (HOST_ORACLE, test oracle only) must print the same
   bytes. "zone" mode exercises one TZ (from the environment): tzset
   variables, localtime/gmtime/ctime/asctime, every DST transition found in
   many years, mktime around transitions and on out-of-range fields, and
   timegm. "format" mode exercises strftime over every conversion, flag,
   width and modifier, ISO and Sunday/Monday week numbers for 400
   consecutive years, size limits, asctime_r limits and difftime. */
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>

static char output[65536];
static long output_used;
static long lines;

static void flush_output(void)
{
    long done = 0;
    while (done < output_used) {
        long count = (long)write(1, output + done, (size_t)(output_used - done));
        if (count <= 0) exit(3);
        done += count;
    }
    output_used = 0;
}

static void put_char(int c)
{
    if (output_used == (long)sizeof output) flush_output();
    output[output_used++] = (char)c;
}

static void put_raw(const char *text)
{
    while (*text) put_char(*text++);
}

static void put_text(const char *text, long length)
{
    static const char hex[] = "0123456789abcdef";
    long i;
    for (i = 0; i < length; i++) {
        int c = (unsigned char)text[i];
        if (c == '\n') put_raw("\\n");
        else if (c == '\t') put_raw("\\t");
        else if (c == '\\') put_raw("\\\\");
        else if (c < 32 || c > 126) {
            put_raw("\\x");
            put_char(hex[c >> 4]);
            put_char(hex[c & 15]);
        } else put_char(c);
    }
}

static void put_long(long value)
{
    char digits[24];
    int count = 0;
    unsigned long magnitude = value < 0 ? 0 - (unsigned long)value : (unsigned long)value;
    if (value < 0) put_char('-');
    do {
        digits[count++] = (char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude);
    while (count) put_char(digits[--count]);
}

static void put_hex(unsigned long value)
{
    static const char hex[] = "0123456789abcdef";
    int shift;
    for (shift = 60; shift >= 0; shift -= 4) put_char(hex[(value >> shift) & 15]);
}

static void end_line(void)
{
    put_char('\n');
    lines++;
}

static void put_tm(const struct tm *value)
{
    put_long(value->tm_year);
    put_char('/');
    put_long(value->tm_mon);
    put_char('/');
    put_long(value->tm_mday);
    put_char(' ');
    put_long(value->tm_hour);
    put_char(':');
    put_long(value->tm_min);
    put_char(':');
    put_long(value->tm_sec);
    put_raw(" w");
    put_long(value->tm_wday);
    put_raw(" y");
    put_long(value->tm_yday);
    put_raw(" d");
    put_long(value->tm_isdst);
}

/* glibc's struct tm carries tm_gmtoff/tm_zone, which its strftime prefers.
   This runtime has the nine standard fields only and takes %z/%Z from the
   current TZ by tm_isdst, as glibc does for a record without tm_zone. The
   oracle gets that record. */
#ifdef HOST_ORACLE
static long oracle_daylight_offset;
static void oracle_setup(void)
{
    long t;
    struct tm value;
    oracle_daylight_offset = -timezone;
    for (t = 0; t < 3L * 366 * 86400; t += 600) {
        if (localtime_r(&t, &value) && value.tm_isdst > 0) {
            oracle_daylight_offset = value.tm_gmtoff;
            return;
        }
    }
}
static void prepare(struct tm *value)
{
    value->tm_zone = NULL;
    value->tm_gmtoff = value->tm_isdst > 0 ? oracle_daylight_offset : -timezone;
}
#else
static void oracle_setup(void)
{
}
static void prepare(struct tm *value)
{
    (void)value;
}
#endif

static unsigned long seed_state = 88172645463325252UL;
static unsigned long next_random(void)
{
    seed_state = seed_state * 6364136223846793005UL + 1442695040888963407UL;
    return seed_state >> 11;
}

static long random_range(long low, long high)
{
    return low + (long)(next_random() % (unsigned long)(high - low + 1));
}

static void show_format(const char *format, const struct tm *value, long size)
{
    char text[512];
    struct tm copy;
    size_t length;
    copy = *value;
    prepare(&copy);
    memset(text, 'Z', sizeof text);
    length = strftime(text, (size_t)size, format, &copy);
    put_long((long)length);
    put_char('[');
    if (length) put_text(text, (long)length);
    put_char(']');
}

static const char zone_format[] = "%a %b %e %H:%M:%S %Z %z %Y %j %U %W %V %G %u %s";

static void show_local(long t)
{
    struct tm value;
    struct tm *pointer;
    char text[32];
    char *line;
    put_raw("t ");
    put_long(t);
    errno = 0;
    pointer = localtime(&t);
    if (!pointer) {
        put_raw(" local error ");
        put_long(errno);
        end_line();
        return;
    }
    value = *pointer;
    put_raw(" local ");
    put_tm(&value);
    put_char(' ');
    show_format(zone_format, &value, 512);
    end_line();
    line = ctime(&t);
    put_raw("  ctime ");
    if (line) put_text(line, (long)strlen(line));
    else put_long(errno);
    line = ctime_r(&t, text);
    put_raw(" ctime_r ");
    if (line) put_text(line, (long)strlen(line));
    else put_long(errno);
    end_line();
}

static void show_utc(long t)
{
    struct tm value;
    char text[32];
    put_raw("u ");
    put_long(t);
    errno = 0;
    if (!gmtime_r(&t, &value)) {
        put_raw(" error ");
        put_long(errno);
    } else {
        put_char(' ');
        put_tm(&value);
        put_raw(" asctime_r ");
        if (asctime_r(&value, text)) put_text(text, (long)strlen(text));
        else put_long(errno);
    }
    end_line();
}

static void show_mktime(const char *label, struct tm *value, int utc)
{
    struct tm copy;
    long result;
    copy = *value;
    errno = 0;
    result = utc ? timegm(&copy) : mktime(&copy);
    put_raw(label);
    put_char(' ');
    put_tm(value);
    put_raw(" -> ");
    put_long(result);
    if (result == -1) {
        put_raw(" errno ");
        put_long(errno);
    }
    put_char(' ');
    put_tm(&copy);
    end_line();
}

/* Round trip of a timestamp through localtime and mktime with each
   requested daylight flag. */
static void round_trip(long t)
{
    struct tm value;
    int flag;
    if (!localtime_r(&t, &value)) return;
    for (flag = -1; flag <= 1; flag++) {
        value.tm_isdst = flag;
        show_mktime("rt", &value, 0);
    }
}

/* Exact instant in (low, high] where localtime's daylight flag changes. */
static long transition(long low, long high)
{
    struct tm a;
    struct tm b;
    int start;
    localtime_r(&low, &a);
    start = a.tm_isdst;
    while (high - low > 1) {
        long middle = low + (high - low) / 2;
        localtime_r(&middle, &b);
        if (b.tm_isdst == start) low = middle;
        else high = middle;
    }
    return high;
}

static void around_transition(long t)
{
    static const int minutes[] = { -120, -90, -61, -60, -59, -30, -1, 0, 1,
                                   30, 59, 60, 61, 90, 120 };
    struct tm base[2];
    long stamp;
    int side;
    int index;
    int flag;
    show_local(t - 1);
    show_local(t);
    show_local(t + 1);
    for (side = 0; side < 2; side++) {
        stamp = t - 1 + side;
        localtime_r(&stamp, &base[side]);
        for (index = 0; index < 15; index++) {
            for (flag = -1; flag <= 1; flag++) {
                struct tm request;
                request = base[side];
                request.tm_min += minutes[index];
                request.tm_isdst = flag;
                show_mktime("tr", &request, 0);
            }
        }
    }
}

static long jan1(long year)
{
    struct tm value;
    memset(&value, 0, sizeof value);
    value.tm_year = (int)(year - 1900);
    value.tm_mday = 1;
    return timegm(&value);
}

/* Walk a year in six-hour steps, hashing every local record and resolving
   each daylight change to the second. */
static void walk_year(long year)
{
    long start = jan1(year) - 86400;
    long end = jan1(year + 1) + 86400;
    long t;
    long previous = start;
    int previous_dst;
    unsigned long hash = 1469598103934665603UL;
    struct tm value;
    if (!localtime_r(&start, &value)) return;
    previous_dst = value.tm_isdst;
    for (t = start; t <= end; t += 21600) {
        if (!localtime_r(&t, &value)) break;
        hash = (hash ^ (unsigned long)(value.tm_sec + 61L * value.tm_min
                                       + 3600L * value.tm_hour)) * 1099511628211UL;
        hash = (hash ^ (unsigned long)(value.tm_mday + 32L * value.tm_mon
                                       + 512L * value.tm_yday + 262144L * value.tm_wday))
            * 1099511628211UL;
        hash = (hash ^ (unsigned long)(value.tm_year + 7L * value.tm_isdst)) * 1099511628211UL;
        if (value.tm_isdst != previous_dst) around_transition(transition(previous, t));
        previous = t;
        previous_dst = value.tm_isdst;
    }
    put_raw("year ");
    put_long(year);
    put_raw(" hash ");
    put_hex(hash);
    end_line();
}

static void zone_mode(void)
{
    static const long years[] = { -5000, -100, -1, 0, 1, 4, 100, 1600, 1800, 1850,
                                  1899, 1900, 1901, 1902, 1969, 1970, 1971, 1972,
                                  1999, 2000, 2037, 2038, 2039, 2040, 2100, 2400,
                                  2401, 3000, 9999, 10000, 30000 };
    static const long extremes[] = {
        LONG_MIN, LONG_MIN + 1, LONG_MAX, LONG_MAX - 1, -1, 0, 1,
        67768036191676799L, 67768036191676800L, 67768036191694799L,
        67768036191658800L, -67768040609740800L, -67768040609740801L,
        -67768040609722801L, -67768040609758800L, 2147483647L, 2147483648L,
        -2147483648L, -2147483649L, 253402300799L, 253402300800L,
        -62167219200L, -62167219201L, 4611686018427387904L,
        -4611686018427387904L, 185542587187199L, 185542587187200L,
        185542587100000L, 1000000000000000L, 10000000000000000L,
        -1000000000000000L, -10000000000000000L, 60000000000000000L,
        -60000000000000000L };
    long i;
    long year;
    tzset();
    oracle_setup();
    put_raw("tzname [");
    put_text(tzname[0], (long)strlen(tzname[0]));
    put_raw("] [");
    put_text(tzname[1], (long)strlen(tzname[1]));
    put_raw("] timezone ");
    put_long(timezone);
    put_raw(" daylight ");
    put_long(daylight);
    end_line();
    for (i = 0; i < (long)(sizeof extremes / sizeof extremes[0]); i++) {
        show_local(extremes[i]);
        show_utc(extremes[i]);
    }
    for (i = 0; i < (long)(sizeof years / sizeof years[0]); i++) {
        long start = jan1(years[i]);
        long leap_day = start + 59L * 86400;
        show_local(start - 1);
        show_local(start);
        show_local(leap_day - 1);
        show_local(leap_day);
        show_local(leap_day + 86400);
        show_utc(start - 1);
        show_utc(leap_day);
        walk_year(years[i]);
    }
    for (year = 1903; year <= 2036; year++) walk_year(year);
    for (i = 0; i < 1500; i++) {
        long t = (long)(next_random() >> 12) - (1L << 40);
        show_local(t);
        show_utc(t);
        round_trip(t);
    }
    for (i = 0; i < 1500; i++) {
        long t = random_range(-2208988800L, 2177452800L);
        show_local(t);
        round_trip(t);
    }
    for (i = 0; i < 3000; i++) {
        struct tm request;
        memset(&request, 0, sizeof request);
        request.tm_year = (int)random_range(-10, 210);
        request.tm_mon = (int)random_range(-40, 40);
        request.tm_mday = (int)random_range(-500, 500);
        request.tm_hour = (int)random_range(-200, 200);
        request.tm_min = (int)random_range(-3000, 3000);
        request.tm_sec = (int)random_range(-10000, 10000);
        request.tm_isdst = (int)random_range(-1, 2);
        request.tm_wday = (int)random_range(-9, 9);
        request.tm_yday = (int)random_range(-999, 999);
        if (i % 3 == 0) {
            request.tm_mon = (int)random_range(0, 11);
            request.tm_mday = (int)random_range(1, 31);
            request.tm_hour = (int)random_range(0, 23);
            request.tm_min = (int)random_range(0, 59);
            request.tm_sec = (int)random_range(0, 60);
        }
        show_mktime("mk", &request, 0);
        show_mktime("gm", &request, 1);
    }
    {
        static const int big[] = { INT_MAX, INT_MIN, INT_MAX - 1900, INT_MAX - 1899,
                                   -1900, -1901, 2147481747, -2147483647 };
        int a;
        int b;
        for (a = 0; a < 8; a++) {
            for (b = 0; b < 6; b++) {
                struct tm request;
                memset(&request, 0, sizeof request);
                request.tm_year = big[a];
                request.tm_mday = 1;
                request.tm_isdst = -1;
                if (b == 1) request.tm_mon = 11, request.tm_mday = 31,
                    request.tm_hour = 23, request.tm_min = 59, request.tm_sec = 59;
                if (b == 2) request.tm_mon = INT_MAX;
                if (b == 3) request.tm_mon = INT_MIN;
                if (b == 4) request.tm_sec = INT_MAX, request.tm_min = INT_MAX;
                if (b == 5) request.tm_mday = INT_MIN, request.tm_hour = INT_MIN;
                show_mktime("big", &request, 0);
                show_mktime("bgm", &request, 1);
            }
        }
    }
}

static const char conversions[] =
    " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

static void format_grid(const struct tm *value)
{
    static const char *const flags[] = { "", "_", "-", "0", "^", "#", "^#", "_^", "-0" };
    static const char *const widths[] = { "", "1", "5", "12" };
    static const char *const modifiers[] = { "", "E", "O" };
    char format[32];
    int c;
    int f;
    int w;
    int m;
    for (c = 0; conversions[c]; c++) {
        for (f = 0; f < 9; f++) {
            for (w = 0; w < 4; w++) {
                for (m = 0; m < 3; m++) {
                    strcpy(format, "<%");
                    strcat(format, flags[f]);
                    strcat(format, widths[w]);
                    strcat(format, modifiers[m]);
                    format[strlen(format) + 1] = '\0';
                    format[strlen(format)] = conversions[c];
                    strcat(format, ">");
                    put_text(format, (long)strlen(format));
                    put_char(' ');
                    show_format(format, value, 512);
                    end_line();
                }
            }
        }
    }
}

static void put_double_bits(double value)
{
    unsigned long bits;
    memcpy(&bits, &value, sizeof bits);
    put_hex(bits);
}

static void format_mode(void)
{
    static const int records[][9] = {
        { 13, 5, 7, 5, 2, 124, 2, 64, 0 },
        { 59, 59, 23, 31, 11, 99, 5, 364, 1 },
        { 0, 0, 0, 1, 0, -2000, 0, 0, -1 },
        { 60, 7, 12, 29, 1, 8100, 4, 59, 2 },
        { -5, -61, -13, -9, -1, -2001, -1, -7, 0 },
        { 99, 99, 99, 99, 12, 9000, 9, 400, 1 },
        { 1, 2, 3, 4, 5, -1901, 6, 365, 0 },
        { 0, 0, 0, 1, 0, -1900, 1, 0, 0 },
        { 0, 0, 0, 1, 0, INT_MAX, 0, 0, 0 },
        { INT_MIN, INT_MAX, INT_MIN, INT_MAX, INT_MIN, INT_MIN, 3, INT_MAX, 0 }
    };
    static const char *const formats[] = {
        "%c", "%x %X", "%D %T %R %r", "%F", "%y %C %Y %G %g", "%e%k%l",
        "%Ec|%EC|%Ex|%EX|%Ey|%EY|%Od|%Oe|%OH|%OI|%Om|%OM|%OS|%Ou|%OU|%OV|%Ow|%OW|%Oy",
        "%^c|%#c|%^#c|%30c|%030c|%^30c", "%10F|%010F|%_10F|%-10F|%^F", "%%|%5%|%E%|%O%|%_%",
        "%n%t%5n%5t", "%p %P %^p %^P %#p %#P %10p %010P", "%Z %z %_8Z %08z %-z %#Z %^Z",
        "%s %5s %-5s %_5s %05s", "plain text", "", "%", "abc%", "%5", "%E", "%O", "%_",
        "%^", "%#", "%-", "%0", "%10", "%E5", "%5E", "%2147483647d", "%2147483648d",
        "%99999999999999999999d", "%Ea %OA %Eb %OB %Eh", "%Ej %Oj %Ek %Ok %El %Ol",
        "%Es %Os %En %On %Et %Ot %Ep %Op %EP %OP %Ez %Oz %EZ %OZ",
        "%ER %OR %ET %OT %Er %Or %ED %OD %EF %OF %Ec %Oc %Ex %Ox %EX %OX %EC %OC",
        "%EG %OG %Eg %Og %EV %OV %EU %OU %EW %OW %Eu %Ou %Ew %Ow %Ed %Ee %EH %EI %EM %Em %ES",
        "%0e %-e %_d %-d %0k %-l %_H"
    };
    static const char *const sized[] = { "%Y-%m-%d", "%c", "abc", "%10a", "%_5d", "%-5d",
                                         "%010y", "%s", "%z", "%Z", "" };
    static const long stamps[] = { LONG_MIN, LONG_MAX, 0, -1, 1, 9007199254740993L,
                                   -9007199254740993L, 9223372036854775807L - 511L,
                                   4611686018427387905L, -4611686018427387905L };
    struct tm value;
    long i;
    long j;
    long year;
    char text[32];
    tzset();
    oracle_setup();
    for (i = 0; i < (long)(sizeof records / sizeof records[0]); i++) {
        memset(&value, 0, sizeof value);
        value.tm_sec = records[i][0];
        value.tm_min = records[i][1];
        value.tm_hour = records[i][2];
        value.tm_mday = records[i][3];
        value.tm_mon = records[i][4];
        value.tm_year = records[i][5];
        value.tm_wday = records[i][6];
        value.tm_yday = records[i][7];
        value.tm_isdst = records[i][8];
        put_raw("record ");
        put_tm(&value);
        end_line();
        for (j = 0; j < (long)(sizeof formats / sizeof formats[0]); j++) {
            put_text(formats[j], (long)strlen(formats[j]));
            put_char(' ');
            show_format(formats[j], &value, 512);
            end_line();
        }
        if (i < 6) format_grid(&value);
        for (j = 0; j < (long)(sizeof sized / sizeof sized[0]); j++) {
            long size;
            for (size = 0; size < 30; size++) {
                put_raw("size ");
                put_long(size);
                put_char(' ');
                put_text(sized[j], (long)strlen(sized[j]));
                put_char(' ');
                show_format(sized[j], &value, size);
                end_line();
            }
        }
        errno = 0;
        put_raw("asctime ");
        if (asctime_r(&value, text)) put_text(text, (long)strlen(text));
        else put_long(errno);
        put_raw(" | ");
        {
            char *line = asctime(&value);
            if (line) put_text(line, (long)strlen(line));
            else put_long(errno);
        }
        end_line();
    }
    /* Week numbers around every year boundary for 400 consecutive years
       (one full Gregorian cycle), plus a negative-year stretch. */
    for (year = 1801; year <= 2200 + 200; year++) {
        long start = jan1(year);
        long day;
        if (year > 2200 && year < 2400 - 3) continue;
        for (day = -7; day <= 7; day++) {
            long t = start + day * 86400;
            gmtime_r(&t, &value);
            show_format("%Y-%m-%d %a %G %g %V %U %W %j %u %w %C %y", &value, 512);
            end_line();
        }
    }
    for (year = -420; year <= 20; year++) {
        long start = jan1(year);
        long day;
        for (day = -4; day <= 4; day += 2) {
            long t = start + day * 86400;
            gmtime_r(&t, &value);
            show_format("%Y-%m-%d %a %G %g %V %U %W %j %C %y %D %F", &value, 512);
            end_line();
        }
    }
    for (i = 0; i < (long)(sizeof stamps / sizeof stamps[0]); i++) {
        for (j = 0; j < (long)(sizeof stamps / sizeof stamps[0]); j++) {
            put_raw("difftime ");
            put_long(stamps[i]);
            put_char(' ');
            put_long(stamps[j]);
            put_char(' ');
            put_double_bits(difftime(stamps[i], stamps[j]));
            end_line();
        }
    }
    for (i = 0; i < 2000; i++) {
        long a = (long)(next_random() << 11);
        long b = (long)(next_random() << 11) >> (next_random() % 60);
        put_raw("difftime ");
        put_double_bits(difftime(a, b));
        put_char(' ');
        put_double_bits(difftime(b, a));
        end_line();
    }
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    if (strcmp(argv[1], "zone") == 0) zone_mode();
    else if (strcmp(argv[1], "format") == 0) format_mode();
    else return 2;
    put_raw("lines ");
    put_long(lines);
    put_char('\n');
    flush_output();
    return 0;
}
