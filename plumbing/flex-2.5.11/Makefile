CC = ../../../seed-cc/seed-cc
AR = ../../../seed-cc/seed-ar
BIN = ../../bin
PREP = $(BIN)/lexer-prepare
LIBL = ../heirloom-devtools-070527/lex/libl.a
CFLAGS = -I.
OBJECTS = ccl.o dfa.o ecs.o gen.o main.o misc.o nfa.o parse.o scan-tmp.o skel.o sym.o tblcmp.o yylex.o options.o scanopt.o buf.o
FINAL = ccl.o dfa.o ecs.o gen.o main.o misc.o nfa.o parse.o scan.o skel.o sym.o tblcmp.o yylex.o options.o scanopt.o buf.o
all: $(BIN)/flex
parse.c: parse.y
	$(BIN)/oyacc -d parse.y
	$(BIN)/cp y.tab.c parse.c
	$(BIN)/cp y.tab.h parse.h
parse.h: parse.c
scan-ascii.l: scan.lex.l
	$(PREP) ascii scan.lex.l scan-ascii.l
heirloom-scan.c: scan-ascii.l parse.h
	$(BIN)/lex -Y../heirloom-devtools-070527/lex scan-ascii.l
	$(BIN)/cp lex.yy.c heirloom-scan.c
scan-tmp.c: heirloom-scan.c
	$(PREP) scanner heirloom-scan.c scan-tmp.c
flex-tmp: $(OBJECTS) $(LIBL)
	$(CC) -static -o $@ $(OBJECTS) $(LIBL)
scan.c: flex-tmp scan.l
	./flex-tmp scan.l
	$(BIN)/cp lex.yy.c scan.c
$(BIN)/flex: $(FINAL) $(LIBL)
	$(CC) -static -o $@ $(FINAL) $(LIBL)
%.o: %.c config.h parse.h
	$(CC) $(CFLAGS) -c $< -o $@
