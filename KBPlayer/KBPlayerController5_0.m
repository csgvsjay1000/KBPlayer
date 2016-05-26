//
//  KBPlayerController5_0.m
//  KBPlayer
//
//  Created by chengshenggen on 5/24/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayerController5_0.h"
#import "KBPlayerEnumHeaders.h"
#import "KBFFmpegHeader5_0.h"
#import "VRPlayControlView.h"
#import "ViewController.h"
#import "KBPlayerHeader.h"
#import "OpenGLView20.h"
#import "CacheView.h"

@interface KBPlayerController5_0 (){
    AVFrame *_pFrameYUV;
}

@property(nonatomic,strong)VRPlayControlView *controlView;
@property(nonatomic,strong)OpenGLView20 *glView;


@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSThread *read_tid;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSThread *audioThread;
@property(nonatomic,strong)NSTimer *timer;
@property(nonatomic,assign)KBPlayerState playerState;

@end

@implementation KBPlayerController5_0


-(void)viewDidLoad{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.glView];
    [self.view addSubview:self.controlView];
    [CacheView show:self.glView];
    [self layoutSubPages];
    if (_videoDictionary[keyVideoUrl]) {
        av_register_all();
        avformat_network_init();
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
    
    quit = 0;
    _is = av_malloc(sizeof(VideoState));
    if (!_is) {
        return;
    }
    strlcpy(_is->filename, [_videoDictionary[keyVideoUrl] UTF8String], sizeof(_is->filename));
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
    _read_tid = [[NSThread alloc] initWithTarget:self selector:@selector(read_thread) object:nil];
    _read_tid.name = @"com.3glasses.vrshow.read";

    [_read_tid start];
}

-(void)reloadPlayer{
    [self doExit];
    [CacheView show:self.glView];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self schedule_refresh:40];
        [self doInitPlayer];
    });

}

#pragma mark - read thread
static int decode_interrupt_cb(void *ctx)
{
    return quit;
}
-(void)read_thread{
    _is->video_stream = -1;
    _is->audio_stream = -1;
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
    for (i = 0; i < _is->ic->nb_streams; i++) {
        if (_is->ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            _is->audio_st = _is->ic->streams[i];
            _is->audio_stream = i;
            break;
        }
    }
    if (_is->video_stream >= 0) {
        [self video_stream_component_open:_is->video_stream];
    }
    if (_is->audio_stream >= 0) {
        [self audio_stream_component_open:_is->audio_stream];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [CacheView hide];
    });
    for (; ; ) {
        if (quit) {
            break;
        }
        if (_is->videoq.size>MAX_VIDEOQ_SIZE || _is->audioq.size>MAX_AUDIOQ_SIZE ) {
            printf("audioq.size %d, videoq.size %d\n",_is->audioq.size,_is->videoq.size);

            usleep(10*1000);
            continue;
        }
        if (av_read_frame(_is->ic, packet)>=0) {
            if (packet->stream_index == _is->video_stream) {
                packet_queue_put(&_is->videoq, packet);
            }else if (packet->stream_index == _is->audio_stream) {
                packet_queue_put(&_is->audioq, packet);
            } else {
                av_free_packet(packet);
            }
        }else{
            if (_is->ic->pb->error == 0) {
                NSLog(@"no network");
                if (_is->video_stream>=0) {
                    packet_queue_put_nullpacket(&_is->videoq);
                }
                if (_is->audio_stream>=0) {
                    packet_queue_put_nullpacket(&_is->audioq);
                }
                usleep(100*1000);
                continue;
            }else{
                NSLog(@"av_read_frame error");
                [self doExit];
                ret = 2;
                break;
            }
        }
        
        
    }
    
    
fail:
    NSLog(@"fail");
    
    if (_is->video_stream>=0) {
        [self video_stream_close];
    }
    if (_is->audio_stream >= 0) {
        [self audio_stream_close];
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
    _is = NULL;
    [CacheView hide];

    if (ret == 2 && _playerState != KBPlayerStateUserBack) {
        [self reloadPlayer];
    }
    
}

