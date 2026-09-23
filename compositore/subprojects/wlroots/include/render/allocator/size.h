#ifndef MINERVA_ALLOCATOR_SIZE_H
#define MINERVA_ALLOCATOR_SIZE_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <limits.h>

/* Reject before allocating or multiplying signed dimensions. Also bounds the
 * result to the signed file-offset domain used by ftruncate(). */
static inline bool minerva_buffer_size(int stride, int height,
		size_t alignment, size_t *result) {
	if (stride <= 0 || height <= 0 || alignment == 0 ||
			(size_t)height > SIZE_MAX / (size_t)stride) {
		return false;
	}
	size_t size = (size_t)stride * (size_t)height;
	size_t padding = (alignment - size % alignment) % alignment;
	if (size > SIZE_MAX - padding || size + padding > INT64_MAX) {
		return false;
	}
	*result = size + padding;
	return true;
}
#endif
