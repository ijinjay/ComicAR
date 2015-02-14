//
//  CameraViewController.m
//  ComicAR
//
//  Created by 靳杰 on 15/2/3.
//  Copyright (c) 2015年 靳杰. All rights reserved.
//

#import "CameraViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <opencv2/highgui/highgui_c.h>
#import "CameraView.h"
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <GLKit/GLKMath.h>

@interface CameraViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property (weak, nonatomic) IBOutlet UIButton *changeButton;
- (IBAction)switchCameraAction:(id)sender;
@property (weak, nonatomic) IBOutlet CameraView *CameraView;
@property (weak, nonatomic) IBOutlet UIButton *returnButton;
@property (weak, nonatomic) IBOutlet UIButton *voiceButton;
@property (weak, nonatomic) IBOutlet UIButton *snapButton;
@property (weak, nonatomic) IBOutlet UIButton *expressionButton;
- (IBAction)faceDetect:(id)sender;


// cameraView相关，处理照相机的输入输出
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic) AVCaptureSession         *session;
@property (nonatomic) AVCaptureDeviceInput     *videoDeviceInput;
@property (nonatomic) AVCaptureVideoDataOutput *output;
@property (nonatomic) dispatch_queue_t          outputQueue;
@property (nonatomic) AVCaptureDevice *         device;
@property (nonatomic) NSInteger                 sampleTimes;
@property (nonatomic) BOOL                      isRunning;

// 识别动漫图形
@property (nonatomic) BOOL isNeedRecognizePic;
@property (nonatomic) BOOL isRecognizeSuccess;

// Face detect 人脸检测，上传人脸部分图片，通过调用face ++接口获取任务表情
@property (nonatomic) BOOL isNeedDetectFace;
@property (nonatomic) BOOL isDetectSuccess;

@end

@implementation CameraViewController {
    // 3D model相关，使用Metal技术优化
    id <MTLDevice> mtlDevice;
    id <MTLCommandQueue> mtlCommandQueue;
    MTLRenderPassDescriptor *mtlRenderPassDescriptor;
    CAMetalLayer *metalLayer;
    id <CAMetalDrawable> frameDrawable;
    CADisplayLink *displayLink;
    
    MTLRenderPipelineDescriptor *renderPipelineDescriptor;
    id <MTLRenderPipelineState> renderPipelineState;
    id <MTLBuffer> object;
}

typedef struct {
    GLKVector2 position;
} Triangle;

// CameraView Handle
BOOL isPad() {
    return ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
}
- (NSString *)getCameraQuanity {
    NSString *result = AVCaptureSessionPresetHigh;
    NSUserDefaults *user = [NSUserDefaults standardUserDefaults];
    NSArray *iphone = [NSArray arrayWithObjects:AVCaptureSessionPresetHigh, AVCaptureSessionPreset1280x720, AVCaptureSessionPresetPhoto, nil];
    NSArray *ipad = [NSArray arrayWithObjects:AVCaptureSessionPresetPhoto, AVCaptureSessionPreset640x480, AVCaptureSessionPresetMedium,nil];
    if ([user objectForKey:@"quanity"] != nil) {
        NSInteger quanity = [user integerForKey:@"quanity"];
        if (isPad()) {
            return ipad[quanity];
        }
        return iphone[quanity];
    } else if (isPad()) {
        // iPad默认为photo
        result = AVCaptureSessionPresetPhoto;
    }
    return result;
}
- (void)checkDeviceAuthorizationStatus {
    NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (granted) {
            [self setDeviceAuthorized:YES];
        } else {
            //Not granted access to mediaType
            dispatch_async(dispatch_get_main_queue(), ^{
                [[[UIAlertView alloc] initWithTitle:@"Error"
                                            message:@"Application doesn't have permission to use Camera, please change privacy settings"
                                           delegate:self
                                  cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
                [self setDeviceAuthorized:NO];
            });
        }
    }];
}
- (void)setupSession {
    _session = [[AVCaptureSession alloc] init];
    _session.sessionPreset = [self getCameraQuanity];
    [[self CameraView] setSession:_session];
}
- (void)setupInput {
    _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    _videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:_device error:&error];
    if (!_videoDeviceInput) {
        NSLog(@"%@", error);
    }
    [_session addInput:_videoDeviceInput];
    [self setVideoDeviceInput:_videoDeviceInput];
}
- (void)setupOutput {
    _output = [[AVCaptureVideoDataOutput alloc] init];
    _output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    //    _output.videoSettings = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [_session addOutput:_output];
}
// OpenCV Handle
- (cv::Mat)cvMatFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels (color channels + alpha)
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to  data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}
- (cv::Mat)cvMatGrayFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}
- (UIImage *)UIImageFromCVMat:(cv::Mat)cvMat {
    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize()*cvMat.total()];
    CGColorSpaceRef colorSpace;
    
    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    CGImageRef imageRef = CGImageCreate(cvMat.cols,                                 //width
                                        cvMat.rows,                                 //height
                                        8,                                          //bits per component
                                        8 * cvMat.elemSize(),                       //bits per pixel
                                        cvMat.step[0],                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    
    
    // Getting UIImage from CGImage
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}
// Create a cv::Mat from sample buffer data
- (cv::Mat) cvMatFromSampleBuffer:(CMSampleBufferRef) sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC4, baseaddress, 0);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return mat;
}
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    self.sampleTimes ++;
    if (_sampleTimes % 5 == 0) {
        UIImage *image = [self UIImageFromCVMat:[self cvMatFromSampleBuffer:sampleBuffer]];
//        NSLog(@"image size %lf, %lf", image.size.width, image.size.height);
        if (_isNeedRecognizePic) {
            // recognize comic picture
            NSLog(@"recognize picture success");
            _isRecognizeSuccess = YES;
            [_snapButton setEnabled:YES];
            [_expressionButton setEnabled:YES];
            [_voiceButton setEnabled:YES];
            _isNeedRecognizePic = NO;
        }
        if (_isNeedDetectFace) {
            // detect Face
            _isDetectSuccess = YES;
            _isNeedDetectFace = NO;
            
            if (_isDetectSuccess) {
                NSLog(@"user expressions");
            }
            [_expressionButton setEnabled:YES];
        }
    }
    if (_sampleTimes == 6) {
        _sampleTimes = 1;
    }
}

