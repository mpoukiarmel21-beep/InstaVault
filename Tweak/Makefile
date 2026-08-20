INSTALL_TARGET_PROCESSES = Instagram
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InstaVault

InstaVault_FILES = Source/Tweak.xm \
	Source/IVContainer.m \
	Source/IVFakeDevice.m \
	Source/IVContainerManager.m \
	Source/IVDeviceSpoofing.m \
	Source/IVLocationSpoofing.m \
	Source/IVStorageManager.m \
	Source/IVDiagnostics.m \
	Source/IVHardwareHook.xm \
	Source/IVIdentifierHook.xm \
	Source/IVKeychainHook.xm \
	Source/IVUserDefaultsHook.xm \
	Source/IVCookieHook.xm \
	Source/IVLocationHook.xm \
	Source/IVAntiDetectHook.xm \
	Source/IVFloatingButton.m \
	Source/IVContainerListVC.m \
	Source/IVContainerCreateVC.m \
	Source/IVMapPickerVC.m \
	Source/IVThemeManager.m

InstaVault_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
InstaVault_FRAMEWORKS = UIKit CoreLocation MapKit Security SystemConfiguration AdSupport
InstaVault_PRIVATE_FRAMEWORKS = MobileGestalt
InstaVault_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
