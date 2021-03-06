//
//  ViewController.m
//  AVCapturePreview2
//
//  Created by annidy on 16/4/16.
//  Copyright © 2016年 annidy. All rights reserved.
//

#import "ViewController.h"
#import "VideoGLView.h"
@import AVFoundation;

#define QUARTZ
//#define LAYER

#include <assert.h>
#include <CoreServices/CoreServices.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <unistd.h>

#import <OpenGL/gl3.h>


@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
#ifdef LAYER
@property (weak) IBOutlet NSImageView *cameraView;
#endif
@property (weak) IBOutlet NSTextField *fpsLabel;
#ifdef QUARTZ
@property (weak) IBOutlet VideoGLView *openGLView;
#endif
@end

@implementation ViewController
{
    AVCaptureSession *_captureSession;
    
    AVSampleBufferDisplayLayer *_videoLayer;
    NSMutableArray *_displayFrameBuffer;
    dispatch_queue_t _captureQueue;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setWantsLayer:YES];
    // Do any additional setup after loading the view.
    
    _captureQueue = dispatch_queue_create("AVCapture2", 0);
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    
    [self initCaptureSession];
    
#ifdef LAYER
    [self initSampleBufferDisplayLayer];
#endif
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}

- (IBAction)startSession:(id)sender {
    if (![_captureSession isRunning]) {
        [_captureSession startRunning];
    }
}
- (IBAction)stopSession:(id)sender {
    if ([_captureSession isRunning]) {
        [_captureSession stopRunning];
    }
}


- (void)initCaptureSession
{
    _captureSession = [[AVCaptureSession alloc] init];
    
    [_captureSession beginConfiguration];
    
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480])
        [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];
    
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSCAssert(captureDevice, @"no device");
    
    NSError *error;
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
    [_captureSession addInput:input];
    
    //-- Create the output for the capture session.
    AVCaptureVideoDataOutput * dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES]; // Probably want to set this to NO when recording
    
    for (int i = 0; i < dataOutput.availableVideoCVPixelFormatTypes.count; i++) {
        char fourr[5] = {0};
        *((int32_t *)fourr) = CFSwapInt32([dataOutput.availableVideoCVPixelFormatTypes[i] intValue]);
        NSLog(@"%s", fourr);
    }
    
    //-- Set to YUV420.
#ifdef LAYER
    [dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
                                   (id)kCVPixelBufferWidthKey:@640,
                                   (id)kCVPixelBufferHeightKey:@480}];
#endif
#ifdef QUARTZ
    [dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_24RGB],
                                   (id)kCVPixelBufferWidthKey:@640,
                                   (id)kCVPixelBufferHeightKey:@480}];

#endif
     
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:self queue:_captureQueue];
    
    NSAssert([_captureSession canAddOutput:dataOutput], @"can't output");
    
    [_captureSession addOutput:dataOutput];
    
    [_captureSession commitConfiguration];

}

- (void)initSampleBufferDisplayLayer
{
#ifdef LAYER
    _videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
    [_videoLayer setFrame:(CGRect){.origin=CGPointZero, .size=self.cameraView.frame.size}];
    _videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _videoLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
    _videoLayer.layoutManager  = [CAConstraintLayoutManager layoutManager];
    _videoLayer.autoresizingMask = kCALayerHeightSizable | kCALayerWidthSizable;
    _videoLayer.contentsGravity = kCAGravityResizeAspect;
    /*
    CMTimebaseRef controlTimebase;
    CMTimebaseCreateWithMasterClock( CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
    
    _videoLayer.controlTimebase = controlTimebase;
    
    // Set the timebase to the initial pts here
    CMTimebaseSetTime(_videoLayer.controlTimebase, CMTimeMakeWithSeconds(CACurrentMediaTime(), 24));
    CMTimebaseSetRate(_videoLayer.controlTimebase, 1.0);
    */
    [self.cameraView.layer addSublayer:_videoLayer];
#endif
}

#define clamp(a) (a>255?255:(a<0?0:a))

