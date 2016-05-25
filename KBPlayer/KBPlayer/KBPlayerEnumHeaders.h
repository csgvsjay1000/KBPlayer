//
//  KBPlayerEnumHeaders.h
//  KBPlayer
//
//  Created by chengshenggen on 5/23/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#ifndef KBPlayerEnumHeaders_h
#define KBPlayerEnumHeaders_h

typedef enum : NSUInteger {
    KBPlayerStateDefault = 10,  //默认读取正常
    KBPlayerStateReadError = 20, //读取数据错误，不在继续读取
    KBPlayerStateReadingNetWeak = 30,  //正在读取数据，网络状态不好
    KBPlayerStateParseFinshed = 40,  //解码完成。
    KBPlayerStateUserBack = 50,  //用户返回。
    
} KBPlayerState;


#endif /* KBPlayerEnumHeaders_h */
