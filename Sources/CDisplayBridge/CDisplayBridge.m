#import "include/CDisplayBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <ColorSync/ColorSync.h>

// ============================================================================
// Private Objective-C Declarations for CGVirtualDisplay (for clean selector typing)
// ============================================================================

@interface NSObject (CGVirtualDisplayPrivateMethods)
- (void)setName:(NSString *)name;
- (void)setVendorID:(uint32_t)vendorID;
- (void)setProductID:(uint32_t)productID;
- (void)setSerialNum:(uint32_t)serialNum;
- (void)setSizeInMillimeters:(CGSize)size;
- (void)setMaxPixelsWide:(uint32_t)w;
- (void)setMaxPixelsHigh:(uint32_t)h;
- (void)setRedPrimary:(CGPoint)p;
- (void)setGreenPrimary:(CGPoint)p;
- (void)setBluePrimary:(CGPoint)p;
- (void)setWhitePoint:(CGPoint)p;
- (void)setQueue:(dispatch_queue_t)q;
- (void)setTerminationHandler:(id)handler;

- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
- (CGDirectDisplayID)displayID;

- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
- (void)setModes:(NSArray *)modes;
- (void)setHiDPI:(unsigned int)hiDPI;
@end

// ============================================================================
// 1. Dynamic CGS & DisplayServices Resolution & Brightness Functions
// ============================================================================

typedef CGError (*CGSGetNumberOfDisplayModesFunc)(CGDirectDisplayID display, int32_t *nModes);
typedef CGError (*CGSGetDisplayModeDescriptionOfLengthFunc)(CGDirectDisplayID display, int32_t idx, MDP_CGSDisplayModeDescription *mode, int32_t length);
typedef CGError (*CGSGetCurrentDisplayModeFunc)(CGDirectDisplayID display, int32_t *modeNum);
typedef CGError (*CGSConfigureDisplayModeFunc)(CGDisplayConfigRef config, CGDirectDisplayID display, int32_t modeNum);
typedef int (*DisplayServicesGetBrightnessFunc)(CGDirectDisplayID display, float *brightness);
typedef int (*DisplayServicesSetBrightnessFunc)(CGDirectDisplayID display, float brightness);
typedef double (*CoreDisplayGetUserBrightnessFunc)(CGDirectDisplayID display);
typedef void (*CoreDisplaySetUserBrightnessFunc)(CGDirectDisplayID display, double brightness);

int32_t MDP_GetNumberOfDisplayModes(CGDirectDisplayID displayID) {
    static CGSGetNumberOfDisplayModesFunc fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (CGSGetNumberOfDisplayModesFunc)dlsym(RTLD_DEFAULT, "CGSGetNumberOfDisplayModes");
    });
    if (!fn) return 0;
    int32_t count = 0;
    if (fn(displayID, &count) == kCGErrorSuccess) {
        return count;
    }
    return 0;
}

bool MDP_GetDisplayModeDescription(CGDirectDisplayID displayID, int32_t index, MDP_CGSDisplayModeDescription *outMode) {
    if (!outMode) return false;
    static CGSGetDisplayModeDescriptionOfLengthFunc fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (CGSGetDisplayModeDescriptionOfLengthFunc)dlsym(RTLD_DEFAULT, "CGSGetDisplayModeDescriptionOfLength");
    });
    if (!fn) return false;
    memset(outMode, 0, sizeof(MDP_CGSDisplayModeDescription));
    return fn(displayID, index, outMode, sizeof(MDP_CGSDisplayModeDescription)) == kCGErrorSuccess;
}

int32_t MDP_GetCurrentDisplayModeNumber(CGDirectDisplayID displayID) {
    static CGSGetCurrentDisplayModeFunc fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (CGSGetCurrentDisplayModeFunc)dlsym(RTLD_DEFAULT, "CGSGetCurrentDisplayMode");
    });
    if (!fn) return -1;
    int32_t modeNum = -1;
    if (fn(displayID, &modeNum) == kCGErrorSuccess) {
        return modeNum;
    }
    return -1;
}

bool MDP_SetDisplayModeNumber(CGDirectDisplayID displayID, int32_t modeNumber) {
    static CGSConfigureDisplayModeFunc fn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fn = (CGSConfigureDisplayModeFunc)dlsym(RTLD_DEFAULT, "CGSConfigureDisplayMode");
    });
    if (!fn) return false;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) {
        return false;
    }
    CGError err = fn(config, displayID, modeNumber);
    if (err != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return false;
    }
    bool ok = (CGCompleteDisplayConfiguration(config, kCGConfigureForSession) == kCGErrorSuccess);
    if (ok && !CGDisplayIsBuiltin(displayID)) {
        // Automatically lock Pure RGB 4:4:4 Full Range (0-255) on external HDMI/DP links
        // so macOS WindowServer never degrades chroma to YCbCr 4:2:0 / 4:2:2!
        MDP_ForceRGB444FullRangeLink(displayID);
    }
    return ok;
}

