//
//  KBPlayer.h
//  KBPlayer
//
//  Created by chengshenggen on 5/26/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface KBPlayer : UIView

-(void)preparePlayWithUrlStr:(NSString *)urlStr;

-(void)play;

-(void)pause;

-(void)stop;

-(void)destoryPlayer;

@end
