//
//  KBPlayerHeader12_0.h
//  KBPlayer
//
//  Created by chengshenggen on 8/10/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#ifndef KBPlayerHeader12_0_h
#define KBPlayerHeader12_0_h

#import "avformat.h"
#import "avcodec.h"
#import "log.h"
#import "swscale.h"
#import <pthread.h>
#import "swresample.h"
#import "time.h"
#import <AVFoundation/AVFoundation.h>
#import <sys/time.h>

#define SDL_AUDIO_BUFFER_SIZE 1024

#define MAX_AUDIOQ_SIZE (5 * 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024)

#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 10.0

#define FF_ALLOC_EVENT   (SDL_USEREVENT)
#define FF_REFRESH_EVENT (SDL_USEREVENT + 1)
#define FF_QUIT_EVENT (SDL_USEREVENT + 2)

#define VIDEO_PICTURE_QUEUE_SIZE 1
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio

typedef struct PacketQueue{
    AVPacketList *first_pkt,*last_pkt;
    int nb_packets;
    int size;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
}PacketQueue;

typedef struct VideoPicture {
    AVFrame* rawdata;
    int width, height; /*source height & width*/
    int allocated;
    double pts;
} VideoPicture;

typedef struct VideoState {
    
    AVFormatContext *pFormatCtx;
    int videoStream, audioStream;
    
    double audio_clock;
    AVStream *audio_st;
    PacketQueue audioq;
    uint8_t *audio_buf;
    unsigned int audio_buf_size;
    unsigned int audio_buf_index;
    AVPacket audio_pkt;
    uint8_t *audio_pkt_data;
    int audio_pkt_size;
    AVFrame *audio_frame;
    AVStream *video_st;
    PacketQueue videoq;
    int audio_hw_buf_size;
    int audio_format_buffer_size;
    double frame_timer;
    double frame_last_pts;
    double frame_last_delay;
    double video_clock; ///<pts of last decoded frame / predicted pts of next decoded frame
    
    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
    int pictq_size, pictq_rindex, pictq_windex;
    pthread_mutex_t pictq_mutex;
    pthread_cond_t pictq_cond;
    
    AVIOContext *io_ctx;
    struct SwsContext *sws_ctx;
    
    struct SwrContext *swr_ctx;

    
    AudioQueueRef playQueue;
    
    AudioStreamBasicDescription format;
    AudioQueueBufferRef playBufs[3];
    UInt32 currentPaketsNum;
    
    AudioStreamPacketDescription *packetDesc;
    
    int audio_tgt_channels;
    int64_t audio_tgt_channel_layout;
    int audio_tgt_freq;
    
    char filename[1024];
    int quit;
    
}VideoState;

//VideoState *global_video_state_12_0;

static void packet_queue_init(PacketQueue *q){
    memset(q, 0, sizeof(PacketQueue));
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->cond, NULL);
}

static int packet_queue_put(PacketQueue *q,AVPacket *pkt){
    
    AVPacketList *pkt1;
    if (av_dup_packet(pkt)<0) {
        return -1;
    }
    pkt1 = av_malloc(sizeof(AVPacketList));
    if (!pkt1) {
        return -1;
    }
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    pthread_mutex_lock(&q->mutex);
    if (!q->last_pkt) {
        q->first_pkt = pkt1;
    }else{
        q->last_pkt->next = pkt1;
    }
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    pthread_cond_signal(&q->cond);
    pthread_mutex_unlock(&q->mutex);
    return 0;
}


static int packet_queue_get(PacketQueue *q,AVPacket *pkt,int block){
    AVPacketList *pkt1;
    int ret;
    pthread_mutex_lock(&q->mutex);
    for (; ; ) {
//        if (global_video_state_12_0->quit) {
//            ret = -1;
//            break;
//        }
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (!q->first_pkt) {
                q->last_pkt = NULL;
            }
            q->nb_packets--;
            q->size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        }else if (!block){
            ret = 0;
            break;
        }else{
            ret = -1;
            struct timeval now;
            struct timespec outtime;
            gettimeofday(&now, NULL);
            
            outtime.tv_sec = now.tv_sec + 10;
            outtime.tv_nsec = now.tv_usec * 1000;
            pthread_cond_timedwait(&q->cond, &q->mutex, &outtime);
            //            pthread_cond_wait(&q->cond, &q->mutex);
            break;
        }
    }
    pthread_mutex_unlock(&q->mutex);
    return ret;
}


#endif /* KBPlayerHeader12_0_h */