bool MDP_GetNativeDisplayBrightness(CGDirectDisplayID displayID, float *outBrightness) {
    if (!outBrightness) return false;
    static DisplayServicesGetBrightnessFunc dsGet = NULL;
    static CoreDisplayGetUserBrightnessFunc cdGet = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
        if (dsHandle) {
            dsGet = (DisplayServicesGetBrightnessFunc)dlsym(dsHandle, "DisplayServicesGetBrightness");
        }
        void *cdHandle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY);
        if (cdHandle) {
            cdGet = (CoreDisplayGetUserBrightnessFunc)dlsym(cdHandle, "CoreDisplay_Display_GetUserBrightness");
        }
    });
    if (dsGet && dsGet(displayID, outBrightness) == 0) {
        return true;
    }
    if (cdGet) {
        double val = cdGet(displayID);
        if (val >= 0.0 && val <= 1.0) {
            *outBrightness = (float)val;
            return true;
        }
    }
    return false;
}

bool MDP_SetNativeDisplayBrightness(CGDirectDisplayID displayID, float brightness) {
    float clamped = fmaxf(0.0f, fminf(1.0f, brightness));
    static DisplayServicesSetBrightnessFunc dsSet = NULL;
    static CoreDisplaySetUserBrightnessFunc cdSet = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
        if (dsHandle) {
            dsSet = (DisplayServicesSetBrightnessFunc)dlsym(dsHandle, "DisplayServicesSetBrightness");
        }
        void *cdHandle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY);
        if (cdHandle) {
            cdSet = (CoreDisplaySetUserBrightnessFunc)dlsym(cdHandle, "CoreDisplay_Display_SetUserBrightness");
        }
    });
    if (dsSet && dsSet(displayID, clamped) == 0) {
        return true;
    }
    if (cdSet) {
        cdSet(displayID, (double)clamped);
        return true;
    }
    return false;
}

// ============================================================================
// 2. Virtual Display (CGVirtualDisplay Private API Wrapper)
// ============================================================================

@implementation MDPVirtualDisplayModeSpec
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}
@end

@interface MDPVirtualDisplayHandle () {
    BOOL _hiDPI;
}
@property (nonatomic, assign, readwrite) CGDirectDisplayID displayID;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) uint32_t vendorID;
@property (nonatomic, assign, readwrite) uint32_t productID;
@property (nonatomic, assign, readwrite) uint32_t serialNum;
@property (nonatomic, strong, readwrite, nullable) id underlyingVirtualDisplay;
@end

@implementation MDPVirtualDisplayHandle

- (BOOL)hiDPI {
    return _hiDPI;
}

+ (BOOL)isSupported {
    return NSClassFromString(@"CGVirtualDisplay") != nil &&
           NSClassFromString(@"CGVirtualDisplayDescriptor") != nil &&
           NSClassFromString(@"CGVirtualDisplaySettings") != nil &&
           NSClassFromString(@"CGVirtualDisplayMode") != nil;
}

+ (nullable instancetype)createWithName:(NSString *)name
                               vendorID:(uint32_t)vendorID
                              productID:(uint32_t)productID
                              serialNum:(uint32_t)serialNum
                      sizeInMillimeters:(CGSize)sizeInMM
                          maxPixelsWide:(uint32_t)maxW
                          maxPixelsHigh:(uint32_t)maxH
                                  hiDPI:(BOOL)hiDPI
                                  modes:(NSArray<MDPVirtualDisplayModeSpec *> *)modes {
    if (![self isSupported]) return nil;

    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");

    id descriptor = [[descClass alloc] init];
    if ([descriptor respondsToSelector:@selector(setName:)]) [descriptor setName:name];
    if ([descriptor respondsToSelector:@selector(setVendorID:)]) [descriptor setVendorID:vendorID];
    if ([descriptor respondsToSelector:@selector(setProductID:)]) [descriptor setProductID:productID];
    if ([descriptor respondsToSelector:@selector(setSerialNum:)]) [descriptor setSerialNum:serialNum];
    if ([descriptor respondsToSelector:@selector(setSizeInMillimeters:)]) [descriptor setSizeInMillimeters:sizeInMM];
    if ([descriptor respondsToSelector:@selector(setMaxPixelsWide:)]) [descriptor setMaxPixelsWide:maxW];
    if ([descriptor respondsToSelector:@selector(setMaxPixelsHigh:)]) [descriptor setMaxPixelsHigh:maxH];

    // Standard Display P3 / sRGB primaries
    if ([descriptor respondsToSelector:@selector(setRedPrimary:)]) [descriptor setRedPrimary:CGPointMake(0.6797, 0.3203)];
    if ([descriptor respondsToSelector:@selector(setGreenPrimary:)]) [descriptor setGreenPrimary:CGPointMake(0.2646, 0.6904)];
    if ([descriptor respondsToSelector:@selector(setBluePrimary:)]) [descriptor setBluePrimary:CGPointMake(0.1494, 0.0596)];
    if ([descriptor respondsToSelector:@selector(setWhitePoint:)]) [descriptor setWhitePoint:CGPointMake(0.3127, 0.3290)];
    if ([descriptor respondsToSelector:@selector(setQueue:)]) [descriptor setQueue:dispatch_get_main_queue()];

    id virtualDisplay = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!virtualDisplay) return nil;

    MDPVirtualDisplayHandle *handle = [[MDPVirtualDisplayHandle alloc] init];
    handle.underlyingVirtualDisplay = virtualDisplay;
    handle.name = name;
    handle.vendorID = vendorID;
    handle.productID = productID;
    handle.serialNum = serialNum;
    handle->_hiDPI = hiDPI;
    handle.displayID = [virtualDisplay displayID];

    [handle applyModes:modes hiDPI:hiDPI];
    return handle;
}

