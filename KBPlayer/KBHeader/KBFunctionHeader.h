//
//  KBFunctionHeader.h
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#ifndef KBFunctionHeader_h
#define KBFunctionHeader_h

#define UIColorFromRGB(rgbValue) UIColorFromRGBA(rgbValue, 1.0)

#define UIColorFromRGBA(rgbValue, alphaValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:alphaValue]

#endif /* KBFunctionHeader_h */