- (NSImage *)imageFromSampleBuffer2:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    uint8_t *yBuffer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    size_t yPitch = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
    uint8_t *cbCrBuffer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);

    size_t cbCrPitch = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
    
    int bytesPerPixel = 4;
    uint8_t *rgbBuffer = malloc(width * height * bytesPerPixel);
    
    
    
    for(int y = 0; y < height; y++) {
        uint8_t *rgbBufferLine = &rgbBuffer[y * width * bytesPerPixel];
        uint8_t *yBufferLine = &yBuffer[y * yPitch];
        uint8_t *cbCrBufferLine = &cbCrBuffer[(y >> 1) * cbCrPitch];
        
        for(int x = 0; x < width; x++) {
            uint8_t y = yBufferLine[x] - 16;
            uint8_t cb = cbCrBufferLine[x & ~1] - 128;
            uint8_t cr = cbCrBufferLine[x | 1] - 128;

            uint8_t *rgbOutput = &rgbBufferLine[x*bytesPerPixel];
            
            int16_t r = (int16_t)roundf( y + cr *  1.4 );
            int16_t g = (int16_t)roundf( y + cb * -0.343 + cr * -0.711 );
            int16_t b = (int16_t)roundf( y + cb *  1.765);
            
            rgbOutput[0] = 0xff;
            rgbOutput[1] = clamp(b);
            rgbOutput[2] = clamp(g);
            rgbOutput[3] = clamp(r);
        }
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgbBuffer, width, height, 8, width * bytesPerPixel, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipLast);
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    //    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    NSImage *image = [[NSImage alloc] initWithCGImage:quartzImage size:NSZeroSize];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(quartzImage);
    free(rgbBuffer);
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    return image;
}
- (NSImage*)uiImageFromCVImageBuffer1:(CVImageBufferRef)imageBuffer {
//CVImageBufferRef imageBuffer =  CMSampleBufferGetImageBuffer(sampleBuffer);

CVPixelBufferLockBaseAddress(imageBuffer, 0);
void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
size_t width = CVPixelBufferGetWidth(imageBuffer);
size_t height = CVPixelBufferGetHeight(imageBuffer);
size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);

CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, baseAddress, bufferSize, NULL);

CGImageRef cgImage = CGImageCreate(width, height, 8, 32, bytesPerRow, rgbColorSpace, kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little, provider, NULL, true, kCGRenderingIntentDefault);

    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:NSZeroSize];
    
return image;
}
- (NSImage*)uiImageFromPixelBuffer:(CVPixelBufferRef)p {
    CIImage* ciImage = [CIImage imageWithCVPixelBuffer:p];
    
    CIContext* context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer : @(YES)}];
    
    CGRect rect = CGRectMake(0, 0, CVPixelBufferGetWidth(p), CVPixelBufferGetHeight(p));
    CGImageRef videoImage = [context createCGImage:ciImage fromRect:rect];
    
    NSImage* image = [[NSImage alloc] initWithCGImage:videoImage size:NSZeroSize];
    CGImageRelease(videoImage);
    
    return image;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    static CMFormatDescriptionRef desc;
    if (!desc) {
        desc = CMSampleBufferGetFormatDescription(sampleBuffer);
        NSLog(@"%@", desc);
    }
#ifdef QUARTZ
    CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  
    [self.openGLView setImage:buffer];
    [self frameUpdate];
#endif
#ifdef LAYER
    //NSImage *nsImage = [self imageFromSampleBuffer:sampleBuffer];
    // CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    NSImage *nsImage = [self imageFromSampleBuffer:sampleBuffer];
    [self.cameraView performSelectorOnMainThread:@selector(setImage:) withObject:nsImage waitUntilDone:YES];
#endif
}

- (void)frameUpdate
{
    static int fps = 0;
    
    static uint64_t        start;
    uint64_t        end;
    uint64_t        elapsed;
    Nanoseconds     elapsedNano;
    
    // Start the clock.
    if (start == 0) {
        start = mach_absolute_time();
    }
    
    
    // Stop the clock.
    
    end = mach_absolute_time();
    
    // Calculate the duration.
    
    elapsed = end - start;
    
    // Convert to nanoseconds.
    
    // Have to do some pointer fun because AbsoluteToNanoseconds
    // works in terms of UnsignedWide, which is a structure rather
    // than a proper 64-bit integer.
    
    elapsedNano = AbsoluteToNanoseconds( *(AbsoluteTime *) &elapsed );
    
    if (* (uint64_t *) &elapsedNano > 1000000000ULL) {
        [self.fpsLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:[NSString stringWithFormat:@"fps %d", fps] waitUntilDone:NO];
        fps = 0;
        start = end;
    }
    
    fps++;
    
}
//CMSampleBufferRef转NSImage
-(NSImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // 锁定pixel buffer的基地址
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    // 得到pixel buffer的基地址
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    // 得到pixel buffer的行字节数
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 得到pixel buffer的宽和高
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    // 创建一个依赖于设备的RGB颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // 根据这个位图context中的像素数据创建一个Quartz image对象
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    // 释放context和颜色空间
    CGContextRelease(context); CGColorSpaceRelease(colorSpace);
    // 用Quartz image创建一个UIImage对象image
    NSImage *image = [[NSImage alloc] initWithCGImage:quartzImage size:NSZeroSize];

    
    // 释放Quartz image对象
    CGImageRelease(quartzImage);
    return (image);
}

@end
