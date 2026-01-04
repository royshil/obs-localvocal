#include "cloud-speech.h"
#include <obs-module.h>
#include <plugin-support.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <ctime>
#include <unordered_set>
#include <algorithm>

#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
#ifdef _WIN32
#define NOMINMAX
#include <Windows.h>
#endif

#include <aws/core/Aws.h>
#include <aws/core/auth/AWSCredentialsProvider.h>
#include <aws/core/auth/signer/AWSAuthEventStreamV4Signer.h>
#include <aws/core/client/ClientConfiguration.h>
#include <aws/core/http/HttpClientFactory.h>
#include <aws/core/http/HttpResponse.h>
#include <aws/core/platform/Environment.h>
#include <aws/core/Region.h>
#include <aws/core/utils/json/JsonSerializer.h>
#include <aws/core/utils/memory/MemorySystemInterface.h>
#include <aws/core/utils/memory/stl/AWSString.h>
#include <aws/core/utils/StringUtils.h>
#include <aws/core/utils/Threading/Semaphore.h>
#include <aws/transcribestreaming/TranscribeStreamingServiceClient.h>
#include <aws/transcribestreaming/TranscribeStreamingServiceEndpointProvider.h>
#include <aws/transcribestreaming/model/PartialResultsStability.h>

#include "aws-memory-manager.h"
#include "ssl-utils.h"
#endif

// Global AWS SDK initialization state with thread-safe initialization
std::atomic<int> g_aws_init_state{0}; // 0=not initialized, 1=initializing, 2=initialized, -1=failed

namespace {
std::mutex g_curl_mutex;
int g_curl_refcount = 0;
bool g_curl_initialized = false;

bool acquire_curl_global()
{
	std::lock_guard<std::mutex> lock(g_curl_mutex);
	if (g_curl_refcount == 0) {
		const CURLcode curl_init_result = curl_global_init(CURL_GLOBAL_DEFAULT);
		if (curl_init_result != CURLE_OK) {
			blog(LOG_ERROR, "curl_global_init failed: %s",
			     curl_easy_strerror(curl_init_result));
			return false;
		}
		g_curl_initialized = true;
	}
	++g_curl_refcount;
	return true;
}

void release_curl_global()
{
	std::lock_guard<std::mutex> lock(g_curl_mutex);
	if (g_curl_refcount <= 0) {
		return;
	}
	--g_curl_refcount;
	if (g_curl_refcount == 0 && g_curl_initialized) {
		curl_global_cleanup();
		g_curl_initialized = false;
	}
}
} // namespace

#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
static Aws::SDKOptions g_aws_options;
static std::mutex g_aws_init_mutex;
static SafeMemoryManager* g_memory_manager = nullptr;

namespace {
class ForceEventStreamSigV4EndpointProvider final
	: public Aws::TranscribeStreamingService::Endpoint::TranscribeStreamingServiceEndpointProvider {
public:
	Aws::Endpoint::ResolveEndpointOutcome ResolveEndpoint(const Aws::Endpoint::EndpointParameters& endpointParameters) const override
	{
		auto outcome =
			Aws::TranscribeStreamingService::Endpoint::TranscribeStreamingServiceEndpointProvider::ResolveEndpoint(
				endpointParameters);
		if (!outcome.IsSuccess()) {
			return outcome;
		}

		auto endpoint = outcome.GetResultWithOwnership();
		if (auto& attrsOpt = endpoint.AccessAttributes()) {
			attrsOpt->authScheme.SetName(Aws::Auth::EVENTSTREAM_SIGV4_SIGNER);
		} else {
			Aws::Endpoint::AWSEndpoint::EndpointAttributes attrs{};
			attrs.authScheme.SetName(Aws::Auth::EVENTSTREAM_SIGV4_SIGNER);
			endpoint.SetAttributes(std::move(attrs));
		}

		return Aws::Endpoint::ResolveEndpointOutcome(std::move(endpoint));
	}
};
} // namespace

