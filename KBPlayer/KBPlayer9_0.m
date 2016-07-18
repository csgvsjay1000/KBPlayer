//
//  KBPlayer9_0.m
//  KBPlayer
//
//  Created by chengshenggen on 6/15/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "KBPlayer9_0.h"
#import "KBFFmpegHeader5_0.h"
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"

@interface KBPlayer9_0 (){
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    AAPLEAGLLayer *_glLayer;

}

@property(nonatomic,copy)NSString *urlStr;
@property(nonatomic,assign)VideoState *is;
@property(nonatomic,strong)NSThread *read_tid;
@property(nonatomic,strong)NSThread *videoThread;
@property(nonatomic,strong)NSTimer *timer;

@end

@implementation KBPlayer9_0

#pragma mark - life cycle
-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        av_register_all();
        avformat_network_init();
        _glLayer = [[AAPLEAGLLayer alloc] initWithFrame:self.bounds];
        [self.layer addSublayer:_glLayer];
        
    }
    return self;
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
    [self schedule_refresh:40];
    pthread_mutex_init(&_is->pictq_mutex, NULL);
    pthread_cond_init(&_is->pictq_cond, NULL);
//    [self initH264Decoder];
    _read_tid = [[NSThread alloc] initWithTarget:self selector:@selector(read_thread) object:nil];
    _read_tid.name = @"com.3glasses.vrshow.read";
    
    
    [_read_tid start];
    
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
    if (_is->video_stream >= 0) {
        [self video_stream_component_open:_is->video_stream];
    }
    
    AVPacket pkt1, *packet = &pkt1;
    packet = NULL;
    packet=(AVPacket *)av_malloc(sizeof(AVPacket));
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
        }
    }
fail:
    NSLog(@"fail");
    
    
}

-(void)video_stream_component_open:(int)stream_index{

    _is->video_current_pts_time = av_gettime();
    packet_queue_init(&_is->videoq);
//    _videoThread = [[NSThread alloc] initWithTarget:self selector:@selector(playVideoThread) object:nil];
//    _videoThread.name = @"com.3glasses.vrshow.video";
//    [_videoThread start];
}

-(void)playVideoThread{
    AVPacket pkt1, *packet = &pkt1;
    double pts;

    for (; ; ) {
        if (quit) {
            break;
        }
//        if ([self playFinshed]) {
//            break;
//        }
        if (packet_queue_get(&_is->videoq, packet, 1) < 0) {
            // means we quit getting packets
            continue;
        }
        if (packet->dts != AV_NOPTS_VALUE) {
            pts = packet->dts;
        } else {
            pts = 0;
        }
        
        
        av_free_packet(packet);

    }
    
    
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
    AVPacket pkt1, *packet = &pkt1;
    double pts;
    if (packet_queue_get(&_is->videoq, packet, 1) < 0) {
        // means we quit getting packets
        return;
    }
    if (packet->dts != AV_NOPTS_VALUE) {
        pts = packet->dts;
    } else {
        pts = 0;
    }
    
    uint32_t nalSize = (uint32_t)(packet->size - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    uint8_t *buffer = packet->data;
    buffer[0] = *(pNalSize + 3);
    buffer[1] = *(pNalSize + 2);
    buffer[2] = *(pNalSize + 1);
    buffer[3] = *(pNalSize);
    
    
    CVPixelBufferRef pixelBuffer = NULL;
    int nalType = buffer[4] & 0x1F;
    switch (nalType) {
        case 0x05:
            NSLog(@"Nal type is IDR frame");
            if([self initH264Decoder]) {
                pixelBuffer = [self decode:packet];
            }
            break;
        case 0x07:
            NSLog(@"Nal type is SPS");
            _spsSize = packet->size - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, buffer + 4, _spsSize);
            break;
        case 0x08:
            NSLog(@"Nal type is PPS");
            _ppsSize = packet->size - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, buffer + 4, _ppsSize);
            break;
            
        default:
            NSLog(@"Nal type is B/P frame");
            pixelBuffer = [self decode:packet];
            break;
    }

//    CVPixelBufferRef pix = [self decode:packet];
    if (pixelBuffer) {
        _glLayer.pixelBuffer = pixelBuffer;

    }

    av_free_packet(packet);
    
}

-(BOOL)initH264Decoder {
    if(_deocderSession) {
        return YES;
    }
    
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        CFDictionaryRef attrs = NULL;
        const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
        //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
        //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
        attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = NULL;
        
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL, attrs,
                                              &callBackRecord,
                                              &_deocderSession);
        CFRelease(attrs);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
    }
    
    return YES;
}

static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

-(CVPixelBufferRef)decode:(AVPacket *)vp {
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                          (void*)vp->data, vp->size,
                                                          kCFAllocatorNull,
                                                          NULL, 0, vp->size,
                                                          0, &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {vp->size};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
            }
            
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}



@end
