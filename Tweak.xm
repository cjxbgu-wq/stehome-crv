// ============================================================================
// Vdcampro — 严格照参考源码版
// ============================================================================
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <unistd.h>
#include <string.h>
#include <math.h>
#include <zlib.h>

// ============================ 路径宏 ============================
#define VCAM_DIR   @"/var/jb/var/mobile/Library/vcamplus"
#define VCAM_VIDEO VCAM_DIR @"/video.mp4"
#define VCAM_IMAGE VCAM_DIR @"/image.jpg"
#define VCAM_FLAG  VCAM_DIR @"/enabled"
#define VCAM_LOG   VCAM_DIR @"/debug.log"
#define VCAM_ACTIONS VCAM_DIR @"/actions.plist"
#define VCAM_LICENSE VCAM_DIR @"/license.vcam"
#define VCAM_LICENSE_STATE VCAM_DIR @"/license-state.plist"
#define VCAM_DEVICE_SEED VCAM_DIR @"/device-seed"
#define VCAM123_TEMP_MOV @"/var/jb/var/mobile/Library/temp.mov"

// 只内置 RSA 公钥；签发私钥绝不放入插件。卡密格式：VCAM1.payload.signature
static NSString *const kVCAMLicensePublicKey = @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzfGTRh3CX6mO9v8mAJQm+ZUwBiKCNaENUytrsQp5Tx061AyyU5NRfmlrz5O9CKfoq8+dvOwpJaa9jVdYxdzJGxacN5q4XWg82GQdjh/klcw9tZxP3jlTy4n4GvekPaYu9nEmTzgko0ZoyOjpqOCV19jElPnh5N05YpZnonrjk2rRz6vPHYmwNWD3CFQrvn6r6L0C1uxcS3wbPNCt/Dzcmjubasggv6vlPVwgLKRw2DQ7jFKyZioesCazLr/RfR9KNnKSI7ZIozMaOjrgKgacF2NeXkAQ2dWbgseYBcXMBx3qTcmyCU/RjvceMLDybAFtxpg0DcbSBHjocvkktHOO2QIDAQAB";

// ============================ MSHook 声明 ============================
#ifdef __cplusplus
extern "C" {
#endif
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);
#ifdef __cplusplus
}
#endif
typedef void (*MSHookFunction_t)(void *, void *, void **);
static MSHookFunction_t _pMSHookFunction = NULL;

// ============================ 前向声明 ============================
static void vcam_hookPHAsset(void);
static void vcam_hookClass(Class cls);
static void vcam_isaSwizzleDelegate(id delegate);
static void vcam_installHooks(void);
static void vcam_installWebCamHook(void);
static void vcam_webcontent_installHooks(void);
static void vcam_hookMetadataDelegate(Class dcls);
static void vcam_hookPhotoCaptureOnClass(Class cls);
static void vcam_hookPhotoDataOnClass(Class cls);
static void vcam_hookPhotoDelegate(Class cls);
static void vcam_hookRecordingDelegate(Class cls);
static CIImage *vcam_applyVideoTransforms(CIImage *img);
static BOOL vcam_licenseIsValid(void);
static NSString *vcam_deviceCode(void);

// ============================ PHPicker 声明 ============================
@class PHPickerViewController, PHPickerResult, PHPickerConfiguration, PHPickerFilter;
@protocol PHPickerViewControllerDelegate <NSObject>
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results;
@end
@interface PHPickerFilter : NSObject
+ (PHPickerFilter *)videosFilter;
+ (PHPickerFilter *)imagesFilter;
@end
@interface PHPickerConfiguration : NSObject
- (instancetype)init;
@property (nonatomic, copy) PHPickerFilter *filter;
@property (nonatomic) NSInteger selectionLimit;
@property (nonatomic) NSInteger preferredAssetRepresentationMode;
@end
@interface PHPickerViewController : UIViewController
- (instancetype)initWithConfiguration:(PHPickerConfiguration *)configuration;
@property (nonatomic, weak) id<PHPickerViewControllerDelegate> delegate;
@end
@interface PHPickerResult : NSObject
@property (nonatomic, strong) NSItemProvider *itemProvider;
@end

// ============================ IOSurface / ImageIO ============================
typedef struct __IOSurface *IOSurfaceRef;
extern "C" size_t IOSurfaceGetWidth(IOSurfaceRef surface);
extern "C" size_t IOSurfaceGetHeight(IOSurfaceRef surface);
extern "C" uint32_t IOSurfaceGetPixelFormat(IOSurfaceRef surface);
extern "C" size_t IOSurfaceGetAllocSize(IOSurfaceRef surface);
extern "C" size_t IOSurfaceGetBytesPerRow(IOSurfaceRef surface);
extern "C" int IOSurfaceLock(IOSurfaceRef surface, uint32_t options, uint32_t *seed);
extern "C" int IOSurfaceUnlock(IOSurfaceRef surface, uint32_t options, uint32_t *seed);
extern "C" void *IOSurfaceGetBaseAddress(IOSurfaceRef surface);
extern "C" IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port);

typedef struct CGImageSource *CGImageSourceRef;
extern "C" CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options);
extern "C" CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef src, size_t index, CFDictionaryRef options);

// ============================ PH 框架接口 ============================
@interface PHFetchOptions : NSObject
@property (nonatomic, copy) NSArray *sortDescriptors;
@property (nonatomic, assign) NSUInteger fetchLimit;
@end
@interface PHAsset : NSObject
+ (id)fetchAssetsWithMediaType:(NSInteger)mediaType options:(PHFetchOptions *)options;
- (void)requestContentEditingInputWithOptions:(id)options completionHandler:(void (^)(id input, NSDictionary *info))completionHandler;
@end
@interface PHFetchResult : NSObject
@property (nonatomic, readonly) NSUInteger count;
- (id)firstObject;
@end
@interface PHAdjustmentData : NSObject
- (instancetype)initWithFormatIdentifier:(NSString *)formatIdentifier formatVersion:(NSString *)formatVersion data:(NSData *)data;
@end
@interface PHContentEditingInput : NSObject
@property (nonatomic, readonly) NSURL *fullSizeImageURL;
@end
@interface PHContentEditingOutput : NSObject
- (instancetype)initWithContentEditingInput:(id)contentEditingInput;
@property (nonatomic, readonly) NSURL *renderedContentURL;
@property (nonatomic, strong) PHAdjustmentData *adjustmentData;
@end
@interface PHAssetChangeRequest : NSObject
+ (instancetype)changeRequestForAsset:(PHAsset *)asset;
+ (id)creationRequestForAssetFromImage:(id)image;
+ (id)creationRequestForAssetFromImageAtFileURL:(NSURL *)url;
+ (id)creationRequestForAssetFromVideoAtFileURL:(NSURL *)url;
@property (nonatomic, strong) PHContentEditingOutput *contentEditingOutput;
@end
@interface PHPhotoLibrary : NSObject
+ (PHPhotoLibrary *)sharedPhotoLibrary;
- (void)performChanges:(void (^)(void))changeBlock completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
@end

// ============================ WKWebView ============================
@interface WKUserScript : NSObject
- (instancetype)initWithSource:(NSString *)source injectionTime:(NSInteger)injectionTime forMainFrameOnly:(BOOL)forMainFrameOnly;
@end
@interface WKUserContentController : NSObject
- (void)addUserScript:(WKUserScript *)userScript;
@end

// ============================ 全局 ============================
static BOOL gTweakEnabled = NO;
static NSLock *gLockA = nil, *gLockB = nil, *gLockPT = nil;
static AVAssetReader *gReaderA = nil, *gReaderB = nil, *gReaderPT = nil;
static AVAssetReaderTrackOutput *gOutputA = nil, *gOutputB = nil, *gOutputPT = nil;
static CIContext *gCICtx = nil;
static CIImage *gStaticImage = nil;
static CGImageRef gStaticCGImage = NULL;
static NSMutableSet *gHookIMPs = nil;
static NSMutableSet *gISASwizzledObjects = nil;
static NSMutableSet *gHookedClasses = nil;
static NSMutableSet *gHookedPhotoClasses = nil;
static NSMutableSet *gHookedPhotoCaptureClasses = nil;
static NSMutableSet *gMetaHookedIMPs = nil;
static NSMutableArray *gOverlays = nil;
static char kOverlayKey;
static Class gPreviewLayerClass = nil;
static Class gFakeFaceClass = nil;
static CGRect gFakeFaceBounds = {{0.25, 0.2}, {0.5, 0.5}};
static BOOL gCameraSessionActive = NO;
static NSTimeInterval gLastCaptureTime = 0;
static size_t gLastPhotoW = 0, gLastPhotoH = 0;
static BOOL gIsVCamEditing = NO;
static BOOL gPHAssetHooked = NO;

static int gVideoIndex = 0;
static int gVideoRotation = 0;
static BOOL gVideoFlipH = NO;
static BOOL gVideoPaused = NO;
static CIImage *gPausedFrame = nil;
static CGFloat gVideoOffsetX = 0;
static CGFloat gVideoOffsetY = 0;

static CMSampleBufferRef gPTFrameCache = NULL;
static NSLock *gPTCacheLock = nil;
static dispatch_source_t gPTDecodeTimer = NULL;
static OSType gPTCacheFmt = 0;
static dispatch_queue_t gPTCacheQ = nil;

// 动作播放：配置由 SpringBoard 写入，各 App 进程按 token 同步。
static NSInteger gActionToken = 0;
static NSInteger gActionActive = 0;
static int64_t gActionStartUs = 0;
static int64_t gActionEndUs = 1000000;
static BOOL gActionInited = NO;
static CMSampleBufferRef gActionFrozenA = NULL;
static CMSampleBufferRef gActionFrozenB = NULL;
static CMSampleBufferRef gActionFrozenPT = NULL;
static BOOL gActionFinishedA = NO, gActionFinishedB = NO, gActionFinishedPT = NO;
static OSType gActionFrozenPTFmt = 0;

static BOOL gIsRecordingVideo = NO;
static NSURL *gVirtualRecordingURL = nil;
static id gRecWriter = nil, gRecWriterInput = nil, gRecWriterAdaptor = nil;
static BOOL gRecSessionStarted = NO;
static dispatch_queue_t gRecQueue = nil;
static dispatch_source_t gRecTimer = nil;
static int gRecFrameCount = 0;
static size_t gRecWidth = 0, gRecHeight = 0;
static NSURL *gRecOriginalURL = nil;
static NSString *_cachedBID = nil;
static BOOL _isWeChat = NO;

// IOSurface 函数指针
static int (*iosurf_Lock)(void *, uint32_t, uint32_t *) = NULL;
static int (*iosurf_Unlock)(void *, uint32_t, uint32_t *) = NULL;
static void *(*iosurf_GetBaseAddress)(void *) = NULL;
static size_t (*iosurf_GetWidth)(void *) = NULL;
static size_t (*iosurf_GetHeight)(void *) = NULL;
static size_t (*iosurf_GetBytesPerRow)(void *) = NULL;
static uint32_t (*iosurf_GetPixelFormat)(void *) = NULL;
static size_t (*iosurf_GetAllocSize)(void *) = NULL;
static BOOL gIOSurfFuncsLoaded = NO;

static void vcam_loadIOSurfaceFuncs(void) {
    if (gIOSurfFuncsLoaded) return;
    gIOSurfFuncsLoaded = YES;
    void *h = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
    if (!h) return;
    iosurf_Lock = (int (*)(void *, uint32_t, uint32_t *))dlsym(h, "IOSurfaceLock");
    iosurf_Unlock = (int (*)(void *, uint32_t, uint32_t *))dlsym(h, "IOSurfaceUnlock");
    iosurf_GetBaseAddress = (void *(*)(void *))dlsym(h, "IOSurfaceGetBaseAddress");
    iosurf_GetWidth = (size_t (*)(void *))dlsym(h, "IOSurfaceGetWidth");
    iosurf_GetHeight = (size_t (*)(void *))dlsym(h, "IOSurfaceGetHeight");
    iosurf_GetBytesPerRow = (size_t (*)(void *))dlsym(h, "IOSurfaceGetBytesPerRow");
    iosurf_GetPixelFormat = (uint32_t (*)(void *))dlsym(h, "IOSurfaceGetPixelFormat");
    iosurf_GetAllocSize = (size_t (*)(void *))dlsym(h, "IOSurfaceGetAllocSize");
}

// ============================ 基础 ============================
static void vcam_log(NSString *msg) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:VCAM_LOG]) [fm createFileAtPath:VCAM_LOG contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:VCAM_LOG];
        NSString *line = [NSString stringWithFormat:@"[%@] %@: %@\n", [NSDate date],
                          [[NSProcessInfo processInfo] processName], msg];
        [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile];
    } @catch (NSException *e) {}
}

// ============================ 设备码与签名卡密 ============================
static NSData *vcam_base64URLDecode(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return nil;
    NSMutableString *s = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    [s replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, s.length)];
    while (s.length % 4) [s appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:s options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

static NSString *vcam_deviceCode(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *rawID = nil;
        @try {
            void *mg = dlopen("/System/Library/PrivateFrameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
            if (mg) {
                typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef);
                MGCopyAnswerFn copyAnswer = (MGCopyAnswerFn)dlsym(mg, "MGCopyAnswer");
                if (copyAnswer) {
                    CFTypeRef value = copyAnswer(CFSTR("UniqueDeviceID"));
                    if (value) {
                        if (CFGetTypeID(value) == CFStringGetTypeID()) rawID = [(__bridge NSString *)value copy];
                        CFRelease(value);
                    }
                }
            }
        } @catch (NSException *e) {}
        // 不使用 identifierForVendor：不同 App 进程可能得到不同值，会导致跨进程验签不一致。
        if (rawID.length == 0) {
            rawID = [NSString stringWithContentsOfFile:VCAM_DEVICE_SEED encoding:NSUTF8StringEncoding error:nil];
            if (rawID.length == 0) {
                rawID = [[NSUUID UUID] UUIDString];
                [rawID writeToFile:VCAM_DEVICE_SEED atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        NSString *material = [NSString stringWithFormat:@"com.yourname.vdcampro.device.v1|%@", rawID ?: @""];
        const char *bytes = material.UTF8String;
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);
        NSMutableString *hex = [NSMutableString stringWithCapacity:32];
        for (int i = 0; i < 16; i++) [hex appendFormat:@"%02X", digest[i]];
        NSMutableArray *groups = [NSMutableArray array];
        for (NSUInteger i = 0; i < 32; i += 4) [groups addObject:[hex substringWithRange:NSMakeRange(i, 4)]];
        cached = [groups componentsJoinedByString:@"-"];
    });
    return cached;
}

// 返回已验签且绑定本机的 payload；任何格式、签名、设备或有效期错误均失败。
static NSDictionary *vcam_verifyLicenseCard(NSString *card, NSString **errorOut) {
    if (errorOut) *errorOut = nil;
    NSString *clean = [card stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *parts = [clean componentsSeparatedByString:@"."];
    if (parts.count != 3 || ![parts[0] isEqualToString:@"VCAM1"]) {
        if (errorOut) *errorOut = @"卡密格式不正确";
        return nil;
    }
    NSData *payloadData = vcam_base64URLDecode(parts[1]);
    NSData *signature = vcam_base64URLDecode(parts[2]);
    NSData *publicDER = [[NSData alloc] initWithBase64EncodedString:kVCAMLicensePublicKey options:0];
    if (!payloadData || !signature || !publicDER) {
        if (errorOut) *errorOut = @"卡密编码不完整";
        return nil;
    }
    NSDictionary *attrs = @{
        (__bridge NSString *)kSecAttrKeyType: (__bridge NSString *)kSecAttrKeyTypeRSA,
        (__bridge NSString *)kSecAttrKeyClass: (__bridge NSString *)kSecAttrKeyClassPublic,
        (__bridge NSString *)kSecAttrKeySizeInBits: @2048,
    };
    CFErrorRef createError = NULL;
    SecKeyRef publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicDER,
        (__bridge CFDictionaryRef)attrs, &createError);
    if (createError) { CFRelease(createError); createError = NULL; }
    if (!publicKey) {
        if (errorOut) *errorOut = @"内置公钥不可用";
        return nil;
    }
    CFErrorRef verifyError = NULL;
    BOOL signedOK = SecKeyVerifySignature(publicKey,
        kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
        (__bridge CFDataRef)payloadData, (__bridge CFDataRef)signature, &verifyError);
    CFRelease(publicKey);
    if (verifyError) { CFRelease(verifyError); verifyError = NULL; }
    if (!signedOK) {
        if (errorOut) *errorOut = @"卡密签名无效";
        return nil;
    }
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    NSString *device = [payload isKindOfClass:[NSDictionary class]] ? payload[@"device"] : nil;
    NSNumber *expires = [payload isKindOfClass:[NSDictionary class]] ? payload[@"expires"] : nil;
    NSNumber *issued = [payload isKindOfClass:[NSDictionary class]] ? payload[@"issued"] : nil;
    NSString *type = [payload isKindOfClass:[NSDictionary class]] ? payload[@"type"] : nil;
    if (![device isKindOfClass:[NSString class]] || ![expires isKindOfClass:[NSNumber class]] ||
        ![issued isKindOfClass:[NSNumber class]] || ![type isKindOfClass:[NSString class]]) {
        if (errorOut) *errorOut = @"卡密内容不完整";
        return nil;
    }
    if ([device caseInsensitiveCompare:vcam_deviceCode()] != NSOrderedSame) {
        if (errorOut) *errorOut = @"卡密与本机设备码不匹配";
        return nil;
    }
    BOOL permanent = [type isEqualToString:@"permanent"] && expires.longLongValue == 0;
    BOOL temporary = [type isEqualToString:@"temporary"] && expires.longLongValue > issued.longLongValue;
    if (!permanent && !temporary) {
        if (errorOut) *errorOut = @"卡密类型或有效期无效";
        return nil;
    }
    return payload;
}

static void vcam_resetLicenseCache(void);

static BOOL vcam_activateLicenseCard(NSString *card, NSString **errorOut) {
    NSDictionary *payload = vcam_verifyLicenseCard(card, errorOut);
    if (!payload) return NO;
    NSString *clean = [card stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL written = [clean writeToFile:VCAM_LICENSE atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (!written) {
        if (errorOut) *errorOut = @"激活状态写入失败，请检查插件目录权限";
        return NO;
    }
    [[NSFileManager defaultManager] removeItemAtPath:VCAM_LICENSE_STATE error:nil];
    vcam_resetLicenseCache();
    return YES;
}

static BOOL gLicenseCacheValid = NO;
static NSTimeInterval gLicenseCacheAt = 0;

static BOOL vcam_licenseIsValid(void) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval cacheAge = now - gLicenseCacheAt;
    if (gLicenseCacheAt > 0 && cacheAge >= 0 && cacheAge < 0.75) return gLicenseCacheValid;
    gLicenseCacheAt = now;
    gLicenseCacheValid = NO;
    NSString *card = [NSString stringWithContentsOfFile:VCAM_LICENSE encoding:NSUTF8StringEncoding error:nil];
    if (!card) return NO;
    NSDictionary *payload = vcam_verifyLicenseCard(card, nil);
    if (!payload) return NO;
    int64_t expires = [payload[@"expires"] longLongValue];
    if (expires > 0) {
        if ((int64_t)now >= expires) return NO;
        // 离线临时卡增加回拨检测；它不是联网时间服务的替代品。
        NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:VCAM_LICENSE_STATE];
        int64_t lastSeen = [state[@"lastSeen"] longLongValue];
        if (lastSeen > 0 && (int64_t)now + 300 < lastSeen) return NO;
        if (now > lastSeen + 60) {
            [@{@"lastSeen": @((int64_t)now)} writeToFile:VCAM_LICENSE_STATE atomically:YES];
        }
    }
    gLicenseCacheValid = YES;
    return YES;
}

static void vcam_resetLicenseCache(void) {
    gLicenseCacheAt = 0;
    gLicenseCacheValid = NO;
}

static NSString *vcam_licenseStatusText(void) {
    NSString *card = [NSString stringWithContentsOfFile:VCAM_LICENSE encoding:NSUTF8StringEncoding error:nil];
    if (!card) return @"未激活";
    NSString *error = nil;
    NSDictionary *payload = vcam_verifyLicenseCard(card, &error);
    if (!payload) return error ?: @"卡密无效";
    int64_t expires = [payload[@"expires"] longLongValue];
    if (expires == 0) return vcam_licenseIsValid() ? @"永久卡 · 已激活" : @"永久卡 · 当前不可用";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:expires];
    NSString *when = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    return vcam_licenseIsValid() ? [NSString stringWithFormat:@"临时卡 · 有效至 %@", when] : @"临时卡 · 已过期或时间异常";
}

