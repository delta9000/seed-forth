/* Original seed-forth implementation, MIT license (see LICENSE).
 * The -lm binary64 library: exact rounding/remainder operations, a
 * correctly rounded integer square root, and double-double evaluations of
 * the elementary functions that are rounded once at the end. No code or
 * coefficient is taken from another libm; every table is derived by
 * tests/gcc/math-constants.py and every algorithm is described in MATH.md.
 * Assumes IEEE binary64, LP64 unsigned long, round-to-nearest/ties-even,
 * gradual underflow, and no contraction or excess precision.
 */
#include <math.h>
#include <errno.h>

/* Reading the other union member is the specified AMD64 representation
 * operation of this bounded runtime, not an aliasing pointer cast. */
union seed_math_bits { double number; unsigned long bits; };

#define SEED_SIGN 0x8000000000000000UL
#define SEED_ABS 0x7fffffffffffffffUL
#define SEED_INF 0x7ff0000000000000UL
#define SEED_FRAC 0x000fffffffffffffUL
#define SEED_HIDDEN 0x0010000000000000UL
#define SEED_ONE 0x3ff0000000000000UL
/* 2^54, an exact normalizing factor for every subnormal */
#define SEED_TWO54 18014398509481984.0

/* BEGIN GENERATED TABLES (tests/gcc/math-constants.py) */
#define SEED_LN2_H 0x3fe62e42fefa39efUL /* 0.6931471805599453 */
#define SEED_LN2_L 0x3c7abc9e3b39803fUL /* 2.3190468138462996e-17 */
#define SEED_INVLN2_H 0x3ff71547652b82feUL /* 1.4426950408889634 */
#define SEED_INVLN2_L 0x3c7777d0ffda0d24UL /* 2.0355273740931033e-17 */
#define SEED_INVLN10_H 0x3fdbcb7b1526e50eUL /* 0.4342944819032518 */
#define SEED_INVLN10_L 0x3c695355baaafad3UL /* 1.098319650216765e-17 */
#define SEED_PIO2_H 0x3ff921fb54442d18UL /* 1.5707963267948966 */
#define SEED_PIO2_L 0x3c91a62633145c07UL /* 6.123233995736766e-17 */
#define SEED_PI_H 0x400921fb54442d18UL /* 3.141592653589793 */
#define SEED_PI_L 0x3ca1a62633145c07UL /* 1.2246467991473532e-16 */
#define SEED_THREEPIO4_H 0x4002d97c7f3321d2UL /* 2.356194490192345 */
#define SEED_THREEPIO4_L 0x3c9a79394c9e8a0aUL /* 9.184850993605148e-17 */
#define SEED_S3_H 0xbfc5555555555555UL /* -0.16666666666666666 */
#define SEED_S3_L 0xbc65555555555555UL /* -9.25185853854297e-18 */
#define SEED_S5_H 0x3f81111111111111UL /* 0.008333333333333333 */
#define SEED_S5_L 0x3c01111111111111UL /* 1.1564823173178714e-19 */
#define SEED_C4_H 0x3fa5555555555555UL /* 0.041666666666666664 */
#define SEED_C4_L 0x3c45555555555555UL /* 2.3129646346357427e-18 */
#define SEED_C6_H 0xbf56c16c16c16c17UL /* -0.001388888888888889 */
#define SEED_C6_L 0x3bef49f49f49f49fUL /* 5.300543954373577e-20 */
#define SEED_PIO2_CW1 0x3ff921fb54400000UL /* 1.5707963267341256 */
#define SEED_PIO2_CW2 0x3dd0b4611a600000UL /* 6.077100506303966e-11 */
#define SEED_PIO2_CW3 0x3ba3198a2e000000UL /* 2.0222662487111665e-21 */
#define SEED_PIO2_CW4 0x397b839a252049c1UL /* 8.4784276603689e-32 */
/* log(i/128) as hi, lo for i = 96..192 */
static const unsigned long seed_log_table[194] = {
    0xbfd269621134db92UL, 0xbc7e0efadd9db02bUL,
    0xbfd1bf99635a6b95UL, 0x3c612aeb84249223UL,
    0xbfd1178e8227e47cUL, 0x3c60e63a5f01c691UL,
    0xbfd07138604d5862UL, 0xbc7cdb16ed4e9138UL,
    0xbfcf991c6cb3b379UL, 0xbc6f665066f980a2UL,
    0xbfce530effe71012UL, 0xbc42276041f43042UL,
    0xbfcd1037f2655e7bUL, 0xbc660629242471a2UL,
    0xbfcbd087383bd8adUL, 0xbc3dd355f6a516d7UL,
    0xbfca93ed3c8ad9e3UL, 0xbc6bcafa9de97203UL,
    0xbfc95a5adcf7017fUL, 0xbc5142c507fb7a3dUL,
    0xbfc823c16551a3c2UL, 0x3c61232ce70be781UL,
    0xbfc6f0128b756abcUL, 0x3c68de59c21e166cUL,
    0xbfc5bf406b543db2UL, 0x3c21f5b44c0df7e7UL,
    0xbfc4913d8333b561UL, 0x3c50d5604930f135UL,
    0xbfc365fcb0159016UL, 0xbc57d411a5b944adUL,
    0xbfc23d712a49c202UL, 0x3c66e38161051d69UL,
    0xbfc1178e8227e47cUL, 0x3c50e63a5f01c691UL,
    0xbfbfe89139dbd566UL, 0x3c5ac9f4215f9393UL,
    0xbfbda727638446a2UL, 0xbc5401fa71733019UL,
    0xbfbb6ac88dad5b1cUL, 0x3c40057eed1ca59fUL,
    0xbfb9335e5d594989UL, 0x3c5478a85704ccb7UL,
    0xbfb700d30aeac0e1UL, 0x3c272566212cdd05UL,
    0xbfb4d3115d207eacUL, 0xbc5769f42c7842ccUL,
    0xbfb2aa04a44717a5UL, 0x3c5d15d38d2fa3f7UL,
    0xbfb08598b59e3a07UL, 0x3c5dd7009902bf32UL,
    0xbfaccb73cdddb2ccUL, 0x3c4e48fb0500efd4UL,
    0xbfa894aa149fb343UL, 0xbc3a8be97660a23dUL,
    0xbfa466aed42de3eaUL, 0x3c4cdd6f7f4a137eUL,
    0xbfa0415d89e74444UL, 0xbc4c05cf1d753622UL,
    0xbf98492528c8cabfUL, 0x3c3d192d0619fa67UL,
    0xbf90205658935847UL, 0xbc327c8e8416e71fUL,
    0xbf8010157588de71UL, 0xbc146662d417ced0UL,
    0x0000000000000000UL, 0x0000000000000000UL,
    0x3f7fe02a6b106789UL, 0xbbce44b7e3711ebfUL,
    0x3f8fc0a8b0fc03e4UL, 0xbc183092c59642a1UL,
    0x3f97b91b07d5b11bUL, 0xbc35b602ace3a510UL,
    0x3f9f829b0e783300UL, 0x3c333e3f04f1ef23UL,
    0x3fa39e87b9febd60UL, 0xbc45bfa937f551bbUL,
    0x3fa77458f632dcfcUL, 0x3c418d3ca87b9296UL,
    0x3fab42dd711971bfUL, 0xbc3eb9759c130499UL,
    0x3faf0a30c01162a6UL, 0x3c485f325c5bbacdUL,
    0x3fb16536eea37ae1UL, 0xbc379da3e8c22cdaUL,
    0x3fb341d7961bd1d1UL, 0xbc5b599f227becbbUL,
    0x3fb51b073f06183fUL, 0x3c5a49e39a1a8be4UL,
    0x3fb6f0d28ae56b4cUL, 0xbc5906d99184b992UL,
    0x3fb8c345d6319b21UL, 0xbc24a697ab3424a9UL,
    0x3fba926d3a4ad563UL, 0x3c5942f48aa70ea9UL,
    0x3fbc5e548f5bc743UL, 0x3c35d617ef8161b1UL,
    0x3fbe27076e2af2e6UL, 0xbc361578001e0162UL,
    0x3fbfec9131dbeabbUL, 0xbc55746b9981b36cUL,
    0x3fc0d77e7cd08e59UL, 0x3c69a5dc5e9030acUL,
    0x3fc1b72ad52f67a0UL, 0x3c5483023472cd74UL,
    0x3fc29552f81ff523UL, 0x3c6301771c407dbfUL,
    0x3fc371fc201e8f74UL, 0x3c5de6cb62af18a0UL,
    0x3fc44d2b6ccb7d1eUL, 0x3c69f4f6543e1f88UL,
    0x3fc526e5e3a1b438UL, 0xbc6746ff8a470d3aUL,
    0x3fc5ff3070a793d4UL, 0xbc5bc60efafc6f6eUL,
    0x3fc6d60fe719d21dUL, 0xbc6caae268ecd179UL,
    0x3fc7ab890210d909UL, 0x3c4be36b2d6a0608UL,
    0x3fc87fa06520c911UL, 0xbc6bf7fdbfa08d9aUL,
    0x3fc9525a9cf456b4UL, 0x3c6d904c1d4e2e26UL,
    0x3fca23bc1fe2b563UL, 0x3c493711b07a998cUL,
    0x3fcaf3c94e80bff3UL, 0xbc5398cff3641985UL,
    0x3fcbc286742d8cd6UL, 0x3c54fce744870f55UL,
    0x3fcc8ff7c79a9a22UL, 0xbc64f689f8434012UL,
    0x3fcd5c216b4fbb91UL, 0x3c66e443597e4d40UL,
    0x3fce27076e2af2e6UL, 0xbc461578001e0162UL,
    0x3fcef0adcbdc5936UL, 0x3c648637950dc20dUL,
    0x3fcfb9186d5e3e2bUL, 0xbc6caaae64f21acbUL,
    0x3fd0402594b4d041UL, 0xbc628ec217a5022dUL,
    0x3fd0a324e27390e3UL, 0x3c77dcfde8061c03UL,
    0x3fd1058bf9ae4ad5UL, 0x3c589fa0ab4cb31dUL,
    0x3fd1675cababa60eUL, 0x3c2ce63eab883717UL,
    0x3fd1c898c16999fbUL, 0xbc30e5c62aff1c44UL,
    0x3fd22941fbcf7966UL, 0xbc776f5eb09628afUL,
    0x3fd2895a13de86a3UL, 0x3c77ad24c13f040eUL,
    0x3fd2e8e2bae11d31UL, 0xbc78f4cdb95ebdf9UL,
    0x3fd347dd9a987d55UL, 0xbc64dd4c580919f8UL,
    0x3fd3a64c556945eaUL, 0xbc6c68651945f97cUL,
    0x3fd404308686a7e4UL, 0xbc70bcfb6082ce6dUL,
    0x3fd4618bc21c5ec2UL, 0x3c7f42decdeccf1dUL,
    0x3fd4be5f957778a1UL, 0xbc6259b35b04813dUL,
    0x3fd51aad872df82dUL, 0x3c43927ac19f55e3UL,
    0x3fd5767717455a6cUL, 0x3c7526adb283660cUL,
    0x3fd5d1bdbf5809caUL, 0x3c74236383dc7fe1UL,
    0x3fd62c82f2b9c795UL, 0x3c67b7af915300e5UL,
    0x3fd686c81e9b14afUL, 0xbc6ddea0f7f58e3dUL,
    0x3fd6e08eaa2ba1e4UL, 0xbc7cfb1b39ca3a0fUL,
    0x3fd739d7f6bbd007UL, 0xbc78c76ceb014b04UL,
    0x3fd792a55fdd47a2UL, 0x3c7f057691fe9ed7UL,
    0x3fd7eaf83b82afc3UL, 0x3c792ce979ed2950UL,
    0x3fd842d1da1e8b17UL, 0x3c724ec519784676UL,
    0x3fd89a3386c1425bUL, 0xbc729639dfbbf0fbUL,
    0x3fd8f11e873662c7UL, 0x3c7f85da755a61a3UL,
    0x3fd947941c2116fbUL, 0xbc716cc8bae0bbe4UL,
    0x3fd99d958117e08bUL, 0xbc6a2b6889dc3e72UL,
    0x3fd9f323ecbf984cUL, 0xbc4a92e513217f5cUL,
};
/* 2^(j/64) as hi, lo for j = 0..63 */
static const unsigned long seed_exp2_table[128] = {
    0x3ff0000000000000UL, 0x0000000000000000UL,
    0x3ff02c9a3e778061UL, 0xbc719083535b085dUL,
    0x3ff059b0d3158574UL, 0x3c8d73e2a475b465UL,
    0x3ff0874518759bc8UL, 0x3c6186be4bb284ffUL,
    0x3ff0b5586cf9890fUL, 0x3c98a62e4adc610bUL,
    0x3ff0e3ec32d3d1a2UL, 0x3c403a1727c57b53UL,
    0x3ff11301d0125b51UL, 0xbc96c51039449b3aUL,
    0x3ff1429aaea92de0UL, 0xbc932fbf9af1369eUL,
    0x3ff172b83c7d517bUL, 0xbc819041b9d78a76UL,
    0x3ff1a35beb6fcb75UL, 0x3c8e5b4c7b4968e4UL,
    0x3ff1d4873168b9aaUL, 0x3c9e016e00a2643cUL,
    0x3ff2063b88628cd6UL, 0x3c8dc775814a8495UL,
    0x3ff2387a6e756238UL, 0x3c99b07eb6c70573UL,
    0x3ff26b4565e27cddUL, 0x3c82bd339940e9d9UL,
    0x3ff29e9df51fdee1UL, 0x3c8612e8afad1255UL,
    0x3ff2d285a6e4030bUL, 0x3c90024754db41d5UL,
    0x3ff306fe0a31b715UL, 0x3c86f46ad23182e4UL,
    0x3ff33c08b26416ffUL, 0x3c932721843659a6UL,
    0x3ff371a7373aa9cbUL, 0xbc963aeabf42eae2UL,
    0x3ff3a7db34e59ff7UL, 0xbc75e436d661f5e3UL,
    0x3ff3dea64c123422UL, 0x3c8ada0911f09ebcUL,
    0x3ff4160a21f72e2aUL, 0xbc5ef3691c309278UL,
    0x3ff44e086061892dUL, 0x3c489b7a04ef80d0UL,
    0x3ff486a2b5c13cd0UL, 0x3c73c1a3b69062f0UL,
    0x3ff4bfdad5362a27UL, 0x3c7d4397afec42e2UL,
    0x3ff4f9b2769d2ca7UL, 0xbc94b309d25957e3UL,
    0x3ff5342b569d4f82UL, 0xbc807abe1db13cadUL,
    0x3ff56f4736b527daUL, 0x3c99bb2c011d93adUL,
    0x3ff5ab07dd485429UL, 0x3c96324c054647adUL,
    0x3ff5e76f15ad2148UL, 0x3c9ba6f93080e65eUL,
    0x3ff6247eb03a5585UL, 0xbc9383c17e40b497UL,
    0x3ff6623882552225UL, 0xbc9bb60987591c34UL,
    0x3ff6a09e667f3bcdUL, 0xbc9bdd3413b26456UL,
    0x3ff6dfb23c651a2fUL, 0xbc6bbe3a683c88abUL,
    0x3ff71f75e8ec5f74UL, 0xbc816e4786887a99UL,
    0x3ff75feb564267c9UL, 0xbc90245957316dd3UL,
    0x3ff7a11473eb0187UL, 0xbc841577ee04992fUL,
    0x3ff7e2f336cf4e62UL, 0x3c705d02ba15797eUL,
    0x3ff82589994cce13UL, 0xbc9d4c1dd41532d8UL,
    0x3ff868d99b4492edUL, 0xbc9fc6f89bd4f6baUL,
    0x3ff8ace5422aa0dbUL, 0x3c96e9f156864b27UL,
    0x3ff8f1ae99157736UL, 0x3c85cc13a2e3976cUL,
    0x3ff93737b0cdc5e5UL, 0xbc675fc781b57ebcUL,
    0x3ff97d829fde4e50UL, 0xbc9d185b7c1b85d1UL,
    0x3ff9c49182a3f090UL, 0x3c7c7c46b071f2beUL,
    0x3ffa0c667b5de565UL, 0xbc9359495d1cd533UL,
    0x3ffa5503b23e255dUL, 0xbc9d2f6edb8d41e1UL,
    0x3ffa9e6b5579fdbfUL, 0x3c90fac90ef7fd31UL,
    0x3ffae89f995ad3adUL, 0x3c97a1cd345dcc81UL,
    0x3ffb33a2b84f15fbUL, 0xbc62805e3084d708UL,
    0x3ffb7f76f2fb5e47UL, 0xbc75584f7e54ac3bUL,
    0x3ffbcc1e904bc1d2UL, 0x3c823dd07a2d9e84UL,
    0x3ffc199bdd85529cUL, 0x3c811065895048ddUL,
    0x3ffc67f12e57d14bUL, 0x3c92884dff483cadUL,
    0x3ffcb720dcef9069UL, 0x3c7503cbd1e949dbUL,
    0x3ffd072d4a07897cUL, 0xbc9cbc3743797a9cUL,
    0x3ffd5818dcfba487UL, 0x3c82ed02d75b3707UL,
    0x3ffda9e603db3285UL, 0x3c9c2300696db532UL,
    0x3ffdfc97337b9b5fUL, 0xbc91a5cd4f184b5cUL,
    0x3ffe502ee78b3ff6UL, 0x3c839e8980a9cc8fUL,
    0x3ffea4afa2a490daUL, 0xbc9e9c23179c2893UL,
    0x3ffefa1bee615a27UL, 0x3c9dc7f486a4b6b0UL,
    0x3fff50765b6e4540UL, 0x3c99d3e12dd8a18bUL,
    0x3fffa7c1819e90d8UL, 0x3c874853f3a5931eUL,
};
/* atan(i/32) as hi, lo for i = 0..32 */
static const unsigned long seed_atan_table[66] = {
    0x0000000000000000UL, 0x0000000000000000UL,
    0x3f9ffd55bba97625UL, 0xbc35ec431444912cUL,
    0x3faff55bb72cfdeaUL, 0xbc3c934d86d23f1dUL,
    0x3fb7ee182602f10fUL, 0xbc5cfb654c0c3d98UL,
    0x3fbfd5ba9aac2f6eUL, 0xbc4cd37686760c17UL,
    0x3fc3d6eee8c6626cUL, 0x3c661a3b0ce9281bUL,
    0x3fc7b97b4bce5b02UL, 0x3c5347b0b4f881caUL,
    0x3fcb90d7529260a2UL, 0x3c217b10d2e0e5abUL,
    0x3fcf5b75f92c80ddUL, 0x3c68ab6e3cf7afbdUL,
    0x3fd18bf5a30bf178UL, 0x3c630ca4748b1bf9UL,
    0x3fd362773707ebccUL, 0xbc6963a544b672d8UL,
    0x3fd530ad9951cd4aUL, 0xbc62566480884082UL,
    0x3fd6f61941e4def1UL, 0xbc7c63aae6f6e918UL,
    0x3fd8b24d394a1b25UL, 0x3c7b6d0ba3748fa8UL,
    0x3fda64eec3cc23fdUL, 0xbc724dec1b50b7ffUL,
    0x3fdc0db4c94ec9f0UL, 0xbc7cc1ce70934c34UL,
    0x3fddac670561bb4fUL, 0x3c7a2b7f222f65e2UL,
    0x3fdf40dd0b541418UL, 0xbc6a3992dc382a23UL,
    0x3fe0657e94db30d0UL, 0xbc7d5b495f6349e6UL,
    0x3fe1255d9bfbd2a9UL, 0xbc52bdaee1c0ee35UL,
    0x3fe1e00babdefeb4UL, 0xbc5928df287a668fUL,
    0x3fe2958e59308e31UL, 0xbc709e73b0c6c087UL,
    0x3fe345f01cce37bbUL, 0x3c81021137c71102UL,
    0x3fe3f13fb89e96f4UL, 0x3c7ecf8b492644f0UL,
    0x3fe4978fa3269ee1UL, 0x3c72419a87f2a458UL,
    0x3fe538f57b89061fUL, 0xbc81bb74abda520cUL,
    0x3fe5d58987169b18UL, 0x3c60028e4bc5e7caUL,
    0x3fe66d663923e087UL, 0xbc76ea6febe8bbbaUL,
    0x3fe700a7c5784634UL, 0xbc78c34d25aadef6UL,
    0x3fe78f6bbd5d315eUL, 0x3c8406a089803740UL,
    0x3fe819d0b7158a4dUL, 0xbc7bf76229d3b917UL,
    0x3fe89ff5ff57f1f8UL, 0xbc855b9a5e177a1bUL,
    0x3fe921fb54442d18UL, 0x3c81a62633145c07UL,
};
/* 2/pi = sum of word[j] * 2^(-32(j+1)), j = 0..39 */
static const unsigned long seed_two_over_pi[40] = {
    0xa2f9836eUL, 0x4e441529UL, 0xfc2757d1UL, 0xf534ddc0UL,
    0xdb629599UL, 0x3c439041UL, 0xfe5163abUL, 0xdebbc561UL,
    0xb7246e3aUL, 0x424dd2e0UL, 0x06492eeaUL, 0x09d1921cUL,
    0xfe1deb1cUL, 0xb129a73eUL, 0xe88235f5UL, 0x2ebb4484UL,
    0xe99c7026UL, 0xb45f7e41UL, 0x3991d639UL, 0x835339f4UL,
    0x9c845f8bUL, 0xbdf9283bUL, 0x1ff897ffUL, 0xde05980fUL,
    0xef2f118bUL, 0x5a0a6d1fUL, 0x6d367ecfUL, 0x27cb09b7UL,
    0x4f463f66UL, 0x9e5fea2dUL, 0x7527bac7UL, 0xebe5f17bUL,
    0x3d0739f7UL, 0x8a5292eaUL, 0x6bfb5fb1UL, 0x1f8d5d08UL,
    0x56033046UL, 0xfc7b6babUL, 0xf0cfbc20UL, 0x9af4361dUL,
};
/* END GENERATED TABLES */

