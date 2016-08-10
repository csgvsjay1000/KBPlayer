//
//  KBPlayer12_0.m
//  KBPlayer
//
//  Created by chengshenggen on 8/10/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayer12_0.h"
#import "KBPlayerHeader12_0.h"

@interface KBPlayer12_0 ()

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
    strlcpy(_is->filename, "rtmp://live.hkstv.hk.lxdns.com/live/hks", sizeof(_is->filename));
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
            packet_queue_put(&_is->videoq, packet);
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
    
    return 0;
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