// Initialize AWS SDK safely - call this once during plugin startup
extern "C" bool initialize_aws_sdk_once() {
	// Fast path: already initialized
	int expected = 2;
	if (g_aws_init_state.load(std::memory_order_acquire) == expected) {
		return true;
	}
	
	// Fast path: already failed
	expected = -1;
	if (g_aws_init_state.load(std::memory_order_acquire) == expected) {
		return false;
	}
	
	// Try to acquire initialization lock
	std::lock_guard<std::mutex> lock(g_aws_init_mutex);
	
	// Double-check after acquiring lock
	int current_state = g_aws_init_state.load(std::memory_order_acquire);
	if (current_state == 2) {
		return true; // Already initialized
	}
	if (current_state == -1) {
		return false; // Previously failed
	}
	if (current_state == 1) {
		// Another thread is initializing, wait for it
		while (g_aws_init_state.load(std::memory_order_acquire) == 1) {
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		return g_aws_init_state.load(std::memory_order_acquire) == 2;
	}
	
	// Mark as initializing
	g_aws_init_state.store(1, std::memory_order_release);
	
	try {
		blog(LOG_INFO, "Initializing AWS SDK...");
		
		// Set environment variables to disable problematic features
#ifdef _WIN32
		SetEnvironmentVariableW(L"AWS_EC2_METADATA_DISABLED", L"true");
		SetEnvironmentVariableW(L"AWS_IMDS_CLIENT_DISABLED", L"true");
		SetEnvironmentVariableW(L"AWS_RETRY_QUOTA_DISABLED", L"true");
		SetEnvironmentVariableW(L"AWS_ENABLE_RUNTIME_COMPONENTS", L"false");
		SetEnvironmentVariableW(L"AWS_METADATA_SERVICE_TIMEOUT", L"0");
		SetEnvironmentVariableW(L"AWS_METADATA_SERVICE_NUM_ATTEMPTS", L"0");
#endif
		
		// Initialize AWS SDK with custom memory manager
		Aws::SDKOptions options;
		options.loggingOptions.logLevel = Aws::Utils::Logging::LogLevel::Trace;
		
		// Create custom memory manager to avoid CRT issues
		g_memory_manager = new SafeMemoryManager();
		options.memoryManagementOptions.memoryManager = g_memory_manager;
				
		// Disable HTTP client initialization
		options.httpOptions.installSigPipeHandler = false;
		
		// Initialize the SDK
		Aws::InitAPI(options);
		
		// Store options for shutdown
		g_aws_options = options;
		
		// Mark as successfully initialized
		g_aws_init_state.store(2, std::memory_order_release);
		blog(LOG_INFO, "AWS SDK initialized successfully");
		return true;
		
	} catch (const std::exception& e) {
		blog(LOG_ERROR, "Failed to initialize AWS SDK: %s", e.what());
		g_aws_init_state.store(-1, std::memory_order_release);
		return false;
	} catch (...) {
		blog(LOG_ERROR, "Unknown error occurred during AWS SDK initialization");
		g_aws_init_state.store(-1, std::memory_order_release);
		return false;
	}
}

// Cleanup AWS SDK safely - call this during plugin shutdown
extern "C" void shutdown_aws_sdk() {
	std::lock_guard<std::mutex> lock(g_aws_init_mutex);
	if (g_aws_init_state.load(std::memory_order_acquire) == 2) {
		try {
			Aws::ShutdownAPI(g_aws_options);
			
			// Cleanup memory manager
			if (g_memory_manager) {
				delete g_memory_manager;
				g_memory_manager = nullptr;
			}
			
			g_aws_init_state.store(0, std::memory_order_release);
			blog(LOG_INFO, "AWS SDK shutdown");
		} catch (...) {
			blog(LOG_ERROR, "Error during AWS SDK shutdown");
			g_aws_init_state.store(-1, std::memory_order_release);
		}
	}
}

// Check if AWS SDK is initialized
extern "C" bool is_aws_sdk_initialized() {
	return g_aws_init_state.load(std::memory_order_acquire) == 2;
}
#endif
// Simplified time functions
std::string get_current_time_string() {
	auto now = std::chrono::system_clock::now();
	const std::time_t now_time = std::chrono::system_clock::to_time_t(now);
	auto tm = *std::gmtime(&now_time);
	
	std::stringstream ss;
	ss << std::put_time(&tm, "%Y%m%dT%H%M%SZ");
	return ss.str();
}

std::string get_current_date_string() {
	auto now = std::chrono::system_clock::now();
	const std::time_t now_time = std::chrono::system_clock::to_time_t(now);
	auto tm = *std::gmtime(&now_time);
	
	std::stringstream ss;
	ss << std::put_time(&tm, "%Y%m%d");
	return ss.str();
}

// Callback for curl write data
static size_t WriteCallback(void *contents, size_t size, size_t nmemb, std::string *response) {
	size_t total_size = size * nmemb;
	response->append((char*)contents, total_size);
	return total_size;
}

CloudSpeechProcessor::CloudSpeechProcessor(const CloudSpeechConfig &config)
	: config_(config), initialized_(false) {
	curl_global_acquired_ = acquire_curl_global();
	if (!curl_global_acquired_) {
		initialized_ = false;
		return;
	}
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	if (config_.provider == CloudSpeechProvider::AMAZON_TRANSCRIBE) {
		amazon_ = std::make_unique<AmazonStreamState>();
	}
#endif
	initialized_ = initializeApiClient();
}

CloudSpeechProcessor::~CloudSpeechProcessor() {
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	if (amazon_ && amazon_->started) {
		{
			std::lock_guard<std::mutex> lock(amazon_->mutex);
			amazon_->stop_requested = true;
		}
		amazon_->cv.notify_all();
		if (amazon_->thread.joinable()) {
			amazon_->thread.join();
		}
	}
#endif
	if (curl_global_acquired_) {
		release_curl_global();
		curl_global_acquired_ = false;
	}
}

bool CloudSpeechProcessor::initializeApiClient() {
	// Validate configuration
	if (!validateConfig()) {
		blog(LOG_ERROR, "Invalid cloud speech configuration");
		return false;
	}
	
	blog(LOG_INFO, "Cloud speech processor initialized for provider: %d", static_cast<int>(config_.provider));
	return true;
}

void CloudSpeechProcessor::submitAudio16kMono(const float *audio_data, size_t frames)
{
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	if (!initialized_ || !amazon_ || config_.provider != CloudSpeechProvider::AMAZON_TRANSCRIBE) {
		return;
	}
	if (!audio_data || frames == 0) {
		return;
	}

	ensureAmazonStreamStarted();

	std::vector<int16_t> converted;
	converted.reserve(frames);
	for (size_t i = 0; i < frames; ++i) {
		float sample = (std::max)(-1.0f, (std::min)(1.0f, audio_data[i]));
		converted.push_back(static_cast<int16_t>(sample * 32767.0f));
	}

	{
		std::lock_guard<std::mutex> lock(amazon_->mutex);
		if (amazon_->stop_requested) {
			return;
		}
		amazon_->audio_samples.insert(amazon_->audio_samples.end(), converted.begin(),
					      converted.end());
		constexpr size_t kMaxBufferedAudioSamples = 16000 * 10; // 10 seconds @ 16kHz
		if (amazon_->audio_samples.size() > kMaxBufferedAudioSamples) {
			const size_t to_drop = amazon_->audio_samples.size() - kMaxBufferedAudioSamples;
			for (size_t i = 0; i < to_drop; ++i) {
				amazon_->audio_samples.pop_front();
			}
			blog(LOG_WARNING,
			     "[Transcribe] Audio buffer overflow; dropped %zu old samples",
			     to_drop);
		}
	}
	amazon_->cv.notify_one();
#else
	UNUSED_PARAMETER(audio_data);
	UNUSED_PARAMETER(frames);
#endif
}

bool CloudSpeechProcessor::consumeLatestTranscriptUpdate(std::string &out_text, bool &out_is_final)
{
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	out_text.clear();
	out_is_final = false;

	if (!initialized_ || !amazon_ || config_.provider != CloudSpeechProvider::AMAZON_TRANSCRIBE) {
		return false;
	}

	ensureAmazonStreamStarted();

	std::lock_guard<std::mutex> lock(amazon_->transcript_mutex);
	if (amazon_->transcript_updates.empty()) {
		return false;
	}
	auto update = std::move(amazon_->transcript_updates.front());
	amazon_->transcript_updates.pop_front();
	out_text = std::move(update.text);
	out_is_final = update.is_final;
	return !out_text.empty();
#else
	UNUSED_PARAMETER(out_text);
	UNUSED_PARAMETER(out_is_final);
	return false;
#endif
}

bool CloudSpeechProcessor::validateConfig() const {
	switch (config_.provider) {
	case CloudSpeechProvider::AMAZON_TRANSCRIBE:
		return !config_.api_key.empty() && !config_.region.empty();
	case CloudSpeechProvider::OPENAI:
		return !config_.api_key.empty() && !config_.model.empty();
	case CloudSpeechProvider::GOOGLE:
		return !config_.api_key.empty();
	case CloudSpeechProvider::AZURE:
		return !config_.api_key.empty() && !config_.secret_key.empty() && !config_.region.empty();
	case CloudSpeechProvider::CUSTOM:
		return !config_.endpoint.empty() && !config_.api_key.empty();
	default:
		return false;
	}
}

#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
void CloudSpeechProcessor::ensureAmazonStreamStarted()
{
	if (!amazon_) {
		return;
	}

	bool should_start = false;
	{
		std::lock_guard<std::mutex> lock(amazon_->mutex);
		if (!amazon_->started && !amazon_->stop_requested) {
			amazon_->started = true;
			should_start = true;
		}
	}
	if (should_start) {
		amazon_->thread = std::thread([this]() { amazonStreamThreadMain(); });
	}
}

void CloudSpeechProcessor::amazonStreamThreadMain()
{
	if (!amazon_) {
		return;
	}

	if (!is_aws_sdk_initialized()) {
		blog(LOG_ERROR, "[Transcribe] AWS SDK not initialized; cannot start streaming session.");
		return;
	}
	if (config_.region.empty()) {
		blog(LOG_ERROR, "[Transcribe] AWS region is empty; cannot start streaming session.");
		return;
	}

	try {
		Aws::Client::ClientConfiguration client_config;
		client_config.disableIMDS = true;
#ifdef _WIN32
		std::string ca_path = PEMrootCertsPath();
		if (!ca_path.empty()) {
			client_config.caFile = ca_path.c_str();
		}
		client_config.httpLibOverride = Aws::Http::TransferLibType::CURL_CLIENT;
#endif
		client_config.region = config_.region;
		client_config.connectTimeoutMs = 5000;
		client_config.requestTimeoutMs = 0;

		Aws::Auth::AWSCredentials credentials;
		if (!config_.session_token.empty()) {
			credentials = Aws::Auth::AWSCredentials(config_.api_key, config_.secret_key,
								config_.session_token);
		} else {
			credentials = Aws::Auth::AWSCredentials(config_.api_key, config_.secret_key);
		}

		auto credProvider =
			Aws::MakeShared<Aws::Auth::SimpleAWSCredentialsProvider>("obs-localvocal",
										 credentials);

		Aws::TranscribeStreamingService::TranscribeStreamingServiceClientConfiguration serviceConfig(
			client_config);
		auto endpointProvider =
			Aws::MakeShared<ForceEventStreamSigV4EndpointProvider>("obs-localvocal");
		Aws::TranscribeStreamingService::TranscribeStreamingServiceClient client(
			credProvider, endpointProvider, serviceConfig);

		Aws::TranscribeStreamingService::Model::StartStreamTranscriptionHandler handler;

		auto build_alternative_text =
			[](const Aws::TranscribeStreamingService::Model::Alternative &alt,
			   bool stable_only) -> std::string {
			auto build_from_items = [&](bool include_stable_only) -> std::string {
				if (!alt.ItemsHasBeenSet() || alt.GetItems().empty()) {
					return "";
				}

				const auto &items = alt.GetItems();
				const bool has_stability_data =
					std::any_of(items.begin(), items.end(), [](const auto &item) {
						return item.StableHasBeenSet();
					});

				std::string out;
				for (const auto &item : items) {
					if (!item.ContentHasBeenSet())
						continue;
					if (include_stable_only && has_stability_data) {
						if (!item.StableHasBeenSet() || !item.GetStable())
							continue;
					}

					const std::string content = item.GetContent().c_str();
					if (content.empty())
						continue;

					if (item.TypeHasBeenSet() &&
					    item.GetType() ==
						    Aws::TranscribeStreamingService::Model::ItemType::punctuation) {
						out += content;
					} else {
						if (!out.empty())
							out += " ";
						out += content;
					}
				}
				return out;
			};

			if (stable_only) {
				std::string stable = build_from_items(true);
				if (!stable.empty())
					return stable;
			}

			std::string full = build_from_items(false);
			if (!full.empty())
				return full;

			if (alt.TranscriptHasBeenSet())
				return alt.GetTranscript().c_str();
			return "";
		};

		constexpr size_t kMaxQueuedTranscriptUpdates = 200;
		handler.SetTranscriptEventCallback([this, build_alternative_text](
							   const Aws::TranscribeStreamingService::Model::TranscriptEvent
								   &ev) {
			if (!amazon_) {
				return;
			}
			const auto &transcript = ev.GetTranscript();
			const auto &results = transcript.GetResults();
			for (const auto &result : results) {
				const auto &alternatives = result.GetAlternatives();
				if (alternatives.empty())
					continue;

				const bool is_partial = result.GetIsPartial();
				const std::string text =
					build_alternative_text(alternatives.front(), false);
				if (text.empty())
					continue;

				std::lock_guard<std::mutex> lock(amazon_->transcript_mutex);
				const bool is_final = !is_partial;

				if (!amazon_->transcript_updates.empty()) {
					const auto &last = amazon_->transcript_updates.back();
					if (last.text == text && last.is_final == is_final) {
						continue;
					}
				}

				if (!is_final) {
					if (!amazon_->transcript_updates.empty() &&
					    !amazon_->transcript_updates.back().is_final) {
						amazon_->transcript_updates.back().text = text;
					} else {
						amazon_->transcript_updates.push_back({text, false});
					}
				} else {
					if (!amazon_->transcript_updates.empty() &&
					    !amazon_->transcript_updates.back().is_final) {
						amazon_->transcript_updates.pop_back();
					}
					amazon_->transcript_updates.push_back({text, true});
				}

				while (amazon_->transcript_updates.size() > kMaxQueuedTranscriptUpdates) {
					amazon_->transcript_updates.pop_front();
				}
			}
		});

		handler.SetOnErrorCallback([](
						   const Aws::Client::AWSError<
							   Aws::TranscribeStreamingService::TranscribeStreamingServiceErrors>
							   &error) {
			blog(LOG_ERROR, "[Transcribe] Streaming error: %s", error.GetMessage().c_str());
		});

		Aws::TranscribeStreamingService::Model::StartStreamTranscriptionRequest request;
		constexpr int kTranscribeSampleRateHz = 16000;
		request.SetMediaSampleRateHertz(kTranscribeSampleRateHz);
		request.SetMediaEncoding(Aws::TranscribeStreamingService::Model::MediaEncoding::pcm);
		request.SetEnablePartialResultsStabilization(true);
		request.SetPartialResultsStability(
			Aws::TranscribeStreamingService::Model::PartialResultsStability::high);

		if (config_.language == "en") {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::en_US);
		} else if (config_.language == "es") {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::es_ES);
		} else {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::en_US);
		}

		request.SetEventStreamHandler(handler);

		Aws::Utils::Threading::Semaphore signaling(0, 1);
		auto onResponse = [&](
					  const Aws::TranscribeStreamingService::TranscribeStreamingServiceClient *,
					  const Aws::TranscribeStreamingService::Model::StartStreamTranscriptionRequest &,
					  const Aws::TranscribeStreamingService::Model::StartStreamTranscriptionOutcome &outcome,
					  const std::shared_ptr<const Aws::Client::AsyncCallerContext> &) {
			if (!outcome.IsSuccess()) {
				blog(LOG_ERROR, "[Transcribe] Outcome error: %s",
				     outcome.GetError().GetMessage().c_str());
			}
			signaling.Release();
		};

		auto onStreamReady = [this](Aws::TranscribeStreamingService::Model::AudioStream &stream) {
			if (!amazon_) {
				return;
			}
			{
				std::lock_guard<std::mutex> lock(amazon_->mutex);
				amazon_->running = true;
			}

			const size_t chunk_samples = (kTranscribeSampleRateHz * 20) / 1000; // 20ms chunks

			while (true) {
				std::vector<int16_t> chunk;
				{
					std::unique_lock<std::mutex> lock(amazon_->mutex);
					amazon_->cv.wait(lock, [&]() {
						return amazon_->stop_requested || !amazon_->audio_samples.empty();
					});

					if (amazon_->stop_requested && amazon_->audio_samples.empty()) {
						break;
					}

					const size_t n = (std::min)(chunk_samples, amazon_->audio_samples.size());
					chunk.reserve(n);
					for (size_t i = 0; i < n; ++i) {
						chunk.push_back(amazon_->audio_samples.front());
						amazon_->audio_samples.pop_front();
					}
				}

				if (!chunk.empty()) {
					const unsigned char *p =
						reinterpret_cast<const unsigned char *>(chunk.data());
					Aws::Vector<unsigned char> bytes(p, p + chunk.size() * sizeof(int16_t));
					Aws::TranscribeStreamingService::Model::AudioEvent ev(std::move(bytes));
					if (!stream.WriteAudioEvent(ev)) {
						blog(LOG_ERROR,
						     "[Transcribe] Failed to write audio chunk to stream.");
						break;
					}

					// Try to keep up with real-time, but catch up if we have backlog (to reduce lag).
					const int ms = static_cast<int>((chunk.size() * 1000) / kTranscribeSampleRateHz);
					size_t backlog_samples = 0;
					{
						std::lock_guard<std::mutex> lock(amazon_->mutex);
						backlog_samples = amazon_->audio_samples.size();
					}
					if (backlog_samples < (size_t)kTranscribeSampleRateHz) {
						std::this_thread::sleep_for(std::chrono::milliseconds(ms));
					}
				}
			}

			Aws::TranscribeStreamingService::Model::AudioEvent empty_event;
			stream.WriteAudioEvent(empty_event);
			stream.WaitForDrain(10000);
			stream.Close();
		};

		client.StartStreamTranscriptionAsync(request, onStreamReady, onResponse, nullptr);
		signaling.WaitOne();
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "[Transcribe] Streaming thread exception: %s", e.what());
	}
}
#endif