/* ---- representation helpers ---- */

static double seed_d(unsigned long bits)
{
    union seed_math_bits value;
    value.bits = bits;
    return value.number;
}

static unsigned long seed_b(double x)
{
    union seed_math_bits value;
    value.number = x;
    return value.bits;
}

/* The quiet NaN the AMD64 SSE unit produces for an invalid operation. */
static double seed_invalid(void)
{
    errno = EDOM;
    return seed_d(0xfff8000000000000UL);
}

static double seed_infinity(int negative)
{
    return seed_d(negative ? 0xfff0000000000000UL : SEED_INF);
}

/* 2^k for -1022 <= k <= 1023 */
static double seed_pow2(int k)
{
    return seed_d((unsigned long)(k + 1023) << 52);
}

/* x * 2^k, exact whenever every step stays in the normal range. */
static double seed_scale(double x, int k)
{
    while (k > 1000) {
        x = x * seed_pow2(1000);
        k -= 1000;
    }
    while (k < -1000) {
        x = x * seed_pow2(-1000);
        k += 1000;
    }
    return x * seed_pow2(k);
}

/* floor(log2 |x|) for finite nonzero x */
static int seed_exponent(double x)
{
    unsigned long bits = seed_b(x) & SEED_ABS;
    int exponent;
    if (bits >= SEED_HIDDEN) return (int)(bits >> 52) - 1023;
    exponent = -1075;
    while (bits) {
        bits >>= 1;
        exponent++;
    }
    return exponent;
}

