TOOLCHAIN := $(DEVKITARM)
COMPARE ?= 0

ifeq (compare,$(MAKECMDGOALS))
  COMPARE := 1
endif

ifeq (keeptemps,$(MAKECMDGOALS))
  KEEP_TEMPS := 1
endif

# don't use dkP's base_tools anymore
# because the redefinition of $(CC) conflicts
# with when we want to use $(CC) to preprocess files
# thus, manually create the variables for the bin
# files, or use arm-none-eabi binaries on the system
# if dkP is not installed on this system

ifneq (,$(TOOLCHAIN))
ifneq ($(wildcard $(TOOLCHAIN)/bin),)
export PATH := $(TOOLCHAIN)/bin:$(PATH)
endif
endif

OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
WINDRES := $(PREFIX)windres
AS := $(PREFIX)as

LD := $(PREFIX)ld

# note: the makefile must be set up so MODERNCC is never called
# if MODERN=0
MODERNCC := $(PREFIX)gcc
PATH_MODERNCC := PATH=$(TOOLCHAIN)/bin:PATH $(MODERNCC)

ifeq ($(OS),Windows_NT)
EXE := .exe
else
EXE :=
endif

TITLE       := POKEMON EMER
GAME_CODE   := BPEE
MAKER_CODE  := 01
REVISION    := 0
MODERN      ?= 1
PORTABLE    ?= 0
IS64BIT     ?= 0
TARGET_PLATFORM ?= PLATFORM_SDL2
TARGET_OS       ?= NONE
TILE_RENDERER   ?= RENDERER_EASY_DRAW

ifeq (winwsl,$(MAKECMDGOALS))
  PORTABLE := 1
  TARGET_OS := WINDOWS
endif
ifeq (linux,$(MAKECMDGOALS))
  PORTABLE := 1
  TARGET_OS := LINUX
endif

ifeq ($(PORTABLE),1)
  ifeq ($(IS64BIT),1)
    ifeq ($(TARGET_OS),WINDOWS)
      SDL_DIR := ./SDL2/x86_64-w64-mingw32
    endif
    ASM_PSEUDO_OP_CONV := sed -e 's/\.4byte/\.int/g;s/\.2byte/\.short/g'
    FIX_UNDERSCORE := $(OBJCOPY)
    LEADING_UNDERSCORE_FLAG :=
  else
    SDL_DIR := ./SDL2/i686-w64-mingw32
    ASM_PSEUDO_OP_CONV := sed -e 's/\.4byte/\.int/g;s/\.2byte/\.short/g'
    #FIX_UNDERSCORE is required for 32 bit windows
    ifeq ($(TARGET_OS),WINDOWS)
      FIX_UNDERSCORE := $(OBJCOPY) --prefix-symbol _
      LEADING_UNDERSCORE_FLAG := -fleading-underscore
    else
      FIX_UNDERSCORE := $(OBJCOPY)
      LEADING_UNDERSCORE_FLAG :=
    endif
  endif

  PLATFORM_LFLAGS :=
  PLATFORM_INCLUDES :=
  PLATFORM_CFLAGS :=
  BUILD_FEXTENSION :=
  OS_CFLAGS :=
  OS_LFLAGS :=

  ifeq ($(TARGET_OS),WINDOWS)
    OS_CFLAGS :=
    OS_LFLAGS := -lwinmm -lxinput
    BUILD_FEXTENSION := .exe
  else
    OS_CFLAGS :=
    OS_LFLAGS := -no-pie
  endif

  #Windows only
  ifeq ($(TARGET_OS),WINDOWS)
    ifneq ($(NO_STD_LIB),1)
      PLATFORM_LFLAGS += -lmingw32
    endif
  endif

  ifeq ($(TARGET_PLATFORM), PLATFORM_SDL2)
    PLATFORM_LFLAGS += -lSDL2main -lSDL2 -lm
    ifeq ($(IS64BIT),0)
      PLATFORM_INCLUDES += -DSDL_DISABLE_IMMINTRIN_H -DSDL_DISABLE_MMINTRIN_H -DSDL_DISABLE_XMMINTRIN_H -DSDL_DISABLE_EMMINTRIN_H -DSDL_DISABLE_PMMINTRIN_H
    endif
  endif

  ifeq ($(TARGET_PLATFORM), PLATFORM_WIN32)
    ifeq ($(NO_STD_LIB),1)
      PLATFORM_LFLAGS += -Wl,-e__main -nostdlib
      CPPFLAGS += -D NO_STD_LIB_ENABLED
    endif
    PLATFORM_LFLAGS += -lkernel32 -luser32 -lgdi32
    PLATFORM_INCLUDES += -D SOUND_DISABLED
  endif
else
  ASM_PSEUDO_OP_CONV := cat
  FIX_UNDERSCORE := $(OBJCOPY)
endif

