#import "NativeUI.hpp"
#import "SegmentCodec.hpp"
#include "store.hpp"
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Vision/Vision.h>
#include <atomic>
#include <fstream>
#include <iostream>
#include <memory>
#include <sys/stat.h>
#include <unistd.h>
using namespace afterimage;
static std::unique_ptr<Store> archive;
static std::string smokeOutput;

static NSString* ns(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()] ?: @"";
}

static std::string str(NSString* s) {
    return s ? std::string(s.UTF8String ?: "") : "";
}

static json objJSON(id obj) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:nil];
    return data ? json::parse(std::string((const char*)data.bytes, data.length)) : json();
}

static fs::path defaultRoot() {
    const char* env = getenv("AFTERIMAGE_HOME");
    if (env && *env) {
        return env;
    }
    return fs::path(str(NSHomeDirectory())) / "Library/Application Support/Afterimage";
}

static CGImageRef loadImage(NSString* path) {
    CGImageSourceRef src =
        CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], nil);
    if (!src) {
        return nullptr;
    }
    CGImageRef im = CGImageSourceCreateImageAtIndex(src, 0, nil);
    CFRelease(src);
    return im;
}

static std::vector<unsigned char> grayscale(CGImageRef im) {
    std::vector<unsigned char> p(160 * 90);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(p.data(), 160, 90, 8, 160, cs, kCGImageAlphaNone);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        return {};
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, 160, 90), im);
    CGContextRelease(ctx);
    return p;
}

struct Prepared {
    Frame frame;
    std::vector<unsigned char> bytes;
};

static Prepared prepare(CGImageRef image, Frame f) {
    @autoreleasepool {
        f.width = (int)CGImageGetWidth(image);
        f.height = (int)CGImageGetHeight(image);
        VNRecognizeTextRequest* request = [[VNRecognizeTextRequest alloc] init];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.automaticallyDetectsLanguage = YES;
        VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCGImage:image
                                                                                options:@{}];
        NSError* error = nil;
        if (![handler performRequests:@[ request ] error:&error]) {
            throw std::runtime_error("Text recognition failed: " + str(error.localizedDescription));
        }
        for (VNRecognizedTextObservation* obs in request.results) {
            VNRecognizedText* text = [[obs topCandidates:1] firstObject];
            if (!text) {
                continue;
            }
            auto t = str(text.string);
            if (!f.text.empty()) {
                f.text += '\n';
            }
            f.text += t;
            CGRect r = obs.boundingBox;
            f.boxes.push_back({{"text", t},
                               {"x", r.origin.x},
                               {"y", 1 - r.origin.y - r.size.height},
                               {"w", r.size.width},
                               {"h", r.size.height},
                               {"confidence", text.confidence}});
        }
        NSMutableData* data = [NSMutableData data];
        bool keepJPEG = archive->settings().value("compressionMode", "balanced") == "jpeg";
        CGImageDestinationRef dest = CGImageDestinationCreateWithData(
            (__bridge CFMutableDataRef)data, keepJPEG ? CFSTR("public.jpeg") : CFSTR("public.png"),
            1, nil);
        if (!dest) {
            throw std::runtime_error("Could not create image encoder");
        }
        CGImageDestinationAddImage(
            dest, image,
            (__bridge CFDictionaryRef)
                @{(__bridge NSString*)kCGImageDestinationLossyCompressionQuality : @0.86});
        bool ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        if (!ok) {
            throw std::runtime_error("Image encoding failed");
        }
        std::vector<unsigned char> bytes((const unsigned char*)data.bytes,
                                         (const unsigned char*)data.bytes + data.length);
        return {f, std::move(bytes)};
    }
}

static long long ingest(CGImageRef image, Frame f) {
    auto p = prepare(image, std::move(f));
    auto id = archive->add(p.frame, p.bytes);
    try {
        archive->compact(false);
    } catch (const std::exception&) { /* Saved stills remain readable; maintenance can retry. */
    }
    return id;
}