std::string CloudSpeechProcessor::processAudio(const float *audio_data, size_t frames, uint32_t sample_rate,
					       bool *out_is_final)
{
	blog(LOG_DEBUG, "=== CLOUD SPEECH PROCESS AUDIO START ===");
	blog(LOG_DEBUG, "Processor initialized: %s", initialized_ ? "YES" : "NO");
	blog(LOG_DEBUG, "Provider: %d", static_cast<int>(config_.provider));
	blog(LOG_DEBUG, "Region: %s", config_.region.c_str());
	blog(LOG_DEBUG, "Audio frames: %zu, Sample rate: %u", frames, sample_rate);
	
	if (!initialized_) {
		blog(LOG_ERROR, "Cloud speech processor not initialized");
		return "";
	}
	
	if (out_is_final) {
		*out_is_final = false;
	}

	std::string result;
	bool attempt_is_final = false;
	bool success = retryWithBackoff([&]() -> std::string {
		attempt_is_final = false;
		switch (config_.provider) {
		case CloudSpeechProvider::AMAZON_TRANSCRIBE:
			// In low-latency streaming mode we continuously feed audio via submitAudio16kMono();
			// here we just return the latest transcript update if available.
			{
				std::string text;
				bool is_final = false;
				if (consumeLatestTranscriptUpdate(text, is_final)) {
					attempt_is_final = is_final;
					return text;
				}
				return "";
			}
		case CloudSpeechProvider::OPENAI:
			return transcribeWithOpenAI(audio_data, frames, sample_rate);
		case CloudSpeechProvider::GOOGLE:
			return transcribeWithGoogle(audio_data, frames, sample_rate);
		case CloudSpeechProvider::AZURE:
			return transcribeWithAzure(audio_data, frames, sample_rate);
		case CloudSpeechProvider::CUSTOM:
			return transcribeWithCustom(audio_data, frames, sample_rate);
		default:
			return "";
		}
	}, result);

	if (out_is_final) {
		if (config_.provider == CloudSpeechProvider::AMAZON_TRANSCRIBE) {
			*out_is_final = attempt_is_final && !result.empty();
		} else {
			*out_is_final = !result.empty();
		}
	}
	
	return success ? result : "";
}

