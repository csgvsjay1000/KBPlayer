//
//  CacheView.h
//  VRShow
//
//  Created by chengshenggen on 3/5/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CacheView : UIView

@property(nonatomic,strong)UIActivityIndicatorView *activityView;
@property(nonatomic,strong)UILabel *msgLabel;

+(void)show:(UIView *)inView;

+(void)hide;

@end