- (UIImage *)captureView {
    CGRect rect = [self.CameraView bounds];
    
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self.view.layer renderInContext:context];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self prefersStatusBarHidden];
    
    // layout ipad
    if (isPad()) {
        UIFont *fontt = [UIFont systemFontOfSize:28];
        _changeButton.titleLabel.font = fontt;
        [_changeButton setTitle:@" " forState:UIControlStateNormal];
        _returnButton.titleLabel.font = fontt;
        _expressionButton.titleLabel.font = fontt;
        _snapButton.titleLabel.font = fontt;
        _voiceButton.titleLabel.font = fontt;
    }
    
    // cameraView
    [self setupSession];
    [self checkDeviceAuthorizationStatus];
    [self setupInput];
    [self setupOutput];
    _isRunning = NO;
    _sampleTimes = 0;
    
    _outputQueue = dispatch_queue_create("output queue", DISPATCH_QUEUE_SERIAL);
    [_output setSampleBufferDelegate:self queue:_outputQueue];
    [[_output connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    NSLog(@"end of sessin create");
    
    // focus gesture
    [self prefersStatusBarHidden];
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusGesture:)];
    tapGesture.numberOfTapsRequired = 1;
    [self.CameraView addGestureRecognizer:tapGesture];
    [_session startRunning];
    
    // set backgroundcolor
    NSUserDefaults *user = [NSUserDefaults standardUserDefaults];
    UIColor *color = [NSKeyedUnarchiver unarchiveObjectWithData:[user objectForKey:@"backgroundcolor"]];
    _CameraView.backgroundColor = color;
    NSLog(@"%@", color);
    NSInteger colorIndex = [user integerForKey:@"colorIndex"];
    if ([user objectForKey:@"colorcount"] != nil) {
        colorIndex = (colorIndex + 1)%([user integerForKey:@"colorcount"]);
        [user setInteger:colorIndex forKey:@"colorIndex"];
    }
    
    // picture recognize
    _isNeedRecognizePic = YES;
    _isRecognizeSuccess = NO;
    [_expressionButton setEnabled:NO];
    [_snapButton setEnabled:NO];
    [_voiceButton setEnabled:NO];

    // face detect
    _isNeedDetectFace = NO;
    _isDetectSuccess = NO;
    
    // 3D metal layer
    mtlDevice = MTLCreateSystemDefaultDevice();
    mtlCommandQueue = [mtlDevice newCommandQueue];
    metalLayer = [CAMetalLayer layer];
    [metalLayer setDevice:mtlDevice];
    [metalLayer setPixelFormat:MTLPixelFormatA8Unorm];
    metalLayer.framebufferOnly = YES;
    [metalLayer setFrame:_CameraView.layer.frame];
    metalLayer.backgroundColor = nil;

    //
