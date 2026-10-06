CC = ../../../seed-cc/seed-cc
AR = ../../../seed-cc/seed-ar
BIN = ../../bin
CFLAGS = -D_GNU_SOURCE -D__unused= -I.
OBJECTS = closure.o error.o lalr.o lr0.o main.o mkpar.o output.o reader.o skeleton.o symtab.o verbose.o warshall.o portable.o
all: $(BIN)/oyacc
$(BIN)/oyacc: $(OBJECTS)
	$(CC) -static -o $@ $(OBJECTS)
%.o: %.c config.h
	$(CC) $(CFLAGS) -c $< -o $@