- (BOOL)applyModes:(NSArray<MDPVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI {
    if (!self.underlyingVirtualDisplay) return NO;
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!settingsClass || !modeClass) return NO;

    id settings = [[settingsClass alloc] init];
    NSMutableArray *cgModes = [NSMutableArray arrayWithCapacity:modes.count * 2];

    for (MDPVirtualDisplayModeSpec *spec in modes) {
        id modeObj = [[modeClass alloc] initWithWidth:spec.width height:spec.height refreshRate:spec.refreshRate];
        if (modeObj) {
            [cgModes addObject:modeObj];
        }
        // When HiDPI is enabled, also provide 2x backing resolution modes so macOS offers crisp 2x scaling
        if (hiDPI && spec.width <= 3840) {
            id mode2x = [[modeClass alloc] initWithWidth:spec.width * 2 height:spec.height * 2 refreshRate:spec.refreshRate];
            if (mode2x) {
                [cgModes addObject:mode2x];
            }
        }
    }

    if ([settings respondsToSelector:@selector(setModes:)]) {
        [settings setModes:cgModes];
    }
    if ([settings respondsToSelector:@selector(setHiDPI:)]) {
        [settings setHiDPI:(hiDPI ? 1 : 0)];
    }

    _hiDPI = hiDPI;
    if ([self.underlyingVirtualDisplay respondsToSelector:@selector(applySettings:)]) {
        return [self.underlyingVirtualDisplay applySettings:settings];
    }
    return NO;
}

- (void)invalidate {
    self.underlyingVirtualDisplay = nil;
    self.displayID = kCGNullDirectDisplay;
}

@end

// ============================================================================
// 3. Dual-Architecture DDC/CI Engine (Apple Silicon IOAVService + Intel IOI2C)
// ============================================================================

typedef CFTypeRef (*IOAVServiceCreateFunc)(CFAllocatorRef allocator);
typedef CFTypeRef (*IOAVServiceCreateWithServiceFunc)(CFAllocatorRef allocator, io_service_t service);
typedef IOReturn (*IOAVServiceReadI2CFunc)(CFTypeRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
typedef IOReturn (*IOAVServiceWriteI2CFunc)(CFTypeRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
typedef CGError (*CGSServiceForDisplayNumberFunc)(CGDirectDisplayID display, io_service_t *service);

MDPArchitectureBackend MDP_GetDDCBackendType(void) {
#if defined(__arm64__) || defined(__aarch64__)
    return MDPArchitectureBackendAppleSiliconIOAVService;
#else
    return MDPArchitectureBackendIntelIOFramebuffer;
#endif
}

// Helper: Find IOAVService for an external display on Apple Silicon (M1/M2/M3/M4/M5/M6)
static CFTypeRef MDP_CopyIOAVServiceForDisplay(CGDirectDisplayID displayID, NSString **outName) {
    if (CGDisplayIsBuiltin(displayID)) {
        return NULL;
    }

    static IOAVServiceCreateWithServiceFunc createWithService = NULL;
    static IOAVServiceCreateFunc createDefault = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        createWithService = (IOAVServiceCreateWithServiceFunc)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
        createDefault = (IOAVServiceCreateFunc)dlsym(RTLD_DEFAULT, "IOAVServiceCreate");
    });

    if (!createWithService) return NULL;

    // Count external displays to map displayID order when multiple external monitors are attached
    uint32_t activeDisplays[16];
    uint32_t displayCount = 0;
    CGGetActiveDisplayList(16, activeDisplays, &displayCount);
    int targetExternalIndex = 0;
    int currentExternalIdx = 0;
    for (uint32_t i = 0; i < displayCount; i++) {
        if (!CGDisplayIsBuiltin(activeDisplays[i])) {
            if (activeDisplays[i] == displayID) {
                targetExternalIndex = currentExternalIdx;
                break;
            }
            currentExternalIdx++;
        }
    }

    io_iterator_t iter = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter);
    if (kr != KERN_SUCCESS || iter == IO_OBJECT_NULL) {
        return createDefault ? createDefault(kCFAllocatorDefault) : NULL;
    }

    CFTypeRef matchedAVService = NULL;
    int foundExternalCount = 0;
    io_service_t service = IO_OBJECT_NULL;

    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFTypeRef locationRef = IORegistryEntryCreateCFProperty(service, CFSTR("Location"), kCFAllocatorDefault, 0);
        NSString *location = (__bridge_transfer NSString *)locationRef;

        // Skip embedded internal display proxy
        if (location && [location isEqualToString:@"Embedded"]) {
            IOObjectRelease(service);
            continue;
        }

        CFTypeRef avService = createWithService(kCFAllocatorDefault, service);
        if (avService) {
            if (foundExternalCount == targetExternalIndex) {
                if (outName) {
                    *outName = [NSString stringWithFormat:@"Apple Silicon DCPAVServiceProxy (%@)", location ?: @"External"];
                }
                matchedAVService = avService;
                IOObjectRelease(service);
                break;
            } else {
                CFRelease(avService);
            }
            foundExternalCount++;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);

    if (!matchedAVService && createDefault) {
        matchedAVService = createDefault(kCFAllocatorDefault);
        if (matchedAVService && outName) {
            *outName = @"Apple Silicon Default IOAVService";
        }
    }
    return matchedAVService;
}