static long long importImage(const std::string& path, double time) {
    CGImageRef im = loadImage(ns(path));
    if (!im) {
        throw std::runtime_error("Cannot decode image: " + path);
    }
    Frame f;
    f.time = time;
    f.app = "Imported";
    f.bundle = "local.import";
    f.title = fs::path(path).filename().string();
    f.source = "import";
    try {
        auto id = ingest(im, f);
        CGImageRelease(im);
        return id;
    } catch (...) {
        CGImageRelease(im);
        throw;
    }
}

static int cli(int argc, char** argv) {
    try {
        std::string command = argv[1];
        if (command == "--help" || command == "help" || command == "-h") {
            std::cout
                << "Afterimage 0.1.0 — local, searchable screen memory\n\nUsage: "
                   "afterimage [command]\n  (no command)                 Open the "
                   "desktop app\n  search TEXT [options]        Search visible text "
                   "and titles (literal AND terms)\n  list [options]               "
                   "List captured/imported frames, newest first\n  frame ID          "
                   "           Full metadata and normalized OCR boxes\n  stats       "
                   "                 Archive counts, app counts and disk usage\n  "
                   "compact                      Compress pending screenshots into HEVC chunks\n  "
                   "optimize                     Share identical screenshot data losslessly\n  "
                   "doctor                       Permission status and archive "
                   "location\n  import IMAGE [--time EPOCH]   OCR and archive an "
                   "image locally\n  export ID OUTPUT.jpg         Export a saved "
                   "screenshot\n  delete ID                    Delete a screenshot "
                   "and its search entry\n  prune DAYS                   Delete "
                   "frames older than DAYS\n  settings                     Read "
                   "capture/retention/exclusion settings\n\nOptions: --app BUNDLE_ID "
                   "--from EPOCH --to EPOCH --limit N --offset N\nAll results are "
                   "JSON. AFTERIMAGE_HOME overrides the local archive "
                   "directory.\nThe app is not required for archive queries. "
                   "Start/stop recording in the app.\n";
            return 0;
        }
        archive = std::make_unique<Store>(defaultRoot(), appleSegmentCodec());
        json result;
        if (command == "compact") {
            result = archive->compact();
        } else if (command == "optimize") {
            result = archive->optimize();
        } else if (command == "stats") {
            result = archive->stats();
        } else if (command == "settings") {
            result = archive->settings();
        } else if (command == "doctor") {
            result = {{"screenRecordingPermission", (bool)CGPreflightScreenCaptureAccess()},
                      {"archivePath", archive->root().string()},
                      {"version", "0.1.0"}};
        } else if (command == "frame" && argc == 3) {
            result = archive->frame(std::stoll(argv[2]));
        } else if (command == "delete" && argc == 3) {
            archive->erase(std::stoll(argv[2]));
            result = {{"deleted", std::stoll(argv[2])}};
        } else if (command == "prune" && argc == 3) {
            result = {{"deleted", archive->prune(std::stoi(argv[2]), now())}};
        } else if (command == "import" && (argc == 3 || argc == 5)) {
            double time = now();
            if (argc == 5) {
                if (std::string(argv[3]) != "--time") {
                    throw std::runtime_error("Expected --time EPOCH");
                }
                time = std::stod(argv[4]);
            }
            result = archive->frame(importImage(argv[2], time));
        } else if (command == "export" && argc == 4) {
            if (fs::exists(argv[3])) {
                throw std::runtime_error("Export destination already exists");
            }
            exportScreenshot(archive->image(std::stoll(argv[2])), argv[3]);
            result = {{"exported", argv[3]}};
        } else if (command == "search" || command == "list") {
            std::string q, app;
            int i = 2, limit = 100, offset = 0;
            double from = 0, to = 1e15;
            if (command == "search") {
                if (argc < 3) {
                    throw std::runtime_error("Supply search text");
                }
                q = argv[i++];
            }
            for (; i < argc; i += 2) {
                if (i + 1 >= argc) {
                    throw std::runtime_error("Missing option value");
                }
                std::string k = argv[i], v = argv[i + 1];
                if (k == "--app") {
                    app = v;
                } else if (k == "--from") {
                    from = std::stod(v);
                } else if (k == "--to") {
                    to = std::stod(v);
                } else if (k == "--limit") {
                    limit = std::stoi(v);
                } else if (k == "--offset") {
                    offset = std::stoi(v);
                } else {
                    throw std::runtime_error("Unknown option: " + k);
                }
            }
            result = archive->frames(q, app, from, to, limit, offset);
        } else {
            throw std::runtime_error("Invalid command or arguments. Use --help.");
        }
        std::cout << result.dump(2) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << json({{"error", e.what()}}).dump() << '\n';
        return 1;
    }
}

