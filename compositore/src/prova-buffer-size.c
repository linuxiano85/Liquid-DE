#undef NDEBUG
#include <assert.h>
#include <stdint.h>
#include "render/allocator/size.h"
int main(void) {
	size_t n;
	assert(minerva_buffer_size(131072,32768,1,&n));
	assert(n == UINT64_C(4294967296));
	assert(minerva_buffer_size(12,7,4096,&n) && n==4096);
	assert(!minerva_buffer_size(-1,1,1,&n));
	assert(!minerva_buffer_size(1,0,1,&n));
	assert(!minerva_buffer_size(1,1,0,&n));
	assert(!minerva_buffer_size(INT_MAX,INT_MAX,SIZE_MAX,&n));
}
