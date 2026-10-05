/* Shared returns-twice fixture: the standalone ABI check uses host libc.
   nonlocal-runtime-check.py also links it to the Forth-built leaf objects. */
int setjmp(long *state);
void longjmp(long *state, int value);
typedef void (*JumpCallback)(long *, int);
void host_jump_callback(long *state, int depth, JumpCallback callback);
static int phase;
static long trash(long a,long b,long c,long d,long e,long f,long g,long h) {
  return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h;
}
void seed_jump_callback(long *state, int depth) {
  if (depth) host_jump_callback(state,depth-1,seed_jump_callback);
  else longjmp(state,9);
}
long check_nonlocal(long input) {
  long state[64];
  long keep1=123456789L;
  long keep2=987654321L;
  volatile int i;
  if (setjmp(state)==0) {
    trash(1,2,3,4,5,6,7,8);
    longjmp(state,1);
  }
  if (0==setjmp(state)) {
    trash(8,7,6,5,4,3,2,1);
    longjmp(state,2);
  }
  if (1>setjmp(state)) {
    trash(11,12,13,14,15,16,17,18);
    longjmp(state,3);
  }
  if (!setjmp(state)) {
    trash(21,22,23,24,25,26,27,28);
    longjmp(state,4);
  }
  for (i=0;i<40;i++) {
    if ((1+2+3)==setjmp(state)) {
      if (keep1!=123456789L || keep2!=987654321L) return 1;
    } else {
      trash(i,32,33,34,35,36,37,38);
      longjmp(state,6);
    }
  }
  phase=0;
  switch(setjmp(state)) {
    case 0: phase=1; trash(41,42,43,44,45,46,47,48); longjmp(state,1); break;
    case 1:
      if (phase!=1) return 2;
      phase=2; trash(51,52,53,54,55,56,57,58); longjmp(state,2); break;
    case 2: if (phase!=2) return 3; break;
    default: return 4;
  }
  switch(input) {
    case 7:
      if (0==setjmp(state)) {
        trash(61,62,63,64,65,66,67,68);
        seed_jump_callback(state,6);
      }
      break;
    default: return 5;
  }
  phase=0;
  switch(input) {
    case 7:
      if (!setjmp(state)) { phase=1; break; }
      if (phase!=1) return 6;
      return keep1+keep2==1111111110L ? 0 : 7;
    default: return 8;
  }
  /* Re-enter a still-live function after its switch stack was unwound. */
  trash(71,72,73,74,75,76,77,78);
  longjmp(state,5);
  return 9;
}
