//
//  CacheView.m
//  VRShow
//
//  Created by chengshenggen on 3/5/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "CacheView.h"
#import "Masonry.h"
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <net/if_dl.h>

@interface CacheView ()
{
    NSInteger i;
    int _iBytes;
    int _oBytes;
}

@property (nonatomic, strong) NSString *receivedNetworkSpeed;
@property (nonatomic, strong) NSString *sendNetworkSpeed;
@property (nonatomic, strong) NSTimer *timer;

@end

@implementation CacheView

static CacheView *cacheView;

+(CacheView *)instance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cacheView = [[CacheView alloc] init];
    });
    return cacheView;
}

-(id)init{
    self = [super init];
    if (self) {
        [self addSubview:self.activityView];
        [self addSubview:self.msgLabel];
        
        [self layoutSubPages];
        
    }
    return self;
}

-(void)layoutSubPages{
    [_activityView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.top.right.equalTo(self);
        make.height.equalTo([NSNumber numberWithFloat:30]);
    }];
    [_msgLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_activityView.mas_bottom).offset(2);
        make.centerX.equalTo(self);
    }];
}

+(void)show:(UIView *)inView{
    CacheView *cache = [CacheView instance];
    [cache removeFromSuperview];
    [inView addSubview:cache];
    
    [cache mas_makeConstraints:^(MASConstraintMaker *make) {
        make.size.mas_equalTo(CGSizeMake(100, 60));
        make.center.equalTo(inView);
    }];
    
    [cache.activityView startAnimating];
    cache.msgLabel.text = @"正在加载...";
    
}

#pragma mark - 私有方法


+(void)hide{
    CacheView *cache = [CacheView instance];
    [cache removeFromSuperview];
    [cache.activityView stopAnimating];
    
//    [cache.timer invalidate];
//    cache.msgLabel.text = @"";
}

#pragma mark - setters and getters

-(UIActivityIndicatorView *)activityView{
    if (_activityView == nil) {
        _activityView = [[UIActivityIndicatorView alloc] init];
        _activityView.color = [UIColor whiteColor];
    }
    return _activityView;
}

-(UILabel *)msgLabel{
    if (_msgLabel == nil) {
        _msgLabel = [[UILabel alloc]init];
        _msgLabel.textColor = [UIColor whiteColor];
        _msgLabel.font = [UIFont systemFontOfSize:10.0];
        _msgLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _msgLabel;
}


@end
