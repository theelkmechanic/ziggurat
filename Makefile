# Ziggurat Z-machine interpreter for Commander X16
# Build with UniLib ROM-based windowing library

TARGET    := cx16
PROGRAM   := ZIGGURAT.PRG
SRCDIR    := src
OBJDIR    := obj
CONFIG    := cx16-asm.cfg
UNILIBDIR := $(HOME)/dev/x16/unilib
EMUDIR    := $(HOME)/dev/x16/x16-emulator/build
ROMIMAGE  := rom_ziggurat.bin

# Toolchain flags
# NOTE: -I $(UNILIBDIR) is only used for files that need unilib.inc or thunks.
# It is NOT added globally because UniLib's cbm_kernal.inc/cx16.inc shadow the
# system copies and break KERNAL symbol resolution.
ASFLAGS       := --cpu 65c02
UNILIB_INC    := -I $(UNILIBDIR)
LDFLAGS       := --mapfile ziggurat.map -Ln ziggurat.sym

# Source files (explicit list — excludes windies_*.s)
ZPU_SOURCES := \
	zpu.s \
	zpu_call.s \
	zpu_extended.s \
	zpu_math.s \
	zpu_mem.s \
	zpu_object.s \
	zpu_parse.s \
	zpu_picture.s \
	zpu_print.s \
	zpu_saverestore.s \
	zpu_sound.s \
	zpu_stream.s \
	zpu_window.s

APP_SOURCES := \
	zzmain.s \
	zmwin.s \
	zifmgr.s \
	zscii_type.s

SOURCES := $(ZPU_SOURCES) $(APP_SOURCES)
OBJECTS := $(addprefix $(OBJDIR)/,$(SOURCES:.s=.o))

# UniLib thunks object (compiled from UniLib source tree)
THUNKS_SRC := $(UNILIBDIR)/unilib_thunks.s
THUNKS_OBJ := $(OBJDIR)/unilib_thunks.o

ALL_OBJECTS := $(OBJECTS) $(THUNKS_OBJ)

.PHONY: all clean run debug

all: $(PROGRAM)

$(OBJDIR):
	mkdir -p $@

# Compile Ziggurat source files (no UniLib include path — avoids shadowing system includes)
$(OBJDIR)/%.o: $(SRCDIR)/%.s | $(OBJDIR)
	ca65 -t $(TARGET) $(ASFLAGS) -o $@ $<

# Files that include unilib.inc need the UniLib include path
$(OBJDIR)/zmwin.o: $(SRCDIR)/zmwin.s | $(OBJDIR)
	ca65 -t $(TARGET) $(ASFLAGS) $(UNILIB_INC) -o $@ $<

$(OBJDIR)/zzmain.o: $(SRCDIR)/zzmain.s | $(OBJDIR)
	ca65 -t $(TARGET) $(ASFLAGS) $(UNILIB_INC) -o $@ $<

# Compile UniLib thunks
$(THUNKS_OBJ): $(THUNKS_SRC) | $(OBJDIR)
	ca65 -t $(TARGET) $(ASFLAGS) $(UNILIB_INC) -o $@ $<

# Link
$(PROGRAM): $(CONFIG) $(ALL_OBJECTS)
	cl65 -t $(TARGET) $(LDFLAGS) -C $(CONFIG) -o $@ $(ALL_OBJECTS)
	cp $(PROGRAM) run/$(PROGRAM)

# Common emulator flags
EMUFLAGS := -rom $(ROMIMAGE) -ram 2048 -zeroram -prg $(PROGRAM) -run

# Run in emulator (requires -ram 2048 for UniLib MEMTOP to return A=0 for 256 banks)
run: $(PROGRAM)
	cd run && $(EMUDIR)/x16emu $(EMUFLAGS)

# Run with GDB stub on port 2159 for remote debugging
debug: $(PROGRAM)
	cd run && $(EMUDIR)/x16emu $(EMUFLAGS) -gdb 2159

clean:
	rm -f $(ALL_OBJECTS)
	rm -f $(OBJDIR)/*.d
	rm -f $(PROGRAM) ziggurat.map ziggurat.sym
