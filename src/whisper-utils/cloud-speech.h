#pragma once

#include <obs-module.h>
#include <string>
#include <memory>
#include <functional>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <deque>

// Shared global state for AWS SDK initialization
extern std::atomic<int> g_aws_init_state;

#ifdef ENABLE_AWS_TRANSCRIBE_SDK
#include <aws/core/Aws.h>
#include <aws/core/utils/threading/Semaphore.h>
#include <aws/transcribestreaming/TranscribeStreamingServiceClient.h>
#include <aws/transcribestreaming/model/StartStreamTranscriptionHandler.h>
#include <aws/transcribestreaming/model/StartStreamTranscriptionRequest.h>
#include <aws/transcribestreaming/model/AudioStream.h>
#include <aws/transcribestreaming/model/AudioEvent.h>
#include <aws/transcribestreaming/model/TranscriptEvent.h>

// AWS SDK lifecycle management
extern "C" bool initialize_aws_sdk_once();
extern "C" void shutdown_aws_sdk();
extern "C" bool is_aws_sdk_initialized();

#endif

enum class CloudSpeechProvider { AMAZON_TRANSCRIBE, OPENAI, GOOGLE, AZURE, CUSTOM };

struct CloudSpeechConfig {
	CloudSpeechProvider provider;
	std::string api_key;       // API key for authentication
	std::string session_token; // Session token
	std::string secret_key;    // Secret key (for Azure)
	std::string region;        // Region for Azure
	std::string endpoint;      // Custom endpoint URL
	std::string model;         // Model name (e.g., "whisper-1", "latest")
	std::string language;      // Language code (e.g., "en", "es")
	bool enable_fallback;      // Fall back to local processing on error
	int max_retries;           // Maximum retry attempts
	int timeout_seconds;       // Request timeout in seconds

	// Constructor with default values
	CloudSpeechConfig()
		: provider(CloudSpeechProvider::OPENAI),
		  api_key(""),
		  secret_key(""),
		  region(""),
		  endpoint(""),
		  model("whisper-1"),
		  language("en"),
		  enable_fallback(true),
		  max_retries(3),
		  timeout_seconds(30)
	{
	}
};

// Cloud speech processor interface
class CloudSpeechProcessor {
public:
	explicit CloudSpeechProcessor(const CloudSpeechConfig &config);
	~CloudSpeechProcessor();

	// Process audio data and return transcription
	std::string processAudio(const float *audio_data, size_t frames, uint32_t sample_rate,
				 bool *out_is_final = nullptr);

	// Low-latency Amazon Transcribe streaming: feed audio continuously and consume transcript updates.
	// Audio is expected to be mono float PCM at 16kHz (WHISPER_SAMPLE_RATE).
	void submitAudio16kMono(const float *audio_data, size_t frames);
	bool consumeLatestTranscriptUpdate(std::string &out_text, bool &out_is_final);

	// Validate configuration
	bool validateConfig() const;

	// Check if processor is ready
	bool isReady() const { return initialized_; }
	bool isAmazonStreamingEnabled() const
	{
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
		return config_.provider == CloudSpeechProvider::AMAZON_TRANSCRIBE;
#else
		// Without the AWS SDK, the Amazon streaming code path is compiled out; reporting
		// "enabled" here causes the pipeline to suppress local inference and emit no output.
		return false;
#endif
	}

private:
	CloudSpeechConfig config_;
	bool initialized_;
	bool curl_global_acquired_ = false;

#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	struct AmazonStreamState {
		std::mutex mutex;
		std::condition_variable cv;
		std::deque<int16_t> audio_samples;
		std::thread thread;
		bool stop_requested = false;
		bool started = false;
		bool running = false;

		std::mutex transcript_mutex;
		struct TranscriptUpdate {
			std::string text;
			bool is_final = false;
		};
		std::deque<TranscriptUpdate> transcript_updates;
	};
	std::unique_ptr<AmazonStreamState> amazon_;
#endif

	// Initialize API client based on provider
	bool initializeApiClient();

#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	void ensureAmazonStreamStarted();
	void amazonStreamThreadMain();
#endif

	// Provider-specific implementations
	std::string transcribeWithAmazonTranscribe(const float *audio_data, size_t frames,
						   uint32_t sample_rate, bool *out_is_final);
	std::string transcribeWithAmazonTranscribeREST(const float *audio_data, size_t frames,
						       uint32_t sample_rate);
	std::string transcribeWithOpenAI(const float *audio_data, size_t frames,
					 uint32_t sample_rate);
	std::string transcribeWithGoogle(const float *audio_data, size_t frames,
					 uint32_t sample_rate);
	std::string transcribeWithAzure(const float *audio_data, size_t frames,
					uint32_t sample_rate);
	std::string transcribeWithCustom(const float *audio_data, size_t frames,
					 uint32_t sample_rate);

	// Utility functions
	std::string convertAudioToBase64(const float *audio_data, size_t frames,
					 uint32_t sample_rate);
	std::string sendHttpRequest(const std::string &url, const std::string &payload,
				    const std::string &auth_header);
	std::string sendHttpRequestWithHeaders(const std::string &url, const std::string &payload,
					       const std::vector<std::string> &headers);
	bool retryWithBackoff(std::function<std::string()> operation, std::string &result);
};