// Helper: Find IOFramebuffer service for Intel Macs (e.g. 2019 MacBook Pro Intel / AMD Radeon)
static io_service_t MDP_CopyIntelFramebufferPort(CGDirectDisplayID displayID, NSString **outName) {
    if (CGDisplayIsBuiltin(displayID)) {
        return IO_OBJECT_NULL;
    }

    static CGSServiceForDisplayNumberFunc cgsServiceFn = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cgsServiceFn = (CGSServiceForDisplayNumberFunc)dlsym(RTLD_DEFAULT, "CGSServiceForDisplayNumber");
    });

    if (cgsServiceFn) {
        io_service_t service = IO_OBJECT_NULL;
        if (cgsServiceFn(displayID, &service) == kCGErrorSuccess && service != IO_OBJECT_NULL) {
            IOObjectRetain(service);
            if (outName) *outName = @"Intel IOFramebuffer (CGSService)";
            return service;
        }
    }

    uint32_t targetVendor = CGDisplayVendorNumber(displayID);
    uint32_t targetModel = CGDisplayModelNumber(displayID);

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &iter) != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }

    io_service_t matched = IO_OBJECT_NULL;
    io_service_t serv = IO_OBJECT_NULL;
    while ((serv = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFDictionaryRef info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);
        if (info) {
            CFNumberRef vendorRef = CFDictionaryGetValue(info, CFSTR(kDisplayVendorID));
            CFNumberRef productRef = CFDictionaryGetValue(info, CFSTR(kDisplayProductID));
            uint32_t v = 0, p = 0;
            if (vendorRef) CFNumberGetValue(vendorRef, kCFNumberSInt32Type, &v);
            if (productRef) CFNumberGetValue(productRef, kCFNumberSInt32Type, &p);
            CFRelease(info);

            if (v == targetVendor && p == targetModel) {
                matched = serv;
                if (outName) *outName = @"Intel IOFramebuffer (I2C)";
                break;
            }
        }
        IOObjectRelease(serv);
    }
    IOObjectRelease(iter);
    return matched;
}

bool MDP_ProbeDDCForDisplay(CGDirectDisplayID displayID, NSString * _Nullable * _Nullable outAdapterDescription) {
    if (CGDisplayIsBuiltin(displayID)) {
        if (outAdapterDescription) *outAdapterDescription = @"Built-in Display (Native Brightness API)";
        return false;
    }

    CFTypeRef avService = MDP_CopyIOAVServiceForDisplay(displayID, outAdapterDescription);
    if (avService) {
        CFRelease(avService);
        return true;
    }

    io_service_t fbPort = MDP_CopyIntelFramebufferPort(displayID, outAdapterDescription);
    if (fbPort != IO_OBJECT_NULL) {
        IOItemCount busCount = 0;
        if (IOFBGetI2CInterfaceCount(fbPort, &busCount) == KERN_SUCCESS && busCount > 0) {
            IOObjectRelease(fbPort);
            return true;
        }
        IOObjectRelease(fbPort);
    }

    if (outAdapterDescription) *outAdapterDescription = @"Software LUT / Gamma & Metal Overlay Control";
    return false;
}

bool MDP_WriteDDCValue(CGDirectDisplayID displayID, uint8_t vcpCode, uint16_t value) {
    // Standard DDC/CI Set VCP Feature packet:
    // [0]: 0x84 (Length = 4 bytes following)
    // [1]: 0x03 (Set VCP Feature command)
    // [2]: VCP Opcode (e.g. 0x10 Brightness, 0x12 Contrast, 0x62 Volume)
    // [3]: Value High Byte
    // [4]: Value Low Byte
    // [5]: Checksum = 0x6E ^ 0x51 ^ [0] ^ [1] ^ [2] ^ [3] ^ [4]
    uint8_t packet[6];
    packet[0] = 0x84;
    packet[1] = 0x03;
    packet[2] = vcpCode;
    packet[3] = (uint8_t)((value >> 8) & 0xFF);
    packet[4] = (uint8_t)(value & 0xFF);
    packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];

    // 1. Try Apple Silicon IOAVService path
    static IOAVServiceWriteI2CFunc writeI2C = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        writeI2C = (IOAVServiceWriteI2CFunc)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
    });

    CFTypeRef avService = MDP_CopyIOAVServiceForDisplay(displayID, NULL);
    if (avService && writeI2C) {
        // Single clean I2C transaction to protect monitor EEPROM write endurance
        IOReturn ret = writeI2C(avService, 0x37, 0x51, packet, sizeof(packet));
        CFRelease(avService);
        return (ret == kIOReturnSuccess);
    }
    if (avService) CFRelease(avService);

    // 2. Try Intel IOFramebuffer + IOI2CInterface path
    io_service_t fbPort = MDP_CopyIntelFramebufferPort(displayID, NULL);
    if (fbPort != IO_OBJECT_NULL) {
        bool success = false;
        IOItemCount busCount = 0;
        if (IOFBGetI2CInterfaceCount(fbPort, &busCount) == KERN_SUCCESS) {
            for (IOOptionBits bus = 0; bus < busCount; bus++) {
                io_service_t interface = IO_OBJECT_NULL;
                if (IOFBCopyI2CInterfaceForBus(fbPort, bus, &interface) == KERN_SUCCESS && interface != IO_OBJECT_NULL) {
                    IOI2CConnectRef connect = NULL;
                    if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) == KERN_SUCCESS) {
                        uint8_t intelData[7];
                        intelData[0] = 0x51; // Sub-address included in payload for raw I2C request
                        memcpy(&intelData[1], packet, 6);

                        IOI2CRequest req;
                        memset(&req, 0, sizeof(req));
                        req.commFlags = kNilOptions;
                        req.sendAddress = 0x6E;
                        req.sendTransactionType = kIOI2CSimpleTransactionType;
                        req.sendBuffer = (vm_address_t)&intelData[0];
                        req.sendBytes = sizeof(intelData);
                        req.replyTransactionType = kIOI2CNoTransactionType;

                        if (IOI2CSendRequest(connect, kNilOptions, &req) == KERN_SUCCESS && req.result == KERN_SUCCESS) {
                            success = true;
                        }
                        IOI2CInterfaceClose(connect, kNilOptions);
                    }
                    IOObjectRelease(interface);
                    if (success) break;
                }
            }
        }
        IOObjectRelease(fbPort);
        return success;
    }

    return false;
}

