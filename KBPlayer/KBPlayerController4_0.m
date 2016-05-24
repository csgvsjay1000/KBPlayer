//
//  KBPlayerController4_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/24/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController4_0.h"
#import "KBFFmpegHeader4_0.h"
#import "VRPlayControlView.h"
#import "ViewController.h"
#import "KBPlayerHeader.h"
#import "OpenGLView20.h"


@interface KBPlayerController4_0 (){
    AVFrame *_pFrameYUV;
}

@property(nonatomic,strong)VRPlayControlView *controlView;
@property(nonatomic,strong)OpenGLView20 *glView;


@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSThread *read_tid;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSTimer *timer;


@end

@implementation KBPlayerController4_0

-(void)viewDidLoad{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.glView];
    [self.view addSubview:self.controlView];
    
    [self layoutSubPages];
    if (_videoDictionary[keyVideoUrl]) {
        [self schedule_refresh:40];
        [self doInitPlayer];
    }
    
}

-(void)layoutSubPages{
    [_controlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.bottom.equalTo(self.view);
    }];
}

-(void)dealloc{
    if (_is == NULL) {
        NSLog(@"_is == NULL");
    }else{
        av_free(_is);
        _is = NULL;
        NSLog(@"_is != NULL");
    }
    NSLog(@"%@ dealloc",[self class]);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    _glView.frame = self.view.bounds;
}

-(void)doInitPlayer{
    av_register_all();
    avformat_network_init();
    quit = 0;
    _is = av_malloc(sizeof(VideoState));
    if (!_is) {
        return;
    }
    strlcpy(_is->filename, [_videoDictionary[keyVideoUrl] UTF8String], sizeof(_is->filename));
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
    _read_tid = [[NSThread alloc] initWithTarget:self selector:@selector(read_thread) object:nil];
    [_read_tid start];
}

#pragma mark - read thread
static int decode_interrupt_cb(void *ctx)
{
    return quit;
}
-(void)read_thread{
    _is->video_stream = -1;
    AVFormatContext *ic = NULL;
    ic = avformat_alloc_context();
    int ret=0,err,state = 0;
    
    if (!ic) {
        av_log(NULL, AV_LOG_FATAL, "Could not allocate context.\n");
        ret = -1;
        goto fail;
    }
    ic->interrupt_callback.callback = decode_interrupt_cb;
    ic->interrupt_callback.opaque = _is;
    err = avformat_open_input(&ic, _is->filename, NULL, NULL);
    if (err < 0) {
        av_log(NULL, AV_LOG_FATAL, "Could not open_input.\n");
        ret = -1;
        goto fail;
    }
    _is->ic = ic;
    if (avformat_find_stream_info(_is->ic, NULL) < 0) {
        fprintf(stderr, "Cannot find stream for %s\n", _is->filename);
        ret = -1;
        goto fail;
    }
    av_dump_format(_is->ic, 0, _is->filename, 0);
    int i;
    for (i = 0; i < _is->ic->nb_streams; i++) {
        if (_is->ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO) {
            _is->video_st = _is->ic->streams[i];
            _is->video_stream = i;
            break;
        }
    }
    if (_is->video_stream >= 0) {
        [self video_stream_component_open:_is->video_stream];
    }
    
    _pFrameYUV = NULL;
    _pFrameYUV = av_frame_alloc();
    if (_pFrameYUV == NULL)
        return;

    int numBytes = avpicture_get_size(AV_PIX_FMT_YUV420P, _is->video_st->codec->width,
                                      _is->video_st->codec->height);
    uint8_t* buffer = NULL;
    buffer = (uint8_t *) av_malloc(numBytes * sizeof(uint8_t));
    state = 1;
    avpicture_fill((AVPicture *) _pFrameYUV, buffer, AV_PIX_FMT_YUV420P,
                   _is->video_st->codec->width, _is->video_st->codec->height);
    
    AVPacket pkt1, *packet = &pkt1;
    packet = NULL;
    packet=(AVPacket *)av_malloc(sizeof(AVPacket));
    state = 2;
    
    VideoPicture *vp = av_malloc(sizeof(VideoPicture));
    
    _is->pictq[0] = *vp;
    _is->pictq_windex = 0;
    _is->pictq_rindex = 0;
    _is->pictq_size = 0;

    for (; ; ) {
        if (quit) {
            break;
        }
        if (_is->videoq.size>MAX_VIDEOQ_SIZE) {
            usleep(10*1000);
            continue;
        }
        if (av_read_frame(_is->ic, packet)>=0) {
            if (packet->stream_index == _is->video_stream) {
                packet_queue_put(&_is->videoq, packet);
            }else {
                av_free_packet(packet);
            }
        }else{
            if (_is->ic->pb->error == 0) {

                if (_is->video_stream>=0) {
                    packet_queue_put_nullpacket(&_is->videoq);
                }
                usleep(100*1000);
                continue;
            }else{
                NSLog(@"av_read_frame error");
                
                break;
            }
        }
        
        
    }
    
    
fail:
    NSLog(@"fail");
    
    if (_is->video_stream>=0) {
        [self video_stream_close];
    }
    
    av_free(_pFrameYUV);
    if (state >0) {
        av_free(buffer);
    }
    if (state == 2) {
        av_free(packet);
    }
    
    av_free(vp);
    
    if (ic) {
        avformat_close_input(&ic);
    }
    
    pthread_mutex_destroy(&_is->pictq_mutex);
    pthread_cond_destroy(&_is->pictq_cond);
    
    av_free(_is);
    memset(_is, 0, sizeof(VideoState));
    _is = NULL;
    
    
    
}

