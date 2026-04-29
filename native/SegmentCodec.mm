#import "SegmentCodec.hpp"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#include <chrono>
#include <thread>

using namespace litt;

namespace {
NSURL* url(const fs::path& path) {
    return [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
}

void require(bool condition, NSString* message) {
    if (!condition) {
        throw std::runtime_error((message ?: @"Media operation failed").UTF8String);
    }
}

CGImageRef load(const fs::path& path) {
    auto source = CGImageSourceCreateWithURL((__bridge CFURLRef)url(path), nullptr);
    require(source != nullptr, @"Cannot open image");
    auto image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    require(image != nullptr, @"Cannot decode image");
    return image;
}

void writeImage(CGImageRef image, const fs::path& path, bool jpeg) {
    auto dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url(path),
                                                jpeg ? CFSTR("public.jpeg") : CFSTR("public.png"),
                                                1, nullptr);
    require(dest != nullptr, @"Cannot create decoded image");
    CGImageDestinationAddImage(
        dest, image,
        jpeg ? (__bridge CFDictionaryRef)
                   @{(__bridge NSString*)kCGImageDestinationLossyCompressionQuality : @0.95}
             : nullptr);
    bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    require(ok, @"Cannot save decoded image");
}

void encode(const std::vector<fs::path>& paths, const fs::path& output, double quality) {
    @autoreleasepool {
        require(!paths.empty(), @"Empty video segment");
        auto first = load(paths.front());
        size_t width = CGImageGetWidth(first), height = CGImageGetHeight(first);
        CGImageRelease(first);
        NSError* error = nil;
        AVAssetWriter* writer = [[AVAssetWriter alloc] initWithURL:url(output)
                                                          fileType:AVFileTypeMPEG4
                                                             error:&error];
        require(writer != nil, error.localizedDescription);
        NSDictionary* settings = @{
            AVVideoCodecKey : AVVideoCodecTypeHEVC,
            AVVideoWidthKey : @(width),
            AVVideoHeightKey : @(height),
            AVVideoCompressionPropertiesKey : @{
                AVVideoQualityKey : @(quality),
                AVVideoMaxKeyFrameIntervalKey : @10,
                AVVideoAllowFrameReorderingKey : @NO,
                AVVideoExpectedSourceFrameRateKey : @1
            }
        };
        AVAssetWriterInput* input =
            [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                               outputSettings:settings];
        input.expectsMediaDataInRealTime = NO;
        AVAssetWriterInputPixelBufferAdaptor* adaptor = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                       sourcePixelBufferAttributes:@{
                                           (id)kCVPixelBufferPixelFormatTypeKey :
                                               @(kCVPixelFormatType_32BGRA),
                                           (id)kCVPixelBufferWidthKey : @(width),
                                           (id)kCVPixelBufferHeightKey : @(height),
                                           (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
                                       }];
        require([writer canAddInput:input], @"HEVC encoding unavailable");
        [writer addInput:input];
        require([writer startWriting], writer.error.localizedDescription);
        [writer startSessionAtSourceTime:kCMTimeZero];
        try {
            for (size_t i = 0; i < paths.size(); i++) {
                @autoreleasepool {
                    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
                    while (!input.readyForMoreMediaData &&
                           writer.status == AVAssetWriterStatusWriting &&
                           std::chrono::steady_clock::now() < deadline) {
                        std::this_thread::sleep_for(std::chrono::milliseconds(2));
                    }
                    require(input.readyForMoreMediaData &&
                                writer.status == AVAssetWriterStatusWriting,
                            writer.error.localizedDescription ?: @"Video encoder timed out");
                    auto image = load(paths[i]);
                    CVPixelBufferRef pixel = nullptr;
                    auto status = CVPixelBufferPoolCreatePixelBuffer(
                        nullptr, adaptor.pixelBufferPool, &pixel);
                    if (status != kCVReturnSuccess) {
                        CGImageRelease(image);
                        require(false, @"Cannot allocate video frame");
                    }
                    CVPixelBufferLockBaseAddress(pixel, 0);
                    auto space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                    auto context = CGBitmapContextCreate(
                        CVPixelBufferGetBaseAddress(pixel), width, height, 8,
                        CVPixelBufferGetBytesPerRow(pixel), space,
                        static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst) |
                            kCGBitmapByteOrder32Little);
                    CGColorSpaceRelease(space);
                    if (context) {
                        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
                        CGContextRelease(context);
                    }
                    CGImageRelease(image);
                    CVPixelBufferUnlockBaseAddress(pixel, 0);
                    bool appended = context && [adaptor appendPixelBuffer:pixel
                                                     withPresentationTime:CMTimeMake(i, 1)];
                    CVPixelBufferRelease(pixel);
                    require(appended,
                            writer.error.localizedDescription ?: @"Cannot append video frame");
                }
            }
            [writer endSessionAtSourceTime:CMTimeMake(paths.size(), 1)];
            [input markAsFinished];
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            [writer finishWritingWithCompletionHandler:^{
              dispatch_semaphore_signal(done);
            }];
            require(dispatch_semaphore_wait(
                        done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) == 0,
                    @"Finishing video timed out");
            require(writer.status == AVAssetWriterStatusCompleted,
                    writer.error.localizedDescription);
        } catch (...) {
            [writer cancelWriting];
            throw;
        }
    }
}

void decode(const fs::path& input, int index, const fs::path& output) {
    @autoreleasepool {
        AVURLAsset* asset =
            [AVURLAsset URLAssetWithURL:url(input)
                                options:@{
                                    AVURLAssetPreferPreciseDurationAndTimingKey : @YES
                                }];
        AVAssetImageGenerator* generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        generator.appliesPreferredTrackTransform = YES;
        NSError* error = nil;
        CMTime actual;
        auto image = [generator copyCGImageAtTime:CMTimeMake(index, 1)
                                       actualTime:&actual
                                            error:&error];
        require(image != nullptr, error.localizedDescription ?: @"Cannot decode saved frame");
        try {
            writeImage(image, output, false);
        } catch (...) {
            CGImageRelease(image);
            throw;
        }
        CGImageRelease(image);
        require(CMTimeCompare(actual, CMTimeMake(index, 1)) == 0,
                @"Video frame timestamp mismatch");
    }
}
} // namespace

SegmentCodec appleSegmentCodec() {
    return {encode, decode};
}

void exportScreenshot(const fs::path& input, const fs::path& output) {
    @autoreleasepool {
        auto image = load(input);
        try {
            writeImage(image, output, output.extension() != ".png");
        } catch (...) {
            CGImageRelease(image);
            throw;
        }
        CGImageRelease(image);
    }
}
