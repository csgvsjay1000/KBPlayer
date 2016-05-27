//
//  KBPlayerController7_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/27/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController7_0.h"
#import "KBPlayer7_0.h"
#import "ViewController.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"

@interface KBPlayerController7_0 ()

@property(nonatomic,strong)KBPlayer7_0 *kbplayer;
@property(nonatomic,strong)VRPlayControlView *controlView;

@end

@implementation KBPlayerController7_0

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    if (_videoDictionary[keyVideoUrl]) {
        [self.view addSubview:self.kbplayer];
        [self.kbplayer preparePlayWithUrlStr:_videoDictionary[keyVideoUrl]];
        
    }
    [self.view addSubview:self.controlView];
    [self layoutSubPages];
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


#pragma mark - button actions
-(void)backButtonActions{
    //    [_kbplayer stop];
    [_kbplayer destoryPlayer];
    [self dismissViewControllerAnimated:NO completion:nil];
    // do not lock AudioQueueStop, or may be run into deadlock
    
}

#pragma mark - setters and getters
-(VRPlayControlView *)controlView{
    if (_controlView == nil) {
        _controlView = [[VRPlayControlView alloc] init];
        [_controlView.backButton addTarget:self action:@selector(backButtonActions) forControlEvents:UIControlEventTouchUpInside];
    }
    return _controlView;
}

-(KBPlayer7_0 *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer7_0 alloc] initWithFrame:self.view.bounds];
    }
    return _kbplayer;
}

@end