# use arm-none-eabi-cpp for macOS
# as macOS's default compiler is clang
# and clang's preprocessor will warn on \u
# when preprocessing asm files, expecting a unicode literal
# we can't unconditionally use arm-none-eabi-cpp
# as installations which install binutils-arm-none-eabi
# don't come with it
# CPP := $(PREFIX)cpp
BIT_WIDTH := 32
OTHER_BIT_WIDTH := 64
ASFLAGS64 :=
CPPFLAGS64 :=

# 64 bit specific stuff goes here
ifeq ($(IS64BIT),1)
  BIT_WIDTH := 64
  OTHER_BIT_WIDTH := 32
  ASFLAGS64 :=
  CPPFLAGS64 := -D VER_64BIT
endif

ifeq ($(PORTABLE),1)
  ifeq ($(TARGET_OS),WINDOWS)
    ifeq ($(IS64BIT),1)
      PREFIX := x86_64-w64-mingw32-
    else
      PREFIX := i686-w64-mingw32-
    endif # IS64BIT
  else # LINUX
    PREFIX :=
  endif # TARGET_OS
else
  PREFIX := arm-none-eabi-
endif

FILE_NAME := pokeemerald
BUILD_DIR := build

ROM_NAME := $(FILE_NAME).gba
ELF_NAME := $(ROM_NAME:.gba=.elf)
MAP_NAME := $(ROM_NAME:.gba=.map)
OBJ_DIR_NAME := $(BUILD_DIR)/emerald

MODERN_ROM_NAME := $(FILE_NAME)_modern.gba
MODERN_ELF_NAME := $(MODERN_ROM_NAME:.gba=.elf)
MODERN_MAP_NAME := $(MODERN_ROM_NAME:.gba=.map)
MODERN_OBJ_DIR_NAME := $(BUILD_DIR)/modern

PORTABLE_ROM_NAME := $(FILE_NAME)$(BIT_WIDTH)$(BUILD_FEXTENSION)
PORTABLE_OBJ_DIR_NAME := $(BUILD_DIR)/pc$(BIT_WIDTH)
PORTABLE_ROM_NAME_OTHER := $(FILE_NAME)$(OTHER_BIT_WIDTH)$(BUILD_FEXTENSION)
PORTABLE_OBJ_DIR_NAME_OTHER := $(BUILD_DIR)/pc$(OTHER_BIT_WIDTH)

SHELL := /bin/bash -o pipefail

ELF = $(ROM:.gba=.elf)
MAP = $(ROM:.gba=.map)
SYM = $(ROM:.gba=.sym)

C_SUBDIR = src
GFLIB_SUBDIR = gflib
ASM_SUBDIR = asm
DATA_SRC_SUBDIR = src/data
DATA_ASM_SUBDIR = data
SONG_SUBDIR = sound/songs
MID_SUBDIR = sound/songs/midi
SAMPLE_SUBDIR = sound/direct_sound_samples
CRY_SUBDIR = sound/direct_sound_samples/cries

C_BUILDDIR = $(OBJ_DIR)/$(C_SUBDIR)
GFLIB_BUILDDIR = $(OBJ_DIR)/$(GFLIB_SUBDIR)
ASM_BUILDDIR = $(OBJ_DIR)/$(ASM_SUBDIR)
DATA_ASM_BUILDDIR = $(OBJ_DIR)/$(DATA_ASM_SUBDIR)
SONG_BUILDDIR = $(OBJ_DIR)/$(SONG_SUBDIR)
MID_BUILDDIR = $(OBJ_DIR)/$(MID_SUBDIR)

ifeq ($(PORTABLE),1)
  ASFLAGS := --$(BIT_WIDTH) $(ASFLAGS64) --defsym VER_64BIT=$(IS64BIT) --defsym MODERN=$(MODERN) --defsym PORTABLE=1 --defsym UBFIX=1
else
  ASFLAGS := -mcpu=arm7tdmi --defsym MODERN=$(MODERN)
endif