-(void)video_stream_close{
    AVFormatContext *ic = _is->ic;
    AVCodecContext *codecCtx;
    codecCtx = ic->streams[_is->video_stream]->codec;
    avcodec_close(codecCtx);
    
    sws_freeContext(_is->sws_ctx);
    pthread_cond_signal(&_is->videoq.cond);
    packet_queue_destroy(&_is->videoq);
}

-(void)audio_stream_close{
    AudioQueueStop(_is->playQueue, true);
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(_is->playQueue, _is->playBufs[i]);
    }
    AudioQueueDispose(_is->playQueue, true);
    AVFormatContext *ic = _is->ic;
    AVCodecContext *codecCtx;
    codecCtx = ic->streams[_is->audio_stream]->codec;
    avcodec_close(codecCtx);
    
    free(_is->packetDesc);
    
    swr_free(&_is->swr_ctx);
    pthread_cond_signal(&_is->audioq.cond);

    packet_queue_destroy(&_is->audioq);
}

-(void)playAudioThread{
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueAllocateBuffer(_is->playQueue, _is->audio_buf_size, &_is->playBufs[i]);
        [self readPacketsIntoBuffer:_is->playBufs[i]];
    }
}

-(void)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer{
    if (!buffer) {
        return;
    }
    UInt32 len = buffer->mAudioDataBytesCapacity;
    int len1, audio_data_size;
    double pts;
    /*   len是由SDL传入的SDL缓冲区的大小，如果这个缓冲未满，我们就一直往里填充数据 */
    
    UInt8 *stream = buffer->mAudioData;
    while (len>0) {
        if (quit) {
            break;
        }
        /*  audio_buf_index 和 audio_buf_size 标示我们自己用来放置解码出来的数据的缓冲区，*/
        /*   这些数据待copy到SDL缓冲区， 当audio_buf_index >= audio_buf_size的时候意味着我*/
        /*   们的缓冲为空，没有数据可供copy，这时候需要调用audio_decode_frame来解码出更 */
        /*   多的桢数据 */
        if (_is->audio_buffer_index>=_is->audio_buffer_size) {
            audio_data_size = [self audio_decode_frame:&pts];
            if (audio_data_size < 0) {
                /* silence */
                NSLog(@"audio_data_size < 0");
                _is->audio_buffer_size = 4096;
                //                /* 清零，静音 */
                memset(_is->audio_buf, 0, _is->audio_buffer_size);
            }else{
                _is->audio_buffer_size = audio_data_size;
                //                NSLog(@"audio_data_size :%d",audio_data_size);
            }
            _is->audio_buffer_index = 0;
        }
        len1 = _is->audio_buffer_size - _is->audio_buffer_index;
        if (len1 > len) {
            len1 = len;
        }
        memcpy(stream, (uint8_t *) _is->audio_buf + _is->audio_buffer_index, len1);
        len -= len1;
        stream += len1;
        _is->audio_buffer_index += len1;
        
    }
    buffer->mAudioDataByteSize= buffer->mAudioDataBytesCapacity;
    OSStatus state;
    state = AudioQueueEnqueueBuffer(_is->playQueue, buffer, _is->audio_buf_size, _is->packetDesc);
    if (state != noErr) {
        printf("AudioQueueEnqueueBuffer error\n");
    }else{
//        NSLog(@"AudioQueueEnqueueBuffer success mAudioDataByteSize :%d ",buffer->mAudioDataByteSize);

    }
    
}