MDP_DDCReadResult MDP_ReadDDCValue(CGDirectDisplayID displayID, uint8_t vcpCode) {
    MDP_DDCReadResult result = { .vcpCode = vcpCode, .currentValue = 0, .maxValue = 100, .success = false };

    // DDC/CI Get VCP Feature request packet:
    // [0]: 0x82 (Length = 2 bytes)
    // [1]: 0x01 (Get VCP Feature command)
    // [2]: VCP Opcode
    // [3]: Checksum = 0x6E ^ 0x51 ^ [0] ^ [1] ^ [2]
    uint8_t requestPacket[4];
    requestPacket[0] = 0x82;
    requestPacket[1] = 0x01;
    requestPacket[2] = vcpCode;
    requestPacket[3] = 0x6E ^ 0x51 ^ requestPacket[0] ^ requestPacket[1] ^ requestPacket[2];

    uint8_t reply[11];
    memset(reply, 0, sizeof(reply));

    // 1. Try Apple Silicon IOAVService path
    static IOAVServiceWriteI2CFunc writeI2C = NULL;
    static IOAVServiceReadI2CFunc readI2C = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        writeI2C = (IOAVServiceWriteI2CFunc)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
        readI2C = (IOAVServiceReadI2CFunc)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
    });

    CFTypeRef avService = MDP_CopyIOAVServiceForDisplay(displayID, NULL);
    if (avService && writeI2C && readI2C) {
        if (writeI2C(avService, 0x37, 0x51, requestPacket, sizeof(requestPacket)) == kIOReturnSuccess) {
            usleep(45000); // 45ms DDC/CI turnaround delay per VESA standard
            if (readI2C(avService, 0x37, 0x51, reply, sizeof(reply)) == kIOReturnSuccess) {
                // Reply format: [0]=0x6E, [1]=0x88, [2]=0x02(VCP Reply), [3]=ResultCode(0=NoError), [4]=VCPCode, [5]=Type, [6]=MH, [7]=ML, [8]=SH, [9]=SL, [10]=Checksum
                if (reply[2] == 0x02 && reply[3] == 0x00 && reply[4] == vcpCode) {
                    result.maxValue = ((uint16_t)reply[6] << 8) | reply[7];
                    result.currentValue = ((uint16_t)reply[8] << 8) | reply[9];
                    result.success = true;
                }
            }
        }
        CFRelease(avService);
        return result;
    }
    if (avService) CFRelease(avService);

    // 2. Try Intel IOFramebuffer + IOI2CInterface path
    io_service_t fbPort = MDP_CopyIntelFramebufferPort(displayID, NULL);
    if (fbPort != IO_OBJECT_NULL) {
        IOItemCount busCount = 0;
        if (IOFBGetI2CInterfaceCount(fbPort, &busCount) == KERN_SUCCESS) {
            for (IOOptionBits bus = 0; bus < busCount; bus++) {
                io_service_t interface = IO_OBJECT_NULL;
                if (IOFBCopyI2CInterfaceForBus(fbPort, bus, &interface) == KERN_SUCCESS && interface != IO_OBJECT_NULL) {
                    IOI2CConnectRef connect = NULL;
                    if (IOI2CInterfaceOpen(interface, kNilOptions, &connect) == KERN_SUCCESS) {
                        uint8_t sendBuf[5];
                        sendBuf[0] = 0x51;
                        memcpy(&sendBuf[1], requestPacket, 4);

                        IOI2CRequest req;
                        memset(&req, 0, sizeof(req));
                        req.commFlags = kNilOptions;
                        req.sendAddress = 0x6E;
                        req.sendTransactionType = kIOI2CSimpleTransactionType;
                        req.sendBuffer = (vm_address_t)&sendBuf[0];
                        req.sendBytes = sizeof(sendBuf);
                        req.minReplyDelay = 45000000ULL; // 45ms in nanoseconds
                        req.replyAddress = 0x6F;
                        req.replySubAddress = 0x51;
                        req.replyTransactionType = kIOI2CSimpleTransactionType;
                        req.replyBuffer = (vm_address_t)&reply[0];
                        req.replyBytes = sizeof(reply);

                        if (IOI2CSendRequest(connect, kNilOptions, &req) == KERN_SUCCESS && req.result == KERN_SUCCESS) {
                            if (reply[2] == 0x02 && reply[3] == 0x00) {
                                result.maxValue = ((uint16_t)reply[6] << 8) | reply[7];
                                result.currentValue = ((uint16_t)reply[8] << 8) | reply[9];
                                result.success = true;
                            }
                        }
                        IOI2CInterfaceClose(connect, kNilOptions);
                    }
                    IOObjectRelease(interface);
                    if (result.success) break;
                }
            }
        }
        IOObjectRelease(fbPort);
    }

    return result;
}

