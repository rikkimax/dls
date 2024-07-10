
BETTER_D=/run/media/ryuukk/E0C0C01FC0BFFA3C/dev/kdom/better_d
COMPILER?=LD_PRELOAD=/usr/lib/libmimalloc.so "/home/ryuukk/dev/install/linux/bin64/dmd"
PREVIEWS=-preview=rvaluerefparam -preview=bitfields
ifeq ($(OS), Windows_NT)
	exe = .exe
	dll = .dll
	FLAGS_DEBUG   += -L/OPT:REF
	FLAGS_RELEASE += -L/OPT:REF
else
	exe =
	dll = .so
	LD_LIBRARY_PATH=.
endif

MODE ?= DEBUG
ifeq ($(MODE), DEBUG)
    OPTIMIZE=$(FLAGS_DEBUG)
else ifeq ($(MODE), RELEASE)
    OPTIMIZE=$(FLAGS_RELEASE)
endif


CHECK ?= 0

ifeq ($(CHECK), 1)
	OPTIMIZE += -c -o-
endif


build-dls:
	@$(COMPILER) -of=bin/dls $(OPTIMIZE) $(PREVIEWS) -i -I$(BETTER_D) \
    $(BETTER_D)/rt/object.d $(BETTER_D)/cjson/cJSON.c  dls/main.d

build-dcd:
	cd /run/media/ryuukk/A2523E6A523E42F9/dev/dcd_templates && dub build -c library

build-vscode:
	cd editors/vscode && npm run compile
	cd editors/vscode && vsce package
	cp editors/vscode/*.vsix bin/
# 	vsce publish