/* ---- error-free transformations and double-double arithmetic ---- */

static void seed_two_sum(double a, double b, double *sum, double *error)
{
    double s = a + b;
    double bv = s - a;
    double av = s - bv;
    *sum = s;
    *error = (a - av) + (b - bv);
}

/* Requires |a| >= |b| or a == 0. */
static void seed_fast_two_sum(double a, double b, double *sum, double *error)
{
    double s = a + b;
    *sum = s;
    *error = b - (s - a);
}

/* Veltkamp splitting; |a| < 2^995 keeps the product finite. */
static void seed_split(double a, double *high, double *low)
{
    double c = 134217729.0 * a;
    double h = c - (c - a);
    *high = h;
    *low = a - h;
}

/* Dekker's exact product a*b = p + e (no underflow in the partial products). */
static void seed_two_prod(double a, double b, double *product, double *error)
{
    double ah;
    double al;
    double bh;
    double bl;
    double p = a * b;
    seed_split(a, &ah, &al);
    seed_split(b, &bh, &bl);
    *product = p;
    *error = ((ah * bh - p) + ah * bl + al * bh) + al * bl;
}

static void seed_dd_add(double ah, double al, double bh, double bl,
                        double *rh, double *rl)
{
    double s;
    double e;
    double t;
    double f;
    seed_two_sum(ah, bh, &s, &e);
    seed_two_sum(al, bl, &t, &f);
    e = e + t;
    seed_two_sum(s, e, &s, &e);
    e = e + f;
    seed_two_sum(s, e, rh, rl);
}

static void seed_dd_mul(double ah, double al, double bh, double bl,
                        double *rh, double *rl)
{
    double p;
    double e;
    seed_two_prod(ah, bh, &p, &e);
    e = e + (ah * bl + al * bh);
    seed_fast_two_sum(p, e, rh, rl);
}

static void seed_dd_div(double ah, double al, double bh, double bl,
                        double *rh, double *rl)
{
    double q = ah / bh;
    double p;
    double e;
    double r;
    seed_two_prod(q, bh, &p, &e);
    r = (((ah - p) - e) + al) - q * bl;
    seed_fast_two_sum(q, r / bh, rh, rl);
}

/* Correctly rounded (hi + lo) * 2^k for a double-double with |hi| roughly
 * in [2^-3, 2^3]. Overflow and underflow to zero set ERANGE, matching
 * glibc; nonzero subnormal results do not. */