std::string CloudSpeechProcessor::transcribeWithAmazonTranscribeREST(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert audio to base64
		std::string audio_base64 = convertAudioToBase64(audio_data, frames, sample_rate);
		if (audio_base64.empty()) {
			return "";
		}
		
		// For now, return a placeholder response
		// TODO: Implement proper AWS REST API with signature v4
		blog(LOG_INFO, "Amazon Transcribe REST API fallback - not fully implemented yet");
		blog(LOG_INFO, "Audio converted to base64, length: %zu", audio_base64.length());
		
		// Return a placeholder to indicate the fallback worked
		return "[REST API Fallback] AWS SDK initialization failed, but REST API not yet implemented";
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Amazon Transcribe REST API error: %s", e.what());
		return "";
	}
}

std::string CloudSpeechProcessor::transcribeWithAmazonTranscribe(const float *audio_data, size_t frames,
								 uint32_t sample_rate, bool *out_is_final)
{
#if defined(ENABLE_AWS_TRANSCRIBE_SDK)
	blog(LOG_INFO, "=== AMAZON TRANSCRIBE STREAMING START (AWS SDK) ===");
	
	try {
		if (out_is_final) {
			*out_is_final = false;
		}

		// Ensure AWS SDK is initialized before use
		if (!is_aws_sdk_initialized()) {
			blog(LOG_WARNING, "AWS SDK not initialized, attempting REST API fallback.");
			return transcribeWithAmazonTranscribeREST(audio_data, frames, sample_rate);
		}

		// Configure AWS client with a stable configuration
		// The 'true' argument disables IMDS calls, which are not needed in a desktop plugin.
		Aws::Client::ClientConfiguration client_config;
		client_config.disableIMDS = true;
#ifdef _WIN32
		std::string ca_path = PEMrootCertsPath();
		if (!ca_path.empty()) {
			client_config.caFile = ca_path.c_str();
		}
		// Use cURL HTTP client (required for streaming on Windows)
		client_config.httpLibOverride = Aws::Http::TransferLibType::CURL_CLIENT;
#endif
		client_config.region = config_.region;
		client_config.connectTimeoutMs = 5000;
		client_config.requestTimeoutMs = 30000;
		if (config_.region.empty()) {
			blog(LOG_ERROR, "AWS region is empty; set Cloud Speech -> Region (e.g. us-east-1).");
			return "";
		}
		// Create credentials to avoid default chain that might trigger EC2 metadata
		Aws::Auth::AWSCredentials credentials;
		if (!config_.session_token.empty()) {
			credentials = Aws::Auth::AWSCredentials(config_.api_key, config_.secret_key, config_.session_token);
		} else {
			credentials = Aws::Auth::AWSCredentials(config_.api_key, config_.secret_key);
		}

		blog(LOG_DEBUG, "[obs-localvocal] AWS Credentials Check:");
		blog(LOG_DEBUG, "  - Access Key ID: %s",
		     config_.api_key.empty() ? "[EMPTY]" : "[SET]");
		blog(LOG_DEBUG, "  - Secret Access Key: %s",
		     config_.secret_key.empty() ? "[EMPTY]" : "[SET]");
		blog(LOG_DEBUG, "  - Session Token: %s",
		     config_.session_token.empty() ? "[NOT SET]" : "[SET]");
		
		// Create a credentials provider
		auto credProvider = Aws::MakeShared<Aws::Auth::SimpleAWSCredentialsProvider>("obs-localvocal", credentials);

		// Create service-specific configuration from the general client config
		Aws::TranscribeStreamingService::TranscribeStreamingServiceClientConfiguration serviceConfig(client_config);

		// Force the event-stream SigV4 signer for streaming requests.
		auto endpointProvider = Aws::MakeShared<ForceEventStreamSigV4EndpointProvider>("obs-localvocal");

		// Create Transcribe Streaming client
		Aws::TranscribeStreamingService::TranscribeStreamingServiceClient client(credProvider, endpointProvider, serviceConfig);
		
		// Set up handler for transcription events
		Aws::TranscribeStreamingService::Model::StartStreamTranscriptionHandler handler;
		std::string committed_transcription;
		std::unordered_set<std::string> committed_result_ids;
		std::string latest_partial_transcription;
		std::string latest_final_transcription;
		std::mutex transcription_mutex;

		auto join_transcript = [](const std::string& prefix, const std::string& suffix) -> std::string {
			if (prefix.empty())
				return suffix;
			if (suffix.empty())
				return prefix;
			return prefix + " " + suffix;
		};

		auto build_alternative_text =
			[](const Aws::TranscribeStreamingService::Model::Alternative& alt, bool stable_only) -> std::string {
			auto build_from_items = [&](bool include_stable_only) -> std::string {
				if (!alt.ItemsHasBeenSet() || alt.GetItems().empty()) {
					return "";
				}

				const auto& items = alt.GetItems();
				const bool has_stability_data = std::any_of(items.begin(), items.end(), [](const auto& item) {
					return item.StableHasBeenSet();
				});

				std::string out;
				for (const auto& item : items) {
					if (!item.ContentHasBeenSet())
						continue;
					if (include_stable_only && has_stability_data) {
						if (!item.StableHasBeenSet() || !item.GetStable())
							continue;
					}

					const std::string content = item.GetContent().c_str();
					if (content.empty())
						continue;

					if (item.TypeHasBeenSet() &&
					    item.GetType() == Aws::TranscribeStreamingService::Model::ItemType::punctuation) {
						out += content;
					} else {
						if (!out.empty())
							out += " ";
						out += content;
					}
				}
				return out;
			};

			if (stable_only) {
				std::string stable = build_from_items(true);
				if (!stable.empty()) {
					return stable;
				}
			}

			if (alt.ItemsHasBeenSet() && !alt.GetItems().empty()) {
				std::string full = build_from_items(false);
				if (!full.empty())
					return full;
			}

			if (alt.TranscriptHasBeenSet()) {
				return alt.GetTranscript().c_str();
			}

			return "";
		};
		
		handler.SetTranscriptEventCallback([&](const Aws::TranscribeStreamingService::Model::TranscriptEvent& ev) {
			std::lock_guard<std::mutex> lock(transcription_mutex);
			const auto& transcript = ev.GetTranscript();
			const auto& results = transcript.GetResults();
			for (const auto& result : results) {
				const auto& alternatives = result.GetAlternatives();
				if (alternatives.empty())
					continue;

				const auto& alternative = alternatives.front();
				const bool is_partial = result.GetIsPartial();
				std::string transcriptText = build_alternative_text(alternative, is_partial);
				if (transcriptText.empty())
					continue;

				if (is_partial) {
					latest_partial_transcription =
						join_transcript(committed_transcription, transcriptText);
					blog(LOG_INFO, "[partial] %s", latest_partial_transcription.c_str());
				} else {
					std::string resultId;
					if (result.ResultIdHasBeenSet()) {
						resultId = result.GetResultId().c_str();
					}

					if (resultId.empty() || committed_result_ids.insert(resultId).second) {
						committed_transcription =
							join_transcript(committed_transcription, transcriptText);
					}

					latest_final_transcription = committed_transcription;
					latest_partial_transcription.clear();
					blog(LOG_INFO, "[final] %s", latest_final_transcription.c_str());
				}
			}
		});

		handler.SetInitialResponseCallbackEx([](
			const Aws::TranscribeStreamingService::Model::StartStreamTranscriptionInitialResponse& initial,
			const Aws::Utils::Event::InitialResponseType initialType) {
			blog(LOG_INFO, "[Transcribe] Initial response type: %d", static_cast<int>(initialType));
			if (initial.RequestIdHasBeenSet()) {
				blog(LOG_INFO, "[Transcribe] RequestId: %s", initial.GetRequestId().c_str());
			}
			if (initial.SessionIdHasBeenSet()) {
				blog(LOG_INFO, "[Transcribe] SessionId: %s", initial.GetSessionId().c_str());
			}
		});
 		
		handler.SetOnErrorCallback([](const Aws::Client::AWSError<Aws::TranscribeStreamingService::TranscribeStreamingServiceErrors>& error) {
			blog(LOG_ERROR, "AWS Transcribe error: %s", error.GetMessage().c_str());
			blog(LOG_ERROR, "[Transcribe] Exception: %s", error.GetExceptionName().c_str());
			blog(LOG_ERROR, "[Transcribe] HTTP response code: %d", static_cast<int>(error.GetResponseCode()));
			if (!error.GetRequestId().empty()) {
				blog(LOG_ERROR, "[Transcribe] RequestId: %s", error.GetRequestId().c_str());
			}
			if (!error.GetRemoteHostIpAddress().empty()) {
				blog(LOG_ERROR, "[Transcribe] RemoteHostIp: %s", error.GetRemoteHostIpAddress().c_str());
			}
			const auto& headers = error.GetResponseHeaders();
			if (!headers.empty()) {
				blog(LOG_ERROR, "[Transcribe] Response headers (%zu):", headers.size());
				for (const auto& kv : headers) {
					blog(LOG_ERROR, "[Transcribe]   %s: %s", kv.first.c_str(), kv.second.c_str());
				}
			}
		});
 		
		// Configure transcription request
		Aws::TranscribeStreamingService::Model::StartStreamTranscriptionRequest request;
		request.SetHeadersReceivedEventHandler(
			[](const Aws::Http::HttpRequest*, Aws::Http::HttpResponse* response) {
				if (!response) {
					blog(LOG_WARNING, "[Transcribe] HeadersReceivedEventHandler called with null response");
					return;
				}
				blog(LOG_INFO, "[Transcribe] HTTP headers received, status=%d", static_cast<int>(response->GetResponseCode()));
				const auto& headers = response->GetHeaders();
				if (!headers.empty()) {
					blog(LOG_INFO, "[Transcribe] HTTP response headers (%zu):", headers.size());
					for (const auto& kv : headers) {
						blog(LOG_INFO, "[Transcribe]   %s: %s", kv.first.c_str(), kv.second.c_str());
					}
				}
			});
		request.SetMediaSampleRateHertz(static_cast<int>(sample_rate));
		
		// Set language code - convert from our format to AWS format
		if (config_.language == "en") {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::en_US);
		} else if (config_.language == "es") {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::es_ES);
		} else {
			request.SetLanguageCode(Aws::TranscribeStreamingService::Model::LanguageCode::en_US); // Default to English
		}
		
		request.SetMediaEncoding(Aws::TranscribeStreamingService::Model::MediaEncoding::pcm);
				request.SetEventStreamHandler(handler);

		// Reduce "flicker" in partial captions by having Transcribe stabilize partial results.
		request.SetEnablePartialResultsStabilization(true);
		request.SetPartialResultsStability(Aws::TranscribeStreamingService::Model::PartialResultsStability::high);
		
		// Set up audio streaming
		auto OnStreamReady = [&](Aws::TranscribeStreamingService::Model::AudioStream& stream) {
			blog(LOG_INFO, "Audio stream ready, sending %zu frames in chunks", frames);

			// Convert float audio to int16 for AWS SDK, with clamping
			std::vector<int16_t> pcm(frames);
			for (size_t i = 0; i < frames; ++i) {
				float sample = (std::max)(-1.0f, (std::min)(1.0f, audio_data[i]));
				pcm[i] = static_cast<int16_t>(sample * 32767.0f);
			}

			// Send audio data in 100ms chunks
			const size_t chunk_samples = (sample_rate * 100) / 1000;
			const unsigned char* p = reinterpret_cast<const unsigned char*>(pcm.data());
			const size_t total_bytes = pcm.size() * sizeof(int16_t);

			for (size_t off = 0; off < total_bytes; ) {
				size_t n = (std::min)(total_bytes - off, chunk_samples * sizeof(int16_t));
				Aws::Vector<unsigned char> bytes(p + off, p + off + n);
				Aws::TranscribeStreamingService::Model::AudioEvent chunk_event(std::move(bytes));
				if (!stream.WriteAudioEvent(chunk_event)) {
					blog(LOG_ERROR, "Failed to write audio chunk to stream.");
					return; // Stop streaming if a chunk fails
				}

				// Transcribe streaming expects near real-time audio. Pace the upload at real-time speed
				// to avoid edge cases where END_STREAM arrives before the service processes the final frames.
				std::this_thread::sleep_for(std::chrono::milliseconds(100));
				off += n;
			}

			// Send the required empty audio event to signal the end of the audio stream
			Aws::TranscribeStreamingService::Model::AudioEvent empty_event;
			if (!stream.WriteAudioEvent(empty_event)) {
				blog(LOG_WARNING, "Failed to write empty audio event to signal end of stream.");
				return; // Do not close if the empty event fails
			}
			blog(LOG_INFO, "[Transcribe] Sent empty AudioEvent (end-of-audio).");

			// Ensure the HTTP client has consumed everything we've written (including the empty AudioEvent)
			// before we signal EOF, otherwise the final empty frame can be dropped.
			if (!stream.WaitForDrain(10000)) {
				blog(LOG_WARNING, "Timed out waiting for Transcribe stream drain before Close(); ending stream anyway.");
			}

			// Give the HTTP/2 stack a moment to flush the last DATA frames before we signal EOF.
			std::this_thread::sleep_for(std::chrono::milliseconds(200));

			// Signal end-of-stream to finalize the transcription.
			blog(LOG_INFO, "[Transcribe] Closing request body stream (EOF).");
			stream.Close();
		};
		
		// Set up completion callback
		Aws::Utils::Threading::Semaphore signaling(0, 1);
		auto OnResponseCallback = [&](const Aws::TranscribeStreamingService::TranscribeStreamingServiceClient*,
		                             const Aws::TranscribeStreamingService::Model::StartStreamTranscriptionRequest&,
		                             const Aws::TranscribeStreamingService::Model::StartStreamTranscriptionOutcome& outcome,
		                             const std::shared_ptr<const Aws::Client::AsyncCallerContext>&) {
			if (!outcome.IsSuccess()) {
				blog(LOG_ERROR, "Transcribe streaming failed: %s", 
				     outcome.GetError().GetMessage().c_str());
			}
			signaling.Release();
		};
		
		// Start streaming transcription
		blog(LOG_INFO, "Starting AWS Transcribe streaming...");
		client.StartStreamTranscriptionAsync(request, OnStreamReady, OnResponseCallback, nullptr);
		
		// Wait for completion
		signaling.WaitOne();
		
		// Return latest transcription
		std::lock_guard<std::mutex> lock(transcription_mutex);
		if (!committed_transcription.empty()) {
			if (out_is_final) {
				*out_is_final = true;
			}
			blog(LOG_INFO, "Returning transcription: %s", committed_transcription.c_str());
			return committed_transcription;
		}

		// No final results arrived before the stream ended; return the last partial, but mark it as partial.
		if (!latest_partial_transcription.empty()) {
			if (out_is_final) {
				*out_is_final = false;
			}
			blog(LOG_INFO, "Returning transcription: %s", latest_partial_transcription.c_str());
			return latest_partial_transcription;
		}
		
		blog(LOG_INFO, "No transcription received");
		return "";
		
	} catch (const std::exception& e) {
		blog(LOG_ERROR, "AWS Transcribe exception: %s", e.what());
		return "";
	}