bool MDP_ConfigureHardwareMirror(CGDirectDisplayID sourceDisplay, CGDirectDisplayID targetDisplay, bool enableMirror) {
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) {
        return false;
    }
    CGDirectDisplayID master = enableMirror ? sourceDisplay : kCGNullDirectDisplay;
    if (CGConfigureDisplayMirrorOfDisplay(config, targetDisplay, master) != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return false;
    }
    return CGCompleteDisplayConfiguration(config, kCGConfigureForSession) == kCGErrorSuccess;
}

// ============================================================================
// 4. Deep Hardware Telemetry, Bit-Depth Stabilizer & ColorSync ICC Engine
// ============================================================================

typedef int32_t (*SLSGetDisplayOutputModeLinkDescriptionsFunc)(uint32_t displayID, int32_t modeNum, uint32_t *outBuf, int32_t *ioCount, int32_t *outCurrentIdx);
typedef int32_t (*SLSSetDisplayOutputModeFunc)(uint32_t displayID, uint64_t packedBitDepthAndRange, uint64_t packedEotfAndEncoding);

static void *MDP_GetSkyLightHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    });
    return handle;
}

bool MDP_ForceRGB444FullRangeLink(CGDirectDisplayID displayID) {
    if (CGDisplayIsBuiltin(displayID)) return true;
    return MDP_SetLinkEncodingMode(displayID, 8, true);
}

bool MDP_SetLinkEncodingMode(CGDirectDisplayID displayID, uint32_t targetBpc, bool preferRGB444) {
    if (CGDisplayIsBuiltin(displayID)) return true;
    void *h = MDP_GetSkyLightHandle();
    if (!h) return false;

    static SLSGetDisplayOutputModeLinkDescriptionsFunc getLinks = NULL;
    static SLSSetDisplayOutputModeFunc setOut = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        getLinks = (SLSGetDisplayOutputModeLinkDescriptionsFunc)dlsym(h, "SLSGetDisplayOutputModeLinkDescriptions");
        setOut = (SLSSetDisplayOutputModeFunc)dlsym(h, "SLSSetDisplayOutputMode");
    });
    if (!getLinks || !setOut) return false;

    int32_t curModeNum = MDP_GetCurrentDisplayModeNumber(displayID);
    if (curModeNum < 0) return false;

    uint32_t buf[64];
    memset(buf, 0, sizeof(buf));
    int32_t ioCount = 16;
    int32_t currentIdx = -1;
    if (getLinks(displayID, curModeNum, buf, &ioCount, &currentIdx) != 0 || ioCount <= 0) {
        return false;
    }

    // Each link description is 4 x uint32_t: [bitDepth, dynamicRange (1=Full, 0=Limited), eotf (0=SDR, 2=HDR), pixelEncoding (0=RGB444, 1/2/3=YCbCr)]
    int bestIdx = -1;
    int bestScore = -100000;

    for (int i = 0; i < ioCount; i++) {
        uint32_t bpc   = buf[i * 4 + 0];
        uint32_t range = buf[i * 4 + 1];
        uint32_t eotf  = buf[i * 4 + 2];
        uint32_t enc   = buf[i * 4 + 3];

        int score = 0;
        if (preferRGB444) {
            // Strongly prioritize Pure RGB 4:4:4 (enc == 0) + Full Range 0-255 (range == 1) + SDR Gamma (eotf == 0)
            if (enc == 0) score += 10000;
            if (range == 1) score += 2000;
            if (eotf == 0) score += 500;
            score += (int)bpc * 10;
        } else {
            // Match requested hardware bit depth (e.g. 10-bit or 12-bit), preferring RGB 4:4:4 if available at that bpc
            if (bpc == targetBpc) score += 5000;
            else if (bpc > targetBpc) score += 1000;
            if (enc == 0) score += 2000;
            if (range == 1) score += 500;
        }

        if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
        }
    }

    if (bestIdx < 0) return false;
    uint32_t chosenBpc   = buf[bestIdx * 4 + 0];
    uint32_t chosenRange = buf[bestIdx * 4 + 1];
    uint32_t chosenEotf  = buf[bestIdx * 4 + 2];
    uint32_t chosenEnc   = buf[bestIdx * 4 + 3];

    uint64_t x1 = (uint64_t)chosenBpc | ((uint64_t)chosenRange << 32);
    uint64_t x2 = (uint64_t)chosenEotf | ((uint64_t)chosenEnc << 32);
    return (setOut(displayID, x1, x2) == 0);
}

