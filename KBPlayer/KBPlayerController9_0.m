//
//  KBPlayerController9_0.m
//  KBPlayer
//
//  Created by chengshenggen on 6/15/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController9_0.h"
#import "ViewController.h"
//#import "KBPlayer9_0.h"
#import "KBPlayer9_0.h"

@interface KBPlayerController9_0 ()

@property(nonatomic,strong)KBPlayer9_0 *kbplayer;

@end

@implementation KBPlayerController9_0

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
//    [self.view addSubview:self.kbplayer];
    if (_videoDictionary[keyVideoUrl]) {
        
//        _videoType = [_videoDictionary[keyVideoType] integerValue];
//        _netType = [_videoDictionary[keyNetType] integerValue];
        [self.view addSubview:self.kbplayer];
        [self.kbplayer preparePlayWithUrlStr:_videoDictionary[keyVideoUrl]];
        
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)dealloc{
    
    NSLog(@"%@ dealloc",[self class]);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}


-(KBPlayer9_0 *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer9_0 alloc] initWithFrame:self.view.bounds];
    }
    return _kbplayer;
}

@end