#elif defined(ENABLE_AWS_TRANSCRIBE_FALLBACK)
	blog(LOG_INFO, "=== AMAZON TRANSCRIBE FALLBACK IMPLEMENTATION ===");
	blog(LOG_INFO, "AWS SDK not available - please install AWS SDK for full functionality");
	UNUSED_PARAMETER(audio_data);
	UNUSED_PARAMETER(out_is_final);
	
	// Fallback implementation that shows the structure
	blog(LOG_INFO, "Region: %s", config_.region.c_str());
	blog(LOG_INFO, "Language: %s", config_.language.c_str());
	blog(LOG_INFO, "Sample Rate: %u", sample_rate);
	blog(LOG_INFO, "Audio Frames: %zu", frames);
	
	return "AWS Transcribe SDK not installed - install AWS SDK for full functionality";
#else
	blog(LOG_INFO, "AWS Transcribe support not compiled in");
	return "AWS Transcribe support not available";
#endif
}

std::string CloudSpeechProcessor::transcribeWithOpenAI(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert audio to base64
		std::string audio_base64 = convertAudioToBase64(audio_data, frames, sample_rate);
		if (audio_base64.empty()) {
			return "";
		}
		
		// Prepare JSON payload
		nlohmann::json payload = {
			{"model", config_.model},
			{"file", {
				{"data", audio_base64},
				{"mime", "audio/wav"}
			}},
			{"language", config_.language},
			{"response_format", "json"}
		};
		
		std::string url = "https://api.openai.com/v1/audio/transcriptions";
		std::string auth_header = "Authorization: Bearer " + config_.api_key;
		
		return sendHttpRequest(url, payload.dump(), auth_header);
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "OpenAI transcription error: %s", e.what());
		return "";
	}
}

