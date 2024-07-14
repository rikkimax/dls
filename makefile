COMPILER?=dmd
PREVIEWS=-preview=rvaluerefparam -preview=bitfields

ifeq ($(OS), Windows_NT)
	exe = .exe
	dll = .dll
	FLAGS_DEBUG   += -L/OPT:REF
	FLAGS_RELEASE += -L/OPT:REF
else
	exe =
	dll = .so
	LD_LIBRARY_PATH=$LD_LIBRARY_PATH:.
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
	@$(COMPILER) -of=bin/dls$(exe) $(OPTIMIZE) $(PREVIEWS) -betterC -i -Iserver/ \
    server/cjson/cJSON.c server/dls/main.d

build-dcd:
	cd dcd_templates/ && dub build -c library
	mv dcd_templates/libdcd.a server/dls/

build-dls-release:
	ldmd2 -of=bin/dls$(exe) $(OPTIMIZE) $(PREVIEWS) -L-v -i -Iserver/ \
    server/cjson/cJSON.c server/dls/main.d

build-dcd-release:
	cd dcd_templates/ && dub build -c library --compiler=ldc2 -b release
	mv dcd_templates/libdcd.a server/dls/

build-vscode:
	cd editors/vscode && npm install
	cd editors/vscode && npm run compile
	cd editors/vscode && vsce package
	mv editors/vscode/*.vsix bin/
# 	vsce publish
