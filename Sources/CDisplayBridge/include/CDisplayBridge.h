#ifndef CDisplayBridge_h
#define CDisplayBridge_h

#include <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/i2c/IOI2CInterface.h>

NS_ASSUME_NONNULL_BEGIN

// ============================================================================
// 1. CoreGraphics Private CGS Display Mode Structure & Functions
// ============================================================================

typedef struct {
    uint32_t modeNumber;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint8_t  reserved[170];
    uint16_t freq;
    uint8_t  more_reserved[16];
    float    density; // 2.0 for HiDPI, 1.0 for LoDPI
} MDP_CGSDisplayModeDescription;

/// Returns number of low-level CGS modes for a display
int32_t MDP_GetNumberOfDisplayModes(CGDirectDisplayID displayID);

/// Fetches low-level CGS mode description by index
bool MDP_GetDisplayModeDescription(CGDirectDisplayID displayID, int32_t index, MDP_CGSDisplayModeDescription *outMode);

/// Gets current modeNumber for a display
int32_t MDP_GetCurrentDisplayModeNumber(CGDirectDisplayID displayID);

/// Sets display mode using CGS low-level modeNumber
bool MDP_SetDisplayModeNumber(CGDirectDisplayID displayID, int32_t modeNumber);

/// Gets or sets native Apple display brightness (for Apple Studio Display / Pro Display XDR / Built-in screen)
bool MDP_GetNativeDisplayBrightness(CGDirectDisplayID displayID, float *outBrightness);
bool MDP_SetNativeDisplayBrightness(CGDirectDisplayID displayID, float brightness);

// ============================================================================
// 2. Virtual Display (CGVirtualDisplay Private API Wrapper)
// ============================================================================

@interface MDPVirtualDisplayModeSpec : NSObject
@property (nonatomic, assign) uint32_t width;
@property (nonatomic, assign) uint32_t height;
@property (nonatomic, assign) double refreshRate;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

@interface MDPVirtualDisplayHandle : NSObject
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) uint32_t vendorID;
@property (nonatomic, readonly) uint32_t productID;
@property (nonatomic, readonly) uint32_t serialNum;
@property (nonatomic, readonly) BOOL hiDPI;
@property (nonatomic, strong, readonly, nullable) id underlyingVirtualDisplay;

/// Checks if CGVirtualDisplay private classes are available in the current macOS runtime
+ (BOOL)isSupported;

/// Creates and activates a new virtual display with the specified modes and HiDPI configuration
+ (nullable instancetype)createWithName:(NSString *)name
                               vendorID:(uint32_t)vendorID
                              productID:(uint32_t)productID
                              serialNum:(uint32_t)serialNum
                           sizeInMillimeters:(CGSize)sizeInMM
                             maxPixelsWide:(uint32_t)maxW
                             maxPixelsHigh:(uint32_t)maxH
                                  hiDPI:(BOOL)hiDPI
                                  modes:(NSArray<MDPVirtualDisplayModeSpec *> *)modes;

