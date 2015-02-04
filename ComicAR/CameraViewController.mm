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

@interface CameraViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property (weak, nonatomic) IBOutlet UIButton *changeButton;
- (IBAction)switchCameraAction:(id)sender;
@property (weak, nonatomic) IBOutlet CameraView *CameraView;
@property (weak, nonatomic) IBOutlet UIButton *returnButton;
@property (weak, nonatomic) IBOutlet UIButton *voiceButton;
@property (weak, nonatomic) IBOutlet UIButton *snapButton;
@property (weak, nonatomic) IBOutlet UIButton *expressionButton;


// cameraView相关，处理照相机的输入输出
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic) AVCaptureSession         *session;
@property (nonatomic) AVCaptureDeviceInput     *videoDeviceInput;
@property (nonatomic) AVCaptureVideoDataOutput *output;
@property (nonatomic) dispatch_queue_t          outputQueue;
@property (nonatomic) AVCaptureDevice *         device;
@property (nonatomic) NSInteger                 sampleTimes;
@property (nonatomic) BOOL                      isRunning;

// 3D model相关，使用Metal技术优化

@end

@implementation CameraViewController

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
        NSLog(@"image size %lf, %lf", image.size.width, image.size.height);
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
    // specific session
    [self setupSession];
    [self checkDeviceAuthorizationStatus];
    // input handle
    [self setupInput];
    // output handle
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
@end