std::string CloudSpeechProcessor::transcribeWithGoogle(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert audio to base64
		std::string audio_base64 = convertAudioToBase64(audio_data, frames, sample_rate);
		if (audio_base64.empty()) {
			return "";
		}
		
		// Prepare JSON payload for Google Speech-to-Text
		nlohmann::json payload = {
			{"config", {
				{"encoding", "WAV"},
				{"sampleRateHertz", static_cast<int>(sample_rate)},
				{"languageCode", config_.language},
				{"enableAutomaticPunctuation", true}
			}},
			{"audio", {
				{"content", audio_base64}
			}}
		};
		
		std::string url = "https://speech.googleapis.com/v1/speech:recognize?key=" + config_.api_key;
		
		return sendHttpRequest(url, payload.dump(), "");
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Google transcription error: %s", e.what());
		return "";
	}
}

std::string CloudSpeechProcessor::transcribeWithAzure(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert audio to base64
		std::string audio_base64 = convertAudioToBase64(audio_data, frames, sample_rate);
		if (audio_base64.empty()) {
			return "";
		}
		
		// Prepare JSON payload for Azure Speech Services
		nlohmann::json payload = {
			{"provider", "Azure"},
			{"model", config_.model},
			{"audio", {
				{"data", audio_base64},
				{"mime", "audio/wav"}
			}},
			{"language", config_.language}
		};
		
		std::string url = "https://" + config_.region + ".api.cognitive.microsoft.com/sts/v1.0/issuetoken";
		std::string auth_header = "Ocp-Apim-Subscription-Key: " + config_.api_key;
		
		return sendHttpRequest(url, payload.dump(), auth_header);
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Azure transcription error: %s", e.what());
		return "";
	}
}

