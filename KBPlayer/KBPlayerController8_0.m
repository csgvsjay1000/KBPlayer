//
//  KBPlayerController8_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/27/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController8_0.h"
#import "KBPlayer8_0.h"
#import "ViewController.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"

@interface KBPlayerController8_0 ()<KBPlayer8_0ItemDelegate>

@property(nonatomic,strong)KBPlayer8_0 *kbplayer;
@property(nonatomic,strong)VRPlayControlView *controlView;

@property(nonatomic) BOOL isStopByUser;  //用户手动暂停，暂停有两种情况，1、用户手动暂停，2、网络差导致的暂停。
@property(nonatomic,strong)NSTimer *timer;   //定时器，用于播放按钮，滑动条等隐藏和显示。
@property(nonatomic,strong)NSTimer *refreshTimer;   //定时器，刷新播放进度条。

@property(nonatomic,assign)KBPlayerVideoType videoType;  //普通视频，全景视频
@property(nonatomic,assign)KBPlayerNetType netType;  //本地视频，网络视频，网络直播

@end

@implementation KBPlayerController8_0

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    if (_videoDictionary[keyVideoUrl]) {
        
        _videoType = [_videoDictionary[keyVideoType] integerValue];
        _netType = [_videoDictionary[keyNetType] integerValue];
        [self.view addSubview:self.kbplayer];
        [self.kbplayer preparePlayWithUrlStr:_videoDictionary[keyVideoUrl]];
        
    }
    [self.view addSubview:self.controlView];

    [self layoutSubPages];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(liveViewTaped)]];
    [self liveViewTaped];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshCurrentTime) userInfo:nil repeats:YES];
    if (_netType == KBPlayerNetTypeLive) {
        _controlView.playButton.hidden = YES;
        _controlView.slider.hidden = YES;
        _controlView.currentTimeLabel.hidden = YES;
        _controlView.totalTimeLabel.hidden = YES;
        _controlView.progressView.hidden = YES;
    }
    
    UIImage *image = [UIImage imageNamed:@"loading_bgView"];
    self.view.layer.contents = (id) image.CGImage;
}

-(void)layoutSubPages{
    [_controlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.bottom.equalTo(self.view);
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    _kbplayer.frame = self.view.bounds;
    [_kbplayer refreshFrame];
    
}


-(void)dealloc{
    
    NSLog(@"%@ dealloc",[self class]);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - KBPlayer8_0ItemDelegate

-(void)refreshDuration{
    dispatch_async(dispatch_get_main_queue(), ^{
        _controlView.slider.maximumValue = _kbplayer.duration;
        _controlView.slider.minimumValue = 0.0;
        [self updateTotolTime:_kbplayer.duration updateLabel:self.controlView.totalTimeLabel];
    });

}


#pragma mark - button actions
-(void)backButtonActions{
    //    [_kbplayer stop];
    [_refreshTimer invalidate];
    [_timer invalidate];
    [_kbplayer destoryPlayer];
    [self dismissViewControllerAnimated:NO completion:nil];
    // do not lock AudioQueueStop, or may be run into deadlock
    
}

//点击播放按钮
- (void)playButtonPressed
{
    if (self.isStopByUser) {
        //播放
        [self.kbplayer play];
        [self.controlView.playButton setImage:[UIImage imageNamed:@"player_pause"] forState:UIControlStateNormal];
    }else {
        //暂停
        [self.kbplayer pause];
        [self.controlView.playButton setImage:[UIImage imageNamed:@"player_play"] forState:UIControlStateNormal];
    }
    self.isStopByUser = !self.isStopByUser;
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

- (void)playSliderChangeEnd:(UISlider *)slider
{
    [self updateTotolTime:_kbplayer.currentDuration updateLabel:self.controlView.currentTimeLabel];
    [self seekToTime:slider.value];
}

- (void)seekToTime:(CGFloat)seconds
{
    NSLog(@"value %lf",seconds);
    [_kbplayer pause];
    if([_kbplayer seekToTime:seconds]){
        [_kbplayer play];
    }
}

-(void)refreshCurrentTime{
        
    [self updateTotolTime:_kbplayer.currentDuration updateLabel:self.controlView.currentTimeLabel];
    [self.controlView.slider setValue:_kbplayer.currentDuration animated:YES];
    
}

#pragma mark - private methods
// 将秒转换成时间显示,获取完直接赋值
- (void)updateTotolTime:(CGFloat)time updateLabel:(UILabel *)label
{
    long videoLenth = ceil(time);
    NSString *strtotol = nil;
    if (videoLenth < 3600) {
        strtotol =  [NSString stringWithFormat:@"%02li:%02li",lround(floor(videoLenth/60.f)),lround(floor(videoLenth/1.f))%60];
    } else {
        strtotol =  [NSString stringWithFormat:@"%02li:%02li:%02li",lround(floor(videoLenth/3600.f)),lround(floor(videoLenth%3600)/60.f),lround(floor(videoLenth/1.f))%60];
    }
    label.text = strtotol;
}


#pragma mark - setters and getters
-(VRPlayControlView *)controlView{
    if (_controlView == nil) {
        _controlView = [[VRPlayControlView alloc] init];
        [_controlView.backButton addTarget:self action:@selector(backButtonActions) forControlEvents:UIControlEventTouchUpInside];
        [_controlView.playButton addTarget:self action:@selector(playButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        [_controlView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(buttonViewTaped)]];
        
        [_controlView.slider addTarget:self action:@selector(playSliderChangeEnd:) forControlEvents:UIControlEventTouchUpInside];
        [_controlView.slider addTarget:self action:@selector(playSliderChangeEnd:) forControlEvents:UIControlEventTouchUpOutside];
        [_controlView.slider addTarget:self action:@selector(playSliderChangeEnd:) forControlEvents:UIControlEventTouchCancel];
    }
    return _controlView;
}

-(KBPlayer8_0 *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer8_0 alloc] initWithFrame:self.view.bounds videoType:_videoType];
        _kbplayer.playerDelegate = self;
    }
    return _kbplayer;
}

@end