@interface App : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSWindow* window;
    NativeUI* nativeUI;
    NSMutableDictionary* callbacks;
    NSInteger nextRequest;
    NSStatusItem* statusItem;
    NSMenuItem* recordingItem;
    NSTimer* timer;
    dispatch_queue_t worker, imageWorker;
    std::atomic<uint64_t> latestImageRequest;
    BOOL recording, busy;
    NSInteger generation;
    std::string captureState, lastError, compressionError;
    long long captured, skipped;
    double lastOCR;
    ChangeGate gate;
    json preferences;
}
- (void)performAction:(NSDictionary*)body;
@end
@implementation App

- (void)applicationDidFinishLaunching:(NSNotification*)n {
    (void)n;
    latestImageRequest = 0;
    imageWorker = dispatch_queue_create("app.afterimage.images", DISPATCH_QUEUE_SERIAL);
    worker = dispatch_queue_create("app.afterimage.processing", DISPATCH_QUEUE_SERIAL);
    preferences = archive->settings();
    captureState = "Paused";
    NSMenu* main = [[NSMenu alloc] init];
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    [main addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Afterimage"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Afterimage" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSMenuItem* editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    [main addItem:editItem];
    NSApp.mainMenu = main;
    callbacks = [NSMutableDictionary new];
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1380, 900)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                            NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Afterimage";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    window.minSize = NSMakeSize(840, 600);
    window.delegate = self;
    __weak App* weakSelf = self;
    nativeUI = [[NativeUI alloc]
        initWithRequest:^(NSString* action, json args, UICompletion completion) {
          App* owner = weakSelf;
          if (!owner) {
              return;
          }
          NSString* identity = [NSString stringWithFormat:@"%ld", ++owner->nextRequest];
          owner->callbacks[identity] = [completion copy];
          NSDictionary* arguments = [NSJSONSerialization
              JSONObjectWithData:[ns(args.dump()) dataUsingEncoding:NSUTF8StringEncoding]
                         options:0
                           error:nil];
          [owner performAction:@{@"id" : identity, @"action" : action, @"args" : arguments ?: @{}}];
        }
              imageRoot:ns(archive->root().string())];
    window.contentViewController = nativeUI;
    [window setContentSize:NSMakeSize(1380, 900)];
    if (!smokeOutput.empty() && getenv("AFTERIMAGE_SMOKE_LIGHT")) {
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    if (!smokeOutput.empty() && getenv("AFTERIMAGE_SMOKE_COMPACT")) {
        [window setContentSize:NSMakeSize(840, 578)];
    }
    [window center];
    [window makeKeyAndOrderFront:nil];
    NSMenuItem* settings = [appMenu insertItemWithTitle:@"Settings…"
                                                 action:@selector(showSettings:)
                                          keyEquivalent:@","
                                                atIndex:1];
    settings.target = nativeUI;
    if (!smokeOutput.empty()) {
        [nativeUI smoke:ns(smokeOutput)];
    }
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.title = @"◉";
    statusItem.button.toolTip = @"Afterimage — paused";
    {
        dispatch_async(worker, ^{
          try {
              Store storage(defaultRoot(), appleSegmentCodec());
              storage.compact();
              dispatch_async(dispatch_get_main_queue(), ^{
                compressionError.clear();
              });
          } catch (const std::exception& e) {
              std::string message = e.what();
              dispatch_async(dispatch_get_main_queue(), ^{
                compressionError = "Compression: " + message;
              });
          }
        });
    }
    NSMenu* menu = [[NSMenu alloc] init];
    NSMenuItem* open = [menu addItemWithTitle:@"Open Afterimage"
                                       action:@selector(showWindow:)
                                keyEquivalent:@""];
    open.target = self;
    recordingItem = [menu addItemWithTitle:@"Start recording"
                                    action:@selector(toggle:)
                             keyEquivalent:@""];
    recordingItem.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];
    statusItem.menu = menu;
    NSNotificationCenter* nc = NSWorkspace.sharedWorkspace.notificationCenter;
    [nc addObserver:self
           selector:@selector(suspend:)
               name:NSWorkspaceSessionDidResignActiveNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(suspend:)
               name:NSWorkspaceWillSleepNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(suspend:)
               name:NSWorkspaceScreensDidSleepNotification
             object:nil];
    [self pruneHistory:nil];
    [NSTimer scheduledTimerWithTimeInterval:3600
                                     target:self
                                   selector:@selector(pruneHistory:)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)pruneHistory:(id)sender {
    (void)sender;
    int days = preferences["retentionDays"];
    dispatch_async(worker, ^{
      try {
          archive->prune(days, now());
      } catch (const std::exception& e) {
          std::string msg = e.what();
          dispatch_async(dispatch_get_main_queue(), ^{
            lastError = msg;
          });
      }
    });
}

- (void)showWindow:(id)sender {
    (void)sender;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)flag {
    (void)app;
    (void)flag;
    [self showWindow:nil];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
    (void)app;
    return NO;
}

- (void)windowWillClose:(NSNotification*)n {
    (void)n;
    [self stop];
}

- (void)applicationWillTerminate:(NSNotification*)n {
    (void)n;
    [self stop];
}

- (void)suspend:(NSNotification*)n {
    (void)n;
    [self stop];
    captureState = "Paused after sleep or lock";
}

- (void)stop {
    BOOL wasRecording = recording;
    recording = NO;
    generation++;
    [timer invalidate];
    timer = nil;
    captureState = "Paused";
    recordingItem.title = @"Start recording";
    statusItem.button.title = @"◉";
    statusItem.button.toolTip = @"Afterimage — paused";
    if (wasRecording) {
        dispatch_async(worker, ^{
          try {
              Store storage(defaultRoot(), appleSegmentCodec());
              storage.compact();
              dispatch_async(dispatch_get_main_queue(), ^{
                compressionError.clear();
              });
          } catch (const std::exception& e) {
              std::string message = e.what();
              dispatch_async(dispatch_get_main_queue(), ^{
                compressionError = "Compression: " + message;
              });
          }
        });
    }
}

- (void)start {
    if (recording) {
        return;
    }
    if (!CGPreflightScreenCaptureAccess()) {
        CGRequestScreenCaptureAccess();
        lastError = "Screen Recording permission is required. Enable Afterimage in "
                    "System Settings → Privacy & Security → Screen & System Audio "
                    "Recording, then restart the app.";
        captureState = "Permission needed";
        return;
    }
    recording = YES;
    generation++;
    lastError.clear();
    captureState = "Recording";
    dispatch_async(worker, ^{
      gate.reset();
    });
    recordingItem.title = @"Pause recording";
    statusItem.button.title = @"●";
    statusItem.button.toolTip = @"Afterimage — recording";
    timer = [NSTimer scheduledTimerWithTimeInterval:preferences["interval"].get<int>()
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];
    [self tick:nil];
}

- (void)toggle:(id)sender {
    (void)sender;
    if (recording) {
        [self stop];
    } else {
        [self start];
    }
}

- (void)tick:(id)sender {
    (void)sender;
    if (!recording || busy) {
        return;
    }
    NSRunningApplication* focused = NSWorkspace.sharedWorkspace.frontmostApplication;
    std::string bundle = str(focused.bundleIdentifier), name = str(focused.localizedName);
    // Avoid capturing our UI or any part of the desktop while an excluded app is
    // focused.
    if (bundle == "app.afterimage.local" ||
        std::find(preferences["excluded"].begin(), preferences["excluded"].end(), json(bundle)) !=
            preferences["excluded"].end()) {
        captureState = bundle == "app.afterimage.local" ? "Waiting · Afterimage is focused"
                                                        : "Waiting · excluded app";
        skipped++;
        return;
    }
    busy = YES;
    NSInteger token = generation;
    json settings = preferences;
    [SCShareableContent
        getShareableContentExcludingDesktopWindows:YES
                               onScreenWindowsOnly:YES
                                 completionHandler:^(SCShareableContent* content, NSError* error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                     if (token != generation || !recording) {
                                         busy = NO;
                                         return;
                                     }
                                     if (error || content.displays.count == 0) {
                                         lastError = error ? str(error.localizedDescription)
                                                           : "No display available";
                                         captureState = "Capture unavailable";
                                         busy = NO;
                                         return;
                                     }
                                     SCDisplay* display = nil;
                                     for (SCDisplay* d in content.displays) {
                                         if (d.displayID ==
                                             settings["displayId"].get<unsigned int>()) {
                                             display = d;
                                         }
                                     }
                                     if (!display) {
                                         for (SCDisplay* d in content.displays) {
                                             if (d.displayID == CGMainDisplayID()) {
                                                 display = d;
                                             }
                                         }
                                     }
                                     if (!display) {
                                         display = content.displays.firstObject;
                                     }
                                     NSMutableArray* excluded = [NSMutableArray array];
                                     for (SCRunningApplication* a in content.applications) {
                                         std::string b = str(a.bundleIdentifier);
                                         if (b == "app.afterimage.local" ||
                                             std::find(settings["excluded"].begin(),
                                                       settings["excluded"].end(),
                                                       json(b)) != settings["excluded"].end()) {
                                             [excluded addObject:a];
                                         }
                                     }
                                     SCContentFilter* filter =
                                         [[SCContentFilter alloc] initWithDisplay:display
                                                            excludingApplications:excluded
                                                                 exceptingWindows:@[]];
                                     SCStreamConfiguration* config =
                                         [[SCStreamConfiguration alloc] init];
                                     config.width = display.width;
                                     config.height = display.height;
                                     config.showsCursor = NO;
                                     config.capturesAudio = NO;
                                     Frame f;
                                     f.time = now();
                                     f.app = name;
                                     f.bundle = bundle;
                                     for (SCWindow* w in content.windows) {
                                         if ([w.owningApplication.bundleIdentifier
                                                 isEqualToString:focused.bundleIdentifier] &&
                                             w.windowLayer == 0) {
                                             f.title = str(w.title);
                                             break;
                                         }
                                     }
                                     [SCScreenshotManager
                                         captureImageWithFilter:filter
                                                  configuration:config
                                              completionHandler:^(CGImageRef im, NSError* err) {
                                                if (!im) {
                                                    std::string msg =
                                                        err ? str(err.localizedDescription)
                                                            : "Empty capture";
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                      lastError = msg;
                                                      busy = NO;
                                                      captureState = "Capture unavailable";
                                                    });
                                                    return;
                                                }
                                                CGImageRetain(im);
                                                dispatch_async(worker, ^{
                                                  bool take = false;
                                                  std::string failure;
                                                  double start = now();
                                                  Prepared processed;
                                                  try {
                                                      take = gate.changed(grayscale(im),
                                                                          f.bundle + "\n" + f.title,
                                                                          f.time);
                                                      if (take) {
                                                          processed = prepare(im, f);
                                                      }
                                                  } catch (const std::exception& e) {
                                                      failure = e.what();
                                                      gate.reset();
                                                  }
                                                  CGImageRelease(im);
                                                  double ms = (now() - start) * 1000;
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                    busy = NO;
                                                    std::string active = str(
                                                        NSWorkspace.sharedWorkspace
                                                            .frontmostApplication.bundleIdentifier);
                                                    bool excluded =
                                                        active == "app.afterimage."
                                                                  "local" ||
                                                        std::find(preferences["excluded"].begin(),
                                                                  preferences["excluded"].end(),
                                                                  json(active)) !=
                                                            preferences["excluded"].end();
                                                    if (token != generation || !recording ||
                                                        excluded) {
                                                        dispatch_async(worker, ^{
                                                          gate.reset();
                                                        });
                                                        return;
                                                    }
                                                    if (!failure.empty()) {
                                                        lastError = failure;
                                                        captureState = "Processing error";
                                                        return;
                                                    }
                                                    try {
                                                        if (take) {
                                                            archive->add(processed.frame,
                                                                         processed.bytes);
                                                            captured++;
                                                            dispatch_async(worker, ^{
                                                              try {
                                                                  Store storage(
                                                                      defaultRoot(),
                                                                      appleSegmentCodec());
                                                                  storage.compact(false);
                                                                  dispatch_async(
                                                                      dispatch_get_main_queue(), ^{
                                                                        compressionError.clear();
                                                                      });
                                                              } catch (const std::exception& e) {
                                                                  std::string message = e.what();
                                                                  dispatch_async(
                                                                      dispatch_get_main_queue(), ^{
                                                                        lastError =
                                                                            "Compression: " +
                                                                            message;
                                                                      });
                                                              }
                                                            });
                                                            lastOCR = ms;
                                                        } else {
                                                            skipped++;
                                                        }
                                                        captureState = "Recording";
                                                        lastError.clear();
                                                    } catch (const std::exception& e) {
                                                        lastError = e.what();
                                                        captureState = "Storage error";
                                                        dispatch_async(worker, ^{
                                                          gate.reset();
                                                        });
                                                    }
                                                  });
                                                });
                                              }];
                                   });
                                 }];
}