static double seed_finish(double hi, double lo, int k)
{
    double r = hi + lo;
    double h;
    double l;
    double n;
    double d;
    int negative;
    int e;
    if (r == 0.0) return r;
    e = (int)((seed_b(r) >> 52) & 2047) - 1023 + k;
    negative = hi < 0.0;
    if (e > 1023) {
        errno = ERANGE;
        return seed_infinity(negative);
    }
    if (e >= -1022) return seed_scale(r, k);
    /* Subnormal: round (hi + lo) * 2^(k+1074) to an integer once. */
    if (negative) {
        hi = -hi;
        lo = -lo;
    }
    k += 1074;
    if (k < -3) {
        n = 0.0;
    } else {
        h = seed_scale(hi, k);
        l = seed_scale(lo, k);
        n = (double)(long)h;
        d = ((h - n) - 0.5) + l;
        if (d > 0.0 || (d == 0.0 && ((long)n & 1))) n = n + 1.0;
    }
    r = n * seed_d(1);
    if (r == 0.0) errno = ERANGE;
    return negative ? -r : r;
}

/* ---- exact operations ---- */

double fabs(double x)
{
    return seed_d(seed_b(x) & SEED_ABS);
}

double floor(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long fraction;
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) return x + x;
    if (exponent >= 52) return x;
    if (exponent < 0) {
        if ((bits & SEED_ABS) == 0 || !(bits & SEED_SIGN)) return seed_d(bits & SEED_SIGN);
        return -1.0;
    }
    fraction = SEED_FRAC >> exponent;
    if ((bits & fraction) == 0) return x;
    if (bits & SEED_SIGN) bits += fraction + 1;
    return seed_d(bits & ~fraction);
}

double ceil(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long fraction;
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) return x + x;
    if (exponent >= 52) return x;
    if (exponent < 0) {
        if ((bits & SEED_ABS) == 0 || (bits & SEED_SIGN)) return seed_d(bits & SEED_SIGN);
        return 1.0;
    }
    fraction = SEED_FRAC >> exponent;
    if ((bits & fraction) == 0) return x;
    if (!(bits & SEED_SIGN)) bits += fraction + 1;
    return seed_d(bits & ~fraction);
}

double trunc(double x)
{
    unsigned long bits = seed_b(x);
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) return x + x;
    if (exponent >= 52) return x;
    if (exponent < 0) return seed_d(bits & SEED_SIGN);
    return seed_d(bits & ~(SEED_FRAC >> exponent));
}

double round(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long fraction;
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) return x + x;
    if (exponent >= 52) return x;
    if (exponent < 0) {
        if (exponent == -1) return seed_d((bits & SEED_SIGN) | SEED_ONE);
        return seed_d(bits & SEED_SIGN);
    }
    fraction = SEED_FRAC >> exponent;
    if ((bits & fraction) == 0) return x;
    bits += (fraction + 1) >> 1;
    return seed_d(bits & ~fraction);
}

double rint(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long fraction;
    unsigned long dropped;
    unsigned long half;
    int exponent = (int)((bits >> 52) & 2047) - 1023;
    if (exponent == 1024) return x + x;
    if (exponent >= 52) return x;
    if (exponent < 0) {
        if ((bits & SEED_ABS) > 0x3fe0000000000000UL) return seed_d((bits & SEED_SIGN) | SEED_ONE);
        return seed_d(bits & SEED_SIGN);
    }
    fraction = SEED_FRAC >> exponent;
    dropped = bits & fraction;
    if (dropped == 0) return x;
    half = (fraction + 1) >> 1;
    bits &= ~fraction;
    /* For exponent 0 the units bit is the low exponent bit, which is 1. */
    if (dropped > half || (dropped == half && (bits & (fraction + 1)))) bits += fraction + 1;
    return seed_d(bits);
}

double nearbyint(double x)
{
    return rint(x);
}

/* Out-of-range and NaN conversions give the AMD64 indefinite integer, as
 * glibc does; errno is unchanged. */
long lround(double x)
{
    return (long)round(x);
}

long lrint(double x)
{
    return (long)rint(x);
}

long long llround(double x)
{
    return (long long)round(x);
}

long long llrint(double x)
{
    return (long long)rint(x);
}

/* 1 for a NaN whose quiet bit is clear */
static int seed_signaling(double x)
{
    unsigned long a = seed_b(x) & SEED_ABS;
    return a > SEED_INF && !(a & 0x0008000000000000UL);
}

/* A quiet NaN operand is ignored; a signaling one makes the result NaN
 * (IEEE 754-2008 minNum/maxNum, as glibc). Equal operands give y. */
double fmin(double x, double y)
{
    if (seed_signaling(x) || seed_signaling(y)) return x + y;
    if ((seed_b(x) & SEED_ABS) > SEED_INF) return y;
    if ((seed_b(y) & SEED_ABS) > SEED_INF) return x;
    return x < y ? x : y;
}

double fmax(double x, double y)
{
    if (seed_signaling(x) || seed_signaling(y)) return x + y;
    if ((seed_b(x) & SEED_ABS) > SEED_INF) return y;
    if ((seed_b(y) & SEED_ABS) > SEED_INF) return x;
    return x > y ? x : y;
}

double fdim(double x, double y)
{
    double r;
    if ((seed_b(x) & SEED_ABS) > SEED_INF || (seed_b(y) & SEED_ABS) > SEED_INF) return x + y;
    if (!(x > y)) return 0.0;
    r = x - y;
    if ((seed_b(r) & SEED_ABS) == SEED_INF
        && (seed_b(x) & SEED_ABS) < SEED_INF && (seed_b(y) & SEED_ABS) < SEED_INF)
        errno = ERANGE;
    return r;
}

/* Split finite nonzero |x| into mantissa * 2^exponent, 2^52 <= mantissa < 2^53. */
static unsigned long seed_unpack(unsigned long magnitude, int *exponent)
{
    int field = (int)(magnitude >> 52);
    unsigned long mantissa = magnitude & SEED_FRAC;
    if (field == 0) {
        *exponent = -1074;
        while (mantissa < SEED_HIDDEN) {
            mantissa <<= 1;
            *exponent -= 1;
        }
        return mantissa;
    }
    *exponent = field - 1075;
    return mantissa | SEED_HIDDEN;
}

/* Exact mantissa * 2^exponent for a mantissa below 2^53 known to be
 * representable (a multiple of the subnormal spacing). */
static double seed_pack(unsigned long sign, unsigned long mantissa, int exponent)
{
    if (mantissa == 0) return seed_d(sign);
    while (mantissa < SEED_HIDDEN && exponent > -1074) {
        mantissa <<= 1;
        exponent--;
    }
    while (exponent < -1074) {
        mantissa >>= 1;
        exponent++;
    }
    if (mantissa >= SEED_HIDDEN)
        return seed_d(sign | ((unsigned long)(exponent + 1075) << 52) | (mantissa & SEED_FRAC));
    return seed_d(sign | mantissa);
}

/* |x| mod |y| by binary long division; *parity receives the quotient's
 * lowest bit. Requires finite nonzero |x| >= |y|. */
static unsigned long seed_divide(unsigned long ax, unsigned long ay, int *exponent, int *parity)
{
    int ex;
    int ey;
    int steps;
    unsigned long r = seed_unpack(ax, &ex);
    unsigned long m = seed_unpack(ay, &ey);
    for (steps = ex - ey; steps > 0; steps--) {
        if (r >= m) r -= m;
        r <<= 1;
    }
    *parity = 0;
    if (r >= m) {
        r -= m;
        *parity = 1;
    }
    *exponent = ey;
    return r;
}

double fmod(double x, double y)
{
    unsigned long bx = seed_b(x);
    unsigned long ax = bx & SEED_ABS;
    unsigned long ay = seed_b(y) & SEED_ABS;
    unsigned long r;
    int exponent;
    int parity;
    if (ax > SEED_INF || ay > SEED_INF) return x + y;
    if (ax == SEED_INF || ay == 0) return seed_invalid();
    if (ax < ay) return x;
    r = seed_divide(ax, ay, &exponent, &parity);
    return seed_pack(bx & SEED_SIGN, r, exponent);
}

double remainder(double x, double y)
{
    unsigned long bx = seed_b(x);
    unsigned long ax = bx & SEED_ABS;
    unsigned long ay = seed_b(y) & SEED_ABS;
    unsigned long r;
    unsigned long m;
    unsigned long sign = bx & SEED_SIGN;
    int exponent;
    int parity;
    int ey;
    double fx;
    double fy;
    if (ax > SEED_INF || ay > SEED_INF) return x + y;
    if (ax == SEED_INF || ay == 0) return seed_invalid();
    if (ax < ay) {
        /* Quotient 0 (even): move to |x|-|y| only when 2|x| > |y|. */
        fx = seed_d(ax);
        fy = seed_d(ay);
        if (fx > fy - fx) return seed_d(sign ^ seed_b(fx - fy));
        return x;
    }
    r = seed_divide(ax, ay, &exponent, &parity);
    m = seed_unpack(ay, &ey);
    if (2 * r > m || (2 * r == m && parity)) {
        r = m - r;
        sign ^= SEED_SIGN;
    }
    if (r == 0) return seed_d(bx & SEED_SIGN);
    return seed_pack(sign, r, exponent);
}

