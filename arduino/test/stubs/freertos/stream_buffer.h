// Host stand-in for a FreeRTOS stream buffer (single producer/consumer).
#pragma once
#include <cstddef>
#include <cstdint>
#include <deque>

struct FakeStreamBuffer {
  std::deque<uint8_t> q;
  size_t cap;
};
typedef FakeStreamBuffer *StreamBufferHandle_t;

inline StreamBufferHandle_t xStreamBufferCreate(size_t cap, size_t) {
  auto *b = new FakeStreamBuffer();
  b->cap = cap;
  return b;
}
inline size_t xStreamBufferSend(StreamBufferHandle_t b, const void *d, size_t n, int) {
  const uint8_t *p = (const uint8_t *)d;
  size_t k = 0;
  while (k < n && b->q.size() < b->cap) b->q.push_back(p[k++]);
  return k;
}
inline size_t xStreamBufferReceive(StreamBufferHandle_t b, void *d, size_t n, int) {
  uint8_t *p = (uint8_t *)d;
  size_t k = 0;
  while (k < n && !b->q.empty()) {
    p[k++] = b->q.front();
    b->q.pop_front();
  }
  return k;
}
