//
//  KBPlayer12_0.m
//  KBPlayer
//
//  Created by chengshenggen on 8/10/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayer12_0.h"
#import "KBPlayerHeader12_0.h"

@interface KBPlayer12_0 (){
    struct SwrContext *au_convert_ctx;

}

@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSThread *decode_thread;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSThread *audioThread;

@end

@implementation KBPlayer12_0

-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        av_register_all();
        avformat_network_init();
//        [self addSubview:self.glView];
    }
    return self;
}

#pragma mark - public methods
-(void)preparePlayWithUrlStr:(NSString *)urlStr{
    _is = av_malloc(sizeof(VideoState));
    if (!_is) {
        return;
    }
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cuc_ieschool" ofType:@"flv"];

    
    strlcpy(_is->filename, [path UTF8String], sizeof(_is->filename));
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
    
    _decode_thread = [[NSThread alloc] initWithTarget:self selector:@selector(read_thread) object:nil];
    _decode_thread.name = @"com.3glasses.vrshow.read";
    [_decode_thread start];
}
//
int decode_interrupt_cb_12_0(void *opaque) {
    VideoState *is = opaque;
    return (is && is->quit);
}

-(void)read_thread{
    AVFormatContext *pFormatCtx = NULL;
    AVPacket pkt1, *packet = &pkt1;
    
    int video_index = -1;
    int audio_index = -1;
    int i;
    
    _is->videoStream = -1;
    _is->audioStream = -1;
    
    AVIOInterruptCB interupt_cb;
    
    // will interrupt blocking functions if we quit!
    interupt_cb.callback = decode_interrupt_cb_12_0;
    interupt_cb.opaque = _is;
    if (avio_open2(&_is->io_ctx, _is->filename, 0, &interupt_cb, NULL)) {
        fprintf(stderr, "Cannot open I/O for %s\n", _is->filename);
        return ;
    }
    
    // Open video file
    if (avformat_open_input(&pFormatCtx, _is->filename, NULL, NULL) != 0)
        return; // Couldn't open file
    
    _is->pFormatCtx = pFormatCtx;
    
    // Retrieve stream information
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0)
        return; // Couldn't find stream information
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, _is->filename, 0);
    
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
    
    _is->videoStream = video_index;
    _is->audioStream = audio_index;
    
    if (audio_index>=0) {
        [self stream_component_open:audio_index];
    }
    if (video_index>=0) {
        [self stream_component_open:video_index];
    }
    
    for (; ; ) {
        if (_is->quit) {
            break;
        }
        if (_is->videoq.size>MAX_VIDEOQ_SIZE || _is->audioq.size>MAX_AUDIOQ_SIZE ) {
            printf("audioq.size %d, videoq.size %d\n",_is->audioq.size,_is->videoq.size);
            usleep(10*1000);
            continue;
        }
        if (av_read_frame(_is->pFormatCtx, packet) < 0) {
            if (_is->pFormatCtx->pb->error == 0) {
                usleep(100*1000); /* no error; wait for user input */
                continue;
            } else {
                break;
            }
        }
        // Is this a packet from the video stream?
        if (packet->stream_index == _is->videoStream) {
//            packet_queue_put(&_is->videoq, packet);
        } else if (packet->stream_index == _is->audioStream) {
            packet_queue_put(&_is->audioq, packet);
        } else {
            av_free_packet(packet);
        }
        
    }
    /* all done - wait for it */
    while (!_is->quit) {
        usleep(100*1000); /* no error; wait for user input */
    }
    
}

-(int)stream_component_open:(int)stream_index{
    AVFormatContext *pFormatCtx = _is->pFormatCtx;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    codecCtx = pFormatCtx->streams[stream_index]->codec;
    
    if (codecCtx->codec_type == AVMEDIA_TYPE_AUDIO) {
        
    }
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            _is->audioStream = stream_index;
            _is->audio_st = pFormatCtx->streams[stream_index];
            _is->audio_buf_size = 0;
            _is->audio_buf_index = 0;
            memset(&_is->audio_pkt, 0, sizeof(_is->audio_pkt));
            packet_queue_init(&_is->audioq);
            _is->audio_frame = av_frame_alloc();
            
            //---------------音频------------------//
            uint64_t out_channel_layout=AV_CH_LAYOUT_STEREO;
            enum AVSampleFormat out_sample_fmt=AV_SAMPLE_FMT_S16;
            int out_sample_rate=codecCtx->sample_rate;
            _is->audio_tgt_channels = av_get_channel_layout_nb_channels(out_channel_layout);
            int in_channel_layout = av_get_default_channel_layout(codecCtx->channels);
            
            au_convert_ctx=swr_alloc_set_opts(au_convert_ctx,out_channel_layout, out_sample_fmt, out_sample_rate,
                                              in_channel_layout,codecCtx->sample_fmt , codecCtx->sample_rate,0, NULL);
            swr_init(au_convert_ctx);
            _is->audio_buf = (uint8_t *)av_malloc(AVCODEC_MAX_AUDIO_FRAME_SIZE*2);

            
            AudioStreamBasicDescription format;
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
            _is->audio_format_buffer_size = (format.mBitsPerChannel/8)*format.mSampleRate*0.6;
            _is->packetDesc = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*_is->audio_format_buffer_size);
            AudioQueueStart(_is->playQueue, NULL);
            _audioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioThread) object:nil];
            _audioThread.name = @"com.3glasses.vrshow.audio";
            [_audioThread start];
            _is->audio_hw_buf_size = 0;
            break;
        case AVMEDIA_TYPE_VIDEO:
            _is->videoStream = stream_index;
            _is->video_st = pFormatCtx->streams[stream_index];
            
            _is->sws_ctx = sws_getContext(_is->video_st->codec->width,
                                         _is->video_st->codec->height, _is->video_st->codec->pix_fmt,
                                         _is->video_st->codec->width, _is->video_st->codec->height,
                                         AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
            _is->frame_timer = (double) av_gettime() / 1000000.0;
            _is->frame_last_delay = 40e-3;
            packet_queue_init(&_is->videoq);
            _videoThread = [[NSThread alloc] initWithTarget:self selector:@selector(playVideoThread) object:nil];
            _videoThread.name = @"com.3glasses.vrshow.video";
            [_videoThread start];
            break;
        default:
            break;
    }
    
    return 0;
}

