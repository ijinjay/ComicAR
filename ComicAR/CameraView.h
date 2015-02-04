//
//  CameraView.h
//  OpenCVImage
//
//  Created by 靳杰 on 15/1/31.
//  Copyright (c) 2015年 靳杰. All rights reserved.
//

#ifndef OpenCVImage_CameraView_h
#define OpenCVImage_CameraView_h

#import <UIKit/UIKit.h>

@class AVCaptureSession;

@interface CameraView : UIView

@property (nonatomic) AVCaptureSession *session;

@end
#endif