std::string CloudSpeechProcessor::transcribeWithCustom(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert audio to base64
		std::string audio_base64 = convertAudioToBase64(audio_data, frames, sample_rate);
		if (audio_base64.empty()) {
			return "";
		}
		
		// Prepare JSON payload for custom endpoint
		nlohmann::json payload = {
			{"audio", audio_base64},
			{"sample_rate", static_cast<int>(sample_rate)},
			{"language", config_.language},
			{"model", config_.model}
		};
		
		std::string auth_header = "Authorization: Bearer " + config_.api_key;
		return sendHttpRequest(config_.endpoint, payload.dump(), auth_header);
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Custom transcription error: %s", e.what());
		return "";
	}
}

// Utility functions
std::string CloudSpeechProcessor::convertAudioToBase64(const float *audio_data, size_t frames, uint32_t sample_rate) {
	try {
		// Convert float audio to 16-bit PCM
		std::vector<int16_t> pcm_data(frames);
		for (size_t i = 0; i < frames; i++) {
			pcm_data[i] = static_cast<int16_t>(audio_data[i] * 32767.0f);
		}
		
		// Create WAV header
		const uint16_t channels = 1;
		const uint16_t bits_per_sample = 16;
		const uint16_t block_align = static_cast<uint16_t>((channels * bits_per_sample) / 8);
		const uint32_t byte_rate =
			static_cast<uint32_t>(sample_rate * static_cast<uint32_t>(block_align));
		const size_t data_size = frames * static_cast<size_t>(block_align);
		const size_t file_size = 36 + data_size;
		const uint32_t data_size_le = static_cast<uint32_t>(data_size);
		const uint32_t file_size_le = static_cast<uint32_t>(file_size);
		
		std::vector<uint8_t> wav_buffer;
		wav_buffer.reserve(44 + data_size);
		
		// RIFF header
		wav_buffer.insert(wav_buffer.end(), {'R', 'I', 'F', 'F'});
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&file_size_le),
				  reinterpret_cast<const uint8_t *>(&file_size_le) + 4);
		wav_buffer.insert(wav_buffer.end(), {'W', 'A', 'V', 'E'});
		
		// fmt chunk
		wav_buffer.insert(wav_buffer.end(), {'f', 'm', 't', ' '});
		const uint32_t fmt_chunk_size = 16;
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&fmt_chunk_size),
				  reinterpret_cast<const uint8_t *>(&fmt_chunk_size) + 4);
		const uint16_t audio_format = 1; // PCM
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&audio_format),
				  reinterpret_cast<const uint8_t *>(&audio_format) + 2);
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&channels),
				  reinterpret_cast<const uint8_t *>(&channels) + 2);
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&sample_rate),
				  reinterpret_cast<const uint8_t *>(&sample_rate) + 4);
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&byte_rate),
				  reinterpret_cast<const uint8_t *>(&byte_rate) + 4);
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&block_align),
				  reinterpret_cast<const uint8_t *>(&block_align) + 2);
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&bits_per_sample),
				  reinterpret_cast<const uint8_t *>(&bits_per_sample) + 2);
		
		// data chunk
		wav_buffer.insert(wav_buffer.end(), {'d', 'a', 't', 'a'});
		wav_buffer.insert(wav_buffer.end(),
				  reinterpret_cast<const uint8_t *>(&data_size_le),
				  reinterpret_cast<const uint8_t *>(&data_size_le) + 4);
		
		// Convert float samples to 16-bit PCM
		for (size_t i = 0; i < frames; i++) {
			float sample = audio_data[i];
			// Clamp to [-1.0, 1.0]
			sample = (std::max)((-1.0f), (std::min)((1.0f), (sample)));
			// Convert to 16-bit signed integer
			int16_t pcm_sample = static_cast<int16_t>(sample * 32767);
			wav_buffer.insert(wav_buffer.end(), reinterpret_cast<const uint8_t*>(&pcm_sample), reinterpret_cast<const uint8_t*>(&pcm_sample) + 2);
		}
		
		// Encode to base64
		const std::string base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		std::string base64;
		base64.reserve(((wav_buffer.size() + 2) / 3) * 4);
		
		for (size_t i = 0; i < wav_buffer.size(); i += 3) {
			uint32_t triple = (static_cast<uint32_t>(wav_buffer[i]) << 16) |
				((i + 1 < wav_buffer.size()) ? static_cast<uint32_t>(wav_buffer[i + 1]) << 8 : 0) |
				((i + 2 < wav_buffer.size()) ? static_cast<uint32_t>(wav_buffer[i + 2]) : 0);
			
			base64 += base64_chars[(triple >> 18) & 0x3F];
			base64 += base64_chars[(triple >> 12) & 0x3F];
			base64 += (i + 1 < wav_buffer.size()) ? base64_chars[(triple >> 6) & 0x3F] : '=';
			base64 += (i + 2 < wav_buffer.size()) ? base64_chars[triple & 0x3F] : '=';
		}
		
		return base64;
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Audio conversion error: %s", e.what());
		return "";
	}
}

