//
//  player.c
//  KBPlayer
//
//  Created by chengshenggen on 8/4/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

extern "C"
{
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "SDL.h"
#include "SDL_thread.h"
#include "libavdevice/avdevice.h"
#include "libswresample/swresample.h"
#include "libavutil/pixfmt.h"
#include "libavutil/time.h"
};

/*
 * SDL_Lesson.c
 *
 *  Created on: Aug 12, 2014
 *      Author: clarck
 */

#define SDL_AUDIO_BUFFER_SIZE 1024

#define MAX_AUDIOQ_SIZE (5 * 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024)

#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 10.0

#define SAMPLE_CORRECTION_PERCENT_MAX 10
#define AUDIO_DIFF_AVG_NB 20

#define FF_ALLOC_EVENT   (SDL_USEREVENT)
#define FF_REFRESH_EVENT (SDL_USEREVENT + 1)
#define FF_QUIT_EVENT    (SDL_USEREVENT + 2)

#define VIDEO_PICTURE_QUEUE_SIZE 1

#define DEFAULT_AV_SYNC_TYPE AV_SYNC_VIDEO_MASTER
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
typedef struct PacketQueue {
    AVPacketList *first_pkt, *last_pkt;
    int nb_packets;
    int size;
    SDL_mutex *mutex;
    SDL_cond *cond;
} PacketQueue;

typedef struct VideoPicture {
    SDL_Window *screen;
    SDL_Renderer *renderer;
    SDL_Texture *bmp;
    
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
    
    AVStream *video_st;
    PacketQueue videoq;
    
    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
    int pictq_size, pictq_rindex, pictq_windex;
    SDL_mutex *pictq_mutex;
    SDL_cond *pictq_cond;
    
    SDL_Thread *parse_tid;
    SDL_Thread *audio_tid;
    SDL_Thread *video_tid;
    
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
    
    double video_current_pts; ///<current displayed pts (different from video_clock if frame fifos are used)
    int64_t video_current_pts_time; ///<time (av_gettime) at which we updated video_current_pts - used to have running video pts
    
    double video_clock; ///<pts of last decoded frame / predicted pts of next decoded frame
    
    
    int quit;
} VideoState;

enum {
    AV_SYNC_AUDIO_MASTER, AV_SYNC_VIDEO_MASTER, AV_SYNC_EXTERNAL_MASTER,
};

VideoState *global_video_state;

void packet_queue_init(PacketQueue *q) {
    memset(q, 0, sizeof(PacketQueue));
    q->mutex = SDL_CreateMutex();
    q->cond = SDL_CreateCond();
}

int packet_queue_put(PacketQueue *q, AVPacket *pkt) {
    AVPacketList *pkt1;
    
    pkt1 = (AVPacketList *) av_malloc(sizeof(AVPacketList));
    if (!pkt1) {
        return -1;
    }
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    SDL_LockMutex(q->mutex);
    
    if (!q->last_pkt) {
        q->first_pkt = pkt1;
    } else {
        q->last_pkt->next = pkt1;
    }
    
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    SDL_CondSignal(q->cond);
    SDL_UnlockMutex(q->mutex);
    return 0;
}

static int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block) {
    AVPacketList *pkt1;
    int ret;
    
    SDL_LockMutex(q->mutex);
    
    for (;;) {
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
        } else if (!block) {
            ret = 0;
            break;
        } else {
            SDL_CondWait(q->cond, q->mutex);
        }
    }
    
    SDL_UnlockMutex(q->mutex);
    
    return ret;
}

