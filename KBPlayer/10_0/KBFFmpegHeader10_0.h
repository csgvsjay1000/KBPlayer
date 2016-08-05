//
//  KBFFmpegHeader10_0.h
//  KBPlayer
//
//  Created by chengshenggen on 8/5/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#ifndef KBFFmpegHeader10_0_h
#define KBFFmpegHeader10_0_h

#import "avformat.h"
#import "avcodec.h"
#import "log.h"
#import "swscale.h"
#import <pthread.h>
#import "swresample.h"
#import "time.h"
#import <AVFoundation/AVFoundation.h>
#import <sys/time.h>
#import "OpenGLView20.h"

#define SDL_AUDIO_BUFFER_SIZE 1024

#define MAX_AUDIOQ_SIZE (5 * 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024)

#define NUM_BUFFERS 3
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio

#define VIDEO_PICTURE_QUEUE_SIZE 1
#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 10.0

#define SAMPLE_CORRECTION_PERCENT_MAX 10
#define AUDIO_DIFF_AVG_NB 20

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
    char filename[1024];
    AVFormatContext *ic;
    int videoStream, audioStream;
    AVStream *audio_st;
    AVFrame *audio_frame;
    PacketQueue audioq;
    unsigned int audio_buf_size;
    unsigned int audio_buf_index;
    AVPacket audio_pkt;
    uint8_t *audio_pkt_data;
    int audio_pkt_size;
    uint8_t *audio_buf;
//    DECLARE_ALIGNED(16,uint8_t,audio_buf) [AVCODEC_MAX_AUDIO_FRAME_SIZE * 4];
    DECLARE_ALIGNED(16,uint8_t,audio_buf2) [AVCODEC_MAX_AUDIO_FRAME_SIZE * 4];
    enum AVSampleFormat audio_src_fmt;
    enum AVSampleFormat audio_tgt_fmt;
    int audio_src_channels;
    int audio_tgt_channels;
    int64_t audio_src_channel_layout;
    int64_t audio_tgt_channel_layout;
    int audio_src_freq;
    int audio_tgt_freq;
    
    
    
    struct SwrContext *swr_ctx;
    
    AudioQueueRef playQueue;
    
    AudioStreamBasicDescription format;
    AudioQueueBufferRef playBufs[NUM_BUFFERS];
    UInt32 currentPaketsNum;
    
    AudioStreamPacketDescription *packetDesc;
    
    AVStream *video_st;
    PacketQueue videoq;
    
    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
    int pictq_size, pictq_rindex, pictq_windex;
    pthread_mutex_t pictq_mutex;
    pthread_cond_t pictq_cond;
    
    AVIOContext *io_ctx;
    struct SwsContext *sws_ctx;
    
    double audio_clock;
    
    int av_sync_type;
    double external_clock;/*external clock base*/
    int64_t external_clock_time;
    
    int audio_hw_buf_size;
    double audio_diff_cum;/*used of AV difference average computation*/
    double audio_diff_avg_coef;
    double audio_diff_threshold;
    int audio_diff_avg_count;
    double frame_timer;
    double frame_last_pts;
    double frame_last_delay;
    
    double video_current_pts;
    int64_t video_current_pts_time;
    
    double video_clock;
    
    int quit;
    
}VideoState;

enum {
    AV_SYNC_AUDIO_MASTER, AV_SYNC_VIDEO_MASTER, AV_SYNC_EXTERNAL_MASTER,
};

VideoState *global_video_state;

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
        if (global_video_state->quit) {
            ret = -1;
            break;
        }
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

uint64_t global_video_pkt_pts = AV_NOPTS_VALUE;



#endif /* KBFFmpegHeader10_0_h */