ifeq ($(MODERN),0)
CC1             := tools/agbcc/bin/agbcc$(EXE)
override CFLAGS += -mthumb-interwork -Wimplicit -Wparentheses -Werror -O2 -fhex-asm -g
ROM := $(ROM_NAME)
OBJ_DIR := $(OBJ_DIR_NAME)
LIBPATH := -L ../../tools/agbcc/lib
LIB := $(LIBPATH) -lgcc -lc -L../../libagbsyscall -lagbsyscall
else ifeq ($(PORTABLE),1)
ROM := $(PORTABLE_ROM_NAME)
OBJ_DIR := $(PORTABLE_OBJ_DIR_NAME)
CPPFLAGS += -std=gnu23 -D NONMATCHING -D PORTABLE -D MODERN -D $(TARGET_PLATFORM) -D $(TILE_RENDERER) -D UBFIX $(CPPFLAGS64) $(PLATFORM_INCLUDES) -I$(SDL_DIR)/include -L$(SDL_DIR)/lib
MODERNCC := $(PREFIX)gcc
PATH_MODERNCC := PATH="$(PATH)" $(MODERNCC)
CPP := $(PREFIX)cpp -m$(BIT_WIDTH)
CC1 	:= $(shell $(PREFIX)gcc --print-prog-name=cc1) -quiet
CC1PLUS = $(shell $(PATH_MODERNCC) --print-prog-name=cc1plus) -quiet
override CFLAGS += $(OS_CFLAGS) $(PLATFORM_CFLAGS) -Werror=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-trigraphs -Wimplicit -Wparentheses -Wunused -m$(BIT_WIDTH) -std=gnu23 $(LEADING_UNDERSCORE_FLAG) -fno-dce -fno-builtin -Wno-unused-function -DPORTABLE -DNONMATCHING -D UBFIX -DMODERN=1 -D $(TARGET_PLATFORM) -D $(TILE_RENDERER) -g
LIB := $(LIBPATH) -lgcc -lc
else
CC1              = $(shell $(PATH_MODERNCC) --print-prog-name=cc1) -quiet
CC1PLUS 		 = $(shell $(PATH_MODERNCC) --print-prog-name=cc1plus) -quiet
override CFLAGS += -Wall -Wextra -Werror -Wno-int-in-bool-context -Wno-missing-braces -Wno-unused-parameter -Wno-switch -Wno-unused-local-typedefs -Wno-missing-field-initializers -Wno-ignored-qualifiers -Wno-sign-compare -mthumb -mthumb-interwork -O2 -mabi=apcs-gnu -mtune=arm7tdmi -march=armv4t -fshort-enums -g
ROM := $(MODERN_ROM_NAME)
OBJ_DIR := $(MODERN_OBJ_DIR_NAME)
LIBPATH := -L "$(dir $(shell $(PATH_MODERNCC) -mthumb -print-file-name=libgcc.a))" -L "$(dir $(shell $(PATH_MODERNCC) -mthumb -print-file-name=libnosys.a))" -L "$(dir $(shell $(PATH_MODERNCC) -mthumb -print-file-name=libc.a))"
LIB := $(LIBPATH) -lc -lnosys -lgcc -L../../libagbsyscall -lagbsyscall
endif

# PUBLIC=1 builds the public release, without debug (see PUBLIC_BUILD in include/global.h).
PUBLIC ?= 0
ifeq ($(PUBLIC),1)
ROM := $(ROM:.gba=_public.gba)
OBJ_DIR := $(OBJ_DIR)_public
endif

ifeq ($(PORTABLE),1)
CPPCOMPILEFLAGS := $(OS_CFLAGS) $(PLATFORM_CFLAGS) -Werror=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-trigraphs -Wimplicit -Wparentheses -Wunused -m$(BIT_WIDTH) -std=gnu++23 $(LEADING_UNDERSCORE_FLAG) -fno-dce -fno-builtin -Wno-unused-function -DPORTABLE -DNONMATCHING -DUBFIX -DMODERN=1
else
CPPCOMPILEFLAGS := -Wall -Wextra -Werror -fno-exceptions -Wno-sign-compare -Wno-switch -Wno-missing-field-initializers -std=gnu++23
endif

override CFLAGS += -fno-toplevel-reorder -Wno-unused-function -Wno-pointer-sign -Wno-unused-label -std=gnu23

CPPFLAGS += -iquote include -iquote $(GFLIB_SUBDIR) -Wno-trigraphs
ifneq ($(MODERN),1)
CPPFLAGS += -I tools/agbcc/include -I tools/agbcc -nostdinc -undef
endif
ifeq ($(PUBLIC),1)
CPPFLAGS += -DPUBLIC_BUILD
endif

LDFLAGS = -Map ../../$(MAP) --print-memory-usage 
# LDFLAGS = -Map ../../$(MAP) --no-warn-rwx-segments # Makes the game unable to build both on modern and normal so I removed the --no-warn-rwx-segments part

SHA1 := $(shell { command -v sha1sum || command -v shasum; } 2>/dev/null) -c
GFX := tools/gbagfx/gbagfx$(EXE)
AIF := tools/aif2pcm/aif2pcm$(EXE)
MID := tools/mid2agb/mid2agb$(EXE)
SCANINC := tools/scaninc/scaninc$(EXE)
PREPROC := tools/preproc/preproc$(EXE)
RAMSCRGEN := tools/ramscrgen/ramscrgen$(EXE)
FIX := tools/gbafix/gbafix$(EXE)
MAPJSON := tools/mapjson/mapjson$(EXE)
JSONPROC := tools/jsonproc/jsonproc$(EXE)
SCRIPT := tools/poryscript/poryscript$(EXE)

PERL := perl

