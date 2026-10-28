// Exception entry points for wasm32-wasi, where Zig's libc++abi is built without exception
// support. There is no unwinding on this target, so a C++ throw (slughorn only throws on
// invalid input such as NaN coordinates) reports and aborts instead of being catchable.
#include <stdio.h>
#include <stdlib.h>

void* __cxa_allocate_exception(size_t size) {
	return malloc(size);
}

_Noreturn void __cxa_throw(void* exception, void* type_info, void (*destructor)(void*)) {
	(void)exception;
	(void)type_info;
	(void)destructor;
	fputs("slughorn: C++ exception thrown on wasm (unsupported); aborting\n", stderr);
	abort();
}
