//
//  CameraView.m
//  OpenCVImage
//
//  Created by 靳杰 on 15/1/31.
//  Copyright (c) 2015年 靳杰. All rights reserved.
//

#import "CameraView.h"
#import <AVFoundation/AVFoundation.h>

@implementation CameraView

+ (Class)layerClass {
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session {
    return [(AVCaptureVideoPreviewLayer *)[self layer] session];
}

- (void)setSession:(AVCaptureSession *)session {
    [(AVCaptureVideoPreviewLayer *)[self layer] setSession:session];
}

@end