static NSString *vcam_currentVideoPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *exts = @[@"mp4", @"MP4", @"mov", @"MOV", @"m4v", @"M4V"];
    if (gVideoIndex == 0) {
        if ([fm fileExistsAtPath:VCAM_VIDEO]) return VCAM_VIDEO;
    } else {
        for (NSString *ext in exts) {
            NSString *path = [NSString stringWithFormat:@"%@/%d.%@", VCAM_DIR, gVideoIndex, ext];
            if ([fm fileExistsAtPath:path]) return path;
        }
    }
    if ([fm fileExistsAtPath:VCAM_VIDEO]) return VCAM_VIDEO;
    for (int i = 1; i <= 3; i++) {
        for (NSString *ext in exts) {
            NSString *path = [NSString stringWithFormat:@"%@/%d.%@", VCAM_DIR, i, ext];
            if ([fm fileExistsAtPath:path]) return path;
        }
    }
    return VCAM_VIDEO;
}

static NSString *vcam_passthroughSourcePath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:VCAM123_TEMP_MOV]) return VCAM123_TEMP_MOV;
    return vcam_currentVideoPath();
}

static BOOL vcam_isBufferReplaceWhitelisted(void) {
    static int sCached = -1;
    if (sCached >= 0) return sCached == 1;
    @try {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
        static NSArray *whitelist = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            whitelist = @[
                @"jp.co.hyakugo.smaphobanking",
                @"com.bitkeep.os",
                @"com.MinnaNoGinko.bankapp",
            ];
        });
        sCached = [whitelist containsObject:bid] ? 1 : 0;
    } @catch (NSException *e) { sCached = 0; }
    return sCached == 1;
}

static BOOL vcam_flagExists(void) { return [[NSFileManager defaultManager] fileExistsAtPath:VCAM_FLAG]; }
static BOOL vcam_videoExists(void) { return [[NSFileManager defaultManager] fileExistsAtPath:vcam_currentVideoPath()]; }
static BOOL vcam_imageExists(void) { return [[NSFileManager defaultManager] fileExistsAtPath:VCAM_IMAGE]; }

static BOOL vcam_isEnabled(void) {
    if (!vcam_licenseIsValid()) { gTweakEnabled = NO; return NO; }
    if (!vcam_flagExists()) { gTweakEnabled = NO; return NO; }
    gTweakEnabled = YES;
    return vcam_videoExists() || vcam_imageExists();
}

static void vcam_switchVideo(int index);
static void vcam_writeControls(void);
static void vcam_force_write_controls(void);

// ============================ 六动作配置（参考源码的时间逻辑） ============================
static NSString *vcam_actionName(NSInteger action) {
    NSArray *names = @[@"", @"眨眼", @"摇头", @"张嘴", @"左头", @"右头", @"点头"];
    return action >= 1 && action <= 6 ? names[action] : @"退出动作";
}

static void vcam_defaultActionRange(NSInteger action, int64_t *startUs, int64_t *endUs) {
    // 前三个沿用参考源码的眨／头／嘴默认区间，其余动作可长按自行修改。
    int64_t ranges[7][2] = {
        {0, 1000000}, {1000000, 2000000}, {4000000, 5500000},
        {2500000, 3500000}, {5500000, 6500000}, {6500000, 7500000}, {7500000, 8500000}
    };
    if (action < 1 || action > 6) action = 0;
    if (startUs) *startUs = ranges[action][0];
    if (endUs) *endUs = ranges[action][1];
}

static void vcam_actionRangeFromDictionary(NSDictionary *d, NSInteger action, int64_t *startUs, int64_t *endUs) {
    int64_t s = 0, e = 0;
    vcam_defaultActionRange(action, &s, &e);
    NSString *usS = [NSString stringWithFormat:@"action%ldStartUs", (long)action];
    NSString *usE = [NSString stringWithFormat:@"action%ldEndUs", (long)action];
    NSString *secS = [NSString stringWithFormat:@"action%ldStart", (long)action];
    NSString *secE = [NSString stringWithFormat:@"action%ldEnd", (long)action];
    NSNumber *n = d[usS];
    if (n) s = n.longLongValue;
    else if (d[secS]) s = (int64_t)llround([d[secS] doubleValue] * 1000000.0);
    n = d[usE];
    if (n) e = n.longLongValue;
    else if (d[secE]) e = (int64_t)llround([d[secE] doubleValue] * 1000000.0);
    if (s < 0) s = 0;
    if (e <= s) e = s + 100000;
    if (startUs) *startUs = s;
    if (endUs) *endUs = e;
}

static void vcam_updateActions(void (^block)(NSMutableDictionary *d)) {
    @synchronized(@"com.vdcampro.actions") {
        NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:VCAM_ACTIONS];
        NSMutableDictionary *d = old ? [old mutableCopy] : [NSMutableDictionary dictionary];
        block(d);
        [d writeToFile:VCAM_ACTIONS atomically:YES];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vdcampro.actionChanged"), NULL, NULL, YES);
}

static void vcam_resetActionReaders(void) {
    if (gLockA) { [gLockA lock]; gReaderA = nil; gOutputA = nil; [gLockA unlock]; }
    if (gLockB) { [gLockB lock]; gReaderB = nil; gOutputB = nil; [gLockB unlock]; }
    if (gLockPT) { [gLockPT lock]; gReaderPT = nil; gOutputPT = nil; [gLockPT unlock]; }
    if (gActionFrozenA) { CFRelease(gActionFrozenA); gActionFrozenA = NULL; }
    if (gActionFrozenB) { CFRelease(gActionFrozenB); gActionFrozenB = NULL; }
    if (gActionFrozenPT) { CFRelease(gActionFrozenPT); gActionFrozenPT = NULL; }
    gActionFinishedA = gActionFinishedB = gActionFinishedPT = NO;
    gActionFrozenPTFmt = 0;
    gPausedFrame = nil;
}

static void vcam_checkAction(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:VCAM_ACTIONS];
    NSInteger token = [d[@"actionToken"] integerValue];
    NSInteger action = [d[@"actionActive"] integerValue];
    if (!gActionInited) {
        gActionInited = YES;
        gActionToken = token;
        if (action >= 1 && action <= 6) {
            gActionActive = action;
            vcam_actionRangeFromDictionary(d, action, &gActionStartUs, &gActionEndUs);
            vcam_resetActionReaders();
        }
        return;
    }
    if (token == gActionToken) return;
    gActionToken = token;
    gActionActive = (action >= 1 && action <= 6) ? action : 0;
    if (gActionActive) vcam_actionRangeFromDictionary(d, action, &gActionStartUs, &gActionEndUs);
    vcam_resetActionReaders();
}

static void vcam_triggerAction(NSInteger action) {
    if (action < 0 || action > 6) return;
    vcam_updateActions(^(NSMutableDictionary *d) {
        d[@"actionToken"] = @([d[@"actionToken"] integerValue] + 1);
        d[@"actionActive"] = @(action);
    });
}

static void vcam_readControls(void) {
    if (!vcam_licenseIsValid()) { gTweakEnabled = NO; return; }
    static NSTimeInterval sLastRead = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - sLastRead < 0.3) return;
    sLastRead = now;
    vcam_checkAction();
    @try {
        NSString *content = [NSString stringWithContentsOfFile:VCAM_FLAG encoding:NSUTF8StringEncoding error:nil];
        if (!content || content.length < 3) return;
        NSArray *parts = [content componentsSeparatedByString:@","];
        if (parts.count < 7) return;
        int newIndex = [parts[1] intValue];
        if (newIndex != gVideoIndex) vcam_switchVideo(newIndex);
        gVideoRotation = [parts[2] intValue];
        gVideoFlipH = [parts[3] intValue] != 0;
        BOOL newPaused = [parts[4] intValue] != 0;
        if (newPaused != gVideoPaused) gPausedFrame = nil;
        gVideoPaused = newPaused;
        gVideoOffsetX = [parts[5] doubleValue];
        gVideoOffsetY = [parts[6] doubleValue];
    } @catch (NSException *e) {}
}

static void vcam_force_write_controls(void) {
    @try {
        if (!vcam_licenseIsValid()) { gTweakEnabled = NO; return; }
        NSString *line = [NSString stringWithFormat:@"1,%d,%d,%d,%d,%.4f,%.4f",
            gVideoIndex, gVideoRotation, (int)gVideoFlipH, (int)gVideoPaused,
            gVideoOffsetX, gVideoOffsetY];
        [line writeToFile:VCAM_FLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.vdcampro.controlsChanged"), NULL, NULL, YES);
    } @catch (NSException *e) {}
}

static void vcam_writeControls(void) {
    @try {
        if (!gTweakEnabled) return;
        if (![[NSFileManager defaultManager] fileExistsAtPath:VCAM_FLAG]) return;
        vcam_force_write_controls();
    } @catch (NSException *e) {}
}

static void vcam_switchVideo(int index) {
    gVideoIndex = index;
    if (gLockA) { [gLockA lock]; gReaderA = nil; gOutputA = nil; [gLockA unlock]; }
    if (gLockB) { [gLockB lock]; gReaderB = nil; gOutputB = nil; [gLockB unlock]; }
    if (gLockPT) { [gLockPT lock]; gReaderPT = nil; gOutputPT = nil; [gLockPT unlock]; }
    gPausedFrame = nil;
    if (gStaticCGImage) { CGImageRelease(gStaticCGImage); gStaticCGImage = NULL; }
}

static CIImage *vcam_loadStaticImage(void) {
    // 缓存只保存原图；每次按当前控制值应用旋转／翻转，避免按钮更新后仍用旧方向。
    if (gStaticImage) return vcam_applyVideoTransforms(gStaticImage);
    @try {
        NSData *data = [NSData dataWithContentsOfFile:VCAM_IMAGE];
        if (!data) return nil;
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!src) return nil;
        CGImageRef cgImg = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        CFRelease(src);
        if (!cgImg) return nil;
        gStaticImage = [CIImage imageWithCGImage:cgImg];
        CGImageRelease(cgImg);
        return vcam_applyVideoTransforms(gStaticImage);
    } @catch (NSException *e) { return nil; }
}

// ============================ Reader ============================
static void vcam_applyActionTimeRange(AVAssetReader *reader, AVURLAsset *asset) {
    if (!reader || gActionActive < 1 || gActionActive > 6) return;
    int64_t start = MAX(0, gActionStartUs);
    int64_t end = MAX(start + 100000, gActionEndUs);
    double duration = CMTimeGetSeconds(asset.duration);
    if (duration > 0.05) {
        int64_t durationUs = (int64_t)llround(duration * 1000000.0);
        if (end > durationUs) end = durationUs;
        if (start >= durationUs - 10000) start = 0;
    }
    if (end <= start + 1000) return;
    CMTime startTime = CMTimeMake(start, 1000000);
    CMTime endTime = CMTimeMake(end, 1000000);
    reader.timeRange = CMTimeRangeMake(startTime, CMTimeSubtract(endTime, startTime));
}

static BOOL vcam_openReader(AVAssetReader *__strong *rdr, AVAssetReaderTrackOutput *__strong *out) {
    @try {
        *rdr = nil; *out = nil;
        if (!vcam_videoExists()) return NO;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:vcam_currentVideoPath()]
                             options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) return NO;
        NSError *err = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&err];
        if (!reader || err) return NO;
        NSDictionary *s = @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:tracks[0] outputSettings:s];
        output.alwaysCopiesSampleData = NO;
        if (![reader canAddOutput:output]) return NO;
        [reader addOutput:output];
        vcam_applyActionTimeRange(reader, asset);
        if (![reader startReading]) return NO;
        *rdr = reader; *out = output; return YES;
    } @catch (NSException *e) { return NO; }
}

static BOOL vcam_openReaderForFmt(OSType fmt, AVAssetReader *__strong *rdr, AVAssetReaderTrackOutput *__strong *out) {
    @try {
        *rdr = nil; *out = nil;
        NSString *path = vcam_passthroughSourcePath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (!path || ![fm fileExistsAtPath:path]) return NO;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
                             options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) return NO;
        NSError *err = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&err];
        if (!reader || err) return NO;
        NSDictionary *s = @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(fmt),
                            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:tracks[0] outputSettings:s];
        output.alwaysCopiesSampleData = YES;
        if (![reader canAddOutput:output]) return NO;
        [reader addOutput:output];
        vcam_applyActionTimeRange(reader, asset);
        if (![reader startReading]) return NO;
        *rdr = reader; *out = output; return YES;
    } @catch (NSException *e) { return NO; }
}

static void vcam_actionChannel(AVAssetReader *__strong *rdr, CMSampleBufferRef **cache, BOOL **finished) {
    if (rdr == &gReaderA) { *cache = &gActionFrozenA; *finished = &gActionFinishedA; }
    else if (rdr == &gReaderB) { *cache = &gActionFrozenB; *finished = &gActionFinishedB; }
    else { *cache = &gActionFrozenPT; *finished = &gActionFinishedPT; }
}

static CMSampleBufferRef vcam_retainedSample(CMSampleBufferRef frame) {
    if (frame) CFRetain(frame);
    return frame;
}

static void vcam_updateActionCache(CMSampleBufferRef *slot, CMSampleBufferRef frame) {
    if (!slot || !frame) return;
    CMSampleBufferRef old = *slot;
    *slot = vcam_retainedSample(frame);
    if (old) CFRelease(old);
}

static CMSampleBufferRef vcam_readFrame(NSLock *lock, AVAssetReader *__strong *rdr, AVAssetReaderTrackOutput *__strong *out) {
    [lock lock];
    @try {
        CMSampleBufferRef *actionCache = NULL;
        BOOL *actionFinished = NULL;
        vcam_actionChannel(rdr, &actionCache, &actionFinished);
        BOOL inAction = gActionActive >= 1 && gActionActive <= 6;
        if (inAction && *actionFinished) {
            CMSampleBufferRef frozen = vcam_retainedSample(*actionCache);
            [lock unlock];
            return frozen;
        }
        if (!*rdr || (*rdr).status != AVAssetReaderStatusReading) vcam_openReader(rdr, out);
        CMSampleBufferRef frame = nil;
        if (*rdr) frame = [*out copyNextSampleBuffer];
        if (inAction) {
            if (frame) {
                vcam_updateActionCache(actionCache, frame);
            } else {
                // 与参考源码一致：动作区间解码结束后定格最后一帧，不自动回循环。
                *actionFinished = YES;
                CMSampleBufferRef frozen = vcam_retainedSample(*actionCache);
                [lock unlock];
                return frozen;
            }
        } else if (!frame) {
            if (vcam_openReader(rdr, out)) frame = [*out copyNextSampleBuffer];
        }
        [lock unlock]; return frame;
    } @catch (NSException *e) { [lock unlock]; return NULL; }
}

static CMSampleBufferRef vcam_readFrameFmt(OSType fmt, NSLock *lock, AVAssetReader *__strong *rdr, AVAssetReaderTrackOutput *__strong *out) {
    [lock lock];
    @try {
        BOOL inAction = gActionActive >= 1 && gActionActive <= 6;
        if (inAction && gActionFrozenPTFmt != fmt) {
            if (gActionFrozenPT) { CFRelease(gActionFrozenPT); gActionFrozenPT = NULL; }
            gActionFrozenPTFmt = fmt;
            gActionFinishedPT = NO;
            vcam_openReaderForFmt(fmt, rdr, out);
        }
        if (inAction && gActionFinishedPT) {
            CMSampleBufferRef frozen = vcam_retainedSample(gActionFrozenPT);
            [lock unlock];
            return frozen;
        }
        if (!*rdr || (*rdr).status != AVAssetReaderStatusReading) vcam_openReaderForFmt(fmt, rdr, out);
        CMSampleBufferRef frame = nil;
        if (*rdr) frame = [*out copyNextSampleBuffer];
        if (inAction) {
            if (frame) {
                vcam_updateActionCache(&gActionFrozenPT, frame);
                gActionFrozenPTFmt = fmt;
            } else {
                gActionFinishedPT = YES;
                CMSampleBufferRef frozen = vcam_retainedSample(gActionFrozenPT);
                [lock unlock];
                return frozen;
            }
        } else if (!frame) {
            if (vcam_openReaderForFmt(fmt, rdr, out)) frame = [*out copyNextSampleBuffer];
        }
        [lock unlock]; return frame;
    } @catch (NSException *e) { [lock unlock]; return NULL; }
}

// ============================ Passthrough 缓存 ============================
static void vcam_startPassthroughCache(OSType fmt) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPTCacheLock = [[NSLock alloc] init];
        gPTCacheQ = dispatch_queue_create("vcam.pt.decode", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_sync(gPTCacheQ, ^{
        if (gPTDecodeTimer && gPTCacheFmt == fmt) return;
        if (gPTDecodeTimer) { dispatch_source_cancel(gPTDecodeTimer); gPTDecodeTimer = NULL; }
        gPTCacheFmt = fmt;
        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        gPTDecodeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
        dispatch_source_set_timer(gPTDecodeTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                                  (uint64_t)(NSEC_PER_SEC / 30), (uint64_t)(NSEC_PER_SEC / 100));
        OSType localFmt = fmt;
        dispatch_source_set_event_handler(gPTDecodeTimer, ^{
            CMSampleBufferRef frame = vcam_readFrameFmt(localFmt, gLockPT, &gReaderPT, &gOutputPT);
            if (!frame) return;
            [gPTCacheLock lock];
            CMSampleBufferRef old = gPTFrameCache;
            gPTFrameCache = frame;
            [gPTCacheLock unlock];
            if (old) CFRelease(old);
        });
        dispatch_resume(gPTDecodeTimer);
    });
}

static CMSampleBufferRef vcam_takePassthroughCachedFrame(void) {
    if (!gPTCacheLock) return NULL;
    [gPTCacheLock lock];
    CMSampleBufferRef out = gPTFrameCache;
    if (out) CFRetain(out);
    [gPTCacheLock unlock];
    return out;
}

// ============================ CI 变换 ============================
static CIImage *vcam_aspectFill(CIImage *img, size_t targetW, size_t targetH) {
    CGRect ext = img.extent;
    CGFloat srcW = ext.size.width, srcH = ext.size.height;
    if (srcW <= 0 || srcH <= 0 || targetW == 0 || targetH == 0) return img;
    if ((size_t)srcW == targetW && (size_t)srcH == targetH) return img;
    CGFloat sx = (CGFloat)targetW / srcW, sy = (CGFloat)targetH / srcH;
    CGFloat scale = MAX(sx, sy);
    CGFloat scaledW = srcW * scale, scaledH = srcH * scale;
    img = [img imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGFloat cropX = (scaledW - targetW) / 2.0, cropY = (scaledH - targetH) / 2.0;
    img = [img imageByCroppingToRect:CGRectMake(ext.origin.x * scale + cropX, ext.origin.y * scale + cropY,
        (CGFloat)targetW, (CGFloat)targetH)];
    CGRect finalExt = img.extent;
    if (finalExt.origin.x != 0 || finalExt.origin.y != 0) {
        img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-finalExt.origin.x, -finalExt.origin.y)];
    }
    return img;
}

static CIImage *vcam_aspectFit(CIImage *img, size_t targetW, size_t targetH) {
    CGRect ext = img.extent;
    CGFloat srcW = ext.size.width, srcH = ext.size.height;
    if (srcW <= 0 || srcH <= 0 || targetW == 0 || targetH == 0) return img;
    if ((size_t)srcW == targetW && (size_t)srcH == targetH) return img;
    CGFloat sx = (CGFloat)targetW / srcW, sy = (CGFloat)targetH / srcH;
    CGFloat scale = MIN(sx, sy);
    CGFloat scaledW = srcW * scale, scaledH = srcH * scale;
    img = [img imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGFloat tx = ((CGFloat)targetW - scaledW) / 2.0 - ext.origin.x * scale;
    CGFloat ty = ((CGFloat)targetH - scaledH) / 2.0 - ext.origin.y * scale;
    img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(tx, ty)];
    CIImage *bg = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]]
                   imageByCroppingToRect:CGRectMake(0, 0, (CGFloat)targetW, (CGFloat)targetH)];
    return [img imageByCompositingOverImage:bg];
}