-(int) audio_decode_frame:(double *)pts_ptr {
    int len1, len2, decoded_data_size;
    AVPacket *pkt = &_is->audio_pkt;
    int got_frame = 0;
    double pts;
    int64_t dec_channel_layout;
    int resampled_data_size;
    int n;
    
    for (; ; ) {
        while (_is->audio_pkt_size>0) {
            if (!_is->audio_frame) {
                _is->audio_frame = av_frame_alloc();
            }
            len1 = avcodec_decode_audio4(_is->audio_st->codec, _is->audio_frame,&got_frame, pkt);
            if (len1 < 0) {
                // error, skip the frame
                _is->audio_pkt_size = 0;
                break;
            }
            _is->audio_pkt_data += len1;
            _is->audio_pkt_size -= len1;
            if (!got_frame)
                continue;
            /* 计算解码出来的桢需要的缓冲大小 */
            decoded_data_size = av_samples_get_buffer_size(NULL,_is->audio_frame->channels, _is->audio_frame->nb_samples,_is->audio_frame->format, 1);
            dec_channel_layout = (_is->audio_frame->channel_layout && _is->audio_frame->channels == av_get_channel_layout_nb_channels(_is->audio_frame->channel_layout))?_is->audio_frame->channel_layout:av_get_default_channel_layout(_is->audio_frame->channels);
            
            if (!_is->swr_ctx) {
                _is->swr_ctx = swr_alloc_set_opts(_is->swr_ctx, _is->audio_tgt_channel_layout, _is->audio_tgt_fmt, _is->audio_tgt_freq, dec_channel_layout, _is->audio_frame->format, _is->audio_frame->sample_rate, 0, NULL);
            }
            if (!_is->swr_ctx || swr_init(_is->swr_ctx) < 0) {
                fprintf(stderr, "swr_init() failed\n");
                break;
            }
            if (_is->swr_ctx) {
                const uint8_t **in = (const uint8_t **) _is->audio_frame->extended_data;
                uint8_t *out[] = { _is->audio_buf };
                len2 = swr_convert(_is->swr_ctx, out, sizeof(_is->audio_buf) / _is->audio_tgt_channels/av_get_bytes_per_sample(_is->audio_tgt_fmt), in, _is->audio_frame->nb_samples);
                if (len2 < 0) {
                    fprintf(stderr, "swr_convert() failed\n");
                    break;
                }
                if (len2 == sizeof(_is->audio_buf) / _is->audio_tgt_channels
                    / av_get_bytes_per_sample(_is->audio_tgt_fmt)) {
                    fprintf(stderr,
                            "warning: audio buffer is probably too small\n");
                    swr_init(_is->swr_ctx);
                }
//                _is->audio_buf = _is->audio_buf2;
                resampled_data_size = len2 * _is->audio_tgt_channels
                * av_get_bytes_per_sample(_is->audio_tgt_fmt);
            }else {
//                resampled_data_size = decoded_data_size;
//                _is->audio_buf = _is->audio_frame->data[0];
            }
            pts = _is->audio_clock;
            *pts_ptr = pts;
            n = 2 * _is->audio_st->codec->channels;
            _is->audio_clock += (double) resampled_data_size
            / (double) (n * _is->audio_st->codec->sample_rate);
            
            // We have data, return it and come back for more later
            return resampled_data_size;
            
        }
        if (pkt->data)
            av_free_packet(pkt);
        memset(pkt, 0, sizeof(*pkt));
        
        if (packet_queue_get(&_is->audioq, pkt, 1) < 0)
            return -1;
        
        _is->audio_pkt_data = pkt->data;
        _is->audio_pkt_size = pkt->size;
        /* if update, update the audio clock w/pts */
        if (pkt->pts != AV_NOPTS_VALUE) {
            _is->audio_clock = av_q2d(_is->audio_st->time_base) * pkt->pts;
        }
    }
    
    return 0;
}


static void AQueueOutputCallback(
                                 void * __nullable       inUserData,
                                 AudioQueueRef           inAQ,
                                 AudioQueueBufferRef     inBuffer){
    KBPlayerController5_0 *vc = (__bridge KBPlayerController5_0 *)inUserData;
    if (vc) {
        [vc readPacketsIntoBuffer:inBuffer];
    }
}

