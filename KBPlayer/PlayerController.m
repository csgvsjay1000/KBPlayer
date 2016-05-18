//
//  PlayerController.m
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "PlayerController.h"
#import "FFmpegHeader.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"

@interface PlayerController ()

@property(nonatomic,strong)VRPlayControlView *controlView;

@end

@implementation PlayerController

#pragma mark - life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor blackColor];
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

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

-(void)dealloc{
    NSLog(@"%@ dealloc",[self class]);
}

#pragma mark - button actions
-(void)backButtonActions{
    [self dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - setters and getters
-(VRPlayControlView *)controlView{
    if (_controlView == nil) {
        _controlView = [[VRPlayControlView alloc] init];
        [_controlView.backButton addTarget:self action:@selector(backButtonActions) forControlEvents:UIControlEventTouchUpInside];
    }
    return _controlView;
}


@end
