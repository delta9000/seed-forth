# mkbuiltins emits the literal $PRODUCES basename in its working directory.
# Invoked with make -C builtins; no shell cd or redirection is needed.
.SUFFIXES:
%.c: %.def ../mkbuiltins
	../mkbuiltins $<