static CIImage *vcam_applyOffset(CIImage *img, size_t targetW, size_t targetH, CGFloat offX, CGFloat offY) {
    if (offX == 0 && offY == 0) return img;
    img = [img imageByClampingToExtent];
    CGFloat dx = offX * (CGFloat)targetW;
    CGFloat dy = -offY * (CGFloat)targetH;
    img = [img imageByCroppingToRect:CGRectMake(dx, dy, (CGFloat)targetW, (CGFloat)targetH)];
    CGRect ext = img.extent;
    if (ext.origin.x != 0 || ext.origin.y != 0) {
        img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y)];
    }
    return img;
}

static CIImage *vcam_applyVideoTransforms(CIImage *img) {
    if (!img) return nil;
    if (gVideoRotation == 90) img = [img imageByApplyingOrientation:kCGImagePropertyOrientationRight];
    else if (gVideoRotation == 180) img = [img imageByApplyingOrientation:kCGImagePropertyOrientationDown];
    else if (gVideoRotation == 270) img = [img imageByApplyingOrientation:kCGImagePropertyOrientationLeft];
    if (gVideoFlipH) {
        CGRect ext = img.extent;
        img = [img imageByApplyingTransform:CGAffineTransformMake(-1, 0, 0, 1, 2 * ext.origin.x + ext.size.width, 0)];
    }
    return img;
}

// ============================ 源获取 ============================
static CIImage *vcam_acquireSourceImage(CMSampleBufferRef *outFrameToRelease) {
    if (outFrameToRelease) *outFrameToRelease = NULL;
    @try {
        if (vcam_imageExists()) {
            CIImage *img = vcam_loadStaticImage();
            if (img) return img;
        }
        if (gVideoPaused && gPausedFrame) return vcam_applyVideoTransforms(gPausedFrame);
        CMSampleBufferRef frame = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
        if (!frame) return nil;
        CVImageBufferRef srcPB = CMSampleBufferGetImageBuffer(frame);
        if (!srcPB) { CFRelease(frame); return nil; }
        CIImage *img = [CIImage imageWithCVImageBuffer:srcPB];
        if (!img) { CFRelease(frame); return nil; }
        if (outFrameToRelease) *outFrameToRelease = frame;
        else CFRelease(frame);
        return vcam_applyVideoTransforms(img);
    } @catch (NSException *e) { return nil; }
}

static CVPixelBufferRef vcam_renderToNewBufferMatching(size_t targetW, size_t targetH, OSType fmt) {
    if (!gCICtx) return NULL;
    @try {
        CMSampleBufferRef frameToRelease = NULL;
        CIImage *srcImg = vcam_acquireSourceImage(&frameToRelease);
        if (!srcImg) return NULL;
        srcImg = vcam_aspectFit(srcImg, targetW, targetH);
        CGRect ext = srcImg.extent;
        if (ext.origin.x != 0 || ext.origin.y != 0) {
            srcImg = [srcImg imageByApplyingTransform:CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y)];
        }
        OSType useFmt = fmt;
        if (useFmt != kCVPixelFormatType_32BGRA &&
            useFmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange &&
            useFmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            useFmt = kCVPixelFormatType_32BGRA;
        }
        NSDictionary *pba = @{
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        };
        CVPixelBufferRef newPB = NULL;
        CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, targetW, targetH, useFmt,
                                          (__bridge CFDictionaryRef)pba, &newPB);
        if (r != kCVReturnSuccess || !newPB) {
            if (frameToRelease) CFRelease(frameToRelease);
            return NULL;
        }
        [gCICtx render:srcImg toCVPixelBuffer:newPB];
        CVPixelBufferLockBaseAddress(newPB, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferUnlockBaseAddress(newPB, kCVPixelBufferLock_ReadOnly);
        if (frameToRelease) CFRelease(frameToRelease);
        return newPB;
    } @catch (NSException *e) { return NULL; }
}

static CMSampleBufferRef vcam_buildPassthroughSampleBuffer(CMSampleBufferRef origSb) {
    if (!origSb) return NULL;
    vcam_readControls();
    @try {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ if (!gLockPT) gLockPT = [[NSLock alloc] init]; });
        if (!vcam_videoExists()) return NULL;
        CVImageBufferRef camPB = CMSampleBufferGetImageBuffer(origSb);
        if (!camPB) return NULL;
        OSType camFmt = CVPixelBufferGetPixelFormatType(camPB);
        if (camFmt != kCVPixelFormatType_32BGRA &&
            camFmt != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange &&
            camFmt != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            camFmt = kCVPixelFormatType_32BGRA;
        }
        vcam_startPassthroughCache(camFmt);
        CMSampleBufferRef srcSb = vcam_takePassthroughCachedFrame();
        if (!srcSb) srcSb = vcam_readFrameFmt(camFmt, gLockPT, &gReaderPT, &gOutputPT);
        if (!srcSb) return NULL;
        CVImageBufferRef srcPB = CMSampleBufferGetImageBuffer(srcSb);
        if (!srcPB) { CFRelease(srcSb); return NULL; }
        CMVideoFormatDescriptionRef fd = NULL;
        OSStatus s1 = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, srcPB, &fd);
        if (s1 != noErr || !fd) { CFRelease(srcSb); return NULL; }
        CMSampleTimingInfo timing;
        timing.duration = CMSampleBufferGetDuration(origSb);
        timing.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(origSb);
        timing.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(origSb);
        CMSampleBufferRef newSb = NULL;
        OSStatus s2 = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, srcPB, true, NULL, NULL, fd, &timing, &newSb);
        CFRelease(fd);
        CFRelease(srcSb);
        if (s2 != noErr || !newSb) return NULL;
        return newSb;
    } @catch (NSException *e) { return NULL; }
}

static CMSampleBufferRef vcam_buildReplacementSampleBuffer(CMSampleBufferRef origSb) {
    if (!origSb || !gCICtx) return NULL;
    @try {
        vcam_readControls();
        CVImageBufferRef origPB = CMSampleBufferGetImageBuffer(origSb);
        if (!origPB) return NULL;
        size_t targetW = CVPixelBufferGetWidth(origPB);
        size_t targetH = CVPixelBufferGetHeight(origPB);
        OSType fmt = CVPixelBufferGetPixelFormatType(origPB);
        if (targetW < 64 || targetH < 64) return NULL;
        CVPixelBufferRef newPB = vcam_renderToNewBufferMatching(targetW, targetH, fmt);
        if (!newPB) return NULL;
        CMVideoFormatDescriptionRef fd = NULL;
        OSStatus s1 = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, newPB, &fd);
        if (s1 != noErr || !fd) { CVPixelBufferRelease(newPB); return NULL; }
        CMSampleTimingInfo timing;
        timing.duration = CMSampleBufferGetDuration(origSb);
        timing.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(origSb);
        timing.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(origSb);
        CMSampleBufferRef newSb = NULL;
        OSStatus s2 = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, newPB, true, NULL, NULL, fd, &timing, &newSb);
        CFRelease(fd);
        CVPixelBufferRelease(newPB);
        if (s2 != noErr || !newSb) return NULL;
        return newSb;
    } @catch (NSException *e) { return NULL; }
}

static CVPixelBufferRef vcam_buildReplacementPixelBufferMatching(CVPixelBufferRef oldPB) {
    if (!gCICtx || !oldPB) return NULL;
    @try {
        vcam_readControls();
        size_t targetW = CVPixelBufferGetWidth(oldPB);
        size_t targetH = CVPixelBufferGetHeight(oldPB);
        OSType fmt = CVPixelBufferGetPixelFormatType(oldPB);
        if (targetW < 64 || targetH < 64) return NULL;
        return vcam_renderToNewBufferMatching(targetW, targetH, fmt);
    } @catch (NSException *e) { return NULL; }
}

static NSData *vcam_buildReplacementJPEG(size_t targetW, size_t targetH) {
    if (!gCICtx) return nil;
    if (targetW < 64 || targetH < 64) return nil;
    @try {
        CMSampleBufferRef frameToRelease = NULL;
        CIImage *srcImg = vcam_acquireSourceImage(&frameToRelease);
        if (!srcImg) return nil;
        srcImg = vcam_aspectFit(srcImg, targetW, targetH);
        CGRect ext = srcImg.extent;
        if (ext.origin.x != 0 || ext.origin.y != 0) {
            srcImg = [srcImg imageByApplyingTransform:CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y)];
        }
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSData *jpeg = [gCICtx JPEGRepresentationOfImage:srcImg colorSpace:cs options:@{}];
        CGColorSpaceRelease(cs);
        if (frameToRelease) CFRelease(frameToRelease);
        return jpeg;
    } @catch (NSException *e) { return nil; }
}

// ============================ 核心替换 ============================
static BOOL vcam_replacePixelBuffer(CVPixelBufferRef pixelBuffer) {
    @try {
        if (!pixelBuffer) return NO;
        if (!gCICtx) {
            gCICtx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
            if (!gCICtx) return NO;
        }
        vcam_readControls();
        size_t w = CVPixelBufferGetWidth(pixelBuffer);
        size_t h = CVPixelBufferGetHeight(pixelBuffer);
        if (w < 480 || h < 480) return NO;

        if (vcam_imageExists()) {
            CIImage *img = vcam_loadStaticImage();
            if (!img) return NO;
            img = vcam_aspectFill(img, w, h);
            [gCICtx render:img toCVPixelBuffer:pixelBuffer];
            CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            return YES;
        }

        CIImage *img = nil;
        CMSampleBufferRef frame = nil;
        if (gVideoPaused && gPausedFrame) {
            img = gPausedFrame;
        } else {
            frame = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
            if (!frame) return NO;
            CVImageBufferRef srcPB = CMSampleBufferGetImageBuffer(frame);
            if (srcPB) {
                img = [CIImage imageWithCVImageBuffer:srcPB];
                if (img) {
                    static int sPauseCounter = 0;
                    if (gVideoPaused || (++sPauseCounter >= 15)) {
                        sPauseCounter = 0;
                        CGImageRef cg = [gCICtx createCGImage:img fromRect:img.extent];
                        if (cg) { gPausedFrame = [CIImage imageWithCGImage:cg]; CGImageRelease(cg); }
                    }
                }
            }
            CFRelease(frame);
        }
        if (!img) return NO;
        img = vcam_applyVideoTransforms(img);
        img = vcam_aspectFill(img, w, h);
        img = vcam_applyOffset(img, w, h, gVideoOffsetX, gVideoOffsetY);
        [gCICtx render:img toCVPixelBuffer:pixelBuffer];
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return YES;
    } @catch (NSException *e) { return NO; }
}

static BOOL vcam_replaceInPlace(CMSampleBufferRef sampleBuffer) {
    @try {
        CVImageBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
        return vcam_replacePixelBuffer(pb);
    } @catch (NSException *e) { return NO; }
}

// ============================ nextCGImage ============================
static CGImageRef vcam_nextCGImage(void) {
    if (!vcam_isEnabled()) return NULL;
    vcam_readControls();
    if (vcam_imageExists()) {
        @try {
            CIImage *staticImage = vcam_loadStaticImage();
            return (staticImage && gCICtx) ? [gCICtx createCGImage:staticImage fromRect:staticImage.extent] : NULL;
        } @catch (NSException *e) { return NULL; }
    }
    CIImage *ci = nil;
    CMSampleBufferRef vbuf = nil;
    if (gVideoPaused && gPausedFrame) {
        ci = gPausedFrame;
    } else {
        if (!gLockB) return NULL;
        vbuf = vcam_readFrame(gLockB, &gReaderB, &gOutputB);
        if (!vbuf) return NULL;
        CVImageBufferRef pxb = CMSampleBufferGetImageBuffer(vbuf);
        if (!pxb) { CFRelease(vbuf); return NULL; }
        ci = [CIImage imageWithCVImageBuffer:pxb];
        if (!ci) { CFRelease(vbuf); return NULL; }
        if (gVideoPaused && gCICtx) {
            CGImageRef cg = [gCICtx createCGImage:ci fromRect:ci.extent];
            if (cg) { gPausedFrame = [CIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
    }
    ci = vcam_applyVideoTransforms(ci);
    if (gVideoOffsetX != 0 || gVideoOffsetY != 0) {
        CGRect ext = ci.extent;
        ci = vcam_applyOffset(ci, (size_t)ext.size.width, (size_t)ext.size.height,
                              gVideoOffsetX, gVideoOffsetY);
    }
    CGImageRef result = gCICtx ? [gCICtx createCGImage:ci fromRect:ci.extent] : NULL;
    if (vbuf) CFRelease(vbuf);
    return result;
}

// ============================ currentFrameAsJPEG ============================
static NSData *vcam_currentFrameAsJPEG(void) {
    @try {
        if (!gCICtx) return nil;
        if (vcam_imageExists()) {
            CIImage *img = vcam_loadStaticImage();
            if (!img) return nil;
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            NSData *data = [gCICtx JPEGRepresentationOfImage:img colorSpace:cs options:@{}];
            CGColorSpaceRelease(cs);
            return data;
        }
        CIImage *img = nil;
        CMSampleBufferRef vframe = nil;
        if (gVideoPaused && gPausedFrame) {
            img = gPausedFrame;
        } else {
            vframe = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
            if (!vframe) return nil;
            CVImageBufferRef pxb = CMSampleBufferGetImageBuffer(vframe);
            if (!pxb) { CFRelease(vframe); return nil; }
            img = [CIImage imageWithCVImageBuffer:pxb];
            if (!img) { CFRelease(vframe); return nil; }
        }
        img = vcam_applyVideoTransforms(img);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSData *data = [gCICtx JPEGRepresentationOfImage:img colorSpace:cs options:@{}];
        CGColorSpaceRelease(cs);
        if (vframe) CFRelease(vframe);
        return data;
    } @catch (NSException *e) { return nil; }
}

// ============================ Overlay ============================
@interface OVLay : NSObject
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, weak) CALayer *previewLayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) int failCount;
+ (void)attachTo:(CALayer *)pl;
@end
@implementation OVLay
+ (void)attachTo:(CALayer *)previewLayer {
    @try {
        if (!vcam_isEnabled()) return;
        OVLay *ex = objc_getAssociatedObject(previewLayer, &kOverlayKey);
        if (ex && ex.layer.superlayer) return;
        if (ex) {
            [ex.timer invalidate]; [ex.layer removeFromSuperlayer];
            @synchronized(gOverlays) { [gOverlays removeObject:ex]; }
        }
        OVLay *ctrl = [[OVLay alloc] init];
        ctrl.previewLayer = previewLayer;
        CALayer *ov = [CALayer layer];
        ov.contentsGravity = kCAGravityResizeAspectFill;
        ov.masksToBounds = YES; ov.hidden = YES;
        ov.zPosition = 9999;
        ctrl.layer = ov;
        ov.frame = previewLayer.bounds;
        [previewLayer addSublayer:ov];
        ctrl.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer *t) {
            @try { [ctrl tick]; } @catch (NSException *e) {}
        }];
        objc_setAssociatedObject(previewLayer, &kOverlayKey, ctrl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @synchronized(gOverlays) { [gOverlays addObject:ctrl]; }
        vcam_log(@"Overlay attached");
    } @catch (NSException *e) {}
}
- (void)tick {
    if (!vcam_isEnabled()) { self.layer.hidden = YES; self.failCount = 0; return; }
    CALayer *pl = self.previewLayer; if (!pl) return;
    if (!self.layer.superlayer) {
        @try { [pl addSublayer:self.layer]; } @catch (NSException *e) { return; }
    }
    @try {
        CGRect plBounds = pl.bounds;
        if (plBounds.size.width > 0 && plBounds.size.height > 0 &&
            !CGRectEqualToRect(self.layer.frame, plBounds))
            self.layer.frame = plBounds;
    } @catch (NSException *e) {}
    CGImageRef img = vcam_nextCGImage();
    if (img) {
        size_t iw = CGImageGetWidth(img), ih = CGImageGetHeight(img);
        if (iw > 0 && ih > 0) {
            self.layer.contents = (__bridge id)img;
            self.layer.hidden = NO; self.failCount = 0;
        } else { self.failCount++; }
        CGImageRelease(img);
    } else {
        self.failCount++;
        if (self.failCount > 60) { self.layer.hidden = YES; self.layer.contents = nil; }
    }
}
- (void)dealloc { [_timer invalidate]; }
@end

// ============================ Hook 模板化 ============================
static IMP vcam_hookMethod(Class cls, SEL sel, IMP newIMP) {
    IMP orig = NULL;
    @try { MSHookMessageEx(cls, sel, newIMP, &orig); } @catch (NSException *e) {}
    if (!orig) {
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            orig = method_getImplementation(m);
            class_addMethod(cls, sel, orig, method_getTypeEncoding(m));
            m = class_getInstanceMethod(cls, sel);
            if (m) method_setImplementation(m, newIMP);
        }
    }
    return orig;
}

// ============================ ISA swizzle ============================
typedef void (*OrigCapIMP)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *);

static void vcam_isaSwizzleDelegate(id delegate) {
    @try {
        if (!delegate) return;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ gISASwizzledObjects = [NSMutableSet new]; });
        NSValue *ptr = [NSValue valueWithPointer:(__bridge void *)delegate];
        @synchronized(gISASwizzledObjects) {
            if ([gISASwizzledObjects containsObject:ptr]) return;
        }
        Class origClass = object_getClass(delegate);
        NSString *origName = NSStringFromClass(origClass);
        if ([origName hasPrefix:@"vcam_"]) return;
        NSString *subName = [NSString stringWithFormat:@"vcam_%@_%p", origName, delegate];
        Class subClass = objc_getClass(subName.UTF8String);
        if (!subClass) {
            subClass = objc_allocateClassPair(origClass, subName.UTF8String, 0);
            if (!subClass) {
                vcam_log([NSString stringWithFormat:@"ISA swizzle: alloc fail for %@", origName]);
                return;
            }
            SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
            Class parentClass = origClass;
            IMP newIMP = imp_implementationWithBlock(
                ^(id _s, AVCaptureOutput *o, CMSampleBufferRef sb, AVCaptureConnection *c) {
                    @try {
                        CMSampleBufferRef sbToForward = sb;
                        BOOL builtNew = NO;
                        if (vcam_isEnabled() && sb) {
                            if (vcam_isBufferReplaceWhitelisted()) {
                                CMSampleBufferRef nsb = NULL;
                                BOOL ptTried = NO;
                                if (!vcam_imageExists() && vcam_videoExists()) {
                                    nsb = vcam_buildPassthroughSampleBuffer(sb);
                                    ptTried = YES;
                                }
                                if (!nsb && vcam_imageExists()) {
                                    nsb = vcam_buildReplacementSampleBuffer(sb);
                                }
                                if (nsb) { sbToForward = nsb; builtNew = YES; }
                                else if (!ptTried) { vcam_replaceInPlace(sb); }
                            } else {
                                vcam_replaceInPlace(sb);
                            }
                        }
                        struct objc_super sup;
                        sup.receiver = _s;
                        sup.super_class = parentClass;
                        typedef void (*SuperFn)(struct objc_super *, SEL, id, CMSampleBufferRef, id);
                        ((SuperFn)objc_msgSendSuper)(&sup, sel, o, sbToForward, c);
                        if (builtNew) CFRelease(sbToForward);
                    } @catch (NSException *e) {}
                });
            class_addMethod(subClass, sel, newIMP, "v@:@^{opaqueCMSampleBuffer=}@");
            @synchronized(gHookIMPs) { [gHookIMPs addObject:@((uintptr_t)newIMP)]; }
            objc_registerClassPair(subClass);
        }
        object_setClass(delegate, subClass);
        @synchronized(gISASwizzledObjects) { [gISASwizzledObjects addObject:ptr]; }
        vcam_log([NSString stringWithFormat:@"ISA swizzled %@ → %@", origName, subName]);
    } @catch (NSException *e) {
        vcam_log([NSString stringWithFormat:@"ISA swizzle exc: %@", e.reason]);
    }
}

