//
//  KBPlayer10_0.m
//  KBPlayer
//
//  Created by chengshenggen on 8/4/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayer10_0.h"
#import "KBFFmpegHeader10_0.h"

@interface KBPlayer10_0 ()

@property(nonatomic,copy)NSString *urlStr;
@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSTimer *timer;

@property(nonatomic,strong)NSThread *read_tid;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSThread *audioThread;
@property(nonatomic,strong)OpenGLView20 *glView;  //显示普通视频视图


@end

@implementation KBPlayer10_0

#pragma mark - init
-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.glView];

    }
    return self;
}

-(void)dealloc{
    NSLog(@"%@ dealloc",[self class]);
}

#pragma mark - public method
-(void)preparePlayWithUrlStr:(NSString *)urlStr{
    
    _urlStr = urlStr;
    char *filename = "rtmp://live.hkstv.hk.lxdns.com/live/hks";
    VideoState *is;
    is = av_malloc(sizeof(VideoState));
    // Register all formats and codecs
    av_register_all();
    avformat_network_init();
    _is = is;
    _is->audio_buf = malloc(AVCODEC_MAX_AUDIO_FRAME_SIZE * 4);
    strlcpy(is->filename, filename, sizeof(is->filename));
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
    [self schedule_refresh:40];
    is->av_sync_type = AV_SYNC_AUDIO_MASTER;
    
    _read_tid = [[NSThread alloc] initWithTarget:self selector:@selector(decode_thread) object:nil];
    _read_tid.name = @"com.3glasses.vrshow.read";
    
    
    [_read_tid start];
}

-(void)play{
    
}

-(void)pause{
    
}

-(void)refreshFrame{
    
    _glView.frame = self.bounds;
    
}

#pragma mark - thread
-(void)video_thread{
    VideoState *is = _is;
    AVPacket pkt1, *packet = &pkt1;
    int frameFinished;
    AVFrame *pFrame;
    
    double pts;
    
    pFrame = av_frame_alloc();
    
    for (;;) {
        
        if (packet_queue_get(&is->videoq, packet, 1) < 0) {
            // means we quit getting packets
            break;
        }
        
        pts = 0;
        
        // Save global pts to be stored in pFrame in first call
        global_video_pkt_pts = packet->pts;
        
        // Decode video frame
        avcodec_decode_video2(is->video_st->codec, pFrame, &frameFinished,
                              packet);
        
        if (packet->dts == AV_NOPTS_VALUE && pFrame->opaque
            && *(uint64_t*) pFrame->opaque != AV_NOPTS_VALUE) {
            pts = *(uint64_t *) pFrame->opaque;
        } else if (packet->dts != AV_NOPTS_VALUE) {
            pts = packet->dts;
        } else {
            pts = 0;
        }
        pts *= av_q2d(is->video_st->time_base);
        if (frameFinished) {
            pts = [self synchronize_video:pFrame andPts:pts];
            if ([self queue_picture:is pFrame:pFrame andPts:pts] < 0) {
                break;
            }
        }
        av_free_packet(packet);
    }
    av_free(pFrame);

}

-(void)audio_stream_component_open:(VideoState *)is stream_index:(int)stream_index{
    AVFormatContext *ic = is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    codecCtx = ic->streams[stream_index]->codec;

    AudioStreamBasicDescription format;
    
//    is->audio_hw_buf_size = spec.size;
    _is->audio_tgt_freq = _is->audio_src_freq = codecCtx->sample_rate;
    _is->audio_tgt_fmt = _is->audio_src_fmt = AV_SAMPLE_FMT_S16;
    _is->audio_tgt_channel_layout = _is->audio_src_channel_layout = AV_CH_LAYOUT_STEREO;
    _is->audio_tgt_channels = _is->audio_src_channels = av_get_channel_layout_nb_channels(_is->audio_tgt_channel_layout);
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return;
    }
    ic->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    
    is->audioStream = stream_index;
    is->audio_st = ic->streams[stream_index];
    is->audio_buf_size = 0;
    is->audio_buf_index = 0;
    
    /* averaging filter for audio sync */
    is->audio_diff_avg_coef = exp(log(0.01 / AUDIO_DIFF_AVG_NB));
    is->audio_diff_avg_count = 0;
    /* Correct audio only if larger error than this */
    is->audio_diff_threshold = 2.0 * SDL_AUDIO_BUFFER_SIZE
    / codecCtx->sample_rate;
    
    memset(&is->audio_pkt, 0, sizeof(is->audio_pkt));
    packet_queue_init(&is->audioq);
    
    
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
    
    _is->audio_hw_buf_size = (format.mBitsPerChannel/8)*format.mSampleRate*0.6;
    _is->packetDesc = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*_is->audio_hw_buf_size);
    
    _audioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioThread) object:nil];
    _audioThread.name = @"com.3glasses.vrshow.audio";
    [_audioThread start];
    
}

