#pragma once

#include <aws/core/utils/memory/MemorySystemInterface.h>

#include <cstddef>
#include <cstdlib>

#if defined(_WIN32)
#include <malloc.h>
#endif

class SafeMemoryManager : public Aws::Utils::Memory::MemorySystemInterface {
public:
	void *AllocateMemory(std::size_t blockSize, std::size_t alignment,
			     const char *allocationTag = nullptr) override
	{
		(void)allocationTag;

#if defined(_WIN32)
		return _aligned_malloc(blockSize, alignment);
#else
		void *ptr = nullptr;
		if (posix_memalign(&ptr, alignment, blockSize) != 0) {
			return nullptr;
		}
		return ptr;
#endif
	}

	void FreeMemory(void *memoryPtr) override
	{
		if (!memoryPtr) {
			return;
		}

#if defined(_WIN32)
		_aligned_free(memoryPtr);
#else
		std::free(memoryPtr);
#endif
	}

	void Begin() override {}
	void End() override {}
};