-(void)video_stream_close{
    AVFormatContext *ic = _is->ic;
    AVCodecContext *codecCtx;
    codecCtx = ic->streams[_is->video_stream]->codec;
    avcodec_close(codecCtx);
    
    sws_freeContext(_is->sws_ctx);
    
    packet_queue_destroy(&_is->videoq);
}

-(void)video_stream_component_open:(int)stream_index{
    AVFormatContext *ic = _is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    codecCtx = ic->streams[stream_index]->codec;
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported video codec!\n");
        return;
    }
    if (codecCtx->codec_type == AVMEDIA_TYPE_VIDEO) {
        _is->sws_ctx = sws_getContext(_is->video_st->codec->width,
                                      _is->video_st->codec->height, _is->video_st->codec->pix_fmt,
                                      _is->video_st->codec->width, _is->video_st->codec->height,
                                      AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
//        _is->frame_timer = (double) av_gettime() / 1000000.0;
//        _is->frame_last_delay = 40e-3;
//        _is->video_current_pts_time = av_gettime();
        packet_queue_init(&_is->videoq);
//        codecCtx->get_buffer2 = avcodec_default_get_buffer2;
//        codecCtx->get_format          = avcodec_default_get_format;
//        codecCtx->execute             = avcodec_default_execute;
//        codecCtx->execute2            = avcodec_default_execute2;
        //       codecCtx->release_buffer = our_release_buffer;
        _videoThread = [[NSThread alloc] initWithTarget:self selector:@selector(playVideoThread) object:nil];
        [_videoThread start];
    }
    
}

-(void)playVideoThread{
    
    AVPacket pkt1, *packet = &pkt1;
    int frameFinished;
    AVFrame *pFrame;
    double pts;
    pFrame = av_frame_alloc();
    
    for (; ; ) {
        if (quit) {
            break;
        }
        if (packet_queue_get(&_is->videoq, packet, 1) < 0) {
            // means we quit getting packets
            break;
        }
        pts = 0;
        avcodec_decode_video2(_is->video_st->codec, pFrame, &frameFinished,packet);
        if (packet->dts == AV_NOPTS_VALUE && pFrame->opaque
            && *(uint64_t*) pFrame->opaque != AV_NOPTS_VALUE) {
            pts = *(uint64_t *) pFrame->opaque;
        } else if (packet->dts != AV_NOPTS_VALUE) {
            pts = packet->dts;
        } else {
            pts = 0;
        }
        pts *= av_q2d(_is->video_st->time_base);
        if (frameFinished) {
            pts = [self synchronize_video:pFrame andPts:pts];
            if ([self queue_picture:pFrame andPts:pts] < 0) {
                break;
            }
        }
        av_free_packet(packet);
    }
    av_free(pFrame);
}

