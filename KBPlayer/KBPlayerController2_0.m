//
//  KBPlayerController2_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/20/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController2_0.h"
#import "FFmpegHeader.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"
#import "ViewController.h"

@interface KBPlayerController2_0 ()

@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)VRPlayControlView *controlView;

@property(nonatomic,strong)NSThread *parse_thread;
@property(nonatomic,strong)NSThread *audioThread;
@property(nonatomic,strong)NSThread *videoThread;

@end

@implementation KBPlayerController2_0

#pragma mark - life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.controlView];
    
    [self layoutSubPages];
    if (_videoDictionary[keyVideoUrl]) {
        quit = 0;
        [self doInitVideo];
    }
}

-(void)doInitVideo{
    _is = av_malloc(sizeof(VideoState));
    av_register_all();
    avformat_network_init();
    
    strlcpy(_is->filename, [_videoDictionary[keyVideoUrl] UTF8String], sizeof(_is->filename));
    
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
    
    _parse_thread = [[NSThread alloc] initWithTarget:self selector:@selector(decode_thread) object:nil];
    _parse_thread.name = @"com.3glasses.vrshow.parse_thread";
    [_parse_thread start];
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
    quit = 1;
    if (_is) {
        free(_is);
    }
    
    NSLog(@"%@ dealloc",[self class]);
}

#pragma mark - parse thread
int decode_interrupt_cb(void *opaque) {
    return 0;
}

-(void)decode_thread{
    _is->audioStream = -1;
    _is->videoStream = -1;
    
    AVIOInterruptCB interupt_cb;
    interupt_cb.callback = decode_interrupt_cb;
    interupt_cb.opaque = _is;
    _is->ic = NULL;
    if (avio_open2(&_is->io_ctx, _is->filename, 0, &interupt_cb, NULL)) {
        fprintf(stderr, "Cannot open I/O for %s\n", _is->filename);
        return;
    }
    //Open video file
    if (avformat_open_input(&_is->ic, _is->filename, NULL, NULL) != 0) {
        return; //Couldn't open file
    }
    if (avformat_find_stream_info(_is->ic, NULL) < 0) {
        fprintf(stderr, "Cannot find stream for %s\n", _is->filename);
        return; // Couldn't find stream information
    }
    av_dump_format(_is->ic, 0, _is->filename, 0);
    
    
    avformat_close_input(&_is->ic);
    avformat_network_deinit();

}

#pragma mark - exit parse thread
-(void)doExit{
    if (_is) {
        
    }
}

-(void)stream_close{
    
}


#pragma mark - button actions
-(void)backButtonActions{
    if (_parse_thread) {
        [_parse_thread cancel];
    }
    if (_is) {
        
        
    }
    
    
    [self dismissViewControllerAnimated:NO completion:nil];
    // do not lock AudioQueueStop, or may be run into deadlock
    
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