-(void)playAudioThread{
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueAllocateBuffer(_is->playQueue, _is->audio_hw_buf_size, &_is->playBufs[i]);
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


        /*  audio_buf_index 和 audio_buf_size 标示我们自己用来放置解码出来的数据的缓冲区，*/
        /*   这些数据待copy到SDL缓冲区， 当audio_buf_index >= audio_buf_size的时候意味着我*/
        /*   们的缓冲为空，没有数据可供copy，这时候需要调用audio_decode_frame来解码出更 */
        /*   多的桢数据 */
        if (_is->audio_buf_index>=_is->audio_buf_size) {
            audio_data_size = [self audio_decode_frame:_is pts_ptr:&pts];
            if (audio_data_size < 0) {
                /* silence */
                //                NSLog(@"audio_data_size < 0");
                _is->audio_buf_size = 1024;
                //                /* 清零，静音 */
                memset(_is->audio_buf, 0, _is->audio_buf_size);
            }else{
                audio_data_size = [self synchronize_audio:_is samples:(int16_t *) _is->audio_buf samples_size:audio_data_size pts:pts];
                _is->audio_buf_size = audio_data_size;
                
                //                NSLog(@"audio_data_size :%d",audio_data_size);
            }
            _is->audio_buf_index = 0;
        }
        len1 = _is->audio_buf_size - _is->audio_buf_index;
        if (len1 > len) {
            len1 = len;
        }
        memcpy(stream, (uint8_t *) _is->audio_buf + _is->audio_buf_index, len1);
        len -= len1;
        stream += len1;
        _is->audio_buf_index += len1;
        
    }
    buffer->mAudioDataByteSize= buffer->mAudioDataBytesCapacity;
    OSStatus state;
    state = AudioQueueEnqueueBuffer(_is->playQueue, buffer, _is->audio_hw_buf_size, _is->packetDesc);
    if (state != noErr) {
        printf("AudioQueueEnqueueBuffer error\n");
    }else{
        NSLog(@"AudioQueueEnqueueBuffer success mAudioDataByteSize :%d ",buffer->mAudioDataByteSize);
        
    }
}

static void AQueueOutputCallback(
                                 void * __nullable       inUserData,
                                 AudioQueueRef           inAQ,
                                 AudioQueueBufferRef     inBuffer){
    KBPlayer10_0 *vc = (__bridge KBPlayer10_0 *)inUserData;
    if (vc) {
        [vc readPacketsIntoBuffer:inBuffer];
    }
}

-(void)video_stream_component_open:(int)stream_index{
    VideoState *is = _is;
    AVFormatContext *pFormatCtx = _is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    if (stream_index < 0 || stream_index >= pFormatCtx->nb_streams) {
        return;
    }
    // Get a pointer to the codec context for the video stream
    codecCtx = pFormatCtx->streams[stream_index]->codec;
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return ;
    }
    is->videoStream = stream_index;
    is->video_st = pFormatCtx->streams[stream_index];
    is->sws_ctx = sws_getContext(is->video_st->codec->width,
                                 is->video_st->codec->height, is->video_st->codec->pix_fmt,
                                 is->video_st->codec->width, is->video_st->codec->height,
                                 AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    
    is->frame_timer = (double) av_gettime() / 1000000.0;
    is->frame_last_delay = 40e-3;
    is->video_current_pts_time = av_gettime();
    
    packet_queue_init(&is->videoq);
    _videoThread = [[NSThread alloc] initWithTarget:self selector:@selector(video_thread) object:nil];
    _videoThread.name = @"com.3glasses.vrshow.video";
    [_videoThread start];
}

int decode_interrupt_cb(void *opaque) {
    return (global_video_state && global_video_state->quit);
}