/* Correctly rounded square root by the restoring digit-by-digit method on
 * the integer significand: the 54-bit root and its remainder decide the
 * single rounding (an exact tie is impossible). */
double sqrt(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long mantissa;
    unsigned long remainder_bits = 0;
    unsigned long root = 0;
    unsigned long trial;
    int exponent;
    int i;
    if ((bits & SEED_ABS) == 0) return x;
    if (bits & SEED_SIGN) {
        if ((bits & SEED_ABS) > SEED_INF) return x + x;
        return seed_invalid();
    }
    if (bits >= SEED_INF) return x + x;
    mantissa = seed_unpack(bits, &exponent);
    if (exponent & 1) {
        mantissa <<= 1;
        exponent--;
    }
    /* sqrt(mantissa * 2^54) lies in [2^53, 2^54). */
    for (i = 53; i >= 0; i--) {
        remainder_bits <<= 2;
        if (i >= 27) remainder_bits |= (mantissa >> (2 * i - 54)) & 3;
        trial = (root << 2) | 1;
        if (remainder_bits >= trial) {
            remainder_bits -= trial;
            root = (root << 1) | 1;
        } else {
            root <<= 1;
        }
    }
    /* value = root * 2^((exponent - 54) / 2); keep 53 bits and round. */
    exponent = (exponent - 54) / 2 + 1;
    return seed_d((((unsigned long)(exponent + 1075) << 52) + ((root >> 1) & SEED_FRAC)) + (root & 1));
}

/* (h + l) for h > 0 as a double-double square root, error about 2^-104. */
static void seed_sqrt_dd(double h, double l, double *rh, double *rl)
{
    double s = sqrt(h);
    double p;
    double e;
    seed_two_prod(s, s, &p, &e);
    seed_fast_two_sum(s, (((h - p) - e) + l) / (2.0 * s), rh, rl);
}

/* ---- logarithms ---- */

/* log(x) as rh + rl for finite x > 0, relative error below 2^-68.
 * x = 2^k * m, m in [0.75, 1.5), c = i/128 nearest m, z = (m-c)/(m+c):
 * log(x) = k*log(2) + log(c) + 2*atanh(z), |z| < 2^-8.5. */
static void seed_log_dd(double x, double *rh, double *rl)
{
    unsigned long bits = seed_b(x);
    int k = 0;
    int i;
    double m;
    double c;
    double f;
    double sh;
    double sl;
    double zh;
    double zl;
    double ph;
    double pl;
    double u;
    double poly;
    double kh;
    double kl;
    if (bits < SEED_HIDDEN) {
        bits = seed_b(x * SEED_TWO54);
        k = -54;
    }
    k += (int)(bits >> 52) - 1023;
    m = seed_d((bits & SEED_FRAC) | SEED_ONE);
    if (m >= 1.5) {
        m = m * 0.5;
        k++;
    }
    i = (int)(m * 128.0 + 0.5);
    c = i * 0.0078125;
    f = m - c;
    seed_two_sum(m, c, &sh, &sl);
    zh = f / sh;
    seed_two_prod(zh, sh, &ph, &pl);
    zl = (((f - ph) - pl) - zh * sl) / sh;
    u = zh * zh;
    poly = u * (1.0 / 3.0 + u * (1.0 / 5.0 + u * (1.0 / 7.0 + u * (1.0 / 9.0))));
    seed_fast_two_sum(2.0 * zh, 2.0 * zl + 2.0 * zh * poly, &zh, &zl);
    seed_two_prod((double)k, seed_d(SEED_LN2_H), &kh, &kl);
    kl = kl + k * seed_d(SEED_LN2_L);
    seed_dd_add(kh, kl, seed_d(seed_log_table[2 * (i - 96)]),
                seed_d(seed_log_table[2 * (i - 96) + 1]), &ph, &pl);
    seed_dd_add(ph, pl, zh, zl, rh, rl);
}

/* Shared special cases of log, log2 and log10; returns 1 when *r is set. */
static int seed_log_special(double x, double *r)
{
    unsigned long bits = seed_b(x);
    if ((bits & SEED_ABS) > SEED_INF) {
        *r = x + x;
        return 1;
    }
    if ((bits & SEED_ABS) == 0) {
        errno = ERANGE;
        *r = seed_infinity(1);
        return 1;
    }
    if (bits & SEED_SIGN) {
        *r = seed_invalid();
        return 1;
    }
    if (bits == SEED_INF) {
        *r = x;
        return 1;
    }
    return 0;
}

double log(double x)
{
    double h;
    double l;
    if (seed_log_special(x, &h)) return h;
    seed_log_dd(x, &h, &l);
    return h + l;
}

double log2(double x)
{
    double h;
    double l;
    if (seed_log_special(x, &h)) return h;
    /* Exact powers of two, normal or subnormal, give their exponent. */
    if (seed_b(x) >= SEED_HIDDEN ? (seed_b(x) & SEED_FRAC) == 0 : (seed_b(x) & (seed_b(x) - 1)) == 0)
        return (double)seed_exponent(x);
    seed_log_dd(x, &h, &l);
    seed_dd_mul(h, l, seed_d(SEED_INVLN2_H), seed_d(SEED_INVLN2_L), &h, &l);
    return h + l;
}

double log10(double x)
{
    double h;
    double l;
    if (seed_log_special(x, &h)) return h;
    seed_log_dd(x, &h, &l);
    seed_dd_mul(h, l, seed_d(SEED_INVLN10_H), seed_d(SEED_INVLN10_L), &h, &l);
    return h + l;
}

double log1p(double x)
{
    unsigned long bits = seed_b(x);
    double sh;
    double sl;
    double h;
    double l;
    double tl;
    double ph;
    double pl;
    if ((bits & SEED_ABS) > SEED_INF) return x + x;
    if (bits == 0xbff0000000000000UL) {
        errno = ERANGE;
        return seed_infinity(1);
    }
    if (x < -1.0) return seed_invalid();
    if (bits == SEED_INF) return x;
    if ((bits & SEED_ABS) < 0x3c90000000000000UL) return x;
    /* log(1+x) = log(sh) + log1p(sl/sh), |sl/sh| <= 2^-53. */
    seed_two_sum(1.0, x, &sh, &sl);
    seed_log_dd(sh, &h, &l);
    /* log1p(t) for t = sl/sh, |t| <= 2^-53. Below |x| = 1 the term can be
     * as large as the result, so t is then formed as a double-double. */
    tl = sl / sh;
    pl = 0.0;
    if (fabs(x) < 1.0) {
        seed_two_prod(tl, sh, &ph, &pl);
        pl = ((sl - ph) - pl) / sh - 0.5 * tl * tl;
    }
    seed_dd_add(h, l, tl, pl, &h, &l);
    return h + l;
}

/* ---- exponentials ---- */

/* 2^(yh+yl) = (rh + rl) * 2^k for |yh| <= 1100, relative error ~2^-67.
 * n = nearest(64 y), t = (y - n/64)*log(2), |t| <= log(2)/128:
 * 2^y = 2^(n div 64) * 2^((n mod 64)/64) * (1 + expm1(t)). */
static void seed_exp2_dd(double yh, double yl, double *rh, double *rl, int *k)
{
    double t = yh * 64.0;
    long n = (long)(t < 0.0 ? t - 0.5 : t + 0.5);
    int j = (int)(n & 63);
    double r0;
    double r1;
    double th;
    double tl;
    double q;
    double ph;
    double pl;
    double big;
    double a;
    double b;
    double s;
    double e;
    *k = (int)((n - j) / 64);
    seed_two_sum(yh - (double)n * 0.015625, yl, &r0, &r1);
    seed_dd_mul(r0, r1, seed_d(SEED_LN2_H), seed_d(SEED_LN2_L), &th, &tl);
    q = th * th * (0.5 + th * (1.0 / 6.0 + th * (1.0 / 24.0 + th * (1.0 / 120.0
        + th * (1.0 / 720.0 + th * (1.0 / 5040.0))))));
    seed_fast_two_sum(th, tl + th * tl + q, &ph, &pl);
    big = seed_d(seed_exp2_table[2 * j]);
    seed_two_prod(big, ph, &a, &b);
    seed_two_sum(big, a, &s, &e);
    e = e + (seed_d(seed_exp2_table[2 * j + 1]) + b + big * pl
             + seed_d(seed_exp2_table[2 * j + 1]) * ph);
    seed_fast_two_sum(s, e, rh, rl);
}

