//
//  KBPlayerController12_0.m
//  KBPlayer
//
//  Created by chengshenggen on 8/10/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController12_0.h"
#import "KBPlayer12_0.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader12_0.h"
#import "KBPlayerHeader.h"

@interface KBPlayerController12_0 ()

@property(nonatomic,strong)VRPlayControlView *controlView;
@property(nonatomic,strong)KBPlayer12_0 *kbplayer;
@property(nonatomic,strong)NSTimer *timer;   //定时器，用于播放按钮，滑动条等隐藏和显示。

@end

@implementation KBPlayerController12_0

-(void)viewDidLoad{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.kbplayer];
    [self.view addSubview:self.controlView];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(liveViewTaped)]];
    [self layoutSubPages];
    [_kbplayer preparePlayWithUrlStr:nil];
}

-(void)layoutSubPages{
    [_controlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.bottom.equalTo(self.view);
    }];
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self liveViewTaped];
    _kbplayer.frame = self.view.bounds;
//    [_kbplayer refreshFrame];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - button actions
-(void)backButtonActions{
    
    [self dismissViewControllerAnimated:NO completion:nil];
    // do not lock AudioQueueStop, or may be run into deadlock
    
}

- (void)liveViewTaped
{
    [UIView animateWithDuration:0.2 animations:^{
        _controlView.alpha = 1;
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
        
    }];
    if (_timer) {
        [_timer invalidate];
    }
    //隔5秒钟后,隐藏导航栏,全屏显示
    _timer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(buttonViewTaped) userInfo:nil repeats:NO];
}

- (void)buttonViewTaped
{
    [UIView animateWithDuration:0.2 animations:^{
        //隐藏状态栏
        _controlView.alpha = 0;
        [[UIApplication sharedApplication]setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    }];
}


#pragma mark - setters and getters
-(VRPlayControlView *)controlView{
    if (_controlView == nil) {
        _controlView = [[VRPlayControlView alloc] init];
        [_controlView.backButton addTarget:self action:@selector(backButtonActions) forControlEvents:UIControlEventTouchUpInside];
        [_controlView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(buttonViewTaped)]];
        
    }
    return _controlView;
}

-(KBPlayer12_0 *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer12_0 alloc] initWithFrame:self.view.bounds];
    }
    return _kbplayer;
}


@end
