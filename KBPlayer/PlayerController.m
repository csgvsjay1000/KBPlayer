//
//  PlayerController.m
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "PlayerController.h"
#import "FFmpegHeader.h"
#import "VRPlayControlView.h"
#import "KBPlayerHeader.h"
#import "ViewController.h"

typedef enum : NSUInteger {
    KBPlayerStateDefault = 10,  //默认读取正常
    KBPlayerStateReadError = 20, //读取数据错误，不在继续读取
    KBPlayerStateReadingNetWeak = 30,  //正在读取数据，网络状态不好
} KBPlayerState;

@interface PlayerController (){
    VideoState *_is;
    NSTimer *_timer;
    
    AVFrame *_pFrameYUV;
}

@property(nonatomic,strong)VRPlayControlView *controlView;

@property(nonatomic,assign)KBPlayerState playerState;

@property(nonatomic,strong)NSThread *parse_thread;
@property(nonatomic,strong)NSThread *audioThread;

@end

@implementation PlayerController

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
    _parse_thread = [[NSThread alloc] initWithTarget:self selector:@selector(decode_thread) object:nil];
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
    
    
    NSLog(@"%@ dealloc",[self class]);
}

#pragma mark - parse video
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
    int i;
    for (i = 0; i < _is->ic->nb_streams; i++) {
        if (_is->ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            _is->audio_st = _is->ic->streams[i];
            _is->audioStream = i;
            break;
        }
    }
    if (_is->audioStream>=0) {
        [self audio_stream_component_open:_is->audioStream];
    }
    
    AVPacket pkt1, *packet = &pkt1;
    packet=(AVPacket *)av_malloc(sizeof(AVPacket));
    int j=0;
    for (; ; ) {
        if (quit) {
            break;
        }
        if (_is->audioq.size>MAX_AUDIOQ_SIZE || _is->videoq.size>MAX_VIDEOQ_SIZE) {
            usleep(10*1000);
            NSLog(@"usleep : %d audioq.size:%d  ,videoq.size: %d",j++,_is->audioq.size,_is->videoq.size);
            continue;
        }
        if (!_is->ic) {
            break;
        }
        if (av_read_frame(_is->ic, packet)>=0) {
            if (packet->stream_index == _is->audioStream) {
                packet_queue_put(&_is->audioq, packet);
            }else if (packet->stream_index == _is->videoStream) {
                packet_queue_put(&_is->videoq, packet);
            } else {
                av_free_packet(packet);
            }
        }else{
            if (_is->ic->pb->error == 0) {
                usleep(100*1000);
                NSLog(@"waite : %d audioq.size:%d  ,videoq.size: %d",j++,_is->audioq.size,_is->videoq.size);
                continue;
            }else{
                NSLog(@"av_read_frame error");
                
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"av_read_frame error" delegate:nil cancelButtonTitle:@"哦" otherButtonTitles:nil, nil];
                [alert show];
                _playerState = KBPlayerStateReadError;
                break;
            }
        }
        
        
    }
    if (_is && _is->playQueue) {
        for (int i=0; i<NUM_BUFFERS; i++) {
            AudioQueueFreeBuffer(_is->playQueue, _is->playBufs[i]);
        }
        AudioQueueStop(_is->playQueue, true);
        AudioQueueDispose(_is->playQueue, true);
//        _is->playQueue = nil;
        
        
        NSLog(@"avformat_close_input");
        
        
    }
    avformat_close_input(&_is->ic);

}

static void AQueueOutputCallback(
                                 void * __nullable       inUserData,
                                 AudioQueueRef           inAQ,
                                 AudioQueueBufferRef     inBuffer){
    PlayerController *vc = (__bridge PlayerController *)inUserData;
    [vc readPacketsIntoBuffer:inBuffer];
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
    [_audioThread start];

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
                NSLog(@"audio_data_size :%d",audio_data_size);
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
//    if (state != noErr) {
//        printf("AudioQueueEnqueueBuffer error\n");
//    }else{
//        NSLog(@"AudioQueueEnqueueBuffer success mAudioDataByteSize :%d ",buffer->mAudioDataByteSize);
//    
//    }
    
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
                uint8_t *out[] = { _is->audio_buf2 };
                len2 = swr_convert(_is->swr_ctx, out, sizeof(_is->audio_buf2) / _is->audio_tgt_channels/av_get_bytes_per_sample(_is->audio_tgt_fmt), in, _is->audio_frame->nb_samples);
                if (len2 < 0) {
                    fprintf(stderr, "swr_convert() failed\n");
                    break;
                }
                if (len2 == sizeof(_is->audio_buf2) / _is->audio_tgt_channels
                    / av_get_bytes_per_sample(_is->audio_tgt_fmt)) {
                    fprintf(stderr,
                            "warning: audio buffer is probably too small\n");
                    swr_init(_is->swr_ctx);
                }
                _is->audio_buf = _is->audio_buf2;
                resampled_data_size = len2 * _is->audio_tgt_channels
                * av_get_bytes_per_sample(_is->audio_tgt_fmt);
            }else {
                resampled_data_size = decoded_data_size;
                _is->audio_buf = _is->audio_frame->data[0];
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

#pragma mark - button actions
-(void)backButtonActions{
    if (_parse_thread) {
        [_parse_thread cancel];
    }
    
    quit = 1;
    
    [self dismissViewControllerAnimated:NO completion:nil];
    // do not lock AudioQueueStop, or may be run into deadlock
    
}

#pragma mark - private methods
- (void)registerApplicationObservers{
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    
}

#pragma mark - application observers
-(void)applicationWillEnterForeground{
    
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