// ============================ vcam_hookClass ============================
static void vcam_hookClass(Class cls) {
    @try {
        if (!cls) return;
        NSString *cn = NSStringFromClass(cls);
        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) {
            vcam_log([NSString stringWithFormat:@"Method not found on %@", cn]);
            return;
        }
        IMP cur = method_getImplementation(m);
        @synchronized(gHookIMPs) {
            if ([gHookIMPs containsObject:@((uintptr_t)cur)]) return;
        }
        IMP *store = (IMP *)calloc(1, sizeof(IMP));
        if (!store) return;
        *store = cur;
        SEL cs = sel;
        __block int logCount = 0;
        NSString *capCN = cn;
        IMP hook = imp_implementationWithBlock(
            ^(id _s, AVCaptureOutput *o, CMSampleBufferRef sb, AVCaptureConnection *c) {
                @try {
                    OrigCapIMP fn = (OrigCapIMP)(*store);
                    if (logCount < 3) {
                        logCount++;
                        vcam_log([NSString stringWithFormat:@"HookCall %@ enabled=%@",
                            capCN, vcam_isEnabled() ? @"Y" : @"N"]);
                    }
                    if (!fn) return;
                    CMSampleBufferRef sbToForward = sb;
                    BOOL builtNew = NO;
                    if (vcam_isEnabled() && sb) {
                        if (vcam_isBufferReplaceWhitelisted()) {
                            CMSampleBufferRef nsb = NULL;
                            BOOL ptTried = NO;
                            if (!vcam_imageExists() && vcam_videoExists()) {
                                nsb = vcam_buildPassthroughSampleBuffer(sb);
                                ptTried = YES;
                            }
                            if (!nsb && vcam_imageExists()) {
                                nsb = vcam_buildReplacementSampleBuffer(sb);
                            }
                            if (nsb) { sbToForward = nsb; builtNew = YES; }
                            else if (!ptTried) { vcam_replaceInPlace(sb); }
                        } else {
                            vcam_replaceInPlace(sb);
                        }
                    }
                    fn(_s, cs, o, sbToForward, c);
                    if (builtNew) CFRelease(sbToForward);
                } @catch (NSException *e) {}
            });
        IMP orig = vcam_hookMethod(cls, sel, hook);
        if (orig) *store = orig;
        @synchronized(gHookIMPs) { [gHookIMPs addObject:@((uintptr_t)hook)]; }
        @synchronized(gHookedClasses) { [gHookedClasses addObject:cn]; }
        vcam_log([NSString stringWithFormat:@"Hooked %@", cn]);
    } @catch (NSException *e) {}
}

// ==================== 段 1/3 结束 ====================
// ============================================================================
// Photo 全套
// ============================================================================
static int vcam_replaceBufferIvar(id internal, Class ic, const char *name, BOOL useBufReplace) {
    Ivar iv = class_getInstanceVariable(ic, name);
    if (!iv) return 0;
    ptrdiff_t off = ivar_getOffset(iv);
    CVPixelBufferRef *ptr = (CVPixelBufferRef *)((uint8_t *)(__bridge void *)internal + off);
    if (!ptr || !*ptr) return 0;
    if (useBufReplace) {
        CVPixelBufferRef nb = vcam_buildReplacementPixelBufferMatching(*ptr);
        if (nb) {
            CVPixelBufferRelease(*ptr);
            *ptr = nb;
            return 1;
        }
    }
    return vcam_replacePixelBuffer(*ptr) ? 1 : 0;
}

static void vcam_replacePhotoInternals(id photo) {
    @try {
        if (!photo) return;
        Ivar intIvar = class_getInstanceVariable(objc_getClass("AVCapturePhoto"), "_internal");
        if (!intIvar) return;
        id internal = object_getIvar(photo, intIvar);
        if (!internal) return;
        Class ic = object_getClass(internal);
        int count = 0;
        vcam_loadIOSurfaceFuncs();

        Ivar surfIvar = class_getInstanceVariable(ic, "photoSurface");
        void *surf = NULL;
        size_t surfW = 0, surfH = 0, surfBPR = 0;
        uint32_t surfFmt = 0;
        if (surfIvar) {
            ptrdiff_t off = ivar_getOffset(surfIvar);
            void **surfPtr = (void **)((uint8_t *)(__bridge void *)internal + off);
            surf = *surfPtr;
        }
        if (surf && iosurf_GetWidth && iosurf_GetHeight) {
            surfW = iosurf_GetWidth(surf);
            surfH = iosurf_GetHeight(surf);
            if (iosurf_GetBytesPerRow) surfBPR = iosurf_GetBytesPerRow(surf);
            if (iosurf_GetPixelFormat) surfFmt = iosurf_GetPixelFormat(surf);
        }

        BOOL useBufReplace = vcam_isBufferReplaceWhitelisted();
        count += vcam_replaceBufferIvar(internal, ic, "photoPixelBuffer", useBufReplace);
        count += vcam_replaceBufferIvar(internal, ic, "previewPixelBuffer", useBufReplace);
        count += vcam_replaceBufferIvar(internal, ic, "embeddedThumbnailSourcePixelBuffer", useBufReplace);

        if (surf && iosurf_Lock && iosurf_Unlock && iosurf_GetBaseAddress) {
            iosurf_Lock(surf, 0, NULL);
            void *sbase = iosurf_GetBaseAddress(surf);
            size_t allocSize = iosurf_GetAllocSize ? iosurf_GetAllocSize(surf) : 0;
            if (sbase && allocSize > 0) {
                if (surfFmt == 0x4a504547) {
                    Ivar szIvar = class_getInstanceVariable(ic, "photoSurfaceSize");
                    size_t origJPEGLen = 0;
                    if (szIvar) {
                        ptrdiff_t szOff = ivar_getOffset(szIvar);
                        unsigned long long *szPtr = (unsigned long long *)((uint8_t *)(__bridge void *)internal + szOff);
                        origJPEGLen = (size_t)*szPtr;
                    }
                    if (origJPEGLen == 0 || origJPEGLen > allocSize) origJPEGLen = allocSize;
                    size_t photoW = 0, photoH = 0;
                    @autoreleasepool {
                        NSData *origData = [NSData dataWithBytesNoCopy:sbase length:origJPEGLen freeWhenDone:NO];
                        CGImageSourceRef origSrc = CGImageSourceCreateWithData((__bridge CFDataRef)origData, NULL);
                        if (origSrc) {
                            CGImageRef origImg = CGImageSourceCreateImageAtIndex(origSrc, 0, NULL);
                            if (origImg) {
                                photoW = CGImageGetWidth(origImg);
                                photoH = CGImageGetHeight(origImg);
                                CGImageRelease(origImg);
                            }
                            CFRelease(origSrc);
                        }
                    }
                    if (photoW > 0 && photoH > 0) { gLastPhotoW = photoW; gLastPhotoH = photoH; }
                    NSData *jpeg = nil;
                    if (useBufReplace && photoW > 0 && photoH > 0) jpeg = vcam_buildReplacementJPEG(photoW, photoH);
                    if (!jpeg && photoW > 0 && photoH > 0 && gCICtx) {
                        CIImage *virtImg = nil;
                        if (vcam_imageExists()) virtImg = vcam_loadStaticImage();
                        CMSampleBufferRef _vf = nil;
                        if (!virtImg) {
                            _vf = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
                            if (_vf) {
                                CVImageBufferRef pb = CMSampleBufferGetImageBuffer(_vf);
                                if (pb) virtImg = [CIImage imageWithCVImageBuffer:pb];
                            }
                            if (virtImg) virtImg = vcam_applyVideoTransforms(virtImg);
                        }
                        if (virtImg) {
                            virtImg = vcam_aspectFill(virtImg, photoW, photoH);
                            virtImg = vcam_applyOffset(virtImg, photoW, photoH, gVideoOffsetX, gVideoOffsetY);
                            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                            jpeg = [gCICtx JPEGRepresentationOfImage:virtImg colorSpace:cs options:@{}];
                            CGColorSpaceRelease(cs);
                        }
                        if (_vf) CFRelease(_vf);
                    }
                    if (!jpeg) jpeg = vcam_currentFrameAsJPEG();
                    if (jpeg && jpeg.length <= allocSize) {
                        memcpy(sbase, jpeg.bytes, jpeg.length);
                        if (jpeg.length < allocSize) memset((uint8_t *)sbase + jpeg.length, 0, allocSize - jpeg.length);
                        count++;
                        if (szIvar) {
                            ptrdiff_t szOff = ivar_getOffset(szIvar);
                            unsigned long long *szPtr = (unsigned long long *)((uint8_t *)(__bridge void *)internal + szOff);
                            *szPtr = (unsigned long long)jpeg.length;
                        }
                    }
                } else if (surfW > 0 && surfH > 0) {
                    CVPixelBufferRef tmpPB = NULL;
                    CVReturn tcr = CVPixelBufferCreate(NULL, surfW, surfH, kCVPixelFormatType_32BGRA, NULL, &tmpPB);
                    if (tcr == kCVReturnSuccess && tmpPB) {
                        if (vcam_replacePixelBuffer(tmpPB)) {
                            CVPixelBufferLockBaseAddress(tmpPB, kCVPixelBufferLock_ReadOnly);
                            void *tmpBase = CVPixelBufferGetBaseAddress(tmpPB);
                            size_t tmpBPR = CVPixelBufferGetBytesPerRow(tmpPB);
                            size_t copyBPR = (tmpBPR < surfBPR) ? tmpBPR : surfBPR;
                            for (size_t y = 0; y < surfH; y++) {
                                memcpy((uint8_t *)sbase + y * surfBPR, (uint8_t *)tmpBase + y * tmpBPR, copyBPR);
                            }
                            CVPixelBufferUnlockBaseAddress(tmpPB, kCVPixelBufferLock_ReadOnly);
                            count++;
                        }
                        CVPixelBufferRelease(tmpPB);
                    }
                }
            }
            iosurf_Unlock(surf, 0, NULL);
        }
        vcam_log([NSString stringWithFormat:@"Photo internals: %d buffers replaced", count]);
    } @catch (NSException *e) {}
}

static void vcam_editLatestPhoto(void) {
    if (!vcam_licenseIsValid()) return;
    @try {
        void *h = dlopen("/System/Library/Frameworks/Photos.framework/Photos", RTLD_LAZY);
        if (!h) return;
        Class PHAssetClass = objc_getClass("PHAsset");
        Class PHFetchOptionsClass = objc_getClass("PHFetchOptions");
        Class PHContentEditingOutputClass = objc_getClass("PHContentEditingOutput");
        Class PHAdjustmentDataClass = objc_getClass("PHAdjustmentData");
        Class PHAssetChangeRequestClass = objc_getClass("PHAssetChangeRequest");
        Class PHPhotoLibraryClass = objc_getClass("PHPhotoLibrary");
        if (!PHAssetClass || !PHFetchOptionsClass || !PHContentEditingOutputClass ||
            !PHAdjustmentDataClass || !PHAssetChangeRequestClass || !PHPhotoLibraryClass) return;
        PHFetchOptions *opts = [[PHFetchOptionsClass alloc] init];
        opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        opts.fetchLimit = 1;
        PHFetchResult *result = (PHFetchResult *)[PHAssetClass fetchAssetsWithMediaType:1 options:opts];
        PHAsset *asset = (PHAsset *)[result firstObject];
        if (!asset) return;
        [asset requestContentEditingInputWithOptions:nil completionHandler:^(id input, NSDictionary *info) {
            @try {
                if (!input) return;
                PHContentEditingOutput *output = [[PHContentEditingOutputClass alloc] initWithContentEditingInput:input];
                NSURL *renderedURL = output.renderedContentURL;
                if (!renderedURL) return;
                NSString *ext = [[renderedURL pathExtension] lowercaseString];
                NSData *imgData = nil;
                if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) {
                    CIImage *ci = nil;
                    if (vcam_imageExists()) ci = vcam_loadStaticImage();
                    CMSampleBufferRef _ef = nil;
                    if (!ci && gCICtx) {
                        _ef = vcam_readFrame(gLockB, &gReaderB, &gOutputB);
                        if (_ef) {
                            CVImageBufferRef pb = CMSampleBufferGetImageBuffer(_ef);
                            if (pb) ci = [CIImage imageWithCVImageBuffer:pb];
                        }
                        if (ci) ci = vcam_applyVideoTransforms(ci);
                    }
                    if (ci && gCICtx) {
                        size_t epW = gLastPhotoW > 0 ? gLastPhotoW : 3024;
                        size_t epH = gLastPhotoH > 0 ? gLastPhotoH : 4032;
                        ci = vcam_aspectFill(ci, epW, epH);
                        ci = vcam_applyOffset(ci, epW, epH, gVideoOffsetX, gVideoOffsetY);
                        CGImageRef cgImg = [gCICtx createCGImage:ci fromRect:ci.extent];
                        if (_ef) { CFRelease(_ef); _ef = nil; }
                        if (cgImg) {
                            NSMutableData *heicBuf = [NSMutableData data];
                            CGImageDestinationRef dest = CGImageDestinationCreateWithData(
                                (__bridge CFMutableDataRef)heicBuf,
                                (__bridge CFStringRef)@"public.heic", 1, NULL);
                            if (dest) {
                                CGImageDestinationAddImage(dest, cgImg, NULL);
                                if (CGImageDestinationFinalize(dest)) imgData = heicBuf;
                                CFRelease(dest);
                            }
                            CGImageRelease(cgImg);
                        }
                    }
                    if (_ef) CFRelease(_ef);
                    if (!imgData) imgData = vcam_currentFrameAsJPEG();
                } else {
                    imgData = vcam_currentFrameAsJPEG();
                }
                if (!imgData) return;
                [imgData writeToURL:renderedURL options:NSDataWritingAtomic error:nil];
                PHAdjustmentData *adj = [[PHAdjustmentDataClass alloc]
                    initWithFormatIdentifier:@"com.vcamplus.edit"
                    formatVersion:@"1.0"
                    data:[@"vcam" dataUsingEncoding:NSUTF8StringEncoding]];
                output.adjustmentData = adj;
                gIsVCamEditing = YES;
                PHPhotoLibrary *lib = [PHPhotoLibraryClass performSelector:@selector(sharedPhotoLibrary)];
                [lib performChanges:^{
                    PHAssetChangeRequest *req = [PHAssetChangeRequestClass changeRequestForAsset:asset];
                    req.contentEditingOutput = output;
                } completionHandler:^(BOOL success, NSError *error) {
                    gIsVCamEditing = NO;
                }];
            } @catch (NSException *e) {}
        }];
    } @catch (NSException *e) {}
}

static void vcam_hookPhotoDataOnClass(Class cls) {
    if (!cls) return;
    NSString *cn = NSStringFromClass(cls);
    @synchronized(gHookedPhotoClasses) {
        if ([gHookedPhotoClasses containsObject:cn]) return;
        [gHookedPhotoClasses addObject:cn];
    }
    {
        SEL sel = @selector(fileDataRepresentation);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            typedef NSData *(*F)(id, SEL);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^NSData *(id _self) {
                @try {
                    if (vcam_isEnabled()) {
                        gLastCaptureTime = CACurrentMediaTime();
                        vcam_hookPHAsset();
                        NSData *data = nil;
                        if (gLastPhotoW > 0 && gLastPhotoH > 0 && gCICtx) {
                            CIImage *img = nil;
                            if (vcam_imageExists()) img = vcam_loadStaticImage();
                            CMSampleBufferRef _ff = nil;
                            if (!img) {
                                _ff = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
                                if (_ff) {
                                    CVImageBufferRef pb = CMSampleBufferGetImageBuffer(_ff);
                                    if (pb) img = [CIImage imageWithCVImageBuffer:pb];
                                }
                                if (img) img = vcam_applyVideoTransforms(img);
                            }
                            if (img) {
                                // 与预览、录像一致，aspectFill 填满照片画布
                                img = vcam_aspectFill(img, gLastPhotoW, gLastPhotoH);
                                img = vcam_applyOffset(img, gLastPhotoW, gLastPhotoH, gVideoOffsetX, gVideoOffsetY);
                                CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                                data = [gCICtx JPEGRepresentationOfImage:img colorSpace:cs options:@{}];
                                CGColorSpaceRelease(cs);
                            }
                            if (_ff) CFRelease(_ff);
                        }
                        if (!data) data = vcam_currentFrameAsJPEG();
                        if (data) return data;
                    }
                } @catch (NSException *e) {}
                return orig ? orig(_self, sel) : nil;
            });
            method_setImplementation(m, ni);
        }
    }
    {
        SEL sel = NSSelectorFromString(@"fileDataRepresentationWithCustomizer:");
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            typedef NSData *(*F)(id, SEL, id);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^NSData *(id _self, id customizer) {
                @try {
                    if (vcam_isEnabled()) {
                        gLastCaptureTime = CACurrentMediaTime();
                        vcam_hookPHAsset();
                        NSData *data = vcam_currentFrameAsJPEG();
                        if (data) return data;
                    }
                } @catch (NSException *e) {}
                return orig ? orig(_self, sel, customizer) : nil;
            });
            method_setImplementation(m, ni);
        }
    }
    {
        SEL sel = @selector(CGImageRepresentation);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            typedef CGImageRef (*F)(id, SEL);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^CGImageRef(id _self) {
                @try {
                    if (vcam_isEnabled()) {
                        if (vcam_imageExists()) {
                            CIImage *ci = vcam_loadStaticImage();
                            if (ci && gCICtx) {
                                CGImageRef img = [gCICtx createCGImage:ci fromRect:ci.extent];
                                if (img) return img;
                            }
                        }
                        CGImageRef img = vcam_nextCGImage();
                        if (img) return img;
                    }
                } @catch (NSException *e) {}
                return orig ? orig(_self, sel) : NULL;
            });
            method_setImplementation(m, ni);
        }
    }
    {
        SEL sel = @selector(pixelBuffer);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            typedef CVPixelBufferRef (*F)(id, SEL);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^CVPixelBufferRef(id _self) {
                CVPixelBufferRef pb = orig ? orig(_self, sel) : NULL;
                @try { if (pb && vcam_isEnabled()) vcam_replacePixelBuffer(pb); } @catch (NSException *e) {}
                return pb;
            });
            method_setImplementation(m, ni);
        }
    }
    {
        SEL sel = @selector(previewPixelBuffer);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            typedef CVPixelBufferRef (*F)(id, SEL);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^CVPixelBufferRef(id _self) {
                CVPixelBufferRef pb = orig ? orig(_self, sel) : NULL;
                @try { if (pb && vcam_isEnabled()) vcam_replacePixelBuffer(pb); } @catch (NSException *e) {}
                return pb;
            });
            method_setImplementation(m, ni);
        }
    }
}

typedef void (*OrigPhotoDelegateIMP)(id, SEL, id, id, NSError *);
static void vcam_hookPhotoDelegate(Class cls) {
    @try {
        if (!cls) return;
        SEL sel = @selector(captureOutput:didFinishProcessingPhoto:error:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            IMP cur = method_getImplementation(m);
            BOOL already = NO;
            @synchronized(gHookIMPs) { already = [gHookIMPs containsObject:@((uintptr_t)cur)]; }
            if (!already) {
                class_addMethod(cls, sel, cur, method_getTypeEncoding(m));
                m = class_getInstanceMethod(cls, sel);
                cur = method_getImplementation(m);
                IMP *store = (IMP *)calloc(1, sizeof(IMP));
                if (store) {
                    *store = cur;
                    SEL cs = sel;
                    IMP hook = imp_implementationWithBlock(
                        ^(id _s, id output, id photo, NSError *error) {
                            @try {
                                if (vcam_isEnabled() && !error && photo) {
                                    vcam_hookPhotoDataOnClass(object_getClass(photo));
                                    vcam_hookPHAsset();
                                    vcam_replacePhotoInternals(photo);
                                }
                                OrigPhotoDelegateIMP fn = (OrigPhotoDelegateIMP)(*store);
                                if (fn) fn(_s, cs, output, photo, error);
                            } @catch (NSException *e) {}
                        });
                    method_setImplementation(m, hook);
                    @synchronized(gHookIMPs) { [gHookIMPs addObject:@((uintptr_t)hook)]; }
                }
            }
        }
        SEL osel = @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:);
        Method om = class_getInstanceMethod(cls, osel);
        if (om) {
            IMP ocur = method_getImplementation(om);
            BOOL alreadyOurs = NO;
            @synchronized(gHookIMPs) { alreadyOurs = [gHookIMPs containsObject:@((uintptr_t)ocur)]; }
            if (!alreadyOurs) {
                class_addMethod(cls, osel, ocur, method_getTypeEncoding(om));
                om = class_getInstanceMethod(cls, osel);
                ocur = method_getImplementation(om);
                IMP *ostore = (IMP *)calloc(1, sizeof(IMP));
                if (ostore) {
                    *ostore = ocur;
                    SEL ocs = osel;
                    typedef void (*OldPhotoIMP)(id, SEL, id, CMSampleBufferRef, CMSampleBufferRef, id, id, NSError *);
                    IMP ohook = imp_implementationWithBlock(
                        ^(id _s, id output, CMSampleBufferRef photoSb, CMSampleBufferRef previewSb,
                          id resolved, id bracket, NSError *error) {
                            @try {
                                if (vcam_isEnabled() && !error && photoSb) vcam_replaceInPlace(photoSb);
                                OldPhotoIMP fn = (OldPhotoIMP)(*ostore);
                                if (fn) fn(_s, ocs, output, photoSb, previewSb, resolved, bracket, error);
                            } @catch (NSException *e) {}
                        });
                    method_setImplementation(om, ohook);
                    @synchronized(gHookIMPs) { [gHookIMPs addObject:@((uintptr_t)ohook)]; }
                }
            }
        }
    } @catch (NSException *e) {}
}