/* e^x = (rh + rl) * 2^k for |x| <= 760 */
static void seed_exp_dd(double x, double *rh, double *rl, int *k)
{
    double yh;
    double yl;
    seed_two_prod(x, seed_d(SEED_INVLN2_H), &yh, &yl);
    yl = yl + x * seed_d(SEED_INVLN2_L);
    seed_exp2_dd(yh, yl, rh, rl, k);
}

/* e^x - 1 unscaled for |x| <= 50 */
static void seed_expm1_dd(double x, double *rh, double *rl)
{
    double h;
    double l;
    double q;
    int k;
    if (fabs(x) < 0.005) {
        q = x * x * (0.5 + x * (1.0 / 6.0 + x * (1.0 / 24.0 + x * (1.0 / 120.0
            + x * (1.0 / 720.0 + x * (1.0 / 5040.0))))));
        seed_fast_two_sum(x, q, rh, rl);
        return;
    }
    seed_exp_dd(x, &h, &l, &k);
    seed_dd_add(seed_scale(h, k), seed_scale(l, k), -1.0, 0.0, rh, rl);
}

double exp(double x)
{
    unsigned long bits = seed_b(x);
    double h;
    double l;
    int k;
    if ((bits & SEED_ABS) >= SEED_INF) {
        if (bits == 0xfff0000000000000UL) return 0.0;
        return x + x;
    }
    if (x > 710.0) {
        errno = ERANGE;
        return seed_infinity(0);
    }
    if (x < -746.0) {
        errno = ERANGE;
        return 0.0;
    }
    if ((bits & SEED_ABS) < 0x3c90000000000000UL) return 1.0 + x;
    seed_exp_dd(x, &h, &l, &k);
    return seed_finish(h, l, k);
}

double exp2(double x)
{
    unsigned long bits = seed_b(x);
    double h;
    double l;
    int k;
    if ((bits & SEED_ABS) >= SEED_INF) {
        if (bits == 0xfff0000000000000UL) return 0.0;
        return x + x;
    }
    if (x >= 1024.0) {
        errno = ERANGE;
        return seed_infinity(0);
    }
    if (x < -1080.0) {
        errno = ERANGE;
        return 0.0;
    }
    if ((bits & SEED_ABS) < 0x3c90000000000000UL) return 1.0 + x;
    seed_exp2_dd(x, 0.0, &h, &l, &k);
    return seed_finish(h, l, k);
}

double expm1(double x)
{
    unsigned long bits = seed_b(x);
    double h;
    double l;
    int k;
    if ((bits & SEED_ABS) >= SEED_INF) {
        if (bits == 0xfff0000000000000UL) return -1.0;
        return x + x;
    }
    if (x > 710.0) {
        errno = ERANGE;
        return seed_infinity(0);
    }
    if (x < -40.0) return -1.0;
    if ((bits & SEED_ABS) < 0x3c90000000000000UL) return x;
    if (x <= 50.0) {
        seed_expm1_dd(x, &h, &l);
        return h + l;
    }
    /* Beyond 50 the subtracted 1 is below 2^-72 of the result. */
    seed_exp_dd(x, &h, &l, &k);
    return seed_finish(h, l, k);
}

/* ---- power, cube root, hypotenuse ---- */

/* 0: not an integer, 1: odd integer, 2: even integer (finite y) */
static int seed_integer_class(double y)
{
    unsigned long bits = seed_b(y) & SEED_ABS;
    int exponent = (int)(bits >> 52) - 1023;
    if (bits == 0 || exponent > 52) return 2;
    if (exponent < 0 || (bits & (SEED_FRAC >> exponent))) return 0;
    /* The units bit; for exponent 0 it is the implicit leading 1. */
    if (exponent == 0) return 1;
    return ((bits >> (52 - exponent)) & 1) ? 1 : 2;
}

double pow(double x, double y)
{
    unsigned long bx = seed_b(x);
    unsigned long by = seed_b(y);
    unsigned long ax = bx & SEED_ABS;
    unsigned long ay = by & SEED_ABS;
    int negative;
    int k;
    double lh;
    double ll;
    double wh;
    double wl;
    double r;
    if (ay == 0 || bx == SEED_ONE) return 1.0;
    if (ax > SEED_INF || ay > SEED_INF) return x + y;
    if (ay == SEED_INF) {
        if (ax == SEED_ONE) return 1.0;
        if ((ax < SEED_ONE) == !(by & SEED_SIGN)) return 0.0;
        return seed_infinity(0);
    }
    negative = (bx & SEED_SIGN) && seed_integer_class(y) == 1;
    if (ax == 0) {
        if (by & SEED_SIGN) {
            errno = ERANGE;
            return seed_infinity(negative);
        }
        return negative ? -0.0 : 0.0;
    }
    if (ax == SEED_INF) {
        if (by & SEED_SIGN) return negative ? -0.0 : 0.0;
        return seed_infinity(negative);
    }
    if ((bx & SEED_SIGN) && seed_integer_class(y) == 0) return seed_invalid();
    if (ax == SEED_ONE) return negative ? -1.0 : 1.0;
    /* w = y * log2|x| as a double-double; then 2^w rounded once. */
    seed_log_dd(seed_d(ax), &lh, &ll);
    seed_dd_mul(lh, ll, seed_d(SEED_INVLN2_H), seed_d(SEED_INVLN2_L), &lh, &ll);
    wh = y * lh;
    if (wh > 1100.0) {
        errno = ERANGE;
        return seed_infinity(negative);
    }
    if (wh < -1100.0) {
        errno = ERANGE;
        return negative ? -0.0 : 0.0;
    }
    seed_two_prod(y, lh, &wh, &wl);
    wl = wl + y * ll;
    seed_exp2_dd(wh, wl, &lh, &ll, &k);
    r = seed_finish(lh, ll, k);
    return negative ? -r : r;
}

double cbrt(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    int k = 0;
    int exponent;
    int q;
    int i;
    double m;
    double y;
    double a2;
    double b2;
    double c3;
    double d3;
    double r;
    if (ax == 0 || ax >= SEED_INF) return x + x;
    if (ax < SEED_HIDDEN) {
        ax = seed_b(seed_d(ax) * SEED_TWO54);
        k = -18;
    }
    exponent = (int)(ax >> 52) - 1023;
    q = exponent >= 0 ? exponent / 3 : -((2 - exponent) / 3);
    /* m = |x| / 2^(3q) in [1, 8) */
    m = seed_d(((unsigned long)(exponent - 3 * q + 1023) << 52) | (ax & SEED_FRAC));
    /* Newton from (m+2)/3 >= cbrt(m) decreases monotonically. */
    y = (m + 2.0) / 3.0;
    for (i = 0; i < 7; i++) y = (2.0 * y + m / (y * y)) / 3.0;
    /* One exact-residual correction: y + (m - y^3) / (3 y^2). */
    seed_two_prod(y, y, &a2, &b2);
    seed_two_prod(a2, y, &c3, &d3);
    d3 = d3 + b2 * y;
    r = seed_finish(y, ((m - c3) - d3) / (3.0 * a2), q + k);
    return (bits & SEED_SIGN) ? -r : r;
}

double hypot(double x, double y)
{
    unsigned long ax = seed_b(x) & SEED_ABS;
    unsigned long ay = seed_b(y) & SEED_ABS;
    unsigned long t;
    double a;
    double b;
    double p1;
    double e1;
    double p2;
    double e2;
    double h;
    double l;
    int ea;
    if (ax == SEED_INF || ay == SEED_INF) return seed_infinity(0);
    if (ax > SEED_INF || ay > SEED_INF) return x + y;
    if (ax < ay) {
        t = ax;
        ax = ay;
        ay = t;
    }
    a = seed_d(ax);
    b = seed_d(ay);
    if (ay == 0) return a;
    ea = seed_exponent(a);
    if (ea - seed_exponent(b) > 54) return a;
    a = seed_scale(a, -ea);
    b = seed_scale(b, -ea);
    seed_two_prod(a, a, &p1, &e1);
    seed_two_prod(b, b, &p2, &e2);
    seed_dd_add(p1, e1, p2, e2, &h, &l);
    seed_sqrt_dd(h, l, &h, &l);
    return seed_finish(h, l, ea);
}

/* ---- hyperbolic functions ---- */

double cosh(double x)
{
    unsigned long ax = seed_b(x) & SEED_ABS;
    double a = seed_d(ax);
    double h;
    double l;
    double ih;
    double il;
    int k;
    if (ax > SEED_INF) return x + x;
    if (ax == SEED_INF) return a;
    if (ax < 0x3e40000000000000UL) return 1.0;
    if (a > 760.0) {
        errno = ERANGE;
        return seed_infinity(0);
    }
    seed_exp_dd(a, &h, &l, &k);
    if (a >= 22.0) return seed_finish(h, l, k - 1);
    h = seed_scale(h, k);
    l = seed_scale(l, k);
    seed_dd_div(1.0, 0.0, h, l, &ih, &il);
    seed_dd_add(h, l, ih, il, &h, &l);
    return 0.5 * h + 0.5 * l;
}