-(void)schedule_refresh:(int)delay{
    if (_timer) {
        [_timer invalidate];
    }
    _timer = [NSTimer scheduledTimerWithTimeInterval:delay/1000.0 target:self selector:@selector(video_refresh_timer) userInfo:nil repeats:YES];
}

-(void)video_refresh_timer{
    if (quit) {
        [_timer invalidate];
        return;
    }
    VideoPicture *vp;
    double actual_delay, delay, sync_threshold, ref_clock, diff;
    if (_is->video_st) {
        if (_is->pictq_size == 0) {
            [self schedule_refresh:1];
        }else{
            vp = &_is->pictq[_is->pictq_rindex];
           
            [self video_display];
            
            if (++_is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
                _is->pictq_rindex = 0;
            }
            pthread_mutex_lock(&_is->pictq_mutex);
            _is->pictq_size--;
            pthread_cond_signal(&_is->pictq_cond);
            pthread_mutex_unlock(&_is->pictq_mutex);
        }
    }else{
        [self schedule_refresh:100];
    }
}

-(void)video_display{
    if (_pFrameYUV && _pFrameYUV->data[0]!=NULL) {
        [_glView displayYUV420pData:_pFrameYUV->data[0] width:_is->video_st->codec->width height:_is->video_st->codec->height];
        [_glView displayYUV420pData:_pFrameYUV->data[0] width:_is->video_st->codec->width height:_is->video_st->codec->height];
    }
}


#pragma mark - exit
-(void)doExit{
    if (_timer) {
        [_timer invalidate];
    }
    quit = 1;
    if (_is) {
        pthread_cond_signal(&_is->pictq_cond);
    }
    if (_videoThread) {
        [_videoThread cancel];
    }
}

#pragma mark - synchronize video clock
-(double)synchronize_video:(AVFrame *)src_frame andPts:(double)pts{
    
    double frame_delay;
    if (pts != 0) {
        _is->video_clock = pts;
    }else{
        pts = _is->video_clock;
    }
    frame_delay = av_q2d(_is->video_st->codec->time_base);
    frame_delay += src_frame->repeat_pict*(frame_delay*0.5);
    _is->video_clock += frame_delay;
    return pts;
}


-(int)queue_picture:(AVFrame *)pFrame andPts:(double)pts{
    VideoPicture *vp;
    pthread_mutex_lock(&_is->pictq_mutex);
    while (_is->pictq_size>=VIDEO_PICTURE_QUEUE_SIZE && !quit) {
        pthread_cond_wait(&_is->pictq_cond, &_is->pictq_mutex);
    }
    pthread_mutex_unlock(&_is->pictq_mutex);
    if (quit)
        return -1;
    vp = &_is->pictq[_is->pictq_windex];
    
    
    if (_pFrameYUV) {
        sws_scale(_is->sws_ctx, (uint8_t const * const *) pFrame->data,
                  pFrame->linesize, 0, _is->video_st->codec->height,
                  _pFrameYUV->data, _pFrameYUV->linesize);
        
        vp->pts = pts;
        if (++_is->pictq_windex == VIDEO_PICTURE_QUEUE_SIZE) {
            _is->pictq_windex = 0;
        }
        pthread_mutex_lock(&_is->pictq_mutex);
        _is->pictq_size++;
        pthread_mutex_unlock(&_is->pictq_mutex);
        
    }
    return 0;
}



#pragma mark - button actions
-(void)backButtonActions{
    [self doExit];
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

-(OpenGLView20 *)glView{
    if (_glView == nil) {
        _glView = [[OpenGLView20 alloc] initWithFrame:self.view.bounds];
    }
    return _glView;
}

@end
