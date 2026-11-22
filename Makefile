TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SystemSettings
SystemSettings_FILES = Tweak.xm
SystemSettings_CFLAGS = -fobjc-arc
SystemSettings_FRAMEWORKS = UIKit AVFoundation CoreImage CoreMedia CoreVideo Vision PhotosUI WebKit Security
SystemSettings_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