- (json)state {
    json j = archive->stats();
    j["settings"] = preferences;
    j["recording"] = (bool)recording;
    j["busy"] = (bool)busy;
    j["captureState"] = captureState;
    j["error"] = lastError.empty() ? compressionError : lastError;
    j["permission"] = (bool)CGPreflightScreenCaptureAccess();
    j["capturedThisSession"] = captured;
    j["skippedThisSession"] = skipped;
    j["lastProcessingMs"] = lastOCR;
    j["archivePath"] = archive->root().string();
    json apps = json::array();
    for (NSRunningApplication* a in NSWorkspace.sharedWorkspace.runningApplications) {
        if (a.activationPolicy == NSApplicationActivationPolicyRegular && a.bundleIdentifier &&
            ![a.bundleIdentifier isEqualToString:@"app.afterimage.local"]) {
            apps.push_back({{"name", str(a.localizedName)}, {"bundle", str(a.bundleIdentifier)}});
        }
    }
    j["runningApps"] = apps;
    return j;
}

- (void)reply:(id)request result:(json)value error:(std::string)error {
    UICompletion completion = callbacks[request];
    [callbacks removeObjectForKey:request];
    if (completion) {
        completion(value, error);
    }
}

- (void)performAction:(NSDictionary*)body {
    id request = body[@"id"];
    try {
        json args = objJSON(body[@"args"] ?: @{});
        std::string action = str(body[@"action"]);
        if (action == "state") {
            [self reply:request result:[self state] error:""];
        } else if (action == "frames") {
            [self reply:request
                 result:archive->frames(args.value("query", ""), args.value("app", ""),
                                        args.value("from", 0.0), args.value("to", 1e15),
                                        args.value("limit", 200), args.value("offset", 0))
                  error:""];
        } else if (action == "image") {
            long long id = args.at("id");
            bool priority = args.value("priority", false);
            uint64_t imageToken = priority ? ++latestImageRequest : latestImageRequest.load();
            dispatch_async(imageWorker, ^{
              if (priority && imageToken != latestImageRequest.load()) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request
                         result:json {
                             {
                                 "cancelled", true
                             }
                         }
                          error:""];
                  });
                  return;
              }
              try {
                  Store reader(defaultRoot(), appleSegmentCodec());
                  auto path = reader.image(id).string();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request
                         result:json {
                             {
                                 "path", path
                             }
                         }
                          error:""];
                  });
              } catch (const std::exception& e) {
                  std::string message = e.what();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:nullptr error:message];
                  });
              }
            });
        } else if (action == "frame") {
            [self reply:request result:archive->frame(args.at("id")) error:""];
        } else if (action == "toggle") {
            [self toggle:nil];
            [self reply:request result:[self state] error:""];
        } else if (action == "settings") {
            BOOL was = recording;
            [self stop];
            archive->settings(args);
            preferences = archive->settings();
            if (was) {
                [self start];
            }
            int days = preferences["retentionDays"];
            dispatch_async(worker, ^{
              try {
                  archive->prune(days, now());
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:[self state] error:""];
                  });
              } catch (const std::exception& e) {
                  std::string msg = e.what();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:nullptr error:msg];
                  });
              }
            });
        } else if (action == "delete") {
            long long id = args.at("id");
            dispatch_async(worker, ^{
              try {
                  Store storage(defaultRoot(), appleSegmentCodec());
                  storage.erase(id);
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request
                         result:json {
                             {
                                 "ok", true
                             }
                         }
                          error:""];
                  });
              } catch (const std::exception& e) {
                  std::string message = e.what();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:nullptr error:message];
                  });
              }
            });
        } else if (action == "clear") {
            [self stop];
            dispatch_async(worker, ^{
              try {
                  archive->clear();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:[self state] error:""];
                  });
              } catch (const std::exception& e) {
                  std::string msg = e.what();
                  dispatch_async(dispatch_get_main_queue(), ^{
                    [self reply:request result:nullptr error:msg];
                  });
              }
            });
        } else if (action == "import") {
            NSOpenPanel* panel = NSOpenPanel.openPanel;
            panel.allowedContentTypes = @[ UTTypePNG, UTTypeJPEG ];
            panel.allowsMultipleSelection = YES;
            panel.canChooseDirectories = NO;
            [panel beginSheetModalForWindow:window
                          completionHandler:^(NSModalResponse response) {
                            if (response != NSModalResponseOK) {
                                [self reply:request
                                     result:json {
                                         {
                                             "cancelled", true
                                         }
                                     }
                                      error:""];
                                return;
                            }
                            NSArray<NSURL*>* urls = panel.URLs;
                            dispatch_async(worker, ^{
                              json ids = json::array();
                              std::string err;
                              for (NSURL* url in urls) {
                                  try {
                                      ids.push_back(importImage(str(url.path), now()));
                                  } catch (const std::exception& e) {
                                      err = e.what();
                                      break;
                                  }
                              }
                              dispatch_async(dispatch_get_main_queue(), ^{
                                [self reply:request
                                     result:json {
                                         {
                                             "ids", ids
                                         }
                                     }
                                      error:err];
                              });
                            });
                          }];
        } else if (action == "export") {
            auto path = archive->image(args.at("id"));
            NSSavePanel* panel = NSSavePanel.savePanel;
            panel.nameFieldStringValue =
                ns("afterimage-" + std::to_string(args.at("id").get<long long>()) + ".jpg");
            panel.allowedContentTypes = @[ UTTypeJPEG ];
            [panel beginSheetModalForWindow:window
                          completionHandler:^(NSModalResponse response) {
                            if (response != NSModalResponseOK) {
                                [self reply:request
                                     result:json {
                                         {
                                             "cancelled", true
                                         }
                                     }
                                      error:""];
                                return;
                            }
                            try {
                                exportScreenshot(path, str(panel.URL.path));
                                [self reply:request
                                     result:json {
                                         {
                                             "ok", true
                                         }
                                     }
                                      error:""];
                            } catch (const std::exception& e) {
                                [self reply:request result:nullptr error:e.what()];
                            }
                          }];
        } else if (action == "reveal") {
            [NSWorkspace.sharedWorkspace
                openURL:[NSURL fileURLWithPath:ns(archive->root().string())]];
            [self reply:request
                 result:json {
                     {
                         "ok", true
                     }
                 }
                  error:""];
        } else if (action == "requestPermission") {
            CGRequestScreenCaptureAccess();
            [self reply:request
                 result:json {
                     {
                         "ok", true
                     }
                 }
                  error:""];
        } else if (action == "permission") {
            [NSWorkspace.sharedWorkspace
                openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference."
                                             @"security?Privacy_ScreenCapture"]];
            [self reply:request
                 result:json {
                     {
                         "ok", true
                     }
                 }
                  error:""];
        } else {
            throw std::runtime_error("Unknown action");
        }
    } catch (const std::exception& e) {
        [self reply:request result:nullptr error:e.what()];
    }
}

@end

int main(int argc, char** argv) {
    @autoreleasepool {
        umask(0077);
        if (argc > 1 && std::string(argv[1]) != "--ui-smoke") {
            return cli(argc, argv);
        }
        if (argc == 3) {
            smokeOutput = argv[2];
        }
        try {
            archive = std::make_unique<Store>(defaultRoot(), appleSegmentCodec());
        } catch (const std::exception& e) {
            std::cerr << e.what() << '\n';
            return 1;
        }
        NSApplication* app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        App* delegate = [[App alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
