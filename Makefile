ARCHS = armv7
TARGET = iphone:clang:6.1:6.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iCloudBridge6
iCloudBridge6_FILES = src/Tweak.m src/IB6Policy.m
iCloudBridge6_CFLAGS = -fobjc-arc -Wall -Wextra
iCloudBridge6_FRAMEWORKS = Foundation CoreFoundation Security
iCloudBridge6_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

# No automatic daemon kill, respring or credential renewal on install.