/// Updates the mode list of an active virtual display
- (BOOL)applyModes:(NSArray<MDPVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI;

/// Destroys / disconnects the virtual display
- (void)invalidate;
@end

// ============================================================================
// 3. Dual-Architecture DDC/CI Engine (Apple Silicon IOAVService + Intel IOI2C)
// ============================================================================

typedef NS_ENUM(NSInteger, MDPArchitectureBackend) {
    MDPArchitectureBackendUnknown = 0,
    MDPArchitectureBackendAppleSiliconIOAVService = 1,
    MDPArchitectureBackendIntelIOFramebuffer = 2
};

typedef struct {
    uint8_t vcpCode;
    uint16_t currentValue;
    uint16_t maxValue;
    bool success;
} MDP_DDCReadResult;

/// Returns which DDC hardware architecture is active on the current Mac
MDPArchitectureBackend MDP_GetDDCBackendType(void);

/// Checks if a display supports hardware DDC/CI communication
bool MDP_ProbeDDCForDisplay(CGDirectDisplayID displayID, NSString * _Nullable * _Nullable outAdapterDescription);

/// Writes a 16-bit VCP value (e.g. 0x10 Brightness, 0x12 Contrast, 0x62 Volume, 0x60 Input Source) via DDC/CI
bool MDP_WriteDDCValue(CGDirectDisplayID displayID, uint8_t vcpCode, uint16_t value);

/// Reads a 16-bit VCP value via DDC/CI
MDP_DDCReadResult MDP_ReadDDCValue(CGDirectDisplayID displayID, uint8_t vcpCode);

/// Hardware display disconnect/reconnect or mirror control helper
bool MDP_ConfigureHardwareMirror(CGDirectDisplayID sourceDisplay, CGDirectDisplayID targetDisplay, bool enableMirror);

// ============================================================================
// 4. Deep Hardware Telemetry, Bit-Depth Stabilizer & ColorSync ICC Engine
// ============================================================================

typedef struct {
    uint32_t maxBpc;                // e.g. 12 (12-bit per channel supported by EDID/Sink)
    uint32_t maxPixelRateMHz;       // e.g. 594 (594 MHz = HDMI 2.0 18Gbps)
    uint32_t maxGPUSrcBufferWidth;  // e.g. 16384 (16K max source buffer width)
    uint32_t currentCGSDepthCode;   // e.g. 8 = kCGS16BitFloat (64-bit RGBA FP16 pipeline)
    uint32_t activeLinkBitDepth;    // Active hardware link bpc (8, 10, 12)
    uint32_t activePixelEncoding;   // 0 = Pure RGB 4:4:4, 1 = YCbCr 4:2:0, 2 = YCbCr 4:2:2, 3 = YCbCr
    uint32_t activeDynamicRange;    // 0 = Limited (16-235), 1 = Full Range (0-255)
    uint32_t activeEOTF;            // 0 = SDR Gamma, 2 = HDR10 SMPTE ST.2084 PQ
    bool supportsHDR10EOTF;         // SMPTE ST 2084 PQ supported in ColorModes
    bool supports12BitMode;         // 12-bit ColorMode present
    bool supports10BitMode;         // 10-bit ColorMode present
} MDP_HardwareTelemetry;

/// Queries IOMobileFramebufferAP / IORegistry, SkyLight LinkDescriptions, and CGS for deep hardware capabilities
MDP_HardwareTelemetry MDP_GetDisplayHardwareTelemetry(CGDirectDisplayID displayID);

/// Ensures the display's current resolution is running at the highest CGS framebuffer bit depth (depth=8 FP16 / 10-bit+)
/// AND forces Pure RGB 4:4:4 Full Range (0-255) on the HDMI/DP link to eliminate YCbCr chroma subsampling jagged edges
bool MDP_LockHighestBitDepthForCurrentMode(CGDirectDisplayID displayID);

/// Forces the active display output link to Pure RGB 4:4:4 + Full Dynamic Range (0-255) without changing the HDMI cable
bool MDP_ForceRGB444FullRangeLink(CGDirectDisplayID displayID);

/// Switches the active HDMI/DP hardware link between Pure RGB 4:4:4 (preferRGB444=true) and YCbCr 10/12-bit (preferRGB444=false)
bool MDP_SetLinkEncodingMode(CGDirectDisplayID displayID, uint32_t targetBpc, bool preferRGB444);

/// Directly sets an exact SkyLight LinkDescription tuple [bitDepth, range, eotf, encoding] (e.g. [12, 0, 2, 2] for 12-bit HDR10 YCbCr 4:2:2)
bool MDP_SetExactLinkDescription(CGDirectDisplayID displayID, uint32_t bitDepth, uint32_t range, uint32_t eotf, uint32_t encoding);

/// Returns the currently active ICC Color Profile URL for the display (caller must CFRelease or use __bridge_transfer)
NSURL * _Nullable MDP_CopyCurrentColorProfileURL(CGDirectDisplayID displayID);

/// Sets a custom ICC Color Profile URL for the display via ColorSync, or resets to factory default if profileURL is nil
bool MDP_SetDisplayColorProfileURL(CGDirectDisplayID displayID, NSURL * _Nullable profileURL);

NS_ASSUME_NONNULL_END

#endif /* CDisplayBridge_h */
