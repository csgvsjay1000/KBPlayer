//
//  VRPlayControlView.m
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "VRPlayControlView.h"
#import "KBPLayerHeader.h"

@interface VRPlayControlView ()

@property(nonatomic,strong)UIView *topView;  //顶部视图，放置返回按钮、视屏标题
@property(nonatomic,strong)UIView *bottomView;  //底部视图，放置播放按钮、当前播放时间、进度条、视屏时长。（直播没有底部视图）

@property(nonatomic,strong)UILabel *currentTimeLabel;
@property(nonatomic,strong)UILabel *totalTimeLabel;

@end

@implementation VRPlayControlView

#pragma mark - life cycle
-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.topView];
        [self addSubview:self.bottomView];

        [self.topView addSubview:self.backButton];
        [self.bottomView addSubview:self.playButton];
        [self.bottomView addSubview:self.currentTimeLabel];
        [self.bottomView addSubview:self.progressView];
        [self.bottomView addSubview:self.slider];
        [self.bottomView addSubview:self.totalTimeLabel];

        
        [self layoutSubPages];
    }
    return self;
}

-(void)layoutSubPages{
    
    [_topView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self);
        make.height.equalTo(@64);
    }];
    [_bottomView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.left.right.equalTo(self);
        make.height.equalTo(@49);
    }];
    
    [_backButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(80, 64));
        make.left.centerY.equalTo(_topView);
    }];
    
    [_playButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(80, 49));
        make.left.centerY.equalTo(_bottomView);
    }];
    [_currentTimeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(60, 49));
        make.left.equalTo(_playButton.mas_right);
        make.centerY.equalTo(_bottomView);

    }];
    
    [_progressView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(_currentTimeLabel.mas_right);
        make.right.equalTo(_totalTimeLabel.mas_left);
        make.centerY.equalTo(_bottomView);
        
    }];
    [_slider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.bottom.equalTo(_progressView);
    }];
    
    [_totalTimeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(60, 49));
        make.right.equalTo(_bottomView).offset(-50);
        make.centerY.equalTo(_bottomView);
        
    }];
    
    
}

#pragma mark - setters and getters
-(UIView *)topView{
    if (_topView == nil) {
        _topView = [[UIView alloc] init];
    }
    return _topView;
}

-(UIButton *)backButton{
    if (_backButton == nil) {
        _backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_backButton setImage:[UIImage imageNamed:@"player_back"] forState:UIControlStateNormal];
    }
    return _backButton;
}

-(UIView *)bottomView{
    if (_bottomView == nil) {
        _bottomView = [[UIView alloc] init];

    }
    return _bottomView;
}

-(UIButton *)playButton{
    if (_playButton == nil) {
        _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_playButton setImage:[UIImage imageNamed:@"player_play"] forState:UIControlStateNormal];

    }
    return _playButton;
}

-(UILabel *)currentTimeLabel{
    if (_currentTimeLabel == nil) {
        _currentTimeLabel = [[UILabel alloc] init];
        _currentTimeLabel.textColor = [UIColor whiteColor];
        _currentTimeLabel.font = [UIFont systemFontOfSize:14.0];
        _currentTimeLabel.text = @"00:00";
        _currentTimeLabel.textAlignment = NSTextAlignmentCenter;

    }
    return _currentTimeLabel;
}

-(UILabel *)totalTimeLabel{
    if (_totalTimeLabel == nil) {
        _totalTimeLabel = [[UILabel alloc] init];
        _totalTimeLabel.textColor = [UIColor whiteColor];
        _totalTimeLabel.font = [UIFont systemFontOfSize:14.0];
        _totalTimeLabel.text = @"00:00";
        _totalTimeLabel.textAlignment = NSTextAlignmentCenter;

    }
    return _totalTimeLabel;
}

-(UIProgressView *)progressView{
    if (_progressView == nil) {
        _progressView = [[UIProgressView alloc]initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.progressTintColor = UIColorFromRGB(0xffffff);
    }
    return _progressView;
}

-(UISlider *)slider{
    if (_slider == nil) {
        _slider = [[UISlider alloc] init];
        [_slider setThumbImage:[UIImage imageNamed:@"player_slider"] forState:UIControlStateNormal];
        _slider.minimumTrackTintColor = UIColorFromRGB(0x00cdd0);
        _slider.maximumTrackTintColor = [UIColor clearColor];
    }
    return _slider;
}


@end
