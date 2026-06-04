#include "AudioRingBuffer.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SuniyeAudioRingBuffer {
    float *storage;
    size_t capacity;
    _Atomic uint64_t writeIndex;
    _Atomic uint64_t readIndex;
    _Atomic uint64_t totalWritten;
    _Atomic uint64_t droppedSamples;
};

SuniyeAudioRingBuffer *SuniyeAudioRingBufferCreate(size_t capacity) {
    if (capacity < 2) {
        return NULL;
    }

    SuniyeAudioRingBuffer *buffer = calloc(1, sizeof(SuniyeAudioRingBuffer));
    if (buffer == NULL) {
        return NULL;
    }

    buffer->storage = calloc(capacity, sizeof(float));
    if (buffer->storage == NULL) {
        free(buffer);
        return NULL;
    }

    buffer->capacity = capacity;
    return buffer;
}

void SuniyeAudioRingBufferDestroy(SuniyeAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    free(buffer->storage);
    free(buffer);
}

void SuniyeAudioRingBufferReset(SuniyeAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    atomic_store_explicit(&buffer->writeIndex, 0, memory_order_relaxed);
    atomic_store_explicit(&buffer->readIndex, 0, memory_order_relaxed);
    atomic_store_explicit(&buffer->totalWritten, 0, memory_order_relaxed);
    atomic_store_explicit(&buffer->droppedSamples, 0, memory_order_relaxed);
}

static size_t SuniyeAudioRingBufferWritableCount(
    SuniyeAudioRingBuffer *buffer,
    size_t requestedCount,
    uint64_t *writeIndex
) {
    uint64_t currentWrite = atomic_load_explicit(&buffer->writeIndex, memory_order_relaxed);
    uint64_t currentRead = atomic_load_explicit(&buffer->readIndex, memory_order_acquire);
    size_t available = buffer->capacity - (size_t)(currentWrite - currentRead);
    size_t writable = requestedCount < available ? requestedCount : available;
    if (writable < requestedCount) {
        atomic_fetch_add_explicit(
            &buffer->droppedSamples,
            requestedCount - writable,
            memory_order_relaxed
        );
    }
    *writeIndex = currentWrite;
    return writable;
}

static void SuniyeAudioRingBufferCommitWrite(
    SuniyeAudioRingBuffer *buffer,
    uint64_t nextWriteIndex,
    size_t writtenCount
) {
    atomic_store_explicit(&buffer->writeIndex, nextWriteIndex, memory_order_release);
    atomic_fetch_add_explicit(&buffer->totalWritten, writtenCount, memory_order_relaxed);
}

size_t SuniyeAudioRingBufferWrite(
    SuniyeAudioRingBuffer *buffer,
    const float *samples,
    size_t sampleCount
) {
    if (buffer == NULL || samples == NULL) {
        return 0;
    }

    uint64_t writeIndex = 0;
    size_t written = SuniyeAudioRingBufferWritableCount(buffer, sampleCount, &writeIndex);
    size_t storageIndex = (size_t)(writeIndex % buffer->capacity);
    size_t firstCount = written < buffer->capacity - storageIndex
        ? written
        : buffer->capacity - storageIndex;
    if (firstCount > 0) {
        memcpy(buffer->storage + storageIndex, samples, firstCount * sizeof(float));
    }
    if (written > firstCount) {
        memcpy(buffer->storage, samples + firstCount, (written - firstCount) * sizeof(float));
    }
    SuniyeAudioRingBufferCommitWrite(buffer, writeIndex + written, written);
    return written;
}

size_t SuniyeAudioRingBufferWritePlanar(
    SuniyeAudioRingBuffer *buffer,
    const float *const *channels,
    uint32_t channelCount,
    uint32_t frameCount
) {
    if (buffer == NULL || channels == NULL || channelCount == 0) {
        return 0;
    }

    uint64_t writeIndex = 0;
    size_t written = SuniyeAudioRingBufferWritableCount(buffer, frameCount, &writeIndex);
    for (size_t frame = 0; frame < written; frame++) {
        float mixed = 0;
        uint32_t readableChannels = 0;
        for (uint32_t channel = 0; channel < channelCount; channel++) {
            if (channels[channel] != NULL) {
                mixed += channels[channel][frame];
                readableChannels++;
            }
        }
        if (readableChannels > 1) {
            mixed /= (float)readableChannels;
        }

        buffer->storage[(writeIndex + frame) % buffer->capacity] = mixed;
    }
    SuniyeAudioRingBufferCommitWrite(buffer, writeIndex + written, written);
    return written;
}

size_t SuniyeAudioRingBufferRead(
    SuniyeAudioRingBuffer *buffer,
    float *destination,
    size_t maximumSampleCount
) {
    if (buffer == NULL || destination == NULL) {
        return 0;
    }

    uint64_t readIndex = atomic_load_explicit(&buffer->readIndex, memory_order_relaxed);
    uint64_t writeIndex = atomic_load_explicit(&buffer->writeIndex, memory_order_acquire);
    size_t available = (size_t)(writeIndex - readIndex);
    size_t count = available < maximumSampleCount ? available : maximumSampleCount;

    for (size_t index = 0; index < count; index++) {
        destination[index] = buffer->storage[(readIndex + index) % buffer->capacity];
    }
    atomic_store_explicit(&buffer->readIndex, readIndex + count, memory_order_release);
    return count;
}

uint64_t SuniyeAudioRingBufferTotalWritten(const SuniyeAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }
    return atomic_load_explicit(&buffer->totalWritten, memory_order_relaxed);
}

uint64_t SuniyeAudioRingBufferDroppedSamples(const SuniyeAudioRingBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }
    return atomic_load_explicit(&buffer->droppedSamples, memory_order_relaxed);
}