double get_audio_clock(VideoState *is) {
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

double get_video_clock(VideoState *is) {
    double delta;
    
    delta = (av_gettime() - is->video_current_pts_time) / 1000000.0;
    return is->video_current_pts + delta;
}

double get_external_clock(VideoState *is) {
    return av_gettime() / 1000000.0;
}

double get_master_clock(VideoState *is) {
    if (is->av_sync_type == AV_SYNC_VIDEO_MASTER) {
        return get_video_clock(is);
    } else if (is->av_sync_type == AV_SYNC_AUDIO_MASTER) {
        return get_audio_clock(is);
    } else {
        return get_external_clock(is);
    }
}

/* Add or subtract samples to get a better sync, return new
 audio buffer size */
int synchronize_audio(VideoState *is, short *samples, int samples_size,
                      double pts) {
    int n;
    double ref_clock;
    
    n = 2 * is->audio_st->codec->channels;
    
    if (is->av_sync_type != AV_SYNC_AUDIO_MASTER) {
        double diff, avg_diff;
        int wanted_size, min_size, max_size;
        //int nb_samples;
        
        ref_clock = get_master_clock(is);
        diff = get_audio_clock(is) - ref_clock;
        
        if (diff < AV_NOSYNC_THRESHOLD) {
            // accumulate the diffs
            is->audio_diff_cum = diff
            + is->audio_diff_avg_coef * is->audio_diff_cum;
            if (is->audio_diff_avg_count < AUDIO_DIFF_AVG_NB) {
                is->audio_diff_avg_count++;
            } else {
                avg_diff = is->audio_diff_cum * (1.0 - is->audio_diff_avg_coef);
                if (fabs(avg_diff) >= is->audio_diff_threshold) {
                    wanted_size = samples_size
                    + ((int) (diff * is->audio_st->codec->sample_rate)
                       * n);
                    min_size = samples_size
                    * ((100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    max_size = samples_size
                    * ((100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    if (wanted_size < min_size) {
                        wanted_size = min_size;
                    } else if (wanted_size > max_size) {
                        wanted_size = max_size;
                    }
                    if (wanted_size < samples_size) {
                        /* remove samples */
                        samples_size = wanted_size;
                    } else if (wanted_size > samples_size) {
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
        } else {
            /* difference is TOO big; reset diff stuff */
            is->audio_diff_avg_count = 0;
            is->audio_diff_cum = 0;
        }
    }
    return samples_size;
}

int audio_decode_frame(VideoState *is, double *pts_ptr) {
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
                    && !is->swr_ctx)) {
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
            } else {
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

void audio_callback(void *userdata, Uint8 *stream, int len) {
    VideoState *is = (VideoState *) userdata;
    int len1, audio_data_size;
    
    double pts;
    
    /*   len是由SDL传入的SDL缓冲区的大小，如果这个缓冲未满，我们就一直往里填充数据 */
    while (len > 0) {
        /*  audio_buf_index 和 audio_buf_size 标示我们自己用来放置解码出来的数据的缓冲区，*/
        /*   这些数据待copy到SDL缓冲区， 当audio_buf_index >= audio_buf_size的时候意味着我*/
        /*   们的缓冲为空，没有数据可供copy，这时候需要调用audio_decode_frame来解码出更
         /*   多的桢数据 */
        
        if (is->audio_buf_index >= is->audio_buf_size) {
            audio_data_size = audio_decode_frame(is, &pts);
            /* audio_data_size < 0 标示没能解码出数据，我们默认播放静音 */
            if (audio_data_size < 0) {
                /* silence */
                is->audio_buf_size = 1024;
                /* 清零，静音 */
                memset(is->audio_buf, 0, is->audio_buf_size);
            } else {
                audio_data_size = synchronize_audio(is, (int16_t *) is->audio_buf,
                                                    audio_data_size, pts);
                is->audio_buf_size = audio_data_size;
            }
            is->audio_buf_index = 0;
        }
        /*  查看stream可用空间，决定一次copy多少数据，剩下的下次继续copy */
        len1 = is->audio_buf_size - is->audio_buf_index;
        if (len1 > len) {
            len1 = len;
        }
        
        memcpy(stream, (uint8_t *) is->audio_buf + is->audio_buf_index, len1);
        len -= len1;
        stream += len1;
        is->audio_buf_index += len1;
    }
}

static Uint32 sdl_refresh_timer_cb(Uint32 interval, void *opaque) {
    SDL_Event event;
    event.type = FF_REFRESH_EVENT;
    event.user.data1 = opaque;
    SDL_PushEvent(&event);
    return 0;
}

static void schedule_refresh(VideoState *is, int delay) {
    SDL_AddTimer(delay, sdl_refresh_timer_cb, is);
}

int decode_interrupt_cb(void *opaque) {
    return (global_video_state && global_video_state->quit);
}

void video_display(VideoState *is) {
    SDL_Rect rect;
    VideoPicture *vp;
    float aspect_ratio;
    
    vp = &is->pictq[is->pictq_rindex];
    if (vp->bmp) {
        
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
        
        rect.x = 0;
        rect.y = 0;
        rect.w = vp->width;
        rect.h = vp->height;
        
        SDL_UpdateYUVTexture(vp->bmp, &rect, vp->rawdata->data[0],
                             vp->rawdata->linesize[0], vp->rawdata->data[1],
                             vp->rawdata->linesize[1], vp->rawdata->data[2],
                             vp->rawdata->linesize[2]);
        
        SDL_RenderClear(vp->renderer);
        SDL_RenderCopy(vp->renderer, vp->bmp, &rect, &rect);
        SDL_RenderPresent(vp->renderer);
    }
}

void video_refresh_timer(void *userdata) {
    VideoState *is = (VideoState *) userdata;
    VideoPicture *vp;
    double actual_delay, delay, sync_threshold, ref_clock, diff;
    
    if (is->video_st) {
        if (is->pictq_size == 0) {
            schedule_refresh(is, 1);
        } else {
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
            
            /* update delay to sync to audio */
            ref_clock = get_audio_clock(is);
            diff = vp->pts - ref_clock;
            
            /* update delay to sync to audio if not master source */
            if (is->av_sync_type != AV_SYNC_VIDEO_MASTER) {
                ref_clock = get_master_clock(is);
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
            schedule_refresh(is, (int) (actual_delay * 1000 + 0.5));
            
            /* show the picture! */
            video_display(is);
            
            /* update queue for next picture! */
            if (++is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
                is->pictq_rindex = 0;
            }
            SDL_LockMutex(is->pictq_mutex);
            is->pictq_size--;
            SDL_CondSignal(is->pictq_cond);
            SDL_UnlockMutex(is->pictq_mutex);
        }
    } else {
        schedule_refresh(is, 100);
    }
}

void alloc_picture(void *userdata) {
    printf("\n alloc_picture  \n");
    VideoState *is = (VideoState *) userdata;
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_windex];
    if (vp->bmp) {
        // we already have one make another, bigger/smaller
        SDL_DestroyTexture(vp->bmp);
    }
    
    if (vp->rawdata) {
        av_free(vp->rawdata);
    }
    
    // Allocate a place to put our YUV image on that screen
    vp->screen = SDL_CreateWindow("My Player Window", SDL_WINDOWPOS_UNDEFINED,
                                  SDL_WINDOWPOS_UNDEFINED, is->video_st->codec->width,  //2016.4.12
                                  is->video_st->codec->height,
                                  SDL_WINDOW_OPENGL);
    
    vp->renderer = SDL_CreateRenderer(vp->screen, -1, 0);
    vp->bmp = SDL_CreateTexture(vp->renderer, SDL_PIXELFORMAT_YV12,
                                SDL_TEXTUREACCESS_STREAMING, is->video_st->codec->width, is->video_st->codec->height);
    
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
    
    SDL_LockMutex(is->pictq_mutex);
    vp->allocated = 1;
    SDL_CondSignal(is->pictq_cond);
    SDL_UnlockMutex(is->pictq_mutex);
}

int queue_picture(VideoState *is, AVFrame *pFrame, double pts) {
    VideoPicture *vp;
    //int dst_pic_fmt
    AVPicture pict;
    
    /* wait unitl we have space for a new pic */
    SDL_LockMutex(is->pictq_mutex);
    while (is->pictq_size >= VIDEO_PICTURE_QUEUE_SIZE && !is->quit) {
        SDL_CondWait(is->pictq_cond, is->pictq_mutex);
    }
    SDL_UnlockMutex(is->pictq_mutex);
    
    if (is->quit)
        return -1;
    
    // windex is set to 0 initially
    vp = &is->pictq[is->pictq_windex];
    
    /* allocate or resize the buffer ! */
    if (!vp->bmp || vp->width != is->video_st->codec->width
        || vp->height != is->video_st->codec->height) {
        SDL_Event event;
        
        vp->allocated = 0;
        /* we have to do it in the main thread */
        event.type = FF_ALLOC_EVENT;
        event.user.data1 = is;
        SDL_PushEvent(&event);
        
        /* wait until we have a picture allocated */
        SDL_LockMutex(is->pictq_mutex);
        while (!vp->allocated && !is->quit) {
            SDL_CondWait(is->pictq_cond, is->pictq_mutex);
        }
    }
    SDL_UnlockMutex(is->pictq_mutex);
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
        SDL_LockMutex(is->pictq_mutex);
        is->pictq_size++;
        SDL_UnlockMutex(is->pictq_mutex);
    }
    return 0;
}

double synchronize_video(VideoState *is, AVFrame *src_frame, double pts) {
    
    double frame_delay;
    
    if (pts != 0) {
        /* if we have pts, set video clock to it */
        is->video_clock = pts;
    } else {
        /* if we aren't given a pts, set it to the clock */
        pts = is->video_clock;
    }
    /* update the video clock */
    frame_delay = av_q2d(is->video_st->codec->time_base);
    /* if we are repeating a frame, adjust clock accordingly */
    frame_delay += src_frame->repeat_pict * (frame_delay * 0.5);
    is->video_clock += frame_delay;
    return pts;
}
uint64_t global_video_pkt_pts = AV_NOPTS_VALUE;

/* These are called whenever we allocate a frame
 * buffer. We use this to store the global_pts in
 * a frame at the time it is allocated.
 */


// int our_get_buffer(struct AVCodecContext *c, AVFrame *pic) {
//     int ret = avcodec_default_get_buffer(c, pic);
//     uint64_t *pts = av_malloc(sizeof(uint64_t));
//     *pts = global_video_pkt_pts;
//     pic->opaque = pts;
//     return ret;
// }

// void our_release_buffer(struct AVCodecContext *c, AVFrame *pic) {
//     if (pic)
//         av_freep(&pic->opaque);
//     avcodec_default_release_buffer(c, pic);
// }

int video_thread(void *arg) {
    VideoState *is = (VideoState *) arg;
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
        
        
        // Did we get a video frame?
        if (frameFinished) {
            pts = synchronize_video(is, pFrame, pts);
            if (queue_picture(is, pFrame, pts) < 0) {
                break;
            }
        }
        av_free_packet(packet);
    }
    
    av_free(pFrame);
    return 0;
}

int audio_stream_component_open(VideoState *is, int stream_index) {
    AVFormatContext *ic = is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    SDL_AudioSpec wanted_spec, spec;
    int64_t wanted_channel_layout = 0;
    int wanted_nb_channels;
    /*  SDL支持的声道数为 1, 2, 4, 6 */
    /*  后面我们会使用这个数组来纠正不支持的声道数目 */
    const int next_nb_channels[] = { 0, 0, 1, 6, 2, 6, 4, 6 };
    
    if (stream_index < 0 || stream_index >= ic->nb_streams) {
        return -1;
    }
    
    codecCtx = ic->streams[stream_index]->codec;
    
    wanted_nb_channels = codecCtx->channels;
    if (!wanted_channel_layout
        || wanted_nb_channels
        != av_get_channel_layout_nb_channels(
                                             wanted_channel_layout)) {
            wanted_channel_layout = av_get_default_channel_layout(
                                                                  wanted_nb_channels);
            wanted_channel_layout &= ~AV_CH_LAYOUT_STEREO_DOWNMIX;
        }
    
    wanted_spec.channels = av_get_channel_layout_nb_channels(
                                                             wanted_channel_layout);
    wanted_spec.freq = codecCtx->sample_rate;
    if (wanted_spec.freq <= 0 || wanted_spec.channels <= 0) {
        fprintf(stderr, "Invalid sample rate or channel count!\n");
        return -1;
    }
    wanted_spec.format = AUDIO_S16SYS; // 具体含义请查看“SDL宏定义”部分
    wanted_spec.silence = 0; // 0指示静音
    wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE; // 自定义SDL缓冲区大小
    wanted_spec.callback = audio_callback; // 音频解码的关键回调函数
    wanted_spec.userdata = is; // 传给上面回调函数的外带数据
    
    /*  打开音频设备，这里使用一个while来循环尝试打开不同的声道数(由上面 */
    /*  next_nb_channels数组指定）直到成功打开，或者全部失败 */
    while (SDL_OpenAudio(&wanted_spec, &spec) < 0) {
        fprintf(stderr, "SDL_OpenAudio (%d channels): %s\n",
                wanted_spec.channels, SDL_GetError());
        wanted_spec.channels = next_nb_channels[FFMIN(7, wanted_spec.channels)];
        if (!wanted_spec.channels) {
            fprintf(stderr,
                    "No more channel combinations to tyu, audio open failed\n");
            return -1;
        }
        wanted_channel_layout = av_get_default_channel_layout(
                                                              wanted_spec.channels);
    }
    
    /* 检查实际使用的配置（保存在spec,由SDL_OpenAudio()填充） */
    if (spec.format != AUDIO_S16SYS) {
        fprintf(stderr, "SDL advised audio format %d is not supported!\n",
                spec.format);
        return -1;
    }
    
    if (spec.channels != wanted_spec.channels) {
        wanted_channel_layout = av_get_default_channel_layout(spec.channels);
        if (!wanted_channel_layout) {
            fprintf(stderr, "SDL advised channel count %d is not supported!\n",
                    spec.channels);
            return -1;
        }
    }
    
    is->audio_hw_buf_size = spec.size;
    
    /* 把设置好的参数保存到大结构中 */
    is->audio_src_fmt = is->audio_tgt_fmt = AV_SAMPLE_FMT_S16;
    is->audio_src_freq = is->audio_tgt_freq = spec.freq;
    is->audio_src_channel_layout = is->audio_tgt_channel_layout =
    wanted_channel_layout;
    is->audio_src_channels = is->audio_tgt_channels = spec.channels;
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    ic->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
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
            SDL_PauseAudio(0); // 开始播放静音
            break;
        default:
            break;
    }
    
    return 0;
}

int video_stream_component_open(VideoState *is, int stream_index) {
    AVFormatContext *pFormatCtx = is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    
    if (stream_index < 0 || stream_index >= pFormatCtx->nb_streams) {
        return -1;
    }
    
    // Get a pointer to the codec context for the video stream
    codecCtx = pFormatCtx->streams[stream_index]->codec;
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_VIDEO:
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
            is->video_tid = SDL_CreateThread(video_thread, "video_thread", is);
            
            //        codecCtx->get_buffer = our_get_buffer;
            //       codecCtx->release_buffer = our_release_buffer;
            break;
        default:
            break;
    }
    return 0;
}

int decode_thread(void *arg) {
    VideoState *is = (VideoState *) arg;
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
        return -1;
    }
    
    //Open video file
    if (avformat_open_input(&pFormatCtx, is->filename, NULL, NULL) != 0) {
        return -1; //Couldn't open file
    }
    
    is->ic = pFormatCtx;
    
    //Retrieve stream infomation
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        return -1; // Couldn't find stream information
    }
    
    //Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, is->filename, 0);
    
    //Find the first video stream
    for (i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->coder_type == AVMEDIA_TYPE_VIDEO
            && video_index < 0) {
            video_index = i;
        }
        
        if (pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO
            && audio_index < 0) {
            audio_index = i;
        }
    }
    
    if (audio_index >= 0) {
        /* 所有设置SDL音频流信息的步骤都在这个函数里完成 */
        audio_stream_component_open(is, audio_index);
    }
    
    if (video_index >= 0) {
        video_stream_component_open(is, video_index);
    }
    
    if (is->videoStream < 0 || is->audioStream <= 0) {
        fprintf(stderr, "%s: could not open codec\n", is->filename);
        goto fail;
    }
    
    //main decode loop
    /* 读包的主循环， av_read_frame不停的从文件中读取数据包*/
    for (;;) {
        if (is->quit) {
            break;
        }
        
        //seek  stuff goes here
        /* 这里audioq.size是指队列中的所有数据包带的音频数据的总量或者视频数据总量，并不是包的数量 */
        if (is->audioq.size > MAX_AUDIOQ_SIZE || is->videoq.size > MAX_VIDEOQ_SIZE) {
            SDL_Delay(10);
            continue;
        }
        if (av_read_frame(is->ic, packet) < 0) {
            if (is->ic->pb->error == 0) {
                SDL_Delay(100); /* no error; wait for user input */
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
        SDL_Delay(100);
    }
    
fail: if (1) {
    SDL_Event event;
    event.type = FF_QUIT_EVENT;
    event.user.data1 = is;
    SDL_PushEvent(&event);
}
    return 0;
}

int main(int argc, char *argv[]) {
    char *filename = "rtmp://0fwc91.live1-rtmp.z1.pili.qiniucdn.com/shutong/test1";
    SDL_Event event;
    
    VideoState *is;
    is = av_malloc(sizeof(VideoState));
    
    // Register all formats and codecs
    av_register_all();
    avformat_network_init();
    
    
    
    
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    
    av_strlcpy(is->filename, filename, sizeof(is->filename));
    
    is->pictq_mutex = SDL_CreateMutex();
    is->pictq_cond = SDL_CreateCond();
    
    schedule_refresh(is, 40);
    
    is->av_sync_type = AV_SYNC_AUDIO_MASTER;
    
    is->parse_tid = SDL_CreateThread(decode_thread, "parse_thread", is);
    if (!is->parse_tid) {
        av_free(is);
        return -1;
    }
    
    for (;;) {
        SDL_WaitEvent(&event);
        switch (event.type) {
            case FF_QUIT_EVENT:
            case SDL_QUIT:
                SDL_CondSignal(is->audioq.cond);
                SDL_CondSignal(is->videoq.cond);
                is->quit = 1;
                SDL_Quit();
                return 0;
                break;
            case FF_ALLOC_EVENT:
                alloc_picture(event.user.data1);
                break;
                
            case FF_REFRESH_EVENT:
                video_refresh_timer(event.user.data1);
                break;
        }
    }
    
    return 0;
}
