//
//  KBFFmpegHeader5_0.h
//  KBPlayer
//
//  Created by chengshenggen on 5/24/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#ifndef KBFFmpegHeader5_0_h
#define KBFFmpegHeader5_0_h

#import "avformat.h"
#import "avcodec.h"
#import "log.h"
#import "swscale.h"
#import <pthread.h>
#import "swresample.h"
#import "time.h"
#import <AVFoundation/AVFoundation.h>
#import <sys/time.h>

static int quit = 0;

#define MAX_AUDIOQ_SIZE (5 * 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024)

#define NUM_BUFFERS 3
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio

#define VIDEO_PICTURE_QUEUE_SIZE 1
#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 10.0

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

static int packet_queue_put_nullpacket(PacketQueue *q)
{
    AVPacket pkt1, *pkt = &pkt1;
    av_init_packet(pkt);
    pkt->data = NULL;
    pkt->size = 0;
    return packet_queue_put(q, pkt);
}

static void packet_queue_flush(PacketQueue *q){
    AVPacketList *pkt, *pkt1;
    pthread_mutex_lock(&q->mutex);
    for (pkt = q->first_pkt; pkt; pkt = pkt1) {
        pkt1 = pkt->next;
        av_free_packet(&pkt->pkt);
        av_freep(&pkt);
    }
    q->last_pkt = NULL;
    q->first_pkt = NULL;
    q->nb_packets = 0;
    q->size = 0;
    pthread_mutex_unlock(&q->mutex);
    
}

static void packet_queue_destroy(PacketQueue *q)
{
    packet_queue_flush(q);
    pthread_mutex_destroy(&q->mutex);
    pthread_cond_destroy(&q->cond);
    
}

static int packet_queue_get(PacketQueue *q,AVPacket *pkt,int block){
    AVPacketList *pkt1;
    int ret;
    pthread_mutex_lock(&q->mutex);
    for (; ; ) {
        if (quit) {
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
            
            outtime.tv_sec = now.tv_sec + 5;
            outtime.tv_nsec = now.tv_usec * 1000;
//            pthread_cond_timedwait(&q->cond, &q->mutex, &outtime);
                                    pthread_cond_wait(&q->cond, &q->mutex);
        }
    }
    pthread_mutex_unlock(&q->mutex);
    return ret;
}


typedef struct VideoState {
    char filename[1024];
    AVFormatContext *ic;
    
    double video_clock;
    
    
    int video_stream;
    AVStream *video_st;
    struct SwsContext *sws_ctx;
    PacketQueue videoq;
    
    int pictq_size, pictq_rindex, pictq_windex;
    
    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
    
    pthread_mutex_t pictq_mutex;
    pthread_cond_t pictq_cond;
    
    /** 音频流 */
    int audio_stream;
    AVStream *audio_st;
    AVPacket audio_pkt;
    AVFrame *audio_frame;
    struct SwrContext *swr_ctx;
    PacketQueue audioq;
    UInt32 audio_buf_size;
    double audio_clock;
    unsigned int audio_buffer_index;
    unsigned int audio_buffer_size;
    int audio_pkt_size;
    uint8_t *audio_pkt_data;
    enum AVSampleFormat audio_tgt_fmt;
    int audio_tgt_channels;
    int64_t audio_tgt_channel_layout;
    int audio_tgt_freq;
    
    uint8_t *audio_buf;
    DECLARE_ALIGNED(16,uint8_t,audio_buf2) [AVCODEC_MAX_AUDIO_FRAME_SIZE * 4];
    AudioQueueRef playQueue;
    
    AudioStreamBasicDescription format;
    AudioQueueBufferRef playBufs[NUM_BUFFERS];
    UInt32 currentPaketsNum;
    
    AudioStreamPacketDescription *packetDesc;
    
    
}VideoState;

#endif /* KBFFmpegHeader5_0_h */