double sinh(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    double a = seed_d(ax);
    double h;
    double l;
    double ih;
    double il;
    double r;
    int k;
    if (ax >= SEED_INF) return x + x;
    if (ax < 0x3e40000000000000UL) return x;
    if (a > 760.0) {
        errno = ERANGE;
        return seed_infinity((bits & SEED_SIGN) != 0);
    }
    if (a >= 22.0) {
        seed_exp_dd(a, &h, &l, &k);
        r = seed_finish(h, l, k - 1);
    } else if (a < 1.0) {
        /* (E + E/(E+1)) / 2 with E = expm1(a) avoids cancellation. */
        seed_expm1_dd(a, &h, &l);
        seed_dd_add(h, l, 1.0, 0.0, &ih, &il);
        seed_dd_div(h, l, ih, il, &ih, &il);
        seed_dd_add(h, l, ih, il, &h, &l);
        r = 0.5 * h + 0.5 * l;
    } else {
        seed_exp_dd(a, &h, &l, &k);
        h = seed_scale(h, k);
        l = seed_scale(l, k);
        seed_dd_div(1.0, 0.0, h, l, &ih, &il);
        seed_dd_add(h, l, -ih, -il, &h, &l);
        r = 0.5 * h + 0.5 * l;
    }
    return (bits & SEED_SIGN) ? -r : r;
}

double tanh(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    double a = seed_d(ax);
    double h;
    double l;
    double dh;
    double dl;
    double r;
    if (ax > SEED_INF) return x + x;
    if (ax < 0x3e40000000000000UL) return x;
    if (a >= 22.0) {
        r = 1.0;
    } else {
        /* tanh(a) = E / (E + 2) with E = expm1(2a) */
        seed_expm1_dd(2.0 * a, &h, &l);
        seed_dd_add(h, l, 2.0, 0.0, &dh, &dl);
        seed_dd_div(h, l, dh, dl, &h, &l);
        r = h + l;
    }
    return (bits & SEED_SIGN) ? -r : r;
}

/* ---- circular functions ---- */

/* Bits pos..pos+31 of the 352-bit little-endian product in 32-bit limbs. */
static unsigned long seed_limb_bits(const unsigned long *p, int pos)
{
    int word = pos >> 5;
    int shift = pos & 31;
    unsigned long value = p[word] >> shift;
    if (shift && word + 1 < 11) value |= p[word + 1] << (32 - shift);
    return value & 0xffffffffUL;
}

/* Payne-Hanek reduction for |x| >= 2^20: x*2/pi mod 4 from the integer
 * significand times nine 32-bit words of 2/pi chosen at the binary point. */
static int seed_reduce_large(double x, double *rh, double *rl)
{
    unsigned long bits = seed_b(x);
    unsigned long mantissa = (bits & SEED_FRAC) | SEED_HIDDEN;
    unsigned long m0 = mantissa & 0xffffffffUL;
    unsigned long m1 = mantissa >> 32;
    unsigned long a[9];
    unsigned long p[11];
    unsigned long f[6];
    unsigned long carry;
    unsigned long t;
    int e = (int)((bits >> 52) & 2047) - 1075;
    int first = e >= 34 ? (e - 34) / 32 + 1 : 0;
    int point;
    int quadrant;
    int negate = 0;
    int i;
    double h = 0.0;
    double l = 0.0;
    for (i = 0; i < 9; i++) a[i] = seed_two_over_pi[first + 8 - i];
    for (i = 0; i < 11; i++) p[i] = 0;
    carry = 0;
    for (i = 0; i < 9; i++) {
        t = a[i] * m0 + carry;
        p[i] = t & 0xffffffffUL;
        carry = t >> 32;
    }
    p[9] = carry;
    carry = 0;
    for (i = 0; i < 9; i++) {
        t = a[i] * m1 + p[i + 1] + carry;
        p[i + 1] = t & 0xffffffffUL;
        carry = t >> 32;
    }
    p[10] = carry;
    /* x*2/pi = P * 2^-point modulo 4, with 255 <= point <= 320. */
    point = 32 * (first + 9) - e;
    quadrant = (int)(seed_limb_bits(p, point) & 3);
    for (i = 0; i < 6; i++) f[i] = seed_limb_bits(p, point - 192 + 32 * i);
    if (f[5] & 0x80000000UL) {
        /* Fraction >= 1/2: take the next quadrant and the negative rest. */
        negate = 1;
        quadrant = (quadrant + 1) & 3;
        carry = 1;
        for (i = 0; i < 6; i++) {
            t = ((~f[i]) & 0xffffffffUL) + carry;
            f[i] = t & 0xffffffffUL;
            carry = t >> 32;
        }
    }
    for (i = 0; i < 6; i++)
        seed_dd_add(h, l, (double)(long)f[i] * seed_pow2(32 * i - 192), 0.0, &h, &l);
    seed_dd_mul(h, l, seed_d(SEED_PIO2_H), seed_d(SEED_PIO2_L), &h, &l);
    if (negate != ((bits & SEED_SIGN) != 0)) {
        h = -h;
        l = -l;
    }
    if (bits & SEED_SIGN) quadrant = (4 - quadrant) & 3;
    *rh = h;
    *rl = l;
    return quadrant;
}

/* r = x - n*pi/2 as rh + rl with |r| <= pi/4 (+tiny); returns n mod 4. */
static int seed_reduce(double x, double *rh, double *rl)
{
    double a = fabs(x);
    double dn;
    double r;
    double s1;
    double e1;
    double s2;
    double e2;
    long n;
    if (a <= 0.78539816339744828) {
        *rh = x;
        *rl = 0.0;
        return 0;
    }
    if (a >= 1048576.0) return seed_reduce_large(x, rh, rl);
    /* Cody-Waite with three 33-bit pieces of pi/2: n < 2^20 keeps each
     * product n*piece exact; the fourth piece carries the rest. */
    dn = x * 0.63661977236758134;
    n = (long)(dn < 0.0 ? dn - 0.5 : dn + 0.5);
    dn = (double)n;
    r = x - dn * seed_d(SEED_PIO2_CW1);
    seed_two_sum(r, -(dn * seed_d(SEED_PIO2_CW2)), &s1, &e1);
    seed_two_sum(s1, -(dn * seed_d(SEED_PIO2_CW3)), &s2, &e2);
    seed_two_sum(s2, (e1 + e2) - dn * seed_d(SEED_PIO2_CW4), rh, rl);
    return (int)(n & 3);
}

/* sin(r) for |r| <= pi/4 + tiny as a double-double (Taylor to r^21). */
static void seed_sin_dd(double rh, double rl, double *sh, double *sl)
{
    double uh;
    double ul;
    double u;
    double q;
    double ah;
    double al;
    seed_dd_mul(rh, rl, rh, rl, &uh, &ul);
    u = uh;
    q = -1.0 / 5040.0 + u * (1.0 / 362880.0 + u * (-1.0 / 39916800.0
        + u * (1.0 / 6227020800.0 + u * (-1.0 / 1307674368000.0
        + u * (1.0 / 355687428096000.0 + u * (-1.0 / 121645100408832000.0
        + u * (1.0 / 51090942171709440000.0)))))));
    seed_dd_mul(uh, ul, q, 0.0, &ah, &al);
    seed_dd_add(ah, al, seed_d(SEED_S5_H), seed_d(SEED_S5_L), &ah, &al);
    seed_dd_mul(ah, al, uh, ul, &ah, &al);
    seed_dd_add(ah, al, seed_d(SEED_S3_H), seed_d(SEED_S3_L), &ah, &al);
    seed_dd_mul(ah, al, uh, ul, &ah, &al);
    seed_dd_mul(ah, al, rh, rl, &ah, &al);
    seed_dd_add(rh, rl, ah, al, sh, sl);
}