-(void)decode_thread{
    VideoState *is = _is;
    AVFormatContext *pFormatCtx = NULL;
    AVPacket pkt1, *packet = &pkt1;
    
    int video_index = -1;
    int audio_index = -1;
    int i;
    
    is->videoStream = -1;
    is->audioStream = -1;
    
    AVIOInterruptCB interupt_cb;
    
    global_video_state = is;
    
    // will interrup blocking functions if we quit!
    interupt_cb.callback = decode_interrupt_cb;
    interupt_cb.opaque = is;
    
    if (avio_open2(&is->io_ctx, is->filename, 0, &interupt_cb, NULL)) {
        fprintf(stderr, "Cannot open I/O for %s\n", is->filename);
        return ;
    }
    
    //Open video file
    if (avformat_open_input(&pFormatCtx, is->filename, NULL, NULL) != 0) {
        return ; //Couldn't open file
    }
    
    is->ic = pFormatCtx;
    
    //Retrieve stream infomation
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        return ; // Couldn't find stream information
    }
    
    //Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, is->filename, 0);
    
    //Find the first video stream
    for (i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO
            && video_index < 0) {
            video_index = i;
        }
        
        if (pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO
            && audio_index < 0) {
            audio_index = i;
        }
    }
    is->videoStream = video_index;
    is->audioStream = audio_index;
    if (audio_index >= 0) {
        /* 所有设置SDL音频流信息的步骤都在这个函数里完成 */
        [self audio_stream_component_open:is stream_index:audio_index];
    }
    
    if (video_index >= 0) {
        [self video_stream_component_open:video_index];
    }
    
    /* 读包的主循环， av_read_frame不停的从文件中读取数据包*/
    for (;;) {
        if (is->quit) {
            break;
        }
        //seek  stuff goes here
        /* 这里audioq.size是指队列中的所有数据包带的音频数据的总量或者视频数据总量，并不是包的数量 */
        if (is->audioq.size > MAX_AUDIOQ_SIZE || is->videoq.size > MAX_VIDEOQ_SIZE) {
            usleep(10*1000);
            continue;
        }
        if (av_read_frame(is->ic, packet) < 0) {
            if (is->ic->pb->error == 0) {
                usleep(10*1000);
                continue;
            } else {
                break;
            }
        }
        // Is this a packet from the video stream?
        if (packet->stream_index == is->videoStream) {
            packet_queue_put(&is->videoq, packet);
        } else if (packet->stream_index == is->audioStream) {
            packet_queue_put(&is->audioq, packet);
        } else {
            av_free_packet(packet);
        }
    }
    /*all done - wait for it*/
    while (!is->quit) {
        usleep(10*1000);
    }
    
}

#pragma mark - video display
-(void)video_display:(VideoState *)is{
    VideoPicture *vp;
    float aspect_ratio;
    
    vp = &is->pictq[is->pictq_rindex];
    if (vp && vp->rawdata) {
        printf("video_clock %f,audio_clock %f\n",is->video_clock,is->audio_clock);
        if (is->video_st->codec->sample_aspect_ratio.num == 0) {
            aspect_ratio = 0;
        } else {
            aspect_ratio = av_q2d(is->video_st->codec->sample_aspect_ratio)
            * is->video_st->codec->width / is->video_st->codec->height;
        }
        
        if (aspect_ratio <= 0.0) {
            aspect_ratio = (float) is->video_st->codec->width
            / (float) is->video_st->codec->height;
        }
        
        if (_glView) {
            [_glView displayYUV420pData:vp->rawdata->data[0] width:_is->video_st->codec->width height:_is->video_st->codec->height];
        }
        
    }
}

