//
//  KBPlayerController6_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/26/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController6_0.h"
#import "KBPlayer.h"
#import "ViewController.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"


@interface KBPlayerController6_0 ()

@property(nonatomic,strong)KBPlayer *kbplayer;
@property(nonatomic,strong)VRPlayControlView *controlView;


@end

@implementation KBPlayerController6_0

#pragma mark - life cycle
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

-(void)dealloc{

    NSLog(@"%@ dealloc",[self class]);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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


-(KBPlayer *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer alloc] initWithFrame:self.view.bounds];
    }
    return _kbplayer;
}



@end