static void vcam_hookPhotoCaptureOnClass(Class cls) {
    if (!cls) return;
    NSString *cn = NSStringFromClass(cls);
    @synchronized(gHookedPhotoCaptureClasses) {
        if (!gHookedPhotoCaptureClasses) gHookedPhotoCaptureClasses = [NSMutableSet new];
        if ([gHookedPhotoCaptureClasses containsObject:cn]) return;
        [gHookedPhotoCaptureClasses addObject:cn];
    }
    SEL sel = @selector(capturePhotoWithSettings:delegate:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        typedef void (*F)(id, SEL, AVCapturePhotoSettings *, id);
        __block F orig = NULL;
        IMP ni = imp_implementationWithBlock(^(id _self, AVCapturePhotoSettings *settings, id delegate) {
            @try {
                if (vcam_isEnabled()) gLastCaptureTime = CACurrentMediaTime();
                if (delegate) vcam_hookPhotoDelegate(object_getClass(delegate));
                vcam_hookPHAsset();
            } @catch (NSException *e) {}
            if (orig) orig(_self, sel, settings, delegate);
        });
        IMP origIMP = vcam_hookMethod(cls, sel, ni);
        if (origIMP) orig = (F)origIMP;
    }
    {
        SEL jsel = @selector(JPEGPhotoDataRepresentationForJPEGSampleBuffer:previewPhotoSampleBuffer:);
        Class metaCls = object_getClass(cls);
        Method jm = class_getInstanceMethod(metaCls, jsel);
        if (jm) {
            typedef NSData *(*JF)(Class, SEL, CMSampleBufferRef, CMSampleBufferRef);
            JF jorig = (JF)method_getImplementation(jm);
            IMP nj = imp_implementationWithBlock(^NSData *(Class _self, CMSampleBufferRef jpegSb, CMSampleBufferRef previewSb) {
                @try {
                    if (vcam_isEnabled() && vcam_isBufferReplaceWhitelisted()) {
                        size_t tw = 0, th = 0;
                        if (jpegSb) {
                            CVImageBufferRef pb = CMSampleBufferGetImageBuffer(jpegSb);
                            if (pb) { tw = CVPixelBufferGetWidth(pb); th = CVPixelBufferGetHeight(pb); }
                        }
                        if (tw < 64 || th < 64) { tw = gLastPhotoW > 0 ? gLastPhotoW : 1920; th = gLastPhotoH > 0 ? gLastPhotoH : 1080; }
                        NSData *jpeg = vcam_buildReplacementJPEG(tw, th);
                        if (jpeg) return jpeg;
                    }
                } @catch (NSException *e) {}
                return jorig ? jorig(_self, jsel, jpegSb, previewSb) : nil;
            });
            method_setImplementation(jm, nj);
        }
    }
}

static void vcam_hookPHAsset(void) {
    if (gPHAssetHooked) return;
    void *h = dlopen("/System/Library/Frameworks/Photos.framework/Photos", RTLD_LAZY);
    if (!h) return;
    gPHAssetHooked = YES;

    Class crCls = objc_getClass("PHAssetCreationRequest");
    if (crCls) {
        {
            SEL sel = @selector(addResourceWithType:data:options:);
            Method m = class_getInstanceMethod(crCls, sel);
            if (m) {
                typedef void (*F)(id, SEL, NSInteger, NSData *, id);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^(id _self, NSInteger type, NSData *data, id options) {
                    @try {
                        if (vcam_isEnabled() && type == 1 && data && gLastCaptureTime > 0
                            && (CACurrentMediaTime() - gLastCaptureTime) < 10.0) {
                            NSData *replaced = vcam_currentFrameAsJPEG();
                            if (replaced) {
                                if (orig) orig(_self, sel, type, replaced, options);
                                return;
                            }
                        }
                    } @catch (NSException *e) {}
                    if (orig) orig(_self, sel, type, data, options);
                });
                method_setImplementation(m, ni);
            }
        }
        {
            SEL sel = @selector(addResourceWithType:fileURL:options:);
            Method m = class_getInstanceMethod(crCls, sel);
            if (m) {
                typedef void (*F)(id, SEL, NSInteger, NSURL *, id);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^(id _self, NSInteger type, NSURL *fileURL, id options) {
                    @try {
                        if (vcam_isEnabled() && type == 1 && gLastCaptureTime > 0
                            && (CACurrentMediaTime() - gLastCaptureTime) < 10.0) {
                            NSData *replaced = vcam_currentFrameAsJPEG();
                            if (replaced) {
                                NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_photo.jpg"];
                                if ([replaced writeToFile:tmp atomically:YES]) {
                                    if (orig) orig(_self, sel, type, [NSURL fileURLWithPath:tmp], options);
                                    return;
                                }
                            }
                        }
                    } @catch (NSException *e) {}
                    if (orig) orig(_self, sel, type, fileURL, options);
                });
                method_setImplementation(m, ni);
            }
        }
    }

    Class chCls = objc_getClass("PHAssetChangeRequest");
    if (chCls) {
        {
            SEL sel = @selector(creationRequestForAssetFromImage:);
            Method m = class_getClassMethod(chCls, sel);
            if (m) {
                typedef id (*F)(id, SEL, id);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^id(id _self, id image) {
                    @try {
                        if (vcam_isEnabled() && gLastCaptureTime > 0
                            && (CACurrentMediaTime() - gLastCaptureTime) < 10.0) {
                            CIImage *ci = vcam_imageExists() ? vcam_loadStaticImage() : nil;
                            if (ci && gCICtx) {
                                CGImageRef cgImg = [gCICtx createCGImage:ci fromRect:ci.extent];
                                if (cgImg) {
                                    UIImage *newImg = [UIImage imageWithCGImage:cgImg];
                                    CGImageRelease(cgImg);
                                    if (newImg) return orig ? orig(_self, sel, newImg) : nil;
                                }
                            }
                        }
                    } @catch (NSException *e) {}
                    return orig ? orig(_self, sel, image) : nil;
                });
                method_setImplementation(m, ni);
            }
        }
        {
            SEL sel = @selector(creationRequestForAssetFromImageAtFileURL:);
            Method m = class_getClassMethod(chCls, sel);
            if (m) {
                typedef id (*F)(id, SEL, NSURL *);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^id(id _self, NSURL *fileURL) {
                    @try {
                        if (vcam_isEnabled() && gLastCaptureTime > 0
                            && (CACurrentMediaTime() - gLastCaptureTime) < 10.0) {
                            NSData *replaced = vcam_currentFrameAsJPEG();
                            if (replaced) {
                                NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_photo.jpg"];
                                if ([replaced writeToFile:tmp atomically:YES])
                                    return orig ? orig(_self, sel, [NSURL fileURLWithPath:tmp]) : nil;
                            }
                        }
                    } @catch (NSException *e) {}
                    return orig ? orig(_self, sel, fileURL) : nil;
                });
                method_setImplementation(m, ni);
            }
        }
    }

    Class libCls = objc_getClass("PHPhotoLibrary");
    if (libCls) {
        SEL sel = @selector(performChanges:completionHandler:);
        Method m = class_getInstanceMethod(libCls, sel);
        if (m) {
            typedef void (*F)(id, SEL, id, id);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^(id _self, id changeBlock, id completion) {
                if (gIsVCamEditing) {
                    if (orig) orig(_self, sel, changeBlock, completion);
                    return;
                }
                BOOL shouldEdit = vcam_isEnabled() && gLastCaptureTime > 0
                    && (CACurrentMediaTime() - gLastCaptureTime) < 15.0;
                if (shouldEdit) {
                    void (^origCompletion)(BOOL, NSError *) = (void (^)(BOOL, NSError *))completion;
                    void (^wrappedCompletion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
                        if (success) {
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                                dispatch_get_global_queue(0, 0), ^{ vcam_editLatestPhoto(); });
                        }
                        if (origCompletion) origCompletion(success, error);
                    };
                    if (orig) orig(_self, sel, changeBlock, (id)wrappedCompletion);
                } else {
                    if (orig) orig(_self, sel, changeBlock, completion);
                }
            });
            method_setImplementation(m, ni);
        }
    }
}

// ============================================================================
// Metadata 假人脸
// ============================================================================
typedef void (*OrigMetaDelegateIMP)(id, SEL, id, NSArray *, id);

static id vcam_createFakeFace(void) {
    @try {
        Class baseCls = objc_getClass("AVMetadataFaceObject");
        if (!baseCls) return nil;
        if (!gFakeFaceClass) {
            gFakeFaceClass = objc_allocateClassPair(baseCls, "VCFakeFace", 0);
            if (!gFakeFaceClass) {
                gFakeFaceClass = objc_getClass("VCFakeFace");
                if (!gFakeFaceClass) return nil;
            } else {
                class_addMethod(gFakeFaceClass, @selector(bounds),
                    imp_implementationWithBlock(^CGRect(id _self) { return gFakeFaceBounds; }),
                    "{CGRect={CGPoint=dd}{CGSize=dd}}@:");
                class_addMethod(gFakeFaceClass, @selector(faceID),
                    imp_implementationWithBlock(^NSInteger(id _self) { return 1; }), "q@:");
                class_addMethod(gFakeFaceClass, @selector(type),
                    imp_implementationWithBlock(^NSString *(id _self) { return @"face"; }), "@@:");
                class_addMethod(gFakeFaceClass, @selector(hasRollAngle),
                    imp_implementationWithBlock(^BOOL(id _self) { return YES; }), "B@:");
                class_addMethod(gFakeFaceClass, @selector(hasYawAngle),
                    imp_implementationWithBlock(^BOOL(id _self) { return YES; }), "B@:");
                class_addMethod(gFakeFaceClass, @selector(rollAngle),
                    imp_implementationWithBlock(^CGFloat(id _self) { return 0.0; }), "d@:");
                class_addMethod(gFakeFaceClass, @selector(yawAngle),
                    imp_implementationWithBlock(^CGFloat(id _self) { return 0.0; }), "d@:");
                objc_registerClassPair(gFakeFaceClass);
            }
        }
        return [[gFakeFaceClass alloc] init];
    } @catch (NSException *e) { return nil; }
}

static void vcam_hookMetadataDelegate(Class dcls) {
    @try {
        if (!dcls) return;
        SEL ds = @selector(captureOutput:didOutputMetadataObjects:fromConnection:);
        Method dm = class_getInstanceMethod(dcls, ds);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ gMetaHookedIMPs = [NSMutableSet new]; });
        if (!dm) return;
        IMP cur = method_getImplementation(dm);
        @synchronized(gMetaHookedIMPs) {
            if ([gMetaHookedIMPs containsObject:@((uintptr_t)cur)]) return;
        }
        class_addMethod(dcls, ds, cur, method_getTypeEncoding(dm));
        dm = class_getInstanceMethod(dcls, ds);
        cur = method_getImplementation(dm);
        IMP *store = (IMP *)calloc(1, sizeof(IMP));
        if (!store) return;
        *store = cur;
        SEL cs = ds;
        IMP hook = imp_implementationWithBlock(
            ^(id _s, id output, NSArray *objects, id connection) {
                @try {
                    OrigMetaDelegateIMP fn = (OrigMetaDelegateIMP)(*store);
                    if (!fn) return;
                    if (vcam_isEnabled() && objects.count == 0) {
                        id fakeFace = vcam_createFakeFace();
                        if (fakeFace) {
                            fn(_s, cs, output, @[fakeFace], connection);
                            return;
                        }
                    }
                    fn(_s, cs, output, objects, connection);
                } @catch (NSException *e) {}
            });
        method_setImplementation(dm, hook);
        @synchronized(gMetaHookedIMPs) { [gMetaHookedIMPs addObject:@((uintptr_t)hook)]; }
    } @catch (NSException *e) {}
}

// ============================================================================
// 录像模块
// ============================================================================
static void vcam_recCaptureFrame(void) {
    if (!vcam_licenseIsValid()) { gIsRecordingVideo = NO; return; }
    vcam_readControls();
    if (!gIsRecordingVideo || !gRecWriter || !gRecWriterInput || !gRecWriterAdaptor) return;
    @try {
        typedef BOOL (*ReadyF)(id, SEL);
        SEL rdySel = @selector(isReadyForMoreMediaData);
        ReadyF rdyFn = (ReadyF)[(NSObject *)gRecWriterInput methodForSelector:rdySel];
        if (rdyFn && !rdyFn(gRecWriterInput, rdySel)) return;

        CIImage *virtImg = nil;
        if (vcam_imageExists()) virtImg = vcam_loadStaticImage();
        CMSampleBufferRef vf = nil;
        if (!virtImg) {
            vf = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
            if (vf) {
                CVImageBufferRef pb = CMSampleBufferGetImageBuffer(vf);
                if (pb) virtImg = [CIImage imageWithCVImageBuffer:pb];
            }
            if (virtImg) virtImg = vcam_applyVideoTransforms(virtImg);
        }
        if (!virtImg) { if (vf) CFRelease(vf); return; }

        virtImg = vcam_aspectFill(virtImg, gRecWidth, gRecHeight);
        virtImg = vcam_applyOffset(virtImg, gRecWidth, gRecHeight, gVideoOffsetX, gVideoOffsetY);

        CVPixelBufferRef outPB = NULL;
        NSDictionary *pbAttrs = @{
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (id)kCVPixelBufferWidthKey: @(gRecWidth),
            (id)kCVPixelBufferHeightKey: @(gRecHeight),
        };
        CVReturn cr = CVPixelBufferCreate(NULL, gRecWidth, gRecHeight,
            kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)pbAttrs, &outPB);
        if (cr != kCVReturnSuccess || !outPB) { if (vf) CFRelease(vf); return; }
        if (!gCICtx) { CVPixelBufferRelease(outPB); if (vf) CFRelease(vf); return; }
        [gCICtx render:virtImg toCVPixelBuffer:outPB];

        CMTime pts = CMTimeMake(gRecFrameCount, 30);
        if (!gRecSessionStarted) {
            typedef void (*StartF)(id, SEL, CMTime);
            SEL stSel = @selector(startSessionAtSourceTime:);
            StartF stFn = (StartF)[(NSObject *)gRecWriter methodForSelector:stSel];
            if (stFn) stFn(gRecWriter, stSel, pts);
            gRecSessionStarted = YES;
        }
        typedef BOOL (*AppendF)(id, SEL, CVPixelBufferRef, CMTime);
        SEL appSel = @selector(appendPixelBuffer:withPresentationTime:);
        AppendF appFn = (AppendF)[(NSObject *)gRecWriterAdaptor methodForSelector:appSel];
        if (appFn) appFn(gRecWriterAdaptor, appSel, outPB, pts);
        gRecFrameCount++;

        CVPixelBufferRelease(outPB);
        if (vf) CFRelease(vf);
    } @catch (NSException *e) {}
}

static void vcam_startVirtualRecording(size_t width, size_t height) {
    @try {
        if (gIsRecordingVideo) return;
        if (!gRecQueue) gRecQueue = dispatch_queue_create("com.vcam.rec", DISPATCH_QUEUE_SERIAL);
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_rec.mov"];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        gVirtualRecordingURL = [NSURL fileURLWithPath:tmp];
        if (width == 0) width = 1920;
        if (height == 0) height = 1080;
        gRecWidth = width;
        gRecHeight = height;
        Class writerClass = objc_getClass("AVAssetWriter");
        if (!writerClass) return;
        NSError *err = nil;
        gRecWriter = [[writerClass alloc] initWithURL:gVirtualRecordingURL fileType:AVFileTypeQuickTimeMovie error:&err];
        if (!gRecWriter || err) return;
        NSDictionary *settings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(width),
            AVVideoHeightKey: @(height),
        };
        Class inputClass = objc_getClass("AVAssetWriterInput");
        gRecWriterInput = [[inputClass alloc] initWithMediaType:AVMediaTypeVideo outputSettings:settings];
        typedef void (*SetRTF)(id, SEL, BOOL);
        SEL rtSel = @selector(setExpectsMediaDataInRealTime:);
        SetRTF rtFn = (SetRTF)[(NSObject *)gRecWriterInput methodForSelector:rtSel];
        if (rtFn) rtFn(gRecWriterInput, rtSel, YES);
        Class adaptorClass = objc_getClass("AVAssetWriterInputPixelBufferAdaptor");
        gRecWriterAdaptor = [[adaptorClass alloc] initWithAssetWriterInput:gRecWriterInput sourcePixelBufferAttributes:nil];
        [gRecWriter performSelector:@selector(addInput:) withObject:gRecWriterInput];
        [gRecWriter performSelector:@selector(startWriting)];
        gRecSessionStarted = NO;
        gRecFrameCount = 0;
        gIsRecordingVideo = YES;
        gRecTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gRecQueue);
        dispatch_source_set_timer(gRecTimer, DISPATCH_TIME_NOW, (uint64_t)(NSEC_PER_SEC / 30), NSEC_PER_MSEC);
        dispatch_source_set_event_handler(gRecTimer, ^{ vcam_recCaptureFrame(); });
        dispatch_resume(gRecTimer);
    } @catch (NSException *e) {}
}

static void vcam_stopVirtualRecording(void) {
    if (!gIsRecordingVideo) return;
    gIsRecordingVideo = NO;
    if (gRecTimer) { dispatch_source_cancel(gRecTimer); gRecTimer = nil; }
    if (!gRecWriter) return;
    @try {
        [gRecWriterInput performSelector:@selector(markAsFinished)];
        typedef void (*FinishF)(id, SEL, void(^)(void));
        SEL finSel = @selector(finishWritingWithCompletionHandler:);
        FinishF finFn = (FinishF)[(NSObject *)gRecWriter methodForSelector:finSel];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        finFn(gRecWriter, finSel, ^{ dispatch_semaphore_signal(sem); });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
    } @catch (NSException *e) {}
    gRecWriter = nil;
    gRecWriterInput = nil;
    gRecWriterAdaptor = nil;
}

static void vcam_editLatestVideo(NSURL *virtualURL) {
    if (!vcam_licenseIsValid()) return;
    @try {
        if (!virtualURL || ![[NSFileManager defaultManager] fileExistsAtPath:[virtualURL path]]) return;
        void *h = dlopen("/System/Library/Frameworks/Photos.framework/Photos", RTLD_LAZY);
        if (!h) return;
        Class PHAssetClass = objc_getClass("PHAsset");
        Class PHFetchOptionsClass = objc_getClass("PHFetchOptions");
        Class PHContentEditingOutputClass = objc_getClass("PHContentEditingOutput");
        Class PHAdjustmentDataClass = objc_getClass("PHAdjustmentData");
        Class PHAssetChangeRequestClass = objc_getClass("PHAssetChangeRequest");
        Class PHPhotoLibraryClass = objc_getClass("PHPhotoLibrary");
        if (!PHAssetClass || !PHFetchOptionsClass || !PHContentEditingOutputClass ||
            !PHAdjustmentDataClass || !PHAssetChangeRequestClass || !PHPhotoLibraryClass) return;
        PHFetchOptions *opts = [[PHFetchOptionsClass alloc] init];
        opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        opts.fetchLimit = 1;
        PHFetchResult *result = (PHFetchResult *)[PHAssetClass fetchAssetsWithMediaType:2 options:opts];
        PHAsset *asset = (PHAsset *)[result firstObject];
        if (!asset) return;
        [asset requestContentEditingInputWithOptions:nil completionHandler:^(id input, NSDictionary *info) {
            @try {
                if (!input) return;
                PHContentEditingOutput *output = [[PHContentEditingOutputClass alloc] initWithContentEditingInput:input];
                NSURL *renderedURL = output.renderedContentURL;
                if (!renderedURL) return;
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm removeItemAtURL:renderedURL error:nil];
                if (![fm copyItemAtURL:virtualURL toURL:renderedURL error:nil]) return;
                PHAdjustmentData *adj = [[PHAdjustmentDataClass alloc]
                    initWithFormatIdentifier:@"com.vcamplus.edit"
                    formatVersion:@"1.0"
                    data:[@"vcam-video" dataUsingEncoding:NSUTF8StringEncoding]];
                output.adjustmentData = adj;
                gIsVCamEditing = YES;
                id lib = [PHPhotoLibraryClass performSelector:@selector(sharedPhotoLibrary)];
                typedef void (*PerformF)(id, SEL, void(^)(void), void(^)(BOOL, NSError *));
                SEL perfSel = @selector(performChanges:completionHandler:);
                PerformF perfFn = (PerformF)[(NSObject *)lib methodForSelector:perfSel];
                perfFn(lib, perfSel, ^{
                    id changeReq = [PHAssetChangeRequestClass changeRequestForAsset:asset];
                    [changeReq performSelector:@selector(setContentEditingOutput:) withObject:output];
                }, ^(BOOL success, NSError *error) {
                    gIsVCamEditing = NO;
                });
            } @catch (NSException *e) { gIsVCamEditing = NO; }
        }];
    } @catch (NSException *e) {}
}