-(void)audio_stream_component_open:(int)stream_index{
    AVFormatContext *ic = _is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    AudioStreamBasicDescription format;
    
    codecCtx = ic->streams[stream_index]->codec;
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported audio codec!\n");
        return;
    }
    
    _is->audio_tgt_freq = codecCtx->sample_rate;
    _is->audio_tgt_fmt = AV_SAMPLE_FMT_S16;
    _is->audio_tgt_channel_layout = AV_CH_LAYOUT_STEREO;
    _is->audio_tgt_channels = av_get_channel_layout_nb_channels(_is->audio_tgt_channel_layout);
    
    
    format.mSampleRate = codecCtx->sample_rate;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mBitsPerChannel = 16;
    format.mChannelsPerFrame = 2;
    format.mFramesPerPacket = 1;
    
    format.mBytesPerPacket = format.mBitsPerChannel*format.mChannelsPerFrame/8;
    format.mBytesPerFrame = format.mBytesPerPacket;
    
    _is->format = format;
    AudioQueueNewOutput(&_is->format, AQueueOutputCallback, (__bridge void*)self, NULL, NULL, 0, &_is->playQueue);
    
    _is->audio_buf_size = (format.mBitsPerChannel/8)*format.mSampleRate*0.6;
    _is->packetDesc = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*_is->audio_buf_size);
    memset(&_is->audio_pkt, 0, sizeof(_is->audio_pkt));
    packet_queue_init(&_is->audioq);
    AudioQueueStart(_is->playQueue, NULL);
    _audioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioThread) object:nil];
    _audioThread.name = @"com.3glasses.vrshow.audio";
    [_audioThread start];
    
    
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
        _is->frame_timer = (double) av_gettime() / 1000000.0;
        _is->frame_last_delay = 40e-3;
        _is->video_current_pts_time = av_gettime();
        packet_queue_init(&_is->videoq);
        _videoThread = [[NSThread alloc] initWithTarget:self selector:@selector(playVideoThread) object:nil];
        _videoThread.name = @"com.3glasses.vrshow.video";
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
            continue;
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
    if (_is && _is->video_st) {
        if (_is->pictq_size == 0) {
            [self schedule_refresh:1];
        }else{
            vp = &_is->pictq[_is->pictq_rindex];
            
            _is->video_current_pts = vp->pts;
            _is->video_current_pts_time = av_gettime();
            
            delay = vp->pts - _is->frame_last_pts; /* the pts from last time */
            if (delay <= 0 || delay >= 1.0) {
                /* if incorrect delay, use previous one */
                delay = _is->frame_last_delay;
            }
            /* save for next time */
            _is->frame_last_delay = delay;
            _is->frame_last_pts = vp->pts;
            
            ref_clock = [self get_audio_clock];
            diff = vp->pts - ref_clock;
            sync_threshold =
            (delay > AV_SYNC_THRESHOLD) ? delay : AV_SYNC_THRESHOLD;
            if (fabs(diff) < AV_NOSYNC_THRESHOLD) {
                if (diff <= -sync_threshold) {
                    delay = 0;
                } else if (diff >= sync_threshold) {
                    delay = 2 * delay;
                }
            }
            _is->frame_timer += delay;
            /* computer the REAL delay */
            actual_delay = _is->frame_timer - (av_gettime() / 1000000.0);
            if (actual_delay < 0.010) {
                /* Really it should skip the picture instead */
                actual_delay = 0.010;
            }
            [self schedule_refresh:(int) (actual_delay * 1000 + 0.5)];
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

-(double)get_audio_clock{
    double pts;
    int hw_buf_size, bytes_per_sec, n;
    pts = _is->audio_clock; /* maintained in the audio thread */
    hw_buf_size = _is->audio_buffer_size - _is->audio_buffer_index;
    bytes_per_sec = 0;
    n = _is->audio_st->codec->channels * 2;
    if (_is->audio_st) {
        bytes_per_sec = _is->audio_st->codec->sample_rate * n;
    }
    if (bytes_per_sec) {
        pts -= (double) hw_buf_size / bytes_per_sec;
    }
    return pts;
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
        _videoThread = nil;
    }
    if (_audioThread) {
        [_audioThread cancel];
        _audioThread = nil;
    }
    if (_read_tid) {
        [_read_tid cancel];
        _read_tid = nil;
    }
    avformat_network_deinit();

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
    _playerState = KBPlayerStateUserBack;
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