static void AQueueOutputCallback(
                                 void * __nullable       inUserData,
                                 AudioQueueRef           inAQ,
                                 AudioQueueBufferRef     inBuffer){
    KBPlayer12_0 *vc = (__bridge KBPlayer12_0 *)inUserData;
    if (vc) {
        [vc readPacketsIntoBuffer:inBuffer];
    }
}

-(int) audio_decode_frame:(double *)pts_ptr {
    int len1, data_size = 0, n,decoded_data_size;
    AVPacket *pkt = &_is->audio_pkt;
    double pts;
    
    for (;;) {
        while (_is->audio_pkt_size > 0) {

            int got_frame = 0;
            len1 = avcodec_decode_audio4(_is->audio_st->codec, _is->audio_frame,
                                         &got_frame, pkt);
            if (len1 < 0) {
                /* if error, skip frame */
                _is->audio_pkt_size = 0;
                break;
            }
            
            if (got_frame) {
//                data_size = _is->audio_frame->linesize[0];
                
                data_size = swr_convert(au_convert_ctx,&_is->audio_buf, AVCODEC_MAX_AUDIO_FRAME_SIZE,(const uint8_t **)_is->audio_frame->data , _is->audio_frame->nb_samples);

                data_size = data_size * 2 * 2;
                
            }
            _is->audio_pkt_data += len1;
            _is->audio_pkt_size -= len1;
            if (data_size <= 0) {
                /* No data yet, get more frames */
                continue;
            }
            
            pts = _is->audio_clock;
            *pts_ptr = pts;
            n = 2 * _is->audio_st->codec->channels;
            _is->audio_clock += (double) data_size
            / (double) (n * _is->audio_st->codec->sample_rate);
            
            /* We have data, return it and come back for more later */
            return data_size;
        }
        if (pkt->data)
            av_free_packet(pkt);
        
        if (_is->quit) {
            return -1;
        }
        if (packet_queue_get(&_is->audioq, pkt, 1) < 0) {
            return -1;
        }
        _is->audio_pkt_data = pkt->data;
        _is->audio_pkt_size = pkt->size;
        
        /* if update, update the audio clock w/pts */
        if (pkt->pts != AV_NOPTS_VALUE) {
            _is->audio_clock = av_q2d(_is->audio_st->time_base) * pkt->pts;
        }
    }
    
    return 0;
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
        if (_is->audio_buf_index>=_is->audio_buf_size) {
            audio_data_size = [self audio_decode_frame:&pts];
            if (audio_data_size < 0) {
                /* silence */
                //                NSLog(@"audio_data_size < 0");
                _is->audio_buf_size = 4096;
                //                /* 清零，静音 */
                memset(_is->audio_buf, 0, _is->audio_buf_size);
            }else{
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
    state = AudioQueueEnqueueBuffer(_is->playQueue, buffer, _is->audio_format_buffer_size, _is->packetDesc);
    if (state != noErr) {
        printf("AudioQueueEnqueueBuffer error\n");
    }else{
        NSLog(@"AudioQueueEnqueueBuffer success mAudioDataByteSize :%d ",buffer->mAudioDataByteSize);
        
    }
}

-(void)playAudioThread{
    for (int i=0; i<3; i++) {
        AudioQueueAllocateBuffer(_is->playQueue, _is->audio_format_buffer_size, &_is->playBufs[i]);
        [self readPacketsIntoBuffer:_is->playBufs[i]];
    }
}

-(void)playVideoThread{
    
}

-(double)get_audio_clock{
    double pts;
    int hw_buf_size, bytes_per_sec, n;
    pts = _is->audio_clock; /* maintained in the audio thread */
    hw_buf_size = _is->audio_buf_size - _is->audio_buf_index;
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

@end