static void vcam_hookRecordingDelegate(Class cls) {
    @try {
        if (!cls) return;
        SEL sel = @selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        IMP cur = method_getImplementation(m);
        @synchronized(gHookIMPs) { if ([gHookIMPs containsObject:@((uintptr_t)cur)]) return; }
        class_addMethod(cls, sel, cur, method_getTypeEncoding(m));
        m = class_getInstanceMethod(cls, sel);
        cur = method_getImplementation(m);
        IMP *store = (IMP *)calloc(1, sizeof(IMP));
        if (!store) return;
        *store = cur;
        SEL cs = sel;
        typedef void (*RecDelegateIMP)(id, SEL, id, NSURL *, NSArray *, NSError *);
        IMP hook = imp_implementationWithBlock(
            ^(id _s, id output, NSURL *fileURL, NSArray *connections, NSError *error) {
                @try {
                    if (!error && vcam_licenseIsValid() && gVirtualRecordingURL) {
                        NSFileManager *fm = [NSFileManager defaultManager];
                        if ([fm fileExistsAtPath:[gVirtualRecordingURL path]]) {
                            [fm removeItemAtURL:fileURL error:nil];
                            [fm copyItemAtURL:gVirtualRecordingURL toURL:fileURL error:nil];
                        }
                    }
                    RecDelegateIMP fn = (RecDelegateIMP)(*store);
                    if (fn) fn(_s, cs, output, fileURL, connections, error);
                    if (!error && vcam_licenseIsValid() && gVirtualRecordingURL) {
                        NSURL *virtURL = [gVirtualRecordingURL copy];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                            dispatch_get_global_queue(0, 0), ^{ vcam_editLatestVideo(virtURL); });
                    }
                } @catch (NSException *e) {}
            });
        method_setImplementation(m, hook);
        @synchronized(gHookIMPs) { [gHookIMPs addObject:@((uintptr_t)hook)]; }
    } @catch (NSException *e) {}
}

// ==================== 段 2/3 结束 ====================
// ============================================================================
// Web 相机
// ============================================================================
static void vcam_evalJSInFrame(id webView, id message, NSString *js) {
    @try {
        SEL frameSel = @selector(evaluateJavaScript:inFrame:inContentWorld:completionHandler:);
        if ([webView respondsToSelector:frameSel]) {
            id frameInfo = [message valueForKey:@"frameInfo"];
            Class worldClass = objc_getClass("WKContentWorld");
            id pageWorld = ((id(*)(Class,SEL))objc_msgSend)(worldClass, @selector(pageWorld));
            ((void(*)(id,SEL,id,id,id,id))objc_msgSend)(webView, frameSel, js, frameInfo, pageWorld, nil);
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [webView performSelector:@selector(evaluateJavaScript:completionHandler:) withObject:js withObject:nil];
#pragma clang diagnostic pop
        }
    } @catch (NSException *e) {}
}

@protocol WKScriptMessageHandler <NSObject>
- (void)userContentController:(id)ucc didReceiveScriptMessage:(id)message;
@end
@interface FMHdl : NSObject <WKScriptMessageHandler>
- (void)userContentController:(id)ucc didReceiveScriptMessage:(id)message;
@end
@implementation FMHdl
- (void)userContentController:(id)ucc didReceiveScriptMessage:(id)message {
    @try {
        vcam_readControls();
        static NSData *sLastWebJPEG = nil;
        id webView = [message valueForKey:@"webView"];
        if (!webView) return;
        NSString *body = [message valueForKey:@"body"];
        if ([body isKindOfClass:[NSString class]] && [body hasPrefix:@"vcam-"]) return;
        NSData *jpegData = [NSData dataWithContentsOfFile:VCAM_IMAGE];
        if (!jpegData || jpegData.length == 0) {
            if (gCICtx) {
                CIImage *img = nil;
                CMSampleBufferRef vf = nil;
                if (gVideoPaused && gPausedFrame) {
                    img = gPausedFrame;
                } else {
                    vf = vcam_readFrame(gLockA, &gReaderA, &gOutputA);
                    if (vf) {
                        CVImageBufferRef pb = CMSampleBufferGetImageBuffer(vf);
                        if (pb) img = [CIImage imageWithCVImageBuffer:pb];
                    }
                    if (img) img = vcam_applyVideoTransforms(img);
                }
                if (img) {
                    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                    jpegData = [gCICtx JPEGRepresentationOfImage:img colorSpace:cs options:@{}];
                    CGColorSpaceRelease(cs);
                }
                if (vf) CFRelease(vf);
            }
        }
        if (!jpegData || jpegData.length == 0) {
            if (sLastWebJPEG) jpegData = sLastWebJPEG;
            else return;
        } else {
            sLastWebJPEG = jpegData;
        }
        NSString *b64 = [jpegData base64EncodedStringWithOptions:0];
        NSString *js = [NSString stringWithFormat:@"if(window.__vcamOnFrame)window.__vcamOnFrame('%@');", b64];
        vcam_evalJSInFrame(webView, message, js);
    } @catch (NSException *e) {}
}
@end

static NSString *vcam_buildWebCamJS(void) {
    @try {
        if (!vcam_isEnabled()) return nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:VCAM_FLAG]) return nil;
        return @"(function(){"
        @"  if (window.__vcamInstalled) return; window.__vcamInstalled = true;"
        @"  var orig = navigator.mediaDevices && navigator.mediaDevices.getUserMedia;"
        @"  if (!orig) return;"
        @"  var cv = document.createElement('canvas'); cv.width = 640; cv.height = 480;"
        @"  var ctx = cv.getContext('2d');"
        @"  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, 640, 480);"
        @"  window.__vcamOnFrame = function(b64){"
        @"    var img = new Image();"
        @"    img.onload = function(){ ctx.drawImage(img, 0, 0, cv.width, cv.height); };"
        @"    img.src = 'data:image/jpeg;base64,' + b64;"
        @"  };"
        @"  var stream = cv.captureStream(30);"
        @"  navigator.mediaDevices.getUserMedia = function(c){"
        @"    if (!c || !c.video) return orig.apply(navigator.mediaDevices, arguments);"
        @"    (function loop(){"
        @"      try { window.webkit.messageHandlers.vcamFrame.postMessage('frame'); } catch(e) {}"
        @"      setTimeout(loop, 33);"
        @"    })();"
        @"    return Promise.resolve(stream);"
        @"  };"
        @"})();";
    } @catch (NSException *e) { return nil; }
}

static CVReturn (*orig_WC_CVPBLockBA)(CVPixelBufferRef, CVPixelBufferLockFlags) = NULL;
static __thread int sWC_InReplace = 0;
static CVReturn hooked_WC_CVPBLockBA(CVPixelBufferRef pb, CVPixelBufferLockFlags flags) {
    CVReturn ret = orig_WC_CVPBLockBA(pb, flags);
    if (ret == kCVReturnSuccess && !sWC_InReplace && pb && vcam_isEnabled()) {
        OSType fmt = CVPixelBufferGetPixelFormatType(pb);
        if (fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
            fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            size_t w = CVPixelBufferGetWidth(pb);
            size_t h = CVPixelBufferGetHeight(pb);
            if (w >= 480 && h >= 480 && w <= 1920 && h <= 1920) {
                CVPixelBufferUnlockBaseAddress(pb, flags);
                sWC_InReplace = 1;
                vcam_replacePixelBuffer(pb);
                sWC_InReplace = 0;
                return orig_WC_CVPBLockBA(pb, flags);
            }
        }
    }
    return ret;
}

static int (*orig_IOSurfaceLock)(IOSurfaceRef, uint32_t, uint32_t *) = NULL;
static IOSurfaceRef (*orig_IOSurfaceLookupFromMachPort)(mach_port_t) = NULL;
static int hooked_IOSurfaceLock(IOSurfaceRef surface, uint32_t options, uint32_t *seed) {
    return orig_IOSurfaceLock(surface, options, seed);
}
static IOSurfaceRef hooked_IOSurfaceLookupFromMachPort(mach_port_t port) {
    return orig_IOSurfaceLookupFromMachPort(port);
}

// ★ 编译修复：WebContent / WebKit.GPU / Safari 三个分支都已 return;，
//   本函数不再被调用。加 __attribute__((unused)) 抑制 -Wunused-function，
//   保证 -Werror 下能编译通过。函数体本身保持不变，未来若要恢复 WebContent/GPU 的
//   hook 能力，只需在 vcamplus_init 里把那两个 return; 改回调用本函数即可。
__attribute__((unused))
static void vcam_webcontent_installHooks(void) {
    @try {
        Class wcObserver = objc_getClass("WebCoreAVVideoCaptureSourceObserver");
        if (wcObserver) vcam_hookClass(wcObserver);
        Class vdoClass = objc_getClass("AVCaptureVideoDataOutput");
        if (vdoClass) {
            SEL sel = @selector(setSampleBufferDelegate:queue:);
            Method m = class_getInstanceMethod(vdoClass, sel);
            if (m) {
                IMP ni = imp_implementationWithBlock(^(id _self, id delegate, dispatch_queue_t queue) {
                    @try {
                        if (delegate) vcam_hookClass(object_getClass(delegate));
                    } @catch (NSException *e) {}
                    ((void(*)(id,SEL,id,dispatch_queue_t))method_getImplementation(m))(_self, sel, delegate, queue);
                });
                method_setImplementation(m, ni);
            }
        }
        if (!_pMSHookFunction) {
            void *substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
            if (!substrate) substrate = dlopen("/var/jb/usr/lib/libsubstrate.dylib", RTLD_LAZY);
            if (!substrate) substrate = dlopen("/var/jb/usr/lib/substitute-inserter.dylib", RTLD_LAZY);
            if (substrate) _pMSHookFunction = (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        }
        if (_pMSHookFunction) {
            _pMSHookFunction((void *)CVPixelBufferLockBaseAddress, (void *)hooked_WC_CVPBLockBA, (void **)&orig_WC_CVPBLockBA);
            _pMSHookFunction((void *)IOSurfaceLock, (void *)hooked_IOSurfaceLock, (void **)&orig_IOSurfaceLock);
            _pMSHookFunction((void *)IOSurfaceLookupFromMachPort, (void *)hooked_IOSurfaceLookupFromMachPort, (void **)&orig_IOSurfaceLookupFromMachPort);
        }
    } @catch (NSException *e) {}
}

static void vcam_installWebCamHook(void) {
    @try {
        Class wkClass = objc_getClass("WKWebView");
        if (!wkClass) return;
        SEL sel = @selector(initWithFrame:configuration:);
        Method m = class_getInstanceMethod(wkClass, sel);
        if (m) {
            typedef id (*F)(id, SEL, CGRect, id);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^id(id _self, CGRect frame, id config) {
                @try {
                    NSString *js = vcam_buildWebCamJS();
                    if (js) {
                        id ucc = [config valueForKey:@"userContentController"];
                        if (!ucc) {
                            ucc = [[objc_getClass("WKUserContentController") alloc] init];
                            [config setValue:ucc forKey:@"userContentController"];
                        }
                        static FMHdl *sMsgHandler = nil;
                        if (!sMsgHandler) sMsgHandler = [[FMHdl alloc] init];
                        @try {
                            [(WKUserContentController *)ucc performSelector:@selector(removeScriptMessageHandlerForName:)
                                withObject:@"vcamFrame"];
                        } @catch (NSException *e2) {}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [(WKUserContentController *)ucc performSelector:@selector(addScriptMessageHandler:name:)
                            withObject:sMsgHandler withObject:@"vcamFrame"];
#pragma clang diagnostic pop
                        WKUserScript *script = [(WKUserScript *)[objc_getClass("WKUserScript") alloc]
                            initWithSource:js injectionTime:0 forMainFrameOnly:NO];
                        [(WKUserContentController *)ucc addUserScript:script];
                    }
                } @catch (NSException *e) {}
                return orig(_self, sel, frame, config);
            });
            method_setImplementation(m, ni);
        }
    } @catch (NSException *e) {}
}

// ============================================================================
// vcam_installHooks 装配
// ============================================================================
static void vcam_installHooks(void) {
    if (!_cachedBID) {
        _cachedBID = [[NSBundle mainBundle] bundleIdentifier];
        _isWeChat = [_cachedBID containsString:@"tencent.xin"] || [_cachedBID containsString:@"tencent.qy.xin"];
    }
    // [段1] setSampleBufferDelegate:queue:
    {
        Class cls = objc_getClass("AVCaptureVideoDataOutput");
        SEL sel = @selector(setSampleBufferDelegate:queue:);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef void (*F)(id, SEL, id, dispatch_queue_t);
            __block F orig = NULL;
            IMP ni = imp_implementationWithBlock(^(id _self, id delegate, dispatch_queue_t queue) {
                @try {
                    if (delegate) {
                        Class dcls = object_getClass(delegate);
                        SEL ds = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
                        Method dm = class_getInstanceMethod(dcls, ds);
                        IMP di = dm ? method_getImplementation(dm) : NULL;
                        BOOL isOurs = NO;
                        @synchronized(gHookIMPs) { isOurs = [gHookIMPs containsObject:@((uintptr_t)di)]; }
                        if (!isOurs) {
                            if (!dm) vcam_isaSwizzleDelegate(delegate);
                            else vcam_hookClass(dcls);
                        }
                    }
                } @catch (NSException *e) {}
                if (orig) orig(_self, sel, delegate, queue);
            });
            IMP origIMP = vcam_hookMethod(cls, sel, ni);
            if (origIMP) orig = (F)origIMP;
        }
    }
    // [段2] appendPixelBuffer:withPresentationTime:
    {
        Class cls = objc_getClass("AVAssetWriterInputPixelBufferAdaptor");
        SEL sel = @selector(appendPixelBuffer:withPresentationTime:);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef BOOL (*F)(id, SEL, CVPixelBufferRef, CMTime);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^BOOL(id _self, CVPixelBufferRef pb, CMTime pts) {
                if (_self == gRecWriterAdaptor) return orig ? orig(_self, sel, pb, pts) : NO;
                if (_isWeChat && !gCameraSessionActive) return orig ? orig(_self, sel, pb, pts) : NO;
                if (vcam_isEnabled() && pb) vcam_replacePixelBuffer(pb);
                return orig ? orig(_self, sel, pb, pts) : NO;
            });
            method_setImplementation(m, ni);
        }
    }
    // [段2b] appendSampleBuffer:
    {
        Class cls = objc_getClass("AVAssetWriterInput");
        if (cls) {
            SEL sel = @selector(appendSampleBuffer:);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                typedef BOOL (*F)(id, SEL, CMSampleBufferRef);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^BOOL(id _self, CMSampleBufferRef sb) {
                    @try {
                        if (_self == gRecWriterInput) return orig ? orig(_self, sel, sb) : NO;
                        if (_isWeChat && !gCameraSessionActive) return orig ? orig(_self, sel, sb) : NO;
                        if (vcam_isEnabled() && sb) {
                            CVImageBufferRef pb = CMSampleBufferGetImageBuffer(sb);
                            if (pb) vcam_replacePixelBuffer(pb);
                        }
                    } @catch (NSException *e) {}
                    return orig ? orig(_self, sel, sb) : NO;
                });
                method_setImplementation(m, ni);
            }
        }
    }
    // [段3] startRunning
    {
        Class cls = objc_getClass("AVCaptureSession");
        SEL sel = @selector(startRunning);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef void (*F)(id, SEL);
            __block F orig = NULL;
            IMP ni = imp_implementationWithBlock(^(id _self) {
                if (orig) orig(_self, sel);
                gCameraSessionActive = YES;
                @try {
                    void (^scanOutputs)(id) = ^(id session) {
                        @try {
                            Class vdoClass = objc_getClass("AVCaptureVideoDataOutput");
                            Class metaCls = objc_getClass("AVCaptureMetadataOutput");
                            NSArray *outputs = [session performSelector:@selector(outputs)];
                            for (id output in outputs) {
                                if ([output isKindOfClass:vdoClass]) {
                                    id delegate = [output performSelector:@selector(sampleBufferDelegate)];
                                    if (delegate) {
                                        Class dcls = object_getClass(delegate);
                                        SEL ds = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
                                        Method dm = class_getInstanceMethod(dcls, ds);
                                        IMP di = dm ? method_getImplementation(dm) : NULL;
                                        BOOL isOurs = NO;
                                        @synchronized(gHookIMPs) { isOurs = [gHookIMPs containsObject:@((uintptr_t)di)]; }
                                        if (!isOurs) {
                                            if (!dm) vcam_isaSwizzleDelegate(delegate);
                                            else vcam_hookClass(dcls);
                                        }
                                    }
                                } else if (metaCls && [output isKindOfClass:metaCls]) {
                                    id mdelegate = [output performSelector:@selector(metadataObjectsDelegate)];
                                    if (mdelegate) vcam_hookMetadataDelegate(object_getClass(mdelegate));
                                }
                            }
                        } @catch (NSException *e) {}
                    };
                    scanOutputs(_self);
                    __weak id weakSelf = _self;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{ if (weakSelf) scanOutputs(weakSelf); });
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{ if (weakSelf) scanOutputs(weakSelf); });
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{ if (weakSelf) scanOutputs(weakSelf); });
                } @catch (NSException *e) {}
            });
            IMP origIMP = vcam_hookMethod(cls, sel, ni);
            if (origIMP) orig = (F)origIMP;
        }
    }
    // [段4] stopRunning
    {
        Class cls = objc_getClass("AVCaptureSession");
        SEL sel = @selector(stopRunning);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef void (*F)(id, SEL);
            __block F orig = NULL;
            IMP ni = imp_implementationWithBlock(^(id _self) {
                gCameraSessionActive = NO;
                if (orig) orig(_self, sel);
            });
            IMP origIMP = vcam_hookMethod(cls, sel, ni);
            if (origIMP) orig = (F)origIMP;
        }
    }
    // [段5] addOutput:
    {
        Class cls = objc_getClass("AVCaptureSession");
        SEL sel = @selector(addOutput:);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef void (*F)(id, SEL, id);
            __block F orig = NULL;
            Class vdoClass = objc_getClass("AVCaptureVideoDataOutput");
            Class photoBase = objc_getClass("AVCapturePhotoOutput");
            IMP ni = imp_implementationWithBlock(^(id _self, id output) {
                if (orig) orig(_self, sel, output);
                @try {
                    if (output && photoBase && [output isKindOfClass:photoBase]) {
                        vcam_hookPhotoCaptureOnClass(object_getClass(output));
                    }
                    if (output && vdoClass && [output isKindOfClass:vdoClass]) {
                        id delegate = [output performSelector:@selector(sampleBufferDelegate)];
                        if (delegate) {
                            Class dcls = object_getClass(delegate);
                            SEL ds = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
                            Method dm = class_getInstanceMethod(dcls, ds);
                            IMP di = dm ? method_getImplementation(dm) : NULL;
                            BOOL isOurs = NO;
                            @synchronized(gHookIMPs) { isOurs = [gHookIMPs containsObject:@((uintptr_t)di)]; }
                            if (!isOurs) {
                                if (!dm) vcam_isaSwizzleDelegate(delegate);
                                else vcam_hookClass(dcls);
                            }
                        }
                    }
                    vcam_hookPHAsset();
                } @catch (NSException *e) {}
            });
            IMP origIMP = vcam_hookMethod(cls, sel, ni);
            if (origIMP) orig = (F)origIMP;
        }
    }
    // [段6] CALayer -addSublayer:
    {
        Class cls = objc_getClass("CALayer");
        SEL sel = @selector(addSublayer:);
        Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (m) {
            typedef void (*F)(id, SEL, CALayer *);
            F orig = (F)method_getImplementation(m);
            IMP ni = imp_implementationWithBlock(^(id _self, CALayer *layer) {
                if (orig) orig(_self, sel, layer);
                @try {
                    if (!gPreviewLayerClass || ![layer isKindOfClass:gPreviewLayerClass]) return;
                    if (!vcam_isEnabled()) return;
                    [OVLay attachTo:layer];
                } @catch (NSException *e) {}
            });
            method_setImplementation(m, ni);
        }
    }
    // [段7] AVCaptureVideoPreviewLayer -setSession: / +layerWithSession:
    {
        Class cls = objc_getClass("AVCaptureVideoPreviewLayer");
        if (cls) {
            SEL sel = @selector(setSession:);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                typedef void (*F)(id, SEL, id);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^(id _self, id session) {
                    if (orig) orig(_self, sel, session);
                    @try {
                        if (!session || !vcam_isEnabled()) return;
                        [OVLay attachTo:(CALayer *)_self];
                    } @catch (NSException *e) {}
                });
                method_setImplementation(m, ni);
            }
            SEL sel2 = @selector(layerWithSession:);
            Method m2 = class_getClassMethod(cls, sel2);
            if (m2) {
                typedef id (*F)(id, SEL, id);
                F orig2 = (F)method_getImplementation(m2);
                IMP ni2 = imp_implementationWithBlock(^id(id _self, id session) {
                    id layer = orig2 ? orig2(_self, sel2, session) : nil;
                    @try {
                        if (layer && session && vcam_isEnabled()) [OVLay attachTo:(CALayer *)layer];
                    } @catch (NSException *e) {}
                    return layer;
                });
                method_setImplementation(m2, ni2);
            }
        }
    }
    // [段8] capturePhotoWithSettings:delegate:
    vcam_hookPhotoCaptureOnClass(objc_getClass("AVCapturePhotoOutput"));
    // [段9] AVCapturePhoto 数据方法
    vcam_hookPhotoDataOnClass(objc_getClass("AVCapturePhoto"));
    // [段10] AVCaptureMetadataOutput setMetadataObjectsDelegate:queue:
    {
        Class metaCls = objc_getClass("AVCaptureMetadataOutput");
        if (metaCls) {
            SEL sel = @selector(setMetadataObjectsDelegate:queue:);
            Method m = class_getInstanceMethod(metaCls, sel);
            if (m) {
                typedef void (*F)(id, SEL, id, dispatch_queue_t);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^(id _self, id delegate, dispatch_queue_t queue) {
                    @try {
                        if (delegate) vcam_hookMetadataDelegate(object_getClass(delegate));
                    } @catch (NSException *e) {}
                    if (orig) orig(_self, sel, delegate, queue);
                });
                method_setImplementation(m, ni);
            }
        }
    }
    // [段11] AVCaptureMovieFileOutput 录像
    {
        Class cls = objc_getClass("AVCaptureMovieFileOutput");
        if (cls) {
            SEL sel = @selector(startRecordingToOutputFileURL:recordingDelegate:);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                typedef void (*F)(id, SEL, NSURL *, id);
                F orig = (F)method_getImplementation(m);
                IMP ni = imp_implementationWithBlock(^(id _self, NSURL *url, id delegate) {
                    @try {
                        if (vcam_isEnabled()) {
                            gRecOriginalURL = [url copy];
                            size_t w = 0, h = 0;
                            @try {
                                NSArray *conns = [_self performSelector:@selector(connections)];
                                for (id conn in conns) {
                                    id out = [conn performSelector:@selector(output)];
                                    if (out == _self) {
                                        NSArray *ports = [conn performSelector:@selector(inputPorts)];
                                        if (ports && [ports count] > 0) {
                                            id port = [ports objectAtIndex:0];
                                            if ([port respondsToSelector:@selector(formatDescription)]) {
                                                CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)[port performSelector:@selector(formatDescription)];
                                                if (fmt) {
                                                    CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(fmt);
                                                    w = dims.width; h = dims.height;
                                                }
                                            }
                                        }
                                        // formatDescription 返回的是传感器/编码分辨率（一般横向）。
                                        // 按 videoOrientation 校正宽高，否则竖屏录制得到横屏视频，
                                        // 放进竖屏容器后 aspectFit 居中 → 画面"缩小"。
                                        if ([conn respondsToSelector:@selector(videoOrientation)]) {
                                            NSInteger orient = ((NSInteger (*)(id, SEL))objc_msgSend)(conn, @selector(videoOrientation));
                                            if ((orient == 1 || orient == 2) && w > h) {
                                                size_t tmp = w; w = h; h = tmp;
                                            }
                                            if ((orient == 3 || orient == 4) && h > w) {
                                                size_t tmp = w; w = h; h = tmp;
                                            }
                                        }
                                        break;
                                    }
                                }
                            } @catch (NSException *e) {}
                            if (w == 0 || h == 0) { w = 1080; h = 1920; }
                            vcam_startVirtualRecording(w, h);
                            if (delegate) vcam_hookRecordingDelegate(object_getClass(delegate));
                        }
                    } @catch (NSException *e) {}
                    if (orig) orig(_self, sel, url, delegate);
                });
                method_setImplementation(m, ni);
            }
            SEL sel2 = @selector(stopRecording);
            Method m2 = class_getInstanceMethod(cls, sel2);
            if (m2) {
                typedef void (*F)(id, SEL);
                F orig2 = (F)method_getImplementation(m2);
                IMP ni2 = imp_implementationWithBlock(^(id _self) {
                    @try { if (gIsRecordingVideo) vcam_stopVirtualRecording(); } @catch (NSException *e) {}
                    if (orig2) orig2(_self, sel2);
                });
                method_setImplementation(m2, ni2);
            }
        }
    }
}

