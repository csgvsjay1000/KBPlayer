//
//  KBPlayer.m
//  KBPlayer
//
//  Created by chengshenggen on 5/26/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayer.h"
#import "KBFFmpegHeader6_0.h"
#import "KBPlayerEnumHeaders.h"

@interface KBPlayer ()

@property(nonatomic,copy)NSString *urlStr;
@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSThread *read_tid;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSThread *audioThread;

@property(nonatomic,assign)KBPlayerState playerState;


@end

@implementation KBPlayer

#pragma mark - life cycle
-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        av_register_all();
        avformat_network_init();
    }
    return self;
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

#pragma mark - public methods
-(void)preparePlayWithUrlStr:(NSString *)urlStr{
    _urlStr = urlStr;
    quit = 0;
    _is = av_malloc(sizeof(VideoState));
    if (!_is) {
        return;
    }
    strlcpy(_is->filename, [_urlStr UTF8String], sizeof(_is->filename));

    _read_tid = [[NSThread alloc] initWithTarget:self selector:@selector(read_thread) object:nil];
    _read_tid.name = @"com.3glasses.vrshow.read";
    
    
    [_read_tid start];
    
}

-(void)play{
    
}

-(void)pause{
    
}

-(void)stop{
    quit = 1;
   if (_read_tid) {
      [_read_tid cancel];
      _read_tid = nil;
   }
//   avformat_network_deinit();
}

-(void)destoryPlayer{
   
   _playerState = KBPlayerStateUserBack;
   [self stop];
}


-(void)reloadPlayer{
   [self stop];
//   [CacheView show:self.glView];
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//      [self schedule_refresh:40];
      [self preparePlayWithUrlStr:self.urlStr];
   });
   
}

#pragma mark - read thread
static int decode_interrupt_cb(void *ctx)
{
    return quit;
}

-(void)read_thread{
    
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
        if (_is->ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            _is->audio_st = _is->ic->streams[i];
            _is->audio_stream = i;
            break;
        }
    }
    if (_is->audio_stream >= 0) {
        [self audio_stream_component_open:_is->audio_stream];
    }
    AVPacket pkt1, *packet = &pkt1;
    packet = NULL;
    packet=(AVPacket *)av_malloc(sizeof(AVPacket));
    
    for (; ; ) {
        
        if (quit) {
            break;
        }
        //        if (_playerState == KBPlayerStatePreparePlay) {
        //            usleep(10*1000);
        //            continue;
        //        }
        if ( _is->audioq.size>MAX_AUDIOQ_SIZE ) {
            printf("audioq.size %d\n",_is->audioq.size);
            
            usleep(10*1000);
            continue;
        }
        if (av_read_frame(_is->ic, packet)>=0) {
            if (packet->stream_index == _is->audio_stream) {
                packet_queue_put(&_is->audioq, packet);
            } else {
                av_free_packet(packet);
            }
        }else{
            if (_is->ic->pb->error == 0) {
                NSLog(@"no network");
                if (_is->audio_stream>=0) {
                    packet_queue_put_nullpacket(&_is->audioq);
                }
                usleep(100*1000);
                continue;
            }else{
                NSLog(@"av_read_frame error");
                ret = 2;
//               [self stop];
                break;
            }
        }
        
        
    }
    
fail:
    NSLog(@"fail");
    if (_is->audio_stream >= 0) {
        [self audio_stream_close];
    }
    if (ic) {
        avformat_close_input(&ic);
    }
    av_free(_is);
    _is = NULL;
   if (ret == 2 && _playerState != KBPlayerStateUserBack) {
      [self reloadPlayer];
   }
}



#pragma mark - stream open
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
    uint64_t out_channel_layout=AV_CH_LAYOUT_STEREO;
    //nb_samples: AAC-1024 MP3-1152
    int out_nb_samples=codecCtx->frame_size;
    enum AVSampleFormat out_sample_fmt=AV_SAMPLE_FMT_S16;
    
    int out_sample_rate=codecCtx->sample_rate;
    int out_channels=av_get_channel_layout_nb_channels(out_channel_layout);
    
    _is->out_buffer_size=av_samples_get_buffer_size(NULL,out_channels ,out_nb_samples,out_sample_fmt, 1);
    _is->out_audio_buffer=(uint8_t *)av_malloc(AVCODEC_MAX_AUDIO_FRAME_SIZE*2);
    
    int64_t in_channel_layout=av_get_default_channel_layout(codecCtx->channels);
    _is->swr_ctx = swr_alloc();
    _is->swr_ctx=swr_alloc_set_opts(_is->swr_ctx,out_channel_layout, out_sample_fmt, out_sample_rate,
                                      in_channel_layout,codecCtx->sample_fmt , codecCtx->sample_rate,0, NULL);
    swr_init(_is->swr_ctx);
    
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
   _is->audio_pkt = *(AVPacket *)av_malloc(sizeof(AVPacket));
//   memset(&_is->audio_pkt, 0, sizeof(_is->audio_pkt));
   _is->audio_buffer_index = 0;
   _is->audio_buffer_size = 0;

    _is->audio_buf_size = (format.mBitsPerChannel/8)*format.mSampleRate*0.6;
    _is->packetDesc = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*_is->audio_buf_size);
   packet_queue_init(&_is->audioq);
    AudioQueueStart(_is->playQueue, NULL);
    _audioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioThread) object:nil];
    _audioThread.name = @"com.3glasses.vrshow.audio";
    [_audioThread start];
    
}

#pragma mark - audio thread
-(void)playAudioThread{
    for (int i=0; i<NUM_BUFFERS; i++) {
        AudioQueueAllocateBuffer(_is->playQueue, _is->audio_buf_size, &_is->playBufs[i]);
        [self readPacketsIntoBuffer:_is->playBufs[i]];
    }
}

static void AQueueOutputCallback(
                                 void * __nullable       inUserData,
                                 AudioQueueRef           inAQ,
                                 AudioQueueBufferRef     inBuffer){
    KBPlayer *vc = (__bridge KBPlayer *)inUserData;
    if (vc) {
        [vc readPacketsIntoBuffer:inBuffer];
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
                memset(_is->out_audio_buffer, 0, _is->audio_buffer_size);
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
        memcpy(stream, (uint8_t *) _is->out_audio_buffer + _is->audio_buffer_index, len1);
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
    int resampled_data_size;
    int len1, len2, decoded_data_size;
    int got_frame = 0,n;
    AVPacket *pkt = &_is->audio_pkt;
    double pts;
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
            swr_convert(_is->swr_ctx,&_is->out_audio_buffer, AVCODEC_MAX_AUDIO_FRAME_SIZE,(const uint8_t **)_is->audio_frame->data , _is->audio_frame->nb_samples);
            pts = _is->audio_clock;
            *pts_ptr = pts;
            n = 2 * _is->audio_st->codec->channels;
            _is->audio_clock += (double) resampled_data_size
            / (double) (n * _is->audio_st->codec->sample_rate);
            
            return _is->out_buffer_size;
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

#pragma mark - stream close

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

@end
