//
//  PanormalOpenGLView.h
//  KBPlayer
//
//  Created by chengshenggen on 5/30/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/EAGL.h>
#include <sys/time.h>
#import <CoreMotion/CoreMotion.h>

typedef enum : NSUInteger {
    KBPlayerLocationNone = 10,  //不分左右屏
    KBPlayerLocationLeft = 20,  //
    KBPlayerLocationRight = 30, //
    
    
} KBPlayerLocation;


@interface PanormalOpenGLView : UIView{
    /**
     OpenGL绘图上下文
     */
    EAGLContext             *_glContext;
    
    /**
     帧缓冲区
     */
    GLuint                  _framebuffer;
    
    /**
     渲染缓冲区
     */
    GLuint                  _renderBuffer;
    
    /**
     着色器句柄
     */
    GLuint                  _program;
    
    /**
     YUV纹理数组
     */
    GLuint                  _textureYUV[3];
    
    /**
     视频宽度
     */
    GLuint                  _videoW;
    
    /**
     视频高度
     */
    GLuint                  _videoH;
    
    GLsizei                 _viewScale;
	   
    //void                    *_pYuvData;
    
    int _numIndices;
    GLushort *indices;
    
    GLuint _mvpLocation;
}

@property(nonatomic,strong)CMMotionManager *motionManager;
@property(nonatomic,strong)CMAttitude *referenceAttitude;

@property(nonatomic,assign)KBPlayerLocation playerLocation;

-(id)initWithFrame:(CGRect)frame playerLocation:(KBPlayerLocation)playerLocation;

- (void)displayYUV420pData:(void *)data width:(NSInteger)w height:(NSInteger)h;

@end
