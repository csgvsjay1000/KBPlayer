//
//  KBPlayer8_0.h
//  KBPlayer
//
//  Created by chengshenggen on 5/27/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KBPlayerEnumHeaders.h"

@protocol KBPlayer11_0ItemDelegate <NSObject>

-(void)refreshDuration;  //获取视频时长


@end

@interface KBPlayer11_0 : UIView

@property(nonatomic,assign)CGFloat duration;  //视频时长 (秒)
@property(nonatomic,assign)CGFloat currentDuration;  //当前播放时间 (秒)

@property(nonatomic,weak)id<KBPlayer11_0ItemDelegate> playerDelegate;

@property(nonatomic,assign)KBPlayerVideoType videoType;

-(id)initWithFrame:(CGRect)frame videoType:(KBPlayerVideoType)videoType;

-(void)preparePlayWithUrlStr:(NSString *)urlStr;

-(void)play;

-(void)pause;

-(void)stop;

-(void)destoryPlayer;

-(void)refreshFrame;

-(BOOL)seekToTime:(CGFloat)toTime;

@end
