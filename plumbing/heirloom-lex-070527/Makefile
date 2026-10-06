CC = ../../../../seed-cc/seed-cc
AR = ../../../../seed-cc/seed-ar
BIN = ../../../bin
CFLAGS = -Dunix=1 -I.
OBJECTS = main-unit.o sub1.o sub2.o sub3.o header.o wcio.o parser.o getopt.o lsearch.o
LIBOBJECTS = allprint.o libmain.o reject.o yyless.o yywrap.o
all: $(BIN)/lex libl.a
parser.c: parser.y
	$(BIN)/oyacc parser.y
	$(BIN)/cp y.tab.c parser.c
$(BIN)/lex: $(OBJECTS)
	$(CC) -static -o $@ $(OBJECTS)
libl.a: $(LIBOBJECTS)
	$(AR) rcs $@ $(LIBOBJECTS)
main-unit.o: main-unit.c main.c config.h
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@
