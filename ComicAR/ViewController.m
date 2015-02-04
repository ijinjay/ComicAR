//
//  ViewController.m
//  ComicAR
//
//  Created by 靳杰 on 15/2/2.
//  Copyright (c) 2015年 靳杰. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()<UIActionSheetDelegate>
@property (weak, nonatomic) IBOutlet UIButton *startButton;
@property (weak, nonatomic) IBOutlet UIButton *infoButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *aboutButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *settingButton;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leftSpace;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *rightSpace;
@property (weak, nonatomic) IBOutlet UIToolbar *toolBar;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *barHeight;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *infoHeight;
- (IBAction)setting:(id)sender;
- (IBAction)about:(id)sender;

@property (nonatomic) NSInteger colorIndex;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self prefersStatusBarHidden];
    
    // 更新iPad的界面
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        _leftSpace.constant = 100;
        _rightSpace.constant = 100;
        _startButton.titleLabel.font = [UIFont systemFontOfSize:60];
        _infoButton.titleLabel.font = [UIFont systemFontOfSize:45];
        _barHeight.constant = 80;
        _infoHeight.constant = 80;
        [_aboutButton setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:45]} forState:UIControlStateNormal];
        [_settingButton setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:45]} forState:UIControlStateNormal];
    }
    // 设置界面颜色
    _startButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [_startButton setTitle:@"开启\n奇幻之旅" forState:UIControlStateNormal];
    UIColor *color1 = [UIColor colorWithRed:(46/255.0) green:(204/255.0) blue:(113/255.0) alpha:1.0];
    UIColor *color2 = [UIColor colorWithRed:(26/255.0) green:(188/255.0) blue:(204/255.0) alpha:1.0];
    UIColor *color3 = [UIColor colorWithRed:(231/255.0) green:(76/255.0) blue:(60/255.0) alpha:1.0];
    UIColor *color4 = [UIColor colorWithRed:(142/255.0) green:(68/255.0) blue:(173/255.0) alpha:1.0];
    NSArray *colorArray = [[NSArray alloc] initWithObjects:color1, color2, color3, color4, nil];
    
    NSUserDefaults *user = [NSUserDefaults standardUserDefaults];
    if ([user objectForKey:@"colorIndex"] == nil) {
        _colorIndex = 0;
        [user setInteger:_colorIndex forKey:@"colorIndex"];
    } else {
        _colorIndex = [user integerForKey:@"colorIndex"];
    }
    [user setObject:[NSKeyedArchiver archivedDataWithRootObject:colorArray[_colorIndex]] forKey:@"backgroundcolor"];
    [user setInteger:colorArray.count forKey:@"colorcount"];
    
    _startButton.backgroundColor = colorArray[_colorIndex];
    _infoButton.backgroundColor = colorArray[_colorIndex];
    _aboutButton.tintColor = colorArray[_colorIndex];
    _settingButton.tintColor = colorArray[_colorIndex];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
// 隐藏状态栏
- (BOOL)prefersStatusBarHidden {
    return YES;
}
- (IBAction)setting:(id)sender {

    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"图像清晰度" delegate:self cancelButtonTitle:@"取消" destructiveButtonTitle:nil otherButtonTitles:@"高", @"中", @"低", nil];
    actionSheet.opaque = 0.5;
    
    [actionSheet showInView:self.view];
    
}
- (IBAction)about:(id)sender {
    NSLog(@"tap about");
    
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSUserDefaults *user = [NSUserDefaults standardUserDefaults];
    if (buttonIndex != 3) {
        [user setInteger:buttonIndex forKey:@"quanity"];
    }
}

@end
