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

@interface KBPlayerController6_0 ()

@property(nonatomic,strong)KBPlayer *kbplayer;

@end

@implementation KBPlayerController6_0

#pragma mark - life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    if (_videoDictionary[keyVideoUrl]) {
        [self.view addSubview:self.kbplayer];
        
        
    }
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - setters and getters

-(KBPlayer *)kbplayer{
    if (_kbplayer == nil) {
        _kbplayer = [[KBPlayer alloc] initWithFrame:self.view.bounds];
    }
    return _kbplayer;
}



@end