std::string CloudSpeechProcessor::sendHttpRequestWithHeaders(const std::string &url, const std::string &payload, const std::vector<std::string> &headers) {
	blog(LOG_INFO, "=== HTTP REQUEST WITH HEADERS START ===");
	blog(LOG_INFO, "URL: %s", url.c_str());
	blog(LOG_INFO, "Payload length: %zu", payload.length());
	
	CURL *curl = curl_easy_init();
	if (!curl) {
		blog(LOG_ERROR, "Failed to initialize curl");
		return "";
	}
	
	std::string response;
	struct curl_slist *header_list = nullptr;
	
	// Add headers
	for (const auto& header : headers) {
		header_list = curl_slist_append(header_list, header.c_str());
		blog(LOG_INFO, "Header: %s", header.c_str());
	}
	
	// Configure curl
	curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, config_.timeout_seconds);
	
	// Perform request
	blog(LOG_INFO, "Performing HTTP request...");
	CURLcode res = curl_easy_perform(curl);
	
	// Cleanup
	curl_slist_free_all(header_list);
	curl_easy_cleanup(curl);
	
	blog(LOG_INFO, "HTTP request completed with code: %d", res);
	
	if (res != CURLE_OK) {
		blog(LOG_ERROR, "HTTP request failed: %s", curl_easy_strerror(res));
		return "";
	}
	
	blog(LOG_INFO, "Raw HTTP response: %s", response.c_str());
	
	return response;
}

std::string CloudSpeechProcessor::sendHttpRequest(const std::string &url, const std::string &payload, const std::string &auth_header) {
	blog(LOG_INFO, "=== HTTP REQUEST START ===");
	blog(LOG_INFO, "URL: %s", url.c_str());
	blog(LOG_INFO, "Payload length: %zu", payload.length());
	blog(LOG_INFO, "Auth header: %s", auth_header.c_str());
	
	CURL *curl = curl_easy_init();
	if (!curl) {
		blog(LOG_ERROR, "Failed to initialize curl");
		return "";
	}
	
	std::string response;
	struct curl_slist *headers = nullptr;
	
	// Set headers
	headers = curl_slist_append(headers, "Content-Type: application/json");
	if (!auth_header.empty()) {
		headers = curl_slist_append(headers, auth_header.c_str());
	}
	
	// Configure curl
	curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, config_.timeout_seconds);
	
	// Perform request
	blog(LOG_INFO, "Performing HTTP request...");
	CURLcode res = curl_easy_perform(curl);
	
	// Cleanup
	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);
	
	blog(LOG_INFO, "HTTP request completed with code: %d", res);
	
	if (res != CURLE_OK) {
		blog(LOG_ERROR, "HTTP request failed: %s", curl_easy_strerror(res));
		return "";
	}
	
	blog(LOG_INFO, "Raw HTTP response: %s", response.c_str());
	
	// Parse response and extract transcription
	try {
		nlohmann::json response_json = nlohmann::json::parse(response);
		
		// Handle different response formats based on provider
		switch (config_.provider) {
		case CloudSpeechProvider::OPENAI:
			if (response_json.contains("text")) {
				return response_json["text"].get<std::string>();
			}
			break;
		case CloudSpeechProvider::GOOGLE:
			if (response_json.contains("results") && !response_json["results"].empty()) {
				auto &result = response_json["results"][0];
				if (result.contains("alternatives") && !result["alternatives"].empty()) {
					return result["alternatives"][0]["transcript"].get<std::string>();
				}
			}
			break;
		case CloudSpeechProvider::AMAZON_TRANSCRIBE:
			blog(LOG_WARNING,
			     "Unexpected Amazon Transcribe response parsing request: Amazon Transcribe uses a streaming API.");
			break;
		case CloudSpeechProvider::AZURE:
		case CloudSpeechProvider::CUSTOM:
			if (response_json.contains("transcription")) {
				return response_json["transcription"].get<std::string>();
			} else if (response_json.contains("text")) {
				return response_json["text"].get<std::string>();
			}
			break;
		default:
			break;
		}
		
		blog(LOG_WARNING, "Unexpected response format: %s", response.c_str());
		return "";
		
	} catch (const std::exception &e) {
		blog(LOG_ERROR, "Response parsing error: %s", e.what());
		return "";
	}
}

bool CloudSpeechProcessor::retryWithBackoff(std::function<std::string()> operation, std::string &result) {
	for (int attempt = 0; attempt < config_.max_retries; ++attempt) {
		try {
			result = operation();
			if (!result.empty()) {
				return true;
			}
		} catch (const std::exception &e) {
			blog(LOG_WARNING, "Cloud speech attempt %d failed: %s", attempt + 1, e.what());
		}
		
		// Exponential backoff
		if (attempt < config_.max_retries - 1) {
			int delay_ms = 1000 * (1 << attempt); // 1s, 2s, 4s, etc.
			std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
		}
	}
	
	blog(LOG_ERROR, "All cloud speech attempts failed");
	return false;
}