// ============================================================================
// UI 面板与悬浮球
// ============================================================================
@interface UIHlp : NSObject <PHPickerViewControllerDelegate>
+ (instancetype)shared;
@end

@interface PTSecureField : UITextField
@end
@implementation PTSecureField
- (BOOL)canBecomeFirstResponder { return NO; }
@end

@interface PTContentView : UIView
@end
@implementation PTContentView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (!v) return nil;
    UIView *node = v;
    while (node && node != self) {
        if ([node isKindOfClass:[UIControl class]] || node.tag == 9901) return v;
        node = node.superview;
    }
    return nil;
}
@end

@interface PTWnd : UIWindow
@end
@implementation PTWnd
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 只有三指触摸才把透明窗口设为命中目标，普通触摸继续穿过到原 App。
    if (event.allTouches.count >= 3) return self.rootViewController.view;
    return [super hitTest:point withEvent:event];
}
@end

@interface FWCtrl : NSObject
+ (instancetype)shared;
+ (void)show;
- (void)refreshPanelIfNeeded;
@end

static char kVCAMButtonColorKey;
static char kVCAMActionLongPressKey;

@implementation FWCtrl {
    PTWnd *_window;
    PTSecureField *_secureField;
    PTContentView *_contentView;
    UIButton *_floatBtn;
    UIView *_panel;
    UIScrollView *_scroll;
    NSArray *_segBtns;
    UILabel *_statusBadge;
    UILabel *_licenseStatus;
    UITextField *_licenseInput;
    UISwitch *_toggleSw;
    NSTimer *_licenseTimer;
    BOOL _interfaceHidden;
}

