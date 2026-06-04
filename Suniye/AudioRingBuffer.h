#ifndef SUNIYE_AUDIO_RING_BUFFER_H
#define SUNIYE_AUDIO_RING_BUFFER_H

#include <stddef.h>
#include <stdint.h>

typedef struct SuniyeAudioRingBuffer SuniyeAudioRingBuffer;

SuniyeAudioRingBuffer *SuniyeAudioRingBufferCreate(size_t capacity);
void SuniyeAudioRingBufferDestroy(SuniyeAudioRingBuffer *buffer);
void SuniyeAudioRingBufferReset(SuniyeAudioRingBuffer *buffer);

size_t SuniyeAudioRingBufferWrite(
    SuniyeAudioRingBuffer *buffer,
    const float *samples,
    size_t sampleCount
);

size_t SuniyeAudioRingBufferWritePlanar(
    SuniyeAudioRingBuffer *buffer,
    const float *const *channels,
    uint32_t channelCount,
    uint32_t frameCount
);

size_t SuniyeAudioRingBufferRead(
    SuniyeAudioRingBuffer *buffer,
    float *destination,
    size_t maximumSampleCount
);

uint64_t SuniyeAudioRingBufferTotalWritten(const SuniyeAudioRingBuffer *buffer);
uint64_t SuniyeAudioRingBufferDroppedSamples(const SuniyeAudioRingBuffer *buffer);

#endif