-(void)video_refresh_timer{
    VideoState *is = _is;
    VideoPicture *vp;
    double actual_delay, delay, sync_threshold, ref_clock, diff;
    
    if (is->video_st) {
        if (is->pictq_size == 0) {
            [self schedule_refresh:1];
        }else{
            vp = &is->pictq[is->pictq_rindex];
            
            is->video_current_pts = vp->pts;
            is->video_current_pts_time = av_gettime();
            
            delay = vp->pts - is->frame_last_pts; /* the pts from last time */
            if (delay <= 0 || delay >= 1.0) {
                /* if incorrect delay, use previous one */
                delay = is->frame_last_delay;
            }
            /* save for next time */
            is->frame_last_delay = delay;
            is->frame_last_pts = vp->pts;
            
            ref_clock = [self get_audio_clock:is];
            diff = vp->pts - ref_clock;
            
            /* update delay to sync to audio if not master source */
            if (is->av_sync_type != AV_SYNC_VIDEO_MASTER) {
                ref_clock = [self get_master_clock:is];
                diff = vp->pts - ref_clock;
                
                /* Skip or repeat the frame. Take delay into account
                 FFPlay still doesn't "know if this is the best guess." */
                sync_threshold =
                (delay > AV_SYNC_THRESHOLD) ? delay : AV_SYNC_THRESHOLD;
                if (fabs(diff) < AV_NOSYNC_THRESHOLD) {
                    if (diff <= -sync_threshold) {
                        delay = 0;
                    } else if (diff >= sync_threshold) {
                        delay = 2 * delay;
                    }
                }
            }
            is->frame_timer += delay;
            /* computer the REAL delay */
            actual_delay = is->frame_timer - (av_gettime() / 1000000.0);
            if (actual_delay < 0.010) {
                /* Really it should skip the picture instead */
                actual_delay = 0.010;
            }
            [self schedule_refresh:(int) (actual_delay * 1000 + 0.5)];
            [self video_display:is];
            
            /* update queue for next picture! */
            if (++is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
                is->pictq_rindex = 0;
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

-(void)schedule_refresh:(int)delay{
    if (_timer) {
        [_timer invalidate];
    }
    _timer = [NSTimer scheduledTimerWithTimeInterval:delay/1000.0 target:self selector:@selector(video_refresh_timer) userInfo:nil repeats:YES];
}

-(void)alloc_picture{
    printf("\n alloc_picture  \n");
    VideoState *is = _is;
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_windex];
    
    if (vp->rawdata) {
        av_free(vp->rawdata);
    }
    vp->width = is->video_st->codec->width;
    vp->height = is->video_st->codec->height;
    
    
    AVFrame* pFrameYUV = av_frame_alloc();
    if (pFrameYUV == NULL)
        return;
    int numBytes = avpicture_get_size(AV_PIX_FMT_YUV420P, vp->width,
                                      vp->height);
    
    uint8_t* buffer = (uint8_t *) av_malloc(numBytes * sizeof(uint8_t));
    
    avpicture_fill((AVPicture *) pFrameYUV, buffer, AV_PIX_FMT_YUV420P,
                   vp->width, vp->height);
    
    vp->rawdata = pFrameYUV;
    pthread_mutex_lock(&_is->pictq_mutex);
    vp->allocated = 1;
    pthread_cond_signal(&_is->pictq_cond);
    pthread_mutex_unlock(&_is->pictq_mutex);
}

-(int)queue_picture:(VideoState *)is pFrame:(AVFrame *)pFrame andPts:(double)pts{
    VideoPicture *vp;
    //int dst_pic_fmt
    AVPicture pict;
    
    pthread_mutex_lock(&_is->pictq_mutex);
    while (_is->pictq_size>=VIDEO_PICTURE_QUEUE_SIZE && !is->quit) {
        pthread_cond_wait(&_is->pictq_cond, &_is->pictq_mutex);
    }
    pthread_mutex_unlock(&_is->pictq_mutex);
    
    if (is->quit)
        return -1;
    vp = &is->pictq[is->pictq_windex];
    /* allocate or resize the buffer ! */
    if (vp->width != is->video_st->codec->width
        || vp->height != is->video_st->codec->height) {
        vp->allocated = 0;
        [self alloc_picture];
        
    }
    if (is->quit) {
        return -1;
    }
    /* We have a place to put our picture on the queue */
    if (vp->rawdata) {
        // Convert the image into YUV format that SDL uses
        sws_scale(is->sws_ctx, (uint8_t const * const *) pFrame->data,
                  pFrame->linesize, 0, is->video_st->codec->height,
                  vp->rawdata->data, vp->rawdata->linesize);
        
        vp->pts = pts;
        
        /* now we inform our display thread that we have a pic ready */
        if (++is->pictq_windex == VIDEO_PICTURE_QUEUE_SIZE) {
            is->pictq_windex = 0;
        }
        pthread_mutex_lock(&_is->pictq_mutex);
        _is->pictq_size++;
        pthread_mutex_unlock(&_is->pictq_mutex);
    }
    
    return 0;
}

#pragma mark - decodes
-(int)audio_decode_frame:(VideoState *)is pts_ptr:(double *)pts_ptr{
    
    int len1, len2, decoded_data_size;
    AVPacket *pkt = &is->audio_pkt;
    int got_frame = 0;
    int64_t dec_channel_layout;
    int wanted_nb_samples, resampled_data_size, n;
    
    double pts;
    
    for (;;) {
        while (is->audio_pkt_size > 0) {
            if (!is->audio_frame) {
                if (!(is->audio_frame = av_frame_alloc())) {
                    return AVERROR(ENOMEM);
                }
            } else
                is->audio_frame = av_frame_alloc();
            len1 = avcodec_decode_audio4(is->audio_st->codec, is->audio_frame,
                                         &got_frame, pkt);
            if (len1 < 0) {
                // error, skip the frame
                is->audio_pkt_size = 0;
                break;
            }
            
            is->audio_pkt_data += len1;
            is->audio_pkt_size -= len1;
            if (!got_frame)
                continue;
            /* 计算解码出来的桢需要的缓冲大小 */
            decoded_data_size = av_samples_get_buffer_size(NULL,
                                                           is->audio_frame->channels, is->audio_frame->nb_samples,
                                                           is->audio_frame->format, 1);
            dec_channel_layout =
            (is->audio_frame->channel_layout
             && is->audio_frame->channels
             == av_get_channel_layout_nb_channels(
                                                  is->audio_frame->channel_layout)) ?
            is->audio_frame->channel_layout :
            av_get_default_channel_layout(
                                          is->audio_frame->channels);
            wanted_nb_samples = is->audio_frame->nb_samples;
            
            if (is->audio_frame->format != is->audio_src_fmt
                || dec_channel_layout != is->audio_src_channel_layout
                || is->audio_frame->sample_rate != is->audio_src_freq
                || (wanted_nb_samples != is->audio_frame->nb_samples
                    && !is->swr_ctx)){
                    
                    if (is->swr_ctx)
                        swr_free(&is->swr_ctx);
                    is->swr_ctx = swr_alloc_set_opts(NULL,
                                                     is->audio_tgt_channel_layout, is->audio_tgt_fmt,
                                                     is->audio_tgt_freq, dec_channel_layout,
                                                     is->audio_frame->format, is->audio_frame->sample_rate,
                                                     0, NULL);
                    if (!is->swr_ctx || swr_init(is->swr_ctx) < 0) {
                        fprintf(stderr, "swr_init() failed\n");
                        break;
                    }
                    is->audio_src_channel_layout = dec_channel_layout;
                    is->audio_src_channels = is->audio_st->codec->channels;
                    is->audio_src_freq = is->audio_st->codec->sample_rate;
                    is->audio_src_fmt = is->audio_st->codec->sample_fmt;
            }
            /* 这里我们可以对采样数进行调整，增加或者减少，一般可以用来做声画同步 */
            if (is->swr_ctx) {
                const uint8_t **in =
                (const uint8_t **) is->audio_frame->extended_data;
                uint8_t *out[] = { is->audio_buf2 };
                if (wanted_nb_samples != is->audio_frame->nb_samples) {
                    if (swr_set_compensation(is->swr_ctx,
                                             (wanted_nb_samples - is->audio_frame->nb_samples)
                                             * is->audio_tgt_freq
                                             / is->audio_frame->sample_rate,
                                             wanted_nb_samples * is->audio_tgt_freq
                                             / is->audio_frame->sample_rate) < 0) {
                        fprintf(stderr, "swr_set_compensation() failed\n");
                        break;
                    }
                }
                
                len2 = swr_convert(is->swr_ctx, out,
                                   sizeof(is->audio_buf2) / is->audio_tgt_channels
                                   / av_get_bytes_per_sample(is->audio_tgt_fmt),
                                   in, is->audio_frame->nb_samples);
                if (len2 < 0) {
                    fprintf(stderr, "swr_convert() failed\n");
                    break;
                }
                if (len2
                    == sizeof(is->audio_buf2) / is->audio_tgt_channels
                    / av_get_bytes_per_sample(is->audio_tgt_fmt)) {
                    fprintf(stderr,
                            "warning: audio buffer is probably too small\n");
                    swr_init(is->swr_ctx);
                }
                is->audio_buf = is->audio_buf2;
                resampled_data_size = len2 * is->audio_tgt_channels
                * av_get_bytes_per_sample(is->audio_tgt_fmt);
            }else {
                resampled_data_size = decoded_data_size;
                is->audio_buf = is->audio_frame->data[0];
            }
            
            pts = is->audio_clock;
            *pts_ptr = pts;
            n = 2 * is->audio_st->codec->channels;
            is->audio_clock += (double) resampled_data_size
            / (double) (n * is->audio_st->codec->sample_rate);
            
            // We have data, return it and come back for more later
            return resampled_data_size;
        }
        if (pkt->data)
            av_free_packet(pkt);
        memset(pkt, 0, sizeof(*pkt));
        if (is->quit)
            return -1;
        if (packet_queue_get(&is->audioq, pkt, 1) < 0)
            return -1;
        
        is->audio_pkt_data = pkt->data;
        is->audio_pkt_size = pkt->size;
        
        /* if update, update the audio clock w/pts */
        if (pkt->pts != AV_NOPTS_VALUE) {
            is->audio_clock = av_q2d(is->audio_st->time_base) * pkt->pts;
        }
        
    }
    
    return 0;
}

#pragma mark - get clock
-(double)get_audio_clock:(VideoState *)is{
    double pts;
    int hw_buf_size, bytes_per_sec, n;
    pts = is->audio_clock; /* maintained in the audio thread */
    hw_buf_size = is->audio_buf_size - is->audio_buf_index;
    bytes_per_sec = 0;
    n = is->audio_st->codec->channels * 2;
    if (is->audio_st) {
        bytes_per_sec = is->audio_st->codec->sample_rate * n;
    }
    if (bytes_per_sec) {
        pts -= (double) hw_buf_size / bytes_per_sec;
    }
    printf("%f\n",pts);
    return pts;
}

-(double)get_video_clock:(VideoState *)is{
    double delta;
    
    delta = (av_gettime() - is->video_current_pts_time) / 1000000.0;
    return is->video_current_pts + delta;
}

-(double)get_external_clock:(VideoState *)is{
    return av_gettime() / 1000000.0;
}

-(double)get_master_clock:(VideoState *)is{
    if (is->av_sync_type == AV_SYNC_VIDEO_MASTER) {
        return [self get_video_clock:is];
    } else if (is->av_sync_type == AV_SYNC_AUDIO_MASTER) {
        return [self get_audio_clock:is];;
    } else {
        return [self get_external_clock:is];;
    }
}

-(int)synchronize_audio:(VideoState *)is samples:(short *)samples samples_size:(int)samples_size pts:(double)pts {
    
    int n;
    double ref_clock;
    
    n = 2 * is->audio_st->codec->channels;
    if (is->av_sync_type != AV_SYNC_AUDIO_MASTER) {
        double diff, avg_diff;
        int wanted_size, min_size, max_size;
        ref_clock = [self get_master_clock:is];
        diff = [self get_audio_clock:is] - ref_clock;
        
        if (diff<AV_NOSYNC_THRESHOLD) {
            is->audio_diff_cum = diff + is->audio_diff_avg_coef * is->audio_diff_cum;
            if (is->audio_diff_avg_count < AUDIO_DIFF_AVG_NB) {
                is->audio_diff_avg_count++;
            }else{
                avg_diff = is->audio_diff_cum * (1.0 - is->audio_diff_avg_coef);
                if (fabs(avg_diff) >= is->audio_diff_threshold) {
                    wanted_size = samples_size + ((int) (diff * is->audio_st->codec->sample_rate)
                       * n);
                    min_size = samples_size * ((100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    max_size = samples_size * ((100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    
                    if (wanted_size < min_size) {
                        wanted_size = min_size;
                    } else if (wanted_size > max_size) {
                        wanted_size = max_size;
                    }
                    if (wanted_size < samples_size) {
                        samples_size = wanted_size;
                    }else if (wanted_size > samples_size) {
                        uint8_t *samples_end, *q;
                        int nb;
                        
                        /* add samples by copying final sample*/
                        nb = (samples_size - wanted_size);
                        samples_end = (uint8_t *) samples + samples_size - n;
                        q = samples_end + n;
                        while (nb > 0) {
                            memcpy(q, samples_end, n);
                            q += n;
                            nb -= n;
                        }
                        samples_size = wanted_size;
                    }
                    
                }
            }
            
        }else {
            /* difference is TOO big; reset diff stuff */
            is->audio_diff_avg_count = 0;
            is->audio_diff_cum = 0;
        }
        
    }
    
    
    return samples_size;
}

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


#pragma mark - setters and getters

-(OpenGLView20 *)glView{
    if (_glView == nil) {
        _glView = [[OpenGLView20 alloc] initWithFrame:self.bounds];
    }
    return _glView;
}

@end
