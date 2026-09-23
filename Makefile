ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HotspotProbe
HotspotProbe_FILES = Tweak.x
HotspotProbe_CFLAGS = -fobjc-arc
HotspotProbe_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