bool MDP_SetExactLinkDescription(CGDirectDisplayID displayID, uint32_t bitDepth, uint32_t range, uint32_t eotf, uint32_t encoding) {
    void *h = MDP_GetSkyLightHandle();
    if (!h) return false;

    static SLSSetDisplayOutputModeFunc setOut = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        setOut = (SLSSetDisplayOutputModeFunc)dlsym(h, "SLSSetDisplayOutputMode");
    });
    if (!setOut) return false;

    uint64_t x1 = (uint64_t)bitDepth | ((uint64_t)range << 32);
    uint64_t x2 = (uint64_t)eotf     | ((uint64_t)encoding << 32);
    return (setOut(displayID, x1, x2) == 0);
}

MDP_HardwareTelemetry MDP_GetDisplayHardwareTelemetry(CGDirectDisplayID displayID) {
    MDP_HardwareTelemetry info;
    memset(&info, 0, sizeof(info));
    info.maxBpc = 10;
    info.maxPixelRateMHz = 594;
    info.maxGPUSrcBufferWidth = 16384;
    info.currentCGSDepthCode = 8;
    info.activeLinkBitDepth = 8;
    info.activePixelEncoding = 0;
    info.activeDynamicRange = 1;
    info.supports10BitMode = true;

    // 1. Check current CGS Mode depth & active SkyLight LinkDescription
    int32_t curModeNum = MDP_GetCurrentDisplayModeNumber(displayID);
    int32_t nModes = MDP_GetNumberOfDisplayModes(displayID);
    for (int32_t i = 0; i < nModes; i++) {
        MDP_CGSDisplayModeDescription desc;
        if (MDP_GetDisplayModeDescription(displayID, i, &desc)) {
            if ((int32_t)desc.modeNumber == curModeNum) {
                info.currentCGSDepthCode = desc.depth;
                break;
            }
        }
    }

    void *h = MDP_GetSkyLightHandle();
    if (h && curModeNum >= 0) {
        static SLSGetDisplayOutputModeLinkDescriptionsFunc getLinks = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            getLinks = (SLSGetDisplayOutputModeLinkDescriptionsFunc)dlsym(h, "SLSGetDisplayOutputModeLinkDescriptions");
        });
        if (getLinks) {
            uint32_t buf[64];
            memset(buf, 0, sizeof(buf));
            int32_t ioCount = 16;
            int32_t currentIdx = -1;
            if (getLinks(displayID, curModeNum, buf, &ioCount, &currentIdx) == 0 && currentIdx >= 0 && currentIdx < ioCount) {
                info.activeLinkBitDepth  = buf[currentIdx * 4 + 0];
                info.activeDynamicRange  = buf[currentIdx * 4 + 1];
                info.activeEOTF          = buf[currentIdx * 4 + 2];
                info.activePixelEncoding = buf[currentIdx * 4 + 3];
            }
        }
    }

    // 2. Traverse IOMobileFramebufferAP / IORegistry for DisplayHints & TimingElements
    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferAP"), &iter) == KERN_SUCCESS && iter != IO_OBJECT_NULL) {
        io_service_t serv = IO_OBJECT_NULL;
        while ((serv = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
            CFTypeRef hintsRef = IORegistryEntrySearchCFProperty(serv, kIOServicePlane, CFSTR("DisplayHints"), kCFAllocatorDefault, kIORegistryIterateRecursively);
            if (hintsRef && CFGetTypeID(hintsRef) == CFDictionaryGetTypeID()) {
                NSDictionary *hints = (__bridge NSDictionary *)hintsRef;
                NSNumber *bpc = hints[@"MaxBpc"];
                NSNumber *rate = hints[@"MaxTotalPixelRate"];
                if (bpc) {
                    info.maxBpc = bpc.unsignedIntValue;
                    if (info.maxBpc >= 12) info.supports12BitMode = true;
                }
                if (rate && rate.unsignedIntValue > 0) {
                    info.maxPixelRateMHz = rate.unsignedIntValue / 1000000;
                }
            }
            if (hintsRef) CFRelease(hintsRef);

            CFTypeRef maxSrcRef = IORegistryEntrySearchCFProperty(serv, kIOServicePlane, CFSTR("IOMFBMaxSrcPixels"), kCFAllocatorDefault, kIORegistryIterateRecursively);
            if (maxSrcRef && CFGetTypeID(maxSrcRef) == CFDictionaryGetTypeID()) {
                NSDictionary *maxSrc = (__bridge NSDictionary *)maxSrcRef;
                NSNumber *maxW = maxSrc[@"MaxSrcBufferWidth"];
                if (maxW) info.maxGPUSrcBufferWidth = maxW.unsignedIntValue;
            }
            if (maxSrcRef) CFRelease(maxSrcRef);

            CFTypeRef timingRef = IORegistryEntrySearchCFProperty(serv, kIOServicePlane, CFSTR("TimingElements"), kCFAllocatorDefault, kIORegistryIterateRecursively);
            if (timingRef && CFGetTypeID(timingRef) == CFArrayGetTypeID()) {
                NSArray *timings = (__bridge NSArray *)timingRef;
                for (NSDictionary *elem in timings) {
                    if (![elem isKindOfClass:[NSDictionary class]]) continue;
                    NSArray *colorModes = elem[@"ColorModes"];
                    if (![colorModes isKindOfClass:[NSArray class]]) continue;
                    for (NSDictionary *cm in colorModes) {
                        if (![cm isKindOfClass:[NSDictionary class]]) continue;
                        NSNumber *depth = cm[@"Depth"];
                        NSNumber *eotf = cm[@"EOTF"];
                        if (depth.intValue >= 12) info.supports12BitMode = true;
                        if (depth.intValue >= 10) info.supports10BitMode = true;
                        if (eotf.intValue == 2) info.supportsHDR10EOTF = true;
                    }
                }
            }
            if (timingRef) CFRelease(timingRef);

            IOObjectRelease(serv);
        }
        IOObjectRelease(iter);
    }

    return info;
}

