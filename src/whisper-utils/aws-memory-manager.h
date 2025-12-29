// AWS SDK Memory Manager wrapper to avoid memory allocation issues
class SafeMemoryManager : public Aws::Utils::Memory::MemorySystemInterface {
public:
    void* AllocateMemory(std::size_t blockSize, std::size_t alignment, const char* allocationTag = nullptr) override {
        return _aligned_malloc(blockSize, alignment);
    }
    
    void FreeMemory(void* memoryPtr) override {
        if (memoryPtr) {
            _aligned_free(memoryPtr);
        }
    }

    void Begin() override {}
    void End() override {}
};