/* cos(r) for |r| <= pi/4 + tiny as a double-double (Taylor to r^22). */
static void seed_cos_dd(double rh, double rl, double *ch, double *cl)
{
    double uh;
    double ul;
    double u;
    double q;
    double ah;
    double al;
    seed_dd_mul(rh, rl, rh, rl, &uh, &ul);
    u = uh;
    q = 1.0 / 40320.0 + u * (-1.0 / 3628800.0 + u * (1.0 / 479001600.0
        + u * (-1.0 / 87178291200.0 + u * (1.0 / 20922789888000.0
        + u * (-1.0 / 6402373705728000.0 + u * (1.0 / 2432902008176640000.0
        + u * (-1.0 / 1124000727777607680000.0)))))));
    seed_dd_mul(uh, ul, q, 0.0, &ah, &al);
    seed_dd_add(ah, al, seed_d(SEED_C6_H), seed_d(SEED_C6_L), &ah, &al);
    seed_dd_mul(ah, al, uh, ul, &ah, &al);
    seed_dd_add(ah, al, seed_d(SEED_C4_H), seed_d(SEED_C4_L), &ah, &al);
    seed_dd_mul(ah, al, uh, ul, &ah, &al);
    seed_dd_add(ah, al, -0.5, 0.0, &ah, &al);
    seed_dd_mul(ah, al, uh, ul, &ah, &al);
    seed_dd_add(1.0, 0.0, ah, al, ch, cl);
}

/* Shared front end: returns 1 and sets *r for NaN, infinity and tiny x. */
static int seed_trig_special(double x, unsigned long tiny, double small, double *r)
{
    unsigned long ax = seed_b(x) & SEED_ABS;
    if (ax > SEED_INF) {
        *r = x + x;
        return 1;
    }
    if (ax == SEED_INF) {
        *r = seed_invalid();
        return 1;
    }
    if (ax < tiny) {
        *r = small;
        return 1;
    }
    return 0;
}

double sin(double x)
{
    double h;
    double l;
    int n;
    if (seed_trig_special(x, 0x3e50000000000000UL, x, &h)) return h;
    n = seed_reduce(x, &h, &l);
    if (n & 1) seed_cos_dd(h, l, &h, &l);
    else seed_sin_dd(h, l, &h, &l);
    if (n & 2) return -h - l;
    return h + l;
}

double cos(double x)
{
    double h;
    double l;
    int n;
    if (seed_trig_special(x, 0x3e40000000000000UL, 1.0, &h)) return h;
    n = seed_reduce(x, &h, &l);
    if (n & 1) seed_sin_dd(h, l, &h, &l);
    else seed_cos_dd(h, l, &h, &l);
    if (n == 1 || n == 2) return -h - l;
    return h + l;
}

double tan(double x)
{
    double h;
    double l;
    double sh;
    double sl;
    double ch;
    double cl;
    int n;
    if (seed_trig_special(x, 0x3e40000000000000UL, x, &h)) return h;
    n = seed_reduce(x, &h, &l);
    seed_sin_dd(h, l, &sh, &sl);
    seed_cos_dd(h, l, &ch, &cl);
    if (n & 1) {
        seed_dd_div(ch, cl, sh, sl, &h, &l);
        return -h - l;
    }
    seed_dd_div(sh, sl, ch, cl, &h, &l);
    return h + l;
}

/* atan(y/x) in [0, pi/2] for double-doubles y >= 0, x > 0 (or y > 0).
 * t = min/max ratio, c = i/32 nearest t, d = (t-c)/(1+t*c), |d| <= 1/64:
 * atan(t) = atan(c) + atan(d), with atan(d) by its Taylor series. */
static void seed_atan_dd(double yh, double yl, double xh, double xl, double *rh, double *rl)
{
    int swap = 0;
    int i;
    double th;
    double tl;
    double c;
    double nh;
    double nl;
    double ph;
    double pl;
    double u;
    double q;
    if (yh > xh || (yh == xh && yl > xl)) {
        swap = 1;
        th = yh;
        yh = xh;
        xh = th;
        tl = yl;
        yl = xl;
        xl = tl;
    }
    seed_dd_div(yh, yl, xh, xl, &th, &tl);
    i = (int)(th * 32.0 + 0.5);
    if (i > 0) {
        c = i * 0.03125;
        seed_two_sum(th - c, tl, &nh, &nl);
        seed_two_prod(th, c, &ph, &pl);
        pl = pl + tl * c;
        seed_dd_add(ph, pl, 1.0, 0.0, &ph, &pl);
        seed_dd_div(nh, nl, ph, pl, &th, &tl);
    }
    u = th * th;
    q = u * (-1.0 / 3.0 + u * (1.0 / 5.0 + u * (-1.0 / 7.0 + u * (1.0 / 9.0
        + u * (-1.0 / 11.0 + u * (1.0 / 13.0))))));
    seed_fast_two_sum(th, tl + th * q, &th, &tl);
    if (i > 0)
        seed_dd_add(seed_d(seed_atan_table[2 * i]), seed_d(seed_atan_table[2 * i + 1]),
                    th, tl, &th, &tl);
    if (swap) seed_dd_add(seed_d(SEED_PIO2_H), seed_d(SEED_PIO2_L), -th, -tl, &th, &tl);
    *rh = th;
    *rl = tl;
}

double atan(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    double h;
    double l;
    double r;
    if (ax > SEED_INF) return x + x;
    if (ax < 0x3e40000000000000UL) return x;
    if (ax > 0x43b0000000000000UL) {
        r = seed_d(SEED_PIO2_H);
    } else {
        seed_atan_dd(seed_d(ax), 0.0, 1.0, 0.0, &h, &l);
        r = h + l;
    }
    return (bits & SEED_SIGN) ? -r : r;
}

double atan2(double y, double x)
{
    unsigned long bx = seed_b(x);
    unsigned long by = seed_b(y);
    unsigned long ax = bx & SEED_ABS;
    unsigned long ay = by & SEED_ABS;
    double h;
    double l;
    double r;
    int ex;
    int ey;
    if (ax > SEED_INF || ay > SEED_INF) return x + y;
    if (ay == 0) {
        if (!(bx & SEED_SIGN)) return y;
        r = seed_d(SEED_PI_H);
    } else if (ax == 0) {
        r = seed_d(SEED_PIO2_H);
    } else if (ax == SEED_INF) {
        if (ay == SEED_INF) r = (bx & SEED_SIGN) ? seed_d(SEED_THREEPIO4_H) : 0.5 * seed_d(SEED_PIO2_H);
        else r = (bx & SEED_SIGN) ? seed_d(SEED_PI_H) : 0.0;
    } else if (ay == SEED_INF) {
        r = seed_d(SEED_PIO2_H);
    } else {
        ex = seed_exponent(seed_d(ax));
        ey = seed_exponent(seed_d(ay));
        if (ey - ex > 60) {
            r = seed_d(SEED_PIO2_H);
        } else if (ex - ey > 60) {
            if (bx & SEED_SIGN) {
                r = seed_d(SEED_PI_H);
            } else {
                /* atan(t) rounds like t for t < 2^-59. */
                r = seed_d(ay) / seed_d(ax);
                if (r == 0.0) errno = ERANGE;
            }
        } else {
            seed_atan_dd(seed_scale(seed_d(ay), -ex), 0.0, seed_scale(seed_d(ax), -ex), 0.0, &h, &l);
            if (bx & SEED_SIGN) seed_dd_add(seed_d(SEED_PI_H), seed_d(SEED_PI_L), -h, -l, &h, &l);
            r = h + l;
        }
    }
    return (by & SEED_SIGN) ? -r : r;
}

/* sqrt(1 - a^2) = sqrt((1-a)(1+a)) as a double-double for 0 <= a < 1. */
static void seed_cosine_side(double a, double *rh, double *rl)
{
    double ah;
    double al;
    double bh;
    double bl;
    seed_two_sum(1.0, -a, &ah, &al);
    seed_two_sum(1.0, a, &bh, &bl);
    seed_dd_mul(ah, al, bh, bl, &ah, &al);
    seed_sqrt_dd(ah, al, rh, rl);
}

double asin(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    double h;
    double l;
    double r;
    if (ax > SEED_INF) return x + x;
    if (ax > SEED_ONE) return seed_invalid();
    if (ax < 0x3e50000000000000UL) return x;
    if (ax == SEED_ONE) {
        r = seed_d(SEED_PIO2_H);
    } else {
        seed_cosine_side(seed_d(ax), &h, &l);
        seed_atan_dd(seed_d(ax), 0.0, h, l, &h, &l);
        r = h + l;
    }
    return (bits & SEED_SIGN) ? -r : r;
}

double acos(double x)
{
    unsigned long bits = seed_b(x);
    unsigned long ax = bits & SEED_ABS;
    double h;
    double l;
    if (ax > SEED_INF) return x + x;
    if (ax > SEED_ONE) return seed_invalid();
    if (ax < 0x3c60000000000000UL) return seed_d(SEED_PIO2_H);
    if (ax == SEED_ONE) return (bits & SEED_SIGN) ? seed_d(SEED_PI_H) : 0.0;
    seed_cosine_side(seed_d(ax), &h, &l);
    seed_atan_dd(h, l, seed_d(ax), 0.0, &h, &l);
    if (bits & SEED_SIGN) seed_dd_add(seed_d(SEED_PI_H), seed_d(SEED_PI_L), -h, -l, &h, &l);
    return h + l;
}
