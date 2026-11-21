TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Vdcampro
Vdcampro_FILES = Tweak.xm
Vdcampro_CFLAGS = -fobjc-arc
Vdcampro_FRAMEWORKS = UIKit AVFoundation CoreImage CoreMedia CoreVideo Vision PhotosUI WebKit
Vdcampro_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