+ (instancetype)shared {
    static FWCtrl *inst; static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[FWCtrl alloc] init]; });
    return inst;
}
+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        FWCtrl *inst = [FWCtrl shared];
        if (inst->_window) return;
        [inst createWindow];
    });
}
- (void)createWindow {
    if (_window) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (!scene) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
    }
    if (!scene) {
        static int sRetry = 0; sRetry++;
        if (sRetry > 60) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ [self createWindow]; });
        return;
    }
    CGRect screen = scene.coordinateSpace.bounds;
    _window = [[PTWnd alloc] initWithWindowScene:scene];
    _window.frame = screen;
    _window.windowLevel = UIWindowLevelAlert + 100;
    _window.backgroundColor = [UIColor clearColor];
    _window.hidden = NO;

    UIViewController *rootVC = [UIViewController new];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = YES;
    _window.rootViewController = rootVC;

    // 安全文本容器：悬浮球与面板常驻此层，不靠截屏通知事后隐藏。
    _secureField = [[PTSecureField alloc] initWithFrame:rootVC.view.bounds];
    _secureField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _secureField.secureTextEntry = YES;
    _secureField.backgroundColor = [UIColor clearColor];
    _secureField.text = @" ";
    _secureField.textColor = [UIColor clearColor];
    _secureField.tintColor = [UIColor clearColor];
    [rootVC.view addSubview:_secureField];
    UIView *secureContainer = _secureField.subviews.firstObject;
    if (!secureContainer) secureContainer = _secureField;
    _contentView = [[PTContentView alloc] initWithFrame:secureContainer.bounds];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentView.backgroundColor = [UIColor clearColor];
    [secureContainer addSubview:_contentView];

    UITapGestureRecognizer *threeFinger = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleThreeFingerDoubleTap:)];
    threeFinger.numberOfTouchesRequired = 3;
    threeFinger.numberOfTapsRequired = 2;
    threeFinger.cancelsTouchesInView = NO;
    [rootVC.view addGestureRecognizer:threeFinger];

    CGFloat bs = 56;
    CGFloat bx = screen.size.width - bs - 20;
    CGFloat by = screen.size.height / 2 - bs / 2;
    _floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _floatBtn.frame = CGRectMake(bx, by, bs, bs);
    _floatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.65];
    _floatBtn.layer.cornerRadius = bs / 2;
    _floatBtn.layer.borderWidth = 1.5;
    _floatBtn.layer.borderColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.7 alpha:0.8].CGColor;
    _floatBtn.layer.shadowColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.7 alpha:1.0].CGColor;
    _floatBtn.layer.shadowRadius = 8;
    _floatBtn.layer.shadowOpacity = 0.8;
    _floatBtn.layer.shadowOffset = CGSizeZero;
    UIImage *icon = [UIImage systemImageNamed:@"camera.viewfinder"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightLight]];
    if (icon) {
        [_floatBtn setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        _floatBtn.tintColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.7 alpha:1.0];
    } else {
        [_floatBtn setTitle:@"相机" forState:UIControlStateNormal];
        _floatBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    }
    [_floatBtn addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [_floatBtn addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [_floatBtn addTarget:self action:@selector(btnUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_floatBtn addGestureRecognizer:pan];
    [_contentView addSubview:_floatBtn];

    _licenseTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [self updateStatusBadge];
    }];
    if (!vcam_licenseIsValid()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ [self showPanel]; });
    }
}
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:_floatBtn.superview];
    CGPoint c = CGPointMake(_floatBtn.center.x + t.x, _floatBtn.center.y + t.y);
    CGFloat hw = _floatBtn.frame.size.width / 2;
    CGFloat hh = _floatBtn.frame.size.height / 2;
    c.x = MAX(hw, MIN(_window.bounds.size.width - hw, c.x));
    c.y = MAX(hh, MIN(_window.bounds.size.height - hh, c.y));
    _floatBtn.center = c;
    [pan setTranslation:CGPointZero inView:_floatBtn.superview];
    [self updatePanelPosition];
}
- (void)handleThreeFingerDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    [self setInterfaceHidden:!_interfaceHidden];
}
- (void)setInterfaceHidden:(BOOL)hidden {
    _interfaceHidden = hidden;
    if (hidden) [self dismissPanel];
    _floatBtn.hidden = hidden;
}
- (void)showMenu {
    if (_interfaceHidden) return;
    if (_panel) [self dismissPanel]; else [self showPanel];
}
- (void)showPanel {
    if (_panel || _interfaceHidden) return;
    CGFloat screenW = _window.bounds.size.width;
    CGFloat screenH = _window.bounds.size.height;
    CGFloat pw = MIN(340, screenW - 30);
    CGFloat ph = MIN(640, screenH - 30);
    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, ph)];
    _panel.tag = 9901;
    _panel.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.96];
    _panel.layer.cornerRadius = 18;
    _panel.layer.borderWidth = 1.0;
    _panel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    _panel.clipsToBounds = YES;
    [self buildPanelContent];
    [_contentView addSubview:_panel];
    [self updatePanelPosition];
}
- (void)updatePanelPosition {
    if (!_panel || !_floatBtn || !_window) return;
    CGFloat w = _panel.frame.size.width;
    CGFloat h = _panel.frame.size.height;
    CGRect ballF = _floatBtn.frame;
    CGFloat screenW = _window.bounds.size.width;
    CGFloat screenH = _window.bounds.size.height;
    CGFloat px = 15, py = 15;
    BOOL found = NO;
    CGFloat rightX = CGRectGetMaxX(ballF) + 12;
    if (rightX + w <= screenW - 15) {
        CGFloat ty = ballF.origin.y + ballF.size.height/2 - h/2;
        ty = MAX(15, MIN(screenH - h - 15, ty));
        px = rightX; py = ty; found = YES;
    }
    if (!found) {
        CGFloat leftX = ballF.origin.x - w - 12;
        if (leftX >= 15) {
            CGFloat ty = ballF.origin.y + ballF.size.height/2 - h/2;
            ty = MAX(15, MIN(screenH - h - 15, ty));
            px = leftX; py = ty; found = YES;
        }
    }
    if (!found) {
        px = MAX(15, MIN(screenW - w - 15, ballF.center.x - w / 2));
        py = (ballF.center.y > screenH / 2) ? 15 : screenH - h - 15;
    }
    [UIView animateWithDuration:0.2 animations:^{ self->_panel.frame = CGRectMake(px, py, w, h); }];
}
- (void)btnDown:(UIButton *)btn {
    UIColor *normal = btn.backgroundColor ?: [UIColor clearColor];
    objc_setAssociatedObject(btn, &kVCAMButtonColorKey, normal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView animateWithDuration:0.1 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.94, 0.94);
        btn.alpha = 0.92;
        btn.backgroundColor = [[UIColor systemCyanColor] colorWithAlphaComponent:0.72];
    }];
}
- (void)btnUp:(UIButton *)btn {
    UIColor *normal = objc_getAssociatedObject(btn, &kVCAMButtonColorKey);
    [UIView animateWithDuration:0.15 animations:^{
        btn.transform = CGAffineTransformIdentity;
        btn.alpha = 1.0;
        if (normal) btn.backgroundColor = normal;
    }];
}
- (UIButton *)makeBtn:(NSString *)title bgColor:(UIColor *)bgColor frame:(CGRect)frame tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.backgroundColor = bgColor ?: [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    btn.layer.cornerRadius = 10;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    btn.tag = tag;
    [btn addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(btnUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [btn addTarget:self action:@selector(btnTap:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}
- (UILabel *)makeLabel:(NSString *)text frame:(CGRect)frame size:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    label.textColor = color;
    return label;
}
- (void)buildPanelContent {
    CGFloat cw = _panel.frame.size.width;
    CGFloat padding = 18;
    CGFloat contentW = cw - padding * 2;
    _scroll = [[UIScrollView alloc] initWithFrame:_panel.bounds];
    _scroll.showsVerticalScrollIndicator = YES;
    _scroll.alwaysBounceVertical = YES;
    [_panel addSubview:_scroll];

    CGFloat y = 18;
    UILabel *title = [self makeLabel:@"虚拟相机" frame:CGRectMake(padding, y, 160, 28) size:21 color:[UIColor whiteColor]];
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    [_scroll addSubview:title];
    _statusBadge = [[UILabel alloc] initWithFrame:CGRectMake(cw - padding - 76, y + 2, 76, 24)];
    _statusBadge.layer.cornerRadius = 12;
    _statusBadge.clipsToBounds = YES;
    _statusBadge.textAlignment = NSTextAlignmentCenter;
    _statusBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [_scroll addSubview:_statusBadge];
    y += 40;

    UIView *licenseBox = [[UIView alloc] initWithFrame:CGRectMake(padding, y, contentW, 218)];
    licenseBox.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    licenseBox.layer.cornerRadius = 12;
    [_scroll addSubview:licenseBox];
    UILabel *licenseTitle = [self makeLabel:@"卡密激活（一机一码）" frame:CGRectMake(12, 10, contentW - 24, 20)
        size:15 color:[UIColor whiteColor]];
    [licenseBox addSubview:licenseTitle];
    UILabel *deviceTitle = [self makeLabel:@"设备码 ID（发给签发方）" frame:CGRectMake(12, 36, contentW - 24, 16)
        size:11 color:[[UIColor whiteColor] colorWithAlphaComponent:0.65]];
    [licenseBox addSubview:deviceTitle];
    UILabel *deviceCode = [self makeLabel:vcam_deviceCode() frame:CGRectMake(12, 55, contentW - 82, 42)
        size:12 color:[UIColor systemCyanColor]];
    deviceCode.numberOfLines = 2;
    [licenseBox addSubview:deviceCode];
    UIButton *copyBtn = [self makeBtn:@"复制" bgColor:[[UIColor whiteColor] colorWithAlphaComponent:0.16]
        frame:CGRectMake(contentW - 62, 59, 50, 32) tag:21];
    [licenseBox addSubview:copyBtn];
    _licenseStatus = [self makeLabel:@"" frame:CGRectMake(12, 100, contentW - 24, 18) size:12 color:[UIColor systemOrangeColor]];
    [licenseBox addSubview:_licenseStatus];
    _licenseInput = [[UITextField alloc] initWithFrame:CGRectMake(12, 124, contentW - 24, 38)];
    _licenseInput.placeholder = @"输入永久卡密或临时卡密";
    _licenseInput.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    _licenseInput.textColor = [UIColor whiteColor];
    _licenseInput.font = [UIFont systemFontOfSize:12];
    _licenseInput.layer.cornerRadius = 8;
    _licenseInput.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
    _licenseInput.leftViewMode = UITextFieldViewModeAlways;
    _licenseInput.autocorrectionType = UITextAutocorrectionTypeNo;
    _licenseInput.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    [licenseBox addSubview:_licenseInput];
    UIButton *activateBtn = [self makeBtn:@"激活" bgColor:[[UIColor systemBlueColor] colorWithAlphaComponent:0.9]
        frame:CGRectMake(12, 170, contentW - 24, 36) tag:20];
    [licenseBox addSubview:activateBtn];
    y += 230;

    UIButton *mediaBtn = [self makeBtn:@"选择视频 / 图片" bgColor:[UIColor colorWithRed:0.2 green:0.7 blue:0.9 alpha:0.9]
        frame:CGRectMake(padding, y, contentW, 44) tag:1];
    [_scroll addSubview:mediaBtn];
    y += 54;

    UILabel *videoTitle = [self makeLabel:@"视频源（保留原切换功能）" frame:CGRectMake(padding, y, contentW, 18)
        size:12 color:[[UIColor whiteColor] colorWithAlphaComponent:0.65]];
    [_scroll addSubview:videoTitle];
    y += 22;
    UIView *segBg = [[UIView alloc] initWithFrame:CGRectMake(padding, y, contentW, 38)];
    segBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    segBg.layer.cornerRadius = 10;
    [_scroll addSubview:segBg];
    CGFloat segW = (contentW - 8) / 3.0;
    NSMutableArray *segs = [NSMutableArray array];
    for (int i = 1; i <= 3; i++) {
        UIButton *nBtn = [self makeBtn:[NSString stringWithFormat:@"视频 %d", i] bgColor:[UIColor clearColor]
            frame:CGRectMake(4 + (i-1) * segW, 4, segW - 2, 30) tag:200+i];
        nBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [segBg addSubview:nBtn];
        [segs addObject:nBtn];
    }
    _segBtns = segs;
    [self updateSegmentUI];
    y += 48;

    UILabel *actionTitle = [self makeLabel:@"动作（单击播放 · 长按 2 秒设置时间）" frame:CGRectMake(padding, y, contentW, 20)
        size:12 color:[[UIColor whiteColor] colorWithAlphaComponent:0.75]];
    [_scroll addSubview:actionTitle];
    y += 25;
    CGFloat actionGap = 7;
    CGFloat actionW = (contentW - actionGap * 2) / 3.0;
    for (NSInteger action = 1; action <= 6; action++) {
        NSInteger index = action - 1;
        CGFloat x = padding + (index % 3) * (actionW + actionGap);
        CGFloat ay = y + (index / 3) * 47;
        UIButton *actionBtn = [self makeBtn:vcam_actionName(action)
            bgColor:[[UIColor systemTealColor] colorWithAlphaComponent:0.42]
            frame:CGRectMake(x, ay, actionW, 40) tag:300+action];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(actionLongPress:)];
        lp.minimumPressDuration = 2.0;
        lp.cancelsTouchesInView = NO;
        [actionBtn addGestureRecognizer:lp];
        [_scroll addSubview:actionBtn];
    }
    y += 101;
    UIButton *exitAction = [self makeBtn:@"退出动作并恢复循环" bgColor:[[UIColor systemOrangeColor] colorWithAlphaComponent:0.28]
        frame:CGRectMake(padding, y, contentW, 36) tag:300];
    [_scroll addSubview:exitAction];
    y += 48;

    UILabel *sec2 = [self makeLabel:@"画面微调" frame:CGRectMake(padding, y, contentW, 18)
        size:13 color:[[UIColor whiteColor] colorWithAlphaComponent:0.65]];
    [_scroll addSubview:sec2];
    y += 24;
    CGFloat dpadBase = 134;
    UIView *dpadBg = [[UIView alloc] initWithFrame:CGRectMake(padding, y, dpadBase, dpadBase)];
    dpadBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    dpadBg.layer.cornerRadius = 16;
    [_scroll addSubview:dpadBg];
    NSArray *dIcons = @[@"", @"↑", @"", @"←", @"◎", @"→", @"", @"↓", @""];
    int dTags[] = {0, 100, 0, 102, 103, 104, 0, 105, 0};
    CGFloat dSize = 38, dGap = 6;
    for (int i = 0; i < 9; i++) {
        int row = i / 3; int col = i % 3;
        if (dTags[i] == 0) continue;
        UIColor *bgC = (dTags[i] == 103) ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.9]
            : [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        UIButton *btn = [self makeBtn:dIcons[i] bgColor:bgC
            frame:CGRectMake(8 + col*(dSize+dGap), 8 + row*(dSize+dGap), dSize, dSize) tag:dTags[i]];
        btn.layer.cornerRadius = 8;
        [dpadBg addSubview:btn];
    }
    CGFloat sideX = padding + dpadBase + 14;
    CGFloat sideW = cw - sideX - padding;
    UIButton *rotBtn = [self makeBtn:@"旋转" bgColor:[[UIColor systemPurpleColor] colorWithAlphaComponent:0.9]
        frame:CGRectMake(sideX, y, sideW/2 - 4, 40) tag:101];
    UIButton *flipBtn = [self makeBtn:@"翻转" bgColor:[[UIColor systemPurpleColor] colorWithAlphaComponent:0.9]
        frame:CGRectMake(sideX + sideW/2 + 4, y, sideW/2 - 4, 40) tag:106];
    [_scroll addSubview:rotBtn]; [_scroll addSubview:flipBtn];
    UIButton *playBtn = [self makeBtn:@"播放" bgColor:[[UIColor whiteColor] colorWithAlphaComponent:0.15]
        frame:CGRectMake(sideX, y + 48, sideW/2 - 4, 40) tag:107];
    UIButton *pauseBtn = [self makeBtn:@"暂停" bgColor:[[UIColor whiteColor] colorWithAlphaComponent:0.15]
        frame:CGRectMake(sideX + sideW/2 + 4, y + 48, sideW/2 - 4, 40) tag:108];
    [_scroll addSubview:playBtn]; [_scroll addSubview:pauseBtn];
    y += 146;

    UIView *switchBg = [[UIView alloc] initWithFrame:CGRectMake(padding, y, contentW, 54)];
    switchBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    switchBg.layer.cornerRadius = 12;
    [_scroll addSubview:switchBg];
    UILabel *swTitle = [self makeLabel:@"虚拟相机总开关" frame:CGRectMake(16, 0, 200, 54) size:15 color:[UIColor whiteColor]];
    [switchBg addSubview:swTitle];
    _toggleSw = [[UISwitch alloc] initWithFrame:CGRectMake(contentW - 51 - 12, 11.5, 51, 31)];
    _toggleSw.onTintColor = [UIColor systemGreenColor];
    [_toggleSw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [switchBg addSubview:_toggleSw];
    y += 66;

    UIButton *hideBtn = [self makeBtn:@"隐藏面板" bgColor:[[UIColor systemIndigoColor] colorWithAlphaComponent:0.5]
        frame:CGRectMake(padding, y, contentW, 42) tag:10];
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [_scroll addSubview:hideBtn];
    y += 50;
    UIButton *closeBtn = [self makeBtn:@"✖ 关闭面板（保留悬浮球）" bgColor:[[UIColor systemRedColor] colorWithAlphaComponent:0.2]
        frame:CGRectMake(padding, y, contentW, 42) tag:9];
    [closeBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [_scroll addSubview:closeBtn];
    y += 58;
    _scroll.contentSize = CGSizeMake(cw, y);
    [self updateStatusBadge];
}
- (void)updateStatusBadge {
    BOOL on = vcam_licenseIsValid() && vcam_flagExists();
    _statusBadge.text = on ? @"● 已开启" : @"● 已关闭";
    _statusBadge.textColor = on ? [UIColor systemGreenColor] : [UIColor systemRedColor];
    _statusBadge.backgroundColor = on ? [[UIColor systemGreenColor] colorWithAlphaComponent:0.15]
        : [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
    if (_toggleSw) _toggleSw.on = on;
    if (_licenseStatus) {
        BOOL valid = vcam_licenseIsValid();
        _licenseStatus.text = vcam_licenseStatusText();
        _licenseStatus.textColor = valid ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    }
}
- (void)updateSegmentUI {
    for (UIButton *btn in _segBtns) {
        int idx = (int)(btn.tag - 200);
        if (gVideoIndex == idx) {
            btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor clearColor];
            [btn setTitleColor:[[UIColor whiteColor] colorWithAlphaComponent:0.5] forState:UIControlStateNormal];
        }
    }
}
- (void)dismissPanel {
    [_panel removeFromSuperview];
    _panel = nil;
    _scroll = nil;
    _licenseInput = nil;
    _licenseStatus = nil;
}
- (void)switchChanged:(UISwitch *)sw {
    if (!vcam_licenseIsValid()) {
        sw.on = NO;
        [self showLicenseRequired:@"卡密未激活、已过期或设备不匹配，所有功能已停用。"];
        [self updateStatusBadge];
        return;
    }
    if (sw.isOn) vcam_force_write_controls();
    else [[NSFileManager defaultManager] removeItemAtPath:VCAM_FLAG error:nil];
    [self updateStatusBadge];
}
- (void)showLicenseRequired:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要有效卡密"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [_window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)copyDeviceCode {
    [UIPasteboard generalPasteboard].string = vcam_deviceCode();
    _licenseStatus.text = @"设备码已复制，可发给签发方";
}
- (void)activateFromInput {
    NSString *error = nil;
    BOOL ok = vcam_activateLicenseCard(_licenseInput.text, &error);
    [self updateStatusBadge];
    if (!ok) {
        [self showLicenseRequired:error ?: @"激活失败"];
        return;
    }
    _licenseInput.text = @"";
    [_licenseInput resignFirstResponder];
    vcam_force_write_controls();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活成功"
        message:vcam_licenseStatusText() preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [_window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)actionLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIButton *button = (UIButton *)gesture.view;
    NSInteger action = button.tag - 300;
    if (action < 1 || action > 6) return;
    objc_setAssociatedObject(button, &kVCAMActionLongPressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self editTimeForAction:action];
}
- (void)editTimeForAction:(NSInteger)action {
    NSDictionary *pl = [NSDictionary dictionaryWithContentsOfFile:VCAM_ACTIONS];
    int64_t startUs = 0, endUs = 0;
    vcam_actionRangeFromDictionary(pl, action, &startUs, &endUs);
    NSString *name = vcam_actionName(action);
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"设置「%@」时间", name]
        message:@"单位：秒；动作播放结束后定格最后一帧" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"起始"; tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.3f", startUs / 1000000.0];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"结束"; tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.3f", endUs / 1000000.0];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        double start = [alert.textFields[0].text doubleValue];
        double end = [alert.textFields[1].text doubleValue];
        if (start < 0) start = 0;
        if (end <= start) end = start + 0.1;
        int64_t us = (int64_t)llround(start * 1000000.0);
        int64_t ue = (int64_t)llround(end * 1000000.0);
        vcam_updateActions(^(NSMutableDictionary *d) {
            d[[NSString stringWithFormat:@"action%ldStartUs", (long)action]] = @(us);
            d[[NSString stringWithFormat:@"action%ldEndUs", (long)action]] = @(ue);
            d[[NSString stringWithFormat:@"action%ldStart", (long)action]] = @(us / 1000000.0);
            d[[NSString stringWithFormat:@"action%ldEnd", (long)action]] = @(ue / 1000000.0);
        });
    }]];
    [_window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)btnTap:(UIButton *)b {
    NSInteger tag = b.tag;
    if (tag >= 301 && tag <= 306) {
        NSNumber *longFired = objc_getAssociatedObject(b, &kVCAMActionLongPressKey);
        if (longFired.boolValue) {
            objc_setAssociatedObject(b, &kVCAMActionLongPressKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
    }
    if (tag == 9) { [self dismissPanel]; return; }
    if (tag == 10) { [self setInterfaceHidden:YES]; return; }
    if (tag == 21) { [self copyDeviceCode]; return; }
    if (tag == 20) { [self activateFromInput]; return; }
    if (!vcam_licenseIsValid()) {
        [self updateStatusBadge];
        [self showLicenseRequired:@"卡密未激活、已过期或设备不匹配，所有功能已停用。"];
        return;
    }
    if (tag >= 201 && tag <= 203) {
        gVideoIndex = (int)(tag - 200);
        gPausedFrame = nil;
        [self updateSegmentUI];
        vcam_writeControls();
        return;
    }
    if (tag >= 301 && tag <= 306) {
        if (!vcam_videoExists()) {
            [self showLicenseRequired:@"动作播放需要先选择视频，图片模式没有动作时间区间。"];
            return;
        }
        gVideoPaused = NO;
        vcam_force_write_controls();
        vcam_triggerAction(tag - 300);
        return;
    }
    if (tag == 300) { vcam_triggerAction(0); return; }
    if (tag == 100) gVideoOffsetY += 0.05;
    else if (tag == 101) gVideoRotation = (gVideoRotation + 90) % 360;
    else if (tag == 102) gVideoOffsetX -= 0.05;
    else if (tag == 103) { gVideoOffsetX = 0; gVideoOffsetY = 0; }
    else if (tag == 104) gVideoOffsetX += 0.05;
    else if (tag == 105) gVideoOffsetY -= 0.05;
    else if (tag == 106) gVideoFlipH = !gVideoFlipH;
    else if (tag == 107) gVideoPaused = NO;
    else if (tag == 108) gVideoPaused = YES;
    else if (tag == 1) {
        [self dismissPanel];
        Class cfgCls = NSClassFromString(@"PHPickerConfiguration");
        Class pickCls = NSClassFromString(@"PHPickerViewController");
        if (cfgCls && pickCls) {
            PHPickerConfiguration *cfg = [[cfgCls alloc] init];
            cfg.selectionLimit = 1;
            cfg.preferredAssetRepresentationMode = 1;
            PHPickerViewController *picker = [[pickCls alloc] initWithConfiguration:cfg];
            picker.delegate = (id<PHPickerViewControllerDelegate>)[UIHlp shared];
            [_window.rootViewController presentViewController:picker animated:YES completion:nil];
        }
        return;
    }
    vcam_writeControls();
}
- (void)refreshPanelIfNeeded { if (_panel) [self updateStatusBadge]; }
@end

@implementation UIHlp
+ (instancetype)shared {
    static UIHlp *i; static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [[UIHlp alloc] init]; }); return i;
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!vcam_licenseIsValid()) return;
    if (results.count == 0) return;
    NSItemProvider *prov = results.firstObject.itemProvider;
    if ([prov hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [prov loadFileRepresentationForTypeIdentifier:@"public.movie"
            completionHandler:^(NSURL *url, NSError *error) {
                if (!url || error) {
                    vcam_log([NSString stringWithFormat:@"PHPicker video load err: %@", error]);
                    return;
                }
                NSString *stagedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_picked_input.mov"];
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm createDirectoryAtPath:VCAM_DIR withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:stagedPath error:nil];
                NSError *cpErr = nil;
                [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:stagedPath] error:&cpErr];
                if (cpErr) {
                    vcam_log([NSString stringWithFormat:@"PHPicker stage copy err: %@", cpErr]);
                    return;
                }
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:stagedPath] options:nil];
                AVAssetExportSession *exp = [[AVAssetExportSession alloc] initWithAsset:asset
                                                presetName:AVAssetExportPresetPassthrough];
                NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vcam_picked_output.mov"];
                [fm removeItemAtPath:outPath error:nil];
                exp.outputURL = [NSURL fileURLWithPath:outPath];
                exp.outputFileType = AVFileTypeQuickTimeMovie;
                [exp exportAsynchronouslyWithCompletionHandler:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSFileManager *fm2 = [NSFileManager defaultManager];
                        if (exp.status != AVAssetExportSessionStatusCompleted) {
                            vcam_log([NSString stringWithFormat:@"Export failed status=%ld err=%@",
                                      (long)exp.status, exp.error]);
                            [fm2 removeItemAtPath:VCAM_VIDEO error:nil];
                            [fm2 removeItemAtPath:VCAM_IMAGE error:nil];
                            [fm2 copyItemAtPath:stagedPath toPath:VCAM_VIDEO error:nil];
                        } else {
                            [fm2 removeItemAtPath:VCAM_VIDEO error:nil];
                            [fm2 removeItemAtPath:VCAM_IMAGE error:nil];
                            [fm2 copyItemAtPath:outPath toPath:VCAM_VIDEO error:nil];
                            vcam_log(@"PHPicker → AVAssetExportPresetPassthrough → video.mp4 (clean .mov container)");
                        }
                        [fm2 removeItemAtPath:stagedPath error:nil];
                        [fm2 removeItemAtPath:outPath error:nil];
                        if (gLockA) { [gLockA lock]; gReaderA = nil; gOutputA = nil; [gLockA unlock]; }
                        if (gLockB) { [gLockB lock]; gReaderB = nil; gOutputB = nil; [gLockB unlock]; }
                        if (gLockPT) { [gLockPT lock]; gReaderPT = nil; gOutputPT = nil; [gLockPT unlock]; }
                        gStaticImage = nil;
                        if (gStaticCGImage) { CGImageRelease(gStaticCGImage); gStaticCGImage = NULL; }
                        vcam_force_write_controls();
                        unsigned long long sz = [[fm2 attributesOfItemAtPath:VCAM_VIDEO error:nil] fileSize];
                        vcam_log([NSString stringWithFormat:@"Final video.mp4 (%llu bytes)", sz]);
                        [[FWCtrl shared] refreshPanelIfNeeded];
                    });
                }];
            }];
    } else if ([prov hasItemConformingToTypeIdentifier:@"public.image"]) {
        [prov loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *data, NSError *error) {
            if (!data) return;
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm createDirectoryAtPath:VCAM_DIR withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:VCAM_VIDEO error:nil];
            [data writeToFile:VCAM_IMAGE atomically:YES];
            if (gLockA) { [gLockA lock]; gReaderA = nil; gOutputA = nil; [gLockA unlock]; }
            if (gLockB) { [gLockB lock]; gReaderB = nil; gOutputB = nil; [gLockB unlock]; }
            if (gLockPT) { [gLockPT lock]; gReaderPT = nil; gOutputPT = nil; [gLockPT unlock]; }
            gStaticImage = nil;
            if (gStaticCGImage) { CGImageRelease(gStaticCGImage); gStaticCGImage = NULL; }
            vcam_force_write_controls();
            dispatch_async(dispatch_get_main_queue(), ^{ [[FWCtrl shared] refreshPanelIfNeeded]; });
        }];
    }
}
@end

// ============================================================================
// Constructor
// ============================================================================
__attribute__((used, constructor))
static void vcamplus_init(void) {
    @autoreleasepool {
        NSString *proc = [[NSProcessInfo processInfo] processName];
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";

        // 系统 daemon 黑名单
        static NSSet *daemonBL = nil;
        if (!daemonBL) {
            daemonBL = [NSSet setWithArray:@[
                @"imagent", @"sharingd", @"nanoregistryd", @"locationd",
                @"profiled", @"passd", @"callservicesd", @"anomalydetectiond",
                @"assistantd", @"touchsetupd", @"AccessibilityUIServer", @"remindd",
                @"SafariBookmarksSyncAgent", @"ScreenTimeAgent",
                @"ScreenshotServicesService", @"Spotlight",
                @"mediaserverd", @"backboardd", @"thermalmonitord",
                @"runningboardd", @"wifid", @"configd", @"logd",
                @"PosterBoard", @"WeatherPoster", @"AegirPoster",
                @"AuthenticationServicesAgent", @"CollectionsPoster",
                @"EmojiPosterExtension", @"ExtragalacticPoster",
                @"GradientPosterExtension", @"PhotosPosterProvider",
                @"PhotosReliveWidget", @"PridePosterExtension",
                @"ScreenTimeWidgetExtension", @"UnityPosterExtension",
                @"WeatherWidget", @"PhotoPicker"
            ]];
        }
        if ([daemonBL containsObject:proc]) return;

        [[NSFileManager defaultManager] createDirectoryAtPath:VCAM_DIR
            withIntermediateDirectories:YES attributes:nil error:nil];

        // ★ 修复：WebContent 分支 → 直接返回，不做任何初始化 / 不装任何 hook
        //   Safari 网页渲染和 WebRTC 依赖此进程。在这里装 C 函数全局 hook
        //   (CVPixelBufferLockBaseAddress / IOSurfaceLock / IOSurfaceLookupFromMachPort)
        //   会命中 WebKit 渲染路径 → 触发 RASP 完整性校验 / 死锁 → Safari 白屏或崩溃。
        //   为保证 Safari 100% 能打开，本分支完全不做任何事。
        if ([proc containsString:@"WebContent"]) {
            return;
        }

        // ★ 修复：WebKit.GPU 分支 → 直接返回，不做任何初始化 / 不装任何 hook
        //   同上。GPU 进程是 Safari 的 WebRTC 捕获宿主，在这里 hook C 函数或 ObjC 方法
        //   都会干扰 WebKit 渲染，导致 Safari 打不开。
        //   为保证 Safari 100% 能打开，本分支完全不做任何事。
        BOOL isGPU = [bid containsString:@"WebKit.GPU"] ||
                     ([proc containsString:@"GPU"] && ([bid containsString:@"WebKit"] || [proc containsString:@"WebKit"]));
        if (isGPU) {
            return;
        }

        // Safari UI 进程：不 hook
        if ([bid isEqualToString:@"com.apple.mobilesafari"] || [proc isEqualToString:@"Safari"]) {
            // Safari UI 进程同样不碰。三个进程（UI / WebContent / GPU）全部不接触，
            // Safari 完全运行在原生路径上，100% 能打开。
            // 代价：Safari 网页的 getUserMedia 不替换。
            // 注意：App 内 WKWebView 的虚拟相机不受影响（在普通 App 分支安装）。
            return;
        }

        // SpringBoard
        if ([proc isEqualToString:@"SpringBoard"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ [FWCtrl show]; });
            return;
        }

        // 普通 App
        gLockA = [[NSLock alloc] init];
        gLockB = [[NSLock alloc] init];
        gOverlays = [NSMutableArray new];
        gHookIMPs = [NSMutableSet new];
        gHookedClasses = [NSMutableSet new];
        gHookedPhotoClasses = [NSMutableSet new];
        gPreviewLayerClass = NSClassFromString(@"AVCaptureVideoPreviewLayer");
        gCICtx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
        vcam_installHooks();
        vcam_installWebCamHook();
    }
}