bool MDP_LockHighestBitDepthForCurrentMode(CGDirectDisplayID displayID) {
    int32_t curModeNum = MDP_GetCurrentDisplayModeNumber(displayID);
    int32_t nModes = MDP_GetNumberOfDisplayModes(displayID);
    if (curModeNum < 0 || nModes <= 0) return false;

    MDP_CGSDisplayModeDescription curDesc;
    bool foundCur = false;
    for (int32_t i = 0; i < nModes; i++) {
        if (MDP_GetDisplayModeDescription(displayID, i, &curDesc) && (int32_t)curDesc.modeNumber == curModeNum) {
            foundCur = true;
            break;
        }
    }
    if (!foundCur) return false;

    int32_t bestModeNum = curModeNum;
    uint32_t bestDepth = curDesc.depth;

    for (int32_t i = 0; i < nModes; i++) {
        MDP_CGSDisplayModeDescription candidate;
        if (MDP_GetDisplayModeDescription(displayID, i, &candidate)) {
            if (candidate.width == curDesc.width &&
                candidate.height == curDesc.height &&
                candidate.freq == curDesc.freq &&
                fabsf(candidate.density - curDesc.density) < 0.1f) {
                if (candidate.depth > bestDepth) {
                    bestDepth = candidate.depth;
                    bestModeNum = (int32_t)candidate.modeNumber;
                }
            }
        }
    }

    if (bestModeNum != curModeNum) {
        return MDP_SetDisplayModeNumber(displayID, bestModeNum);
    }
    if (!CGDisplayIsBuiltin(displayID)) {
        MDP_ForceRGB444FullRangeLink(displayID);
    }
    return true;
}

NSURL * _Nullable MDP_CopyCurrentColorProfileURL(CGDirectDisplayID displayID) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) return nil;

    CFDictionaryRef info = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, uuid);
    CFRelease(uuid);
    if (!info) return nil;

    NSDictionary *dict = (__bridge_transfer NSDictionary *)info;
    NSDictionary *factory = dict[(__bridge NSString *)kColorSyncFactoryProfiles];
    NSString *defID = @"1";
    if ([factory isKindOfClass:[NSDictionary class]]) {
        NSString *foundID = factory[(__bridge NSString *)kColorSyncDeviceDefaultProfileID];
        if ([foundID isKindOfClass:[NSString class]] && foundID.length > 0) {
            defID = foundID;
        }
    }

    NSDictionary *custom = dict[(__bridge NSString *)kColorSyncCustomProfiles];
    if ([custom isKindOfClass:[NSDictionary class]]) {
        NSURL *url = custom[defID] ?: custom[@"1"] ?: custom.allValues.firstObject;
        if ([url isKindOfClass:[NSURL class]]) {
            return url;
        }
    }

    if ([factory isKindOfClass:[NSDictionary class]]) {
        NSDictionary *entry = factory[defID];
        if ([entry isKindOfClass:[NSDictionary class]]) {
            NSURL *url = entry[(__bridge NSString *)kColorSyncDeviceProfileURL];
            if ([url isKindOfClass:[NSURL class]]) {
                return url;
            }
        }
    }
    return nil;
}

bool MDP_SetDisplayColorProfileURL(CGDirectDisplayID displayID, NSURL * _Nullable profileURL) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) return false;

    // Dynamically discover the exact profile slot key (e.g. "HDMI HD" on Apple Silicon HDMI, or "1" on DP/built-in)
    // Passing any key not present in FactoryProfiles causes ColorSyncDeviceSetCustomProfiles to reject the entire dictionary!
    NSString *defID = @"1";
    CFDictionaryRef info = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, uuid);
    if (info) {
        NSDictionary *dict = (__bridge_transfer NSDictionary *)info;
        NSDictionary *factory = dict[(__bridge NSString *)kColorSyncFactoryProfiles];
        if ([factory isKindOfClass:[NSDictionary class]]) {
            NSString *foundID = factory[(__bridge NSString *)kColorSyncDeviceDefaultProfileID];
            if ([foundID isKindOfClass:[NSString class]] && foundID.length > 0) {
                defID = foundID;
            } else {
                for (NSString *k in factory.allKeys) {
                    if (![k isEqualToString:(__bridge NSString *)kColorSyncDeviceDefaultProfileID]) {
                        defID = k;
                        break;
                    }
                }
            }
        }
    }

    CFTypeRef val = profileURL ? (__bridge CFURLRef)profileURL : kCFNull;
    NSDictionary *customDict = @{
        defID: (__bridge id)val,
        (__bridge NSString *)kColorSyncProfileUserScope: (__bridge id)kCFPreferencesCurrentUser
    };

    bool ok = ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass, uuid, (__bridge CFDictionaryRef)customDict);
    CFRelease(uuid);
    return ok;
}
