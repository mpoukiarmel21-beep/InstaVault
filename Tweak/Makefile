ARCHS = arm64
TARGET = iphone:clang:latest:13.0

include $(THEOS)/makefiles/common.mk

# NOTE: This is a LIBRARY target (plain dylib), NOT a TWEAK target.
# A tweak.mk target auto-links /Library/Frameworks/CydiaSubstrate.framework,
# which does not exist on non-jailbroken (sideloaded) devices — dyld then
# fails to load the dylib and the whole tweak silently dies. Setting
# InstaVault_USE_SUBSTRATE = 0 did NOT stop the linkage in this Theos/CI
# setup, so we use library.mk instead. All hooks are manual ObjC
# method_setImplementation (no %hook / MSHook*), so no Substrate is needed.
LIBRARY_NAME = InstaVault

InstaVault_FILES = Source/Tweak.xm \
	Source/IVContainer.m \
	Source/IVFakeDevice.m \
	Source/IVContainerManager.m \
	Source/IVDeviceSpoofing.m \
	Source/IVLocationSpoofing.m \
	Source/IVDiagnostics.m \
	Source/IVHardwareHook.xm \
	Source/IVIdentifierHook.xm \
	Source/IVKeychainHook.xm \
	Source/IVCookieHook.xm \
	Source/IVLocationHook.xm \
	Source/IVFloatingButton.m \
	Source/IVContainerListVC.m \
	Source/IVContainerCreateVC.m \
	Source/IVMapPickerVC.m \
	Source/IVThemeManager.m

InstaVault_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-error=unguarded-availability-new
InstaVault_FRAMEWORKS = UIKit CoreLocation MapKit Security SystemConfiguration AdSupport

include $(THEOS_MAKE_PATH)/library.mk
