/* Original seed-forth test grammar; distributed under the repository LICENSE. */
%{
#include <stdio.h>
int yylex(void);
void yyerror(const char *message);
static int result;
%}
%token NUM
%left '+' '-'
%left '*' '/'
%right NEG
%%
input: expr '\n' { result = $1; };
expr: NUM { $$ = $1; }
    | expr '+' expr { $$ = $1 + $3; }
    | expr '-' expr { $$ = $1 - $3; }
    | expr '*' expr { $$ = $1 * $3; }
    | expr '/' expr { $$ = $1 / $3; }
    | '-' expr %prec NEG { $$ = -$2; }
    | '(' expr ')' { $$ = $2; }
    ;
%%
int yylex(void)
{
    int character = getchar();
    int value = 0;
    while (character == ' ' || character == '\t') character = getchar();
    if (character >= '0' && character <= '9') {
        do {
            value = value * 10 + character - '0';
            character = getchar();
        } while (character >= '0' && character <= '9');
        if (character != EOF) ungetc(character, stdin);
        yylval = value;
        return NUM;
    }
    return character == EOF ? 0 : character;
}
void yyerror(const char *message)
{
    (void)message;
    fputs("parse error\n", stderr);
}
int main(void)
{
    if (yyparse()) return 2;
    printf("%d\n", result);
    return 0;
}