TOOLDIRS := $(filter-out tools/agbcc tools/binutils tools/poryscript,$(wildcard tools/*))
TOOLBASE = $(TOOLDIRS:tools/%=%)
TOOLS = $(foreach tool,$(TOOLBASE),tools/$(tool)/$(tool)$(EXE))

MAKEFLAGS += --no-print-directory

# Clear the default suffixes
.SUFFIXES:
# Don't delete intermediate files
.SECONDARY:
# Delete files that weren't built properly
.DELETE_ON_ERROR:

# Secondary expansion is required for dependency variables in object rules.
.SECONDEXPANSION:

.PHONY: all rom clean compare winwsl linux tidy tools mostlyclean clean-tools $(TOOLDIRS) libagbsyscall modern tidymodern tidynonmodern

infoshell = $(foreach line, $(shell $1 | sed "s/ /__SPACE__/g"), $(info $(subst __SPACE__, ,$(line))))

# Build tools when building the rom
# Disable dependency scanning for clean/tidy/tools
# Use a separate minimal makefile for speed
# Since we don't need to reload most of this makefile
ifeq (,$(filter-out all rom compare modern winwsl linux libagbsyscall syms,$(MAKECMDGOALS)))
$(call infoshell, $(MAKE) -f make_tools.mk)
else
NODEP ?= 1
endif

# check if we need to scan dependencies based on the rule
ifeq (,$(MAKECMDGOALS))
  SCAN_DEPS ?= 1
else
  # clean, tidy, tools, mostlyclean, clean-tools, $(TOOLDIRS), tidymodern, tidynonmodern don't even build the ROM
  # berry_fix and libagbsyscall do their own thing
  ifeq (,$(filter-out clean tidy tools mostlyclean clean-tools $(TOOLDIRS) tidymodern tidynonmodern libagbsyscall,$(MAKECMDGOALS)))
    SCAN_DEPS ?= 0
  else
    SCAN_DEPS ?= 1
  endif
endif

ifeq ($(SCAN_DEPS),1)
C_SRCS_IN := $(wildcard $(C_SUBDIR)/*.c $(C_SUBDIR)/*/*.c $(C_SUBDIR)/*/*/*.c)
CPP_SRCS := $(wildcard $(C_SUBDIR)/*.cc $(C_SUBDIR)/*/*.cc $(C_SUBDIR)/*/*/*.cc)
C_SRCS := $(foreach src,$(C_SRCS_IN),$(if $(findstring .inc.c,$(src)),,$(src)))
C_OBJS := $(patsubst $(C_SUBDIR)/%.c,$(C_BUILDDIR)/%.o,$(C_SRCS))
CPP_OBJS := $(patsubst $(C_SUBDIR)/%.cc,$(C_BUILDDIR)/%.o,$(CPP_SRCS))

GFLIB_SRCS := $(wildcard $(GFLIB_SUBDIR)/*.c)
GFLIB_OBJS := $(patsubst $(GFLIB_SUBDIR)/%.c,$(GFLIB_BUILDDIR)/%.o,$(GFLIB_SRCS))

C_ASM_SRCS += $(wildcard $(C_SUBDIR)/*.s $(C_SUBDIR)/*/*.s $(C_SUBDIR)/*/*/*.s)
C_ASM_OBJS := $(patsubst $(C_SUBDIR)/%.s,$(C_BUILDDIR)/%.o,$(C_ASM_SRCS))

ASM_SRCS := $(wildcard $(ASM_SUBDIR)/*.s)
ASM_OBJS := $(patsubst $(ASM_SUBDIR)/%.s,$(ASM_BUILDDIR)/%.o,$(ASM_SRCS))

# get all the data/*.s files EXCEPT the ones with specific rules
REGULAR_DATA_ASM_SRCS := $(filter-out $(DATA_ASM_SUBDIR)/maps.s $(DATA_ASM_SUBDIR)/map_events.s, $(wildcard $(DATA_ASM_SUBDIR)/*.s))

DATA_ASM_SRCS := $(wildcard $(DATA_ASM_SUBDIR)/*.s)
DATA_ASM_OBJS := $(patsubst $(DATA_ASM_SUBDIR)/%.s,$(DATA_ASM_BUILDDIR)/%.o,$(DATA_ASM_SRCS))

SONG_SRCS := $(wildcard $(SONG_SUBDIR)/*.s)
SONG_OBJS := $(patsubst $(SONG_SUBDIR)/%.s,$(SONG_BUILDDIR)/%.o,$(SONG_SRCS))

MID_SRCS := $(wildcard $(MID_SUBDIR)/*.mid)
MID_OBJS := $(patsubst $(MID_SUBDIR)/%.mid,$(MID_BUILDDIR)/%.o,$(MID_SRCS))

ifeq ($(PORTABLE),1)
  OBJS     := $(C_OBJS) $(CPP_OBJS) $(GFLIB_OBJS) $(ASM_OBJS) $(DATA_ASM_OBJS) $(SONG_OBJS) $(MID_OBJS)
else
  OBJS     := $(C_OBJS) $(CPP_OBJS) $(GFLIB_OBJS) $(C_ASM_OBJS) $(ASM_OBJS) $(DATA_ASM_OBJS) $(SONG_OBJS) $(MID_OBJS)
endif

ifeq ($(TARGET_OS),WINDOWS)
  OBJS += $(OBJ_DIR)/res.o
endif

OBJS_REL := $(patsubst $(OBJ_DIR)/%,%,$(OBJS))

SUBDIRS  := $(sort $(dir $(OBJS)))
$(shell mkdir -p $(SUBDIRS))
endif

AUTO_GEN_TARGETS :=

all: rom

tools: tools/poryscript/poryscript $(TOOLDIRS)

syms: $(SYM)

$(TOOLDIRS):
	@$(MAKE) -C $@

rom: $(ROM)
ifeq ($(COMPARE),1)
	@$(SHA1) rom.sha1
endif

# For contributors to make sure a change didn't affect the contents of the ROM.
compare: all

keeptemps: all

clean: mostlyclean clean-tools

clean-tools:
	@$(foreach tooldir,$(TOOLDIRS),$(MAKE) clean -C $(tooldir);)

clean-audio: tidynonmodern tidymodern
	rm -f $(SAMPLE_SUBDIR)/*.bin
	rm -f $(CRY_SUBDIR)/*.bin
	rm -f $(MID_SUBDIR)/*.s

mostlyclean: tidynonmodern tidymodern
	rm -f $(SAMPLE_SUBDIR)/*.bin
	rm -f $(CRY_SUBDIR)/*.bin
	rm -f $(MID_SUBDIR)/*.s
	find . \( -iname '*.1bpp' -o -iname '*.4bpp' -o -iname '*.8bpp' -o -iname '*.gbapal' -o -iname '*.lz' -o -iname '*.rl' -o -iname '*.latfont' -o -iname '*.hwjpnfont' -o -iname '*.fwjpnfont' \) -exec rm {} +
	rm -f $(DATA_ASM_SUBDIR)/layouts/layouts.inc $(DATA_ASM_SUBDIR)/layouts/layouts_table.inc
	rm -f $(DATA_ASM_SUBDIR)/maps/connections.inc $(DATA_ASM_SUBDIR)/maps/events.inc $(DATA_ASM_SUBDIR)/maps/groups.inc $(DATA_ASM_SUBDIR)/maps/headers.inc
	find $(DATA_ASM_SUBDIR)/maps \( -iname 'connections.inc' -o -iname 'events.inc' -o -iname 'header.inc' \) -exec rm {} +
	rm -f $(AUTO_GEN_TARGETS)
	@$(MAKE) clean -C libagbsyscall
	rm -f $(patsubst %.pory,%.inc,$(shell find data/ -type f -name '*.pory'))

tidy: tidynonmodern tidymodern tidyportable

tidynonmodern:
	rm -f $(ROM_NAME) $(ELF_NAME) $(MAP_NAME)
	rm -rf $(OBJ_DIR_NAME)

tidymodern:
	rm -f $(MODERN_ROM_NAME) $(MODERN_ELF_NAME) $(MODERN_MAP_NAME)
	rm -f $(MODERN_ROM_NAME:.gba=_public.gba) $(MODERN_ELF_NAME:.elf=_public.elf) $(MODERN_MAP_NAME:.map=_public.map)
	rm -rf $(MODERN_OBJ_DIR_NAME) $(MODERN_OBJ_DIR_NAME)_public

tidyportable:
	rm -f $(PORTABLE_ROM_NAME)
	rm -f $(PORTABLE_ROM_NAME).exe
	rm -rf $(PORTABLE_OBJ_DIR_NAME)
	rm -f $(PORTABLE_ROM_NAME_OTHER)
	rm -f $(PORTABLE_ROM_NAME_OTHER).exe
	rm -rf $(PORTABLE_OBJ_DIR_NAME_OTHER)

clean-platform:
	rm -f $(PORTABLE_ROM_NAME)
	rm -rf $(PORTABLE_OBJ_DIR_NAME)/src/platform

tools/poryscript/poryscript:
	mkdir -p tools/poryscript
	wget -O tools/poryscript/poryscript.zip "https://github.com/huderlem/poryscript/releases/download/3.6.1/poryscript-linux.zip" -q
	unzip -qo tools/poryscript/poryscript.zip -d tools/
	mv tools/poryscript-linux/* tools/poryscript -f
	rm tools/poryscript-linux -rf
	
ifneq ($(MODERN),0)
$(C_BUILDDIR)/berry_crush.o: override CFLAGS += -Wno-address-of-packed-member
endif

include graphics_file_rules.mk
include map_data_rules.mk
include spritesheet_rules.mk
include json_data_rules.mk
include songs.mk

%.s: ;
%.png: ;
%.pal: ;
%.aif: ;
%.pory: ;

%.1bpp: %.png  ; $(GFX) $< $@
%.4bpp: %.png  ; $(GFX) $< $@
%.8bpp: %.png  ; $(GFX) $< $@
%.gbapal: %.pal ; $(GFX) $< $@
%.gbapal: %.png ; $(GFX) $< $@
%.lz: % ; $(GFX) $< $@
%.rl: % ; $(GFX) $< $@
# gbagfx runs ~26k times in a fresh build. With /bin/sh, make runs these simple commands
# directly instead of starting bash for each one.
%.1bpp %.4bpp %.8bpp %.gbapal %.lz %.rl: SHELL := /bin/sh

$(CRY_SUBDIR)/uncomp_%.bin: $(CRY_SUBDIR)/uncomp_%.aif ; $(AIF) $< $@
$(CRY_SUBDIR)/%.bin: $(CRY_SUBDIR)/%.aif ; $(AIF) $< $@ --compress
sound/%.bin: sound/%.aif ; $(AIF) $< $@
data/maps/%.inc: data/maps/%.pory tools/poryscript/font_config.json tools/poryscript/command_config.json tools/poryscript/poryscript; $(SCRIPT) -i $< -o $@ -fc tools/poryscript/font_config.json -cc tools/poryscript/command_config.json


ifeq ($(MODERN),0)
$(C_BUILDDIR)/libc.o: CC1 := tools/agbcc/bin/old_agbcc$(EXE)
$(C_BUILDDIR)/libc.o: CFLAGS := -O2

$(C_BUILDDIR)/siirtc.o: CFLAGS := -mthumb-interwork

$(C_BUILDDIR)/agb_flash.o: CFLAGS := -O -mthumb-interwork
$(C_BUILDDIR)/agb_flash_1m.o: CFLAGS := -O -mthumb-interwork
$(C_BUILDDIR)/agb_flash_mx.o: CFLAGS := -O -mthumb-interwork

$(C_BUILDDIR)/m4a.o: CC1 := tools/agbcc/bin/old_agbcc$(EXE)

$(C_BUILDDIR)/record_mixing.o: CFLAGS += -ffreestanding
$(C_BUILDDIR)/librfu_intr.o: CC1 := tools/agbcc/bin/agbcc_arm$(EXE)
$(C_BUILDDIR)/librfu_intr.o: CFLAGS := -O2 -mthumb-interwork -quiet
else ifneq ($(PORTABLE),1)
$(C_BUILDDIR)/librfu_intr.o: CFLAGS := -mthumb-interwork -O2 -mabi=apcs-gnu -mtune=arm7tdmi -march=armv4t -fno-toplevel-reorder -Wno-pointer-to-int-cast
endif

ifeq ($(DINFO),1)
override CFLAGS += -g
endif

ifeq ($(PORTABLE),1)
  ifeq ($(DINFO),1)
    override CFLAGS += -O0
  else
    override CFLAGS += -O3
  endif
endif

# The dep rules have to be explicit or else missing files won't be reported.
# As a side effect, they're evaluated immediately instead of when the rule is invoked.
# It doesn't look like $(shell) can be deferred so there might not be a better way.

ifeq ($(SCAN_DEPS),1)
ifeq ($(NODEP),1)
$(C_BUILDDIR)/%.o: $(C_SUBDIR)/%.c
ifeq (,$(KEEP_TEMPS))
	@echo "$(CC1) <flags> -o $@ $<"
	@$(CPP) $(CPPFLAGS) $< | $(PREPROC) $< charmap.txt -i | $(CC1) $(CFLAGS) -o - - | cat - <(echo -e ".text\n\t.align\t2, 0") | $(AS) $(ASFLAGS) -o $@ -
else
	@$(CPP) $(CPPFLAGS) $< -o $(C_BUILDDIR)/$*.i
	@$(PREPROC) $(C_BUILDDIR)/$*.i charmap.txt | $(CC1) $(CFLAGS) -o $(C_BUILDDIR)/$*.s
	@echo -e ".text\n\t.align\t2, 0\n" >> $(C_BUILDDIR)/$*.s
	$(AS) $(ASFLAGS) -o $@ $(C_BUILDDIR)/$*.s
endif
else
define C_DEP
$1: $2 $$(shell $(SCANINC) -I include -I tools/agbcc/include -I gflib $2)
ifeq (,$$(KEEP_TEMPS))
	@echo "$$(CC1) <flags> -o $$@ $$<"
	@$$(CPP) $$(CPPFLAGS) $$< | $$(PREPROC) $$< charmap.txt -i | $$(CC1) $$(CFLAGS) -o - - | cat - <(echo -e ".text\n\t.align\t2, 0") | $$(AS) $$(ASFLAGS) -o $$@ -
else
	@$$(CPP) $$(CPPFLAGS) $$< -o $$(C_BUILDDIR)/$3.i
	@$$(PREPROC) $$(C_BUILDDIR)/$3.i charmap.txt | $$(CC1) $$(CFLAGS) -o $$(C_BUILDDIR)/$3.s
	@echo -e ".text\n\t.align\t2, 0\n" >> $$(C_BUILDDIR)/$3.s
	$$(AS) $$(ASFLAGS) -o $$@ $$(C_BUILDDIR)/$3.s
endif
endef
define CPP_DEP
$1: $2 $$(shell $(SCANINC) -I include -I tools/agbcc/include -I gflib $2)
ifeq (,$$(KEEP_TEMPS))
	@echo "$$(CC1PLUS) <flags> -o $$@ $$<"
	@$$(CPP) $$(CPPFLAGS) $$< | $$(PREPROC) $$< charmap.txt -i | $$(CC1PLUS) $$(CPPCOMPILEFLAGS) -o - - | cat - <(echo -e ".text\n\t.align\t2, 0") | $$(AS) $$(ASFLAGS) -o $$@ -
else
	@$$(CPP) $$(CPPFLAGS) $$< -o $$(C_BUILDDIR)/$3.i
	@$$(PREPROC) $$(C_BUILDDIR)/$3.i charmap.txt | $$(CC1PLUS) $$(CPPCOMPILEFLAGS) -o $$(C_BUILDDIR)/$3.s
	@echo -e ".text\n\t.align\t2, 0\n" >> $$(C_BUILDDIR)/$3.s
	$$(AS) $$(ASFLAGS) -o $$@ $$(C_BUILDDIR)/$3.s
endif
endef
$(foreach src, $(C_SRCS), $(eval $(call C_DEP,$(patsubst $(C_SUBDIR)/%.c,$(C_BUILDDIR)/%.o,$(src)),$(src),$(patsubst $(C_SUBDIR)/%.c,%,$(src)))))
$(foreach src, $(CPP_SRCS), $(eval $(call CPP_DEP,$(patsubst $(C_SUBDIR)/%.cc,$(C_BUILDDIR)/%.o,$(src)),$(src),$(patsubst $(C_SUBDIR)/%.cc,%,$(src)))))
endif

ifeq ($(NODEP),1)
$(GFLIB_BUILDDIR)/%.o: $(GFLIB_SUBDIR)/%.c $$(c_dep)
ifeq (,$(KEEP_TEMPS))
	@echo "$(CC1) <flags> -o $@ $<"
	@$(CPP) $(CPPFLAGS) $< | $(PREPROC) $< charmap.txt -i | $(CC1) $(CFLAGS) -o - - | cat - <(echo -e ".text\n\t.align\t2, 0") | $(AS) $(ASFLAGS) -o $@ -
else
	@$(CPP) $(CPPFLAGS) $< -o $(GFLIB_BUILDDIR)/$*.i
	@$(PREPROC) $(GFLIB_BUILDDIR)/$*.i charmap.txt | $(CC1) $(CFLAGS) -o $(GFLIB_BUILDDIR)/$*.s
	@echo -e ".text\n\t.align\t2, 0\n" >> $(GFLIB_BUILDDIR)/$*.s
	$(AS) $(ASFLAGS) -o $@ $(GFLIB_BUILDDIR)/$*.s
endif
else
define GFLIB_DEP
$1: $2 $$(shell $(SCANINC) -I include -I tools/agbcc/include -I gflib $2)
ifeq (,$$(KEEP_TEMPS))
	@echo "$$(CC1) <flags> -o $$@ $$<"
	@$$(CPP) $$(CPPFLAGS) $$< | $$(PREPROC) $$< charmap.txt -i | $$(CC1) $$(CFLAGS) -o - - | cat - <(echo -e ".text\n\t.align\t2, 0") | $$(AS) $$(ASFLAGS) -o $$@ -
else
	@$$(CPP) $$(CPPFLAGS) $$< -o $$(GFLIB_BUILDDIR)/$3.i
	@$$(PREPROC) $$(GFLIB_BUILDDIR)/$3.i charmap.txt | $$(CC1) $$(CFLAGS) -o $$(GFLIB_BUILDDIR)/$3.s
	@echo -e ".text\n\t.align\t2, 0\n" >> $$(GFLIB_BUILDDIR)/$3.s
	$$(AS) $$(ASFLAGS) -o $$@ $$(GFLIB_BUILDDIR)/$3.s
endif
endef
$(foreach src, $(GFLIB_SRCS), $(eval $(call GFLIB_DEP,$(patsubst $(GFLIB_SUBDIR)/%.c,$(GFLIB_BUILDDIR)/%.o, $(src)),$(src),$(patsubst $(GFLIB_SUBDIR)/%.c,%, $(src)))))
endif

ifeq ($(NODEP),1)
$(C_BUILDDIR)/%.o: $(C_SUBDIR)/%.s
	$(PREPROC) $< charmap.txt | $(CPP) -I include - | $(AS) $(ASFLAGS) -o $@
else
define SRC_ASM_DATA_DEP
$1: $2 $$(shell $(SCANINC) -I include -I "" $2)
	$$(PREPROC) $$< charmap.txt | $$(CPP) -D __assembly__ -I include - | $$(AS) $$(ASFLAGS) -o $$@
endef
$(foreach src, $(C_ASM_SRCS), $(eval $(call SRC_ASM_DATA_DEP,$(patsubst $(C_SUBDIR)/%.s,$(C_BUILDDIR)/%.o, $(src)),$(src))))
endif

ifeq ($(NODEP),1)
$(ASM_BUILDDIR)/%.o: $(ASM_SUBDIR)/%.s
	$(AS) $(ASFLAGS) -o $@ $<
	$(FIX_UNDERSCORE) $@
else
define ASM_DEP
$1: $2 $$(shell $(SCANINC) -I include -I "" $2)
	$$(AS) $$(ASFLAGS) -o $$@ $$<
endef
$(foreach src, $(ASM_SRCS), $(eval $(call ASM_DEP,$(patsubst $(ASM_SUBDIR)/%.s,$(ASM_BUILDDIR)/%.o, $(src)),$(src))))
endif

ifeq ($(NODEP),1)
$(DATA_ASM_BUILDDIR)/%.o: $(DATA_ASM_SUBDIR)/%.s
	$(PREPROC) $< charmap.txt | $(CPP) -D __assembly__ -I include - | $(ASM_PSEUDO_OP_CONV) | $(AS) $(ASFLAGS) -o $@
	$(FIX_UNDERSCORE) $@
else
$(foreach src, $(REGULAR_DATA_ASM_SRCS), $(eval $(call SRC_ASM_DATA_DEP,$(patsubst $(DATA_ASM_SUBDIR)/%.s,$(DATA_ASM_BUILDDIR)/%.o, $(src)),$(src))))
endif
endif

$(SONG_BUILDDIR)/%.o: $(SONG_SUBDIR)/%.s
	$(AS) $(ASFLAGS) -I sound -o $@ $<

$(OBJ_DIR)/sym_bss.ld: sym_bss.txt
	$(RAMSCRGEN) .bss $< ENGLISH > $@

$(OBJ_DIR)/sym_common.ld: sym_common.txt $(C_OBJS) $(CPP_OBJS) $(wildcard common_syms/*.txt)
	$(RAMSCRGEN) COMMON $< ENGLISH -c $(C_BUILDDIR),common_syms > $@

$(OBJ_DIR)/sym_ewram.ld: sym_ewram.txt
	$(RAMSCRGEN) ewram_data $< ENGLISH > $@

$(OBJ_DIR)/res.o: $(C_SUBDIR)/platform/win32res/res.rc $(C_SUBDIR)/platform/win32res/icon.ico
	$(WINDRES) $< -o $@

ifeq ($(MODERN),0)
LD_SCRIPT := ld_script.txt
LD_SCRIPT_DEPS := $(OBJ_DIR)/sym_bss.ld $(OBJ_DIR)/sym_common.ld $(OBJ_DIR)/sym_ewram.ld
else
LD_SCRIPT := ld_script_modern.txt
LD_SCRIPT_DEPS := 
endif

$(OBJ_DIR)/ld_script.ld: $(LD_SCRIPT) $(LD_SCRIPT_DEPS)
	cd $(OBJ_DIR) && sed "s#tools/#../../tools/#g" ../../$(LD_SCRIPT) > ld_script.ld

ifneq ($(PORTABLE),1)
$(ELF): $(OBJ_DIR)/ld_script.ld $(OBJS) libagbsyscall
	@echo "cd $(OBJ_DIR) && $(LD) $(LDFLAGS) -T ld_script.ld -o ../../$@ <objects> <lib>"
	@cd $(OBJ_DIR) && $(LD) $(LDFLAGS) -T ld_script.ld -o ../../$@ $(OBJS_REL) $(LIB)
	$(FIX) $@ -t"$(TITLE)" -c$(GAME_CODE) -m$(MAKER_CODE) -r$(REVISION) --silent

$(ROM): $(ELF)
	$(OBJCOPY) -O binary $< $@
	$(FIX) $@ -p --silent
else
$(ROM): $(OBJS)
	$(MODERNCC) $(CFLAGS) -Wl,--demangle $^ -static-libgcc -L$(SDL_DIR)/lib $(PLATFORM_LFLAGS) $(OS_LFLAGS) -o $@
endif

modern: all
winwsl: all
linux: all

libagbsyscall:
	@$(MAKE) -C libagbsyscall TOOLCHAIN=$(TOOLCHAIN) MODERN=$(MODERN)

###################
### Symbol file ###
###################

ifneq ($(PORTABLE),1)
$(SYM): $(ELF)
	$(OBJDUMP) -t $< | sort -u | grep -E "^0[2389]" | $(PERL) -p -e 's/^(\w{8}) (\w).{6} \S+\t(\w{8}) (\S+)$$/\1 \2 \3 \4/g' > $@
endif
