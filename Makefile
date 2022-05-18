#
# Makefile for Ziggurat
#

SRCDIR = ./src
OBJDIR = ./obj
UNILIBDIR = ../unilib
APP = ZIGGURAT.PRG
CONFIGFILE = cx16-asm.cfg

FLAGS = -t cx16 --cpu 65c02 -g

#OBJECTS  = $(OBJDIR)/zpu.o
#OBJECTS += $(OBJDIR)/zpu_call.o
#OBJECTS += $(OBJDIR)/zpu_extended.o
#OBJECTS += $(OBJDIR)/zpu_math.o
#OBJECTS  = $(OBJDIR)/zpu_mem.o
#OBJECTS += $(OBJDIR)/zpu_object.o
#OBJECTS += $(OBJDIR)/zpu_parse.o
#OBJECTS += $(OBJDIR)/zpu_picture.o
#OBJECTS += $(OBJDIR)/zpu_print.o
#OBJECTS += $(OBJDIR)/zpu_saverestore.o
#OBJECTS += $(OBJDIR)/zpu_sound.o
#OBJECTS += $(OBJDIR)/zpu_stream.o
#OBJECTS += $(OBJDIR)/zpu_window.o
#OBJECTS += $(OBJDIR)/zscii_type.o
OBJECTS  = $(OBJDIR)/zifmgr.o
OBJECTS += $(OBJDIR)/zzmain.o

HEADERS = \
	$(SRCDIR)/ziggurat.inc \
	$(SRCDIR)/zpu.inc \
	$(SRCDIR)/zscii_type.inc \
	$(UNILIBDIR)/cbm_kernal.inc \
	$(UNILIBDIR)/cx16.inc \
	$(UNILIBDIR)/unilib.inc

all: $(APP)

$(APP): $(OBJECTS) $(UNILIBDIR)/libunilib.a
	cl65 $(FLAGS) --asm-include-dir . -C $(CONFIGFILE) -m ziggurat.map -Ln ziggurat.sym -o $(APP) $^

$(OBJDIR):
	mkdir -p $@

$(OBJDIR)/%.o: $(SRCDIR)/%.s $(HEADERS) | $(OBJDIR)
	ca65 $(FLAGS) -I. -I$(UNILIBDIR) -o $@ $<

.PHONY: all clean
clean:
	-rm -r $(OBJDIR)
	-rm $(APP) *.map *.sym
