//
//  VRPlayControlView.h
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface VRPlayControlView : UIView

@property(nonatomic,strong)UIButton *backButton;
@property(nonatomic,strong)UIButton *playButton;

@property(nonatomic,strong)UISlider *slider;
@property(nonatomic,strong)UIProgressView *progressView;

@property(nonatomic,strong)UILabel *currentTimeLabel;
@property(nonatomic,strong)UILabel *totalTimeLabel;
@property(nonatomic,strong)UIButton *doubleButton;


@end