//    renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
//    renderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
//    
//    [_CameraView.layer addSublayer:metalLayer];
//    
//    id <MTLLibrary> lib = [mtlDevice newDefaultLibrary];
//    renderPipelineDescriptor.vertexFunction = [lib newFunctionWithName:@"VertexColor"];
//    renderPipelineDescriptor.fragmentFunction = [lib newFunctionWithName:@"FragmentColor"];
//    renderPipelineState = [mtlDevice newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error: nil];
//    
//    Triangle triangle[3] = { { -.5f, 0.0f }, { 0.5f, 0.0f }, { 0.0f, 0.5f } };
//    
//    object = [mtlDevice newBufferWithBytes:&triangle length:sizeof(Triangle[3]) options:MTLResourceOptionCPUCacheModeDefault];
//    
//    
//    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderScene)];
//    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
    
}
// metal render
- (void)renderScene
{
    id <MTLCommandBuffer>mtlCommandBuffer = [mtlCommandQueue commandBuffer];
    
    while (!frameDrawable){
        frameDrawable = [metalLayer nextDrawable];
    }
    
    if (!mtlRenderPassDescriptor)
        mtlRenderPassDescriptor = [MTLRenderPassDescriptor new];
    
    mtlRenderPassDescriptor.colorAttachments[0].texture = frameDrawable.texture;
    mtlRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    mtlRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.75, 0.25, 1.0, 1.0);
    mtlRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderCommand = [mtlCommandBuffer renderCommandEncoderWithDescriptor: mtlRenderPassDescriptor];
    // Draw objects here
    // set MTLRenderPipelineState..
    [renderCommand endEncoding];
    [mtlCommandBuffer presentDrawable: frameDrawable];
    [mtlCommandBuffer commit];
    mtlRenderPassDescriptor = nil;
    frameDrawable = nil;
}
- (void)dealloc {
    [displayLink invalidate];
    mtlDevice = nil;
    mtlCommandQueue = nil;
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
// 用作摄像头切换
- (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            captureDevice = device;
            break;
        }
    }
    return captureDevice;
}

- (IBAction)switchCameraAction:(id)sender {
    [_changeButton setEnabled:NO];
    // get current camera state
    AVCaptureDevice *currentVideoDevice = [[self videoDeviceInput] device];
    AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
    AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
    // change current position
    switch (currentPosition) {
        case AVCaptureDevicePositionUnspecified:
            preferredPosition = AVCaptureDevicePositionBack;
            break;
        case AVCaptureDevicePositionBack:
            preferredPosition = AVCaptureDevicePositionFront;
            break;
        case AVCaptureDevicePositionFront:
            preferredPosition = AVCaptureDevicePositionBack;
            break;
    }
    
    AVCaptureDevice *videoDevice = [self deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    
    [_session beginConfiguration];
    
    [_session removeInput:[self videoDeviceInput]];
    if ([_session canAddInput:videoDeviceInput]) {
        [_session addInput:videoDeviceInput];
        [self setVideoDeviceInput:videoDeviceInput];
    } else {
        [_session addInput:[self videoDeviceInput]];
    }
    
    [_session commitConfiguration];
    [_changeButton setEnabled:YES];
}

// 隐藏状态栏
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)focusGesture:(id)sender {
    NSLog(@"tap.................");
    //实例化
    CGPoint location = [sender locationInView:self.CameraView];
    AVCaptureDevice *captureDevice = [self device];
    
//    [_CameraView.layer addSublayer:metalLayer];
//    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
    
    
    //先进行判断是否支持控制对焦
    if (captureDevice.isFocusPointOfInterestSupported && [captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error = nil;
        //对cameraDevice进行操作前，需要先锁定，防止其他线程访问，
        [self.device lockForConfiguration:&error];
        [self.device setFocusMode:AVCaptureFocusModeAutoFocus];
        [self.device setFocusPointOfInterest:CGPointMake(location.x, location.y)];
        //操作完成后，记得进行unlock。
        [self.device unlockForConfiguration];
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    NSLog(@"view did disapear");
}
- (void)viewDidAppear:(BOOL)animated {
    NSLog(@"view did appear");
    if (![_session isRunning]) {
        [_session startRunning];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    NSLog(@"view will disappear");
    if ([_session isRunning]) {
        [_session stopRunning];
    }
}
- (IBAction)faceDetect:(id)sender {
    _isDetectSuccess = NO;
    _isNeedDetectFace = YES;
    [_expressionButton setEnabled:NO];
}
@end