## Repo sponsors: [Recall.ai](https://www.recall.ai/product/desktop-recording-sdk?utm_source=github&utm_medium=sponsorship&utm_campaign=royshil-obs-localvocal) - API for desktop recording

If you’re looking for a hosted desktop recording API, consider checking out [Recall.ai](https://www.recall.ai/product/desktop-recording-sdk?utm_source=github&utm_medium=sponsorship&utm_campaign=royshil-obs-localvocal), an API that records Zoom, Google Meet, Microsoft Teams, in-person meetings, and more.

# LocalVocal - Speech AI assistant OBS Plugin

<div align="center">

[![GitHub](https://img.shields.io/github/license/locaal-ai/obs-localvocal)](https://github.com/locaal-ai/obs-localvocal/blob/main/LICENSE)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/locaal-ai/obs-localvocal/push.yaml)](https://github.com/locaal-ai/obs-localvocal/actions/workflows/push.yaml)
[![Total downloads](https://img.shields.io/github/downloads/locaal-ai/obs-localvocal/total)](https://github.com/locaal-ai/obs-localvocal/releases)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/locaal-ai/obs-localvocal)](https://github.com/locaal-ai/obs-localvocal/releases)
[![GitHub stars](https://badgen.net/github/stars/locaal-ai/obs-localvocal)](https://GitHub.com/locaal-ai/obs-localvocal/stargazers/)
<br/>
Download:</br>
[![Static Badge](https://img.shields.io/badge/Windows%20(generic)-0078d6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-windows-x64-generic-Installer.exe) [![Static Badge](https://img.shields.io/badge/Windows%20(NVidia)-0078d6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-windows-x64-nvidia-Installer.exe) [![Static Badge](https://img.shields.io/badge/Windows%20(AMD)-0078d6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-windows-x64-amd-Installer.exe)
[![Static Badge](https://img.shields.io/badge/mac%20Intel-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-macos-x86_64.pkg) [![Static Badge](https://img.shields.io/badge/mac%20M1/2/3-0a0a0a?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-macos-arm64.pkg)
[![Static Badge](https://img.shields.io/badge/Linux%20(generic)-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-generic-x86_64-linux-gnu.deb) [![Static Badge](https://img.shields.io/badge/Linux%20(NVidia)-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-nvidia-x86_64-linux-gnu.deb) [![Static Badge](https://img.shields.io/badge/Linux%20(AMD)-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/locaal-ai/obs-localvocal/releases/download/0.5.3/obs-localvocal-0.5.3-amd-x86_64-linux-gnu.deb)

</div>

## Introduction

LocalVocal lets you transcribe, locally on your machine, speech into text and simultaneously translate to any language. ✅ No GPU required, ✅ no cloud costs, ✅ no network and ✅ no downtime! Privacy first - all data stays on your machine.

The plugin runs [OpenAI's Whisper](https://github.com/openai/whisper) to process real-time speech and predict a transcription, utilizing [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) from [ggerganov](https://github.com/ggerganov) to run the model efficiently on CPUs and GPUs. Translation is done with [CTranslate2](https://github.com/OpenNMT/CTranslate2).

## Usage

<p align="center">
  <a href="https://youtu.be/ns4cP9HFTxQ" target="_blank">
    <img width="30%" src="https://github.com/user-attachments/assets/79ce3db6-b35f-4181-85d0-6c473b931418" />
  </a>&nbsp;
  <a href="https://youtu.be/eTSDcNGsN00" target="_blank">
    <img width="30%" src="https://github.com/user-attachments/assets/4483eb30-98de-4fcd-aa50-d9dbe70060b3" />
  </a>
  &nbsp;
  <a href="https://youtu.be/R04w02qG26o" target="_blank">
    <img width="30%" src="https://github.com/user-attachments/assets/0b995c74-12e8-4216-8519-b26f3d69688f" />
  </a>
  <br/>
  <a href="https://youtu.be/ns4cP9HFTxQ">https://youtu.be/ns4cP9HFTxQ</a>
  <a href="https://youtu.be/eTSDcNGsN00">https://youtu.be/4llyfNi9FGs</a>
  <a href="https://youtu.be/R04w02qG26o">https://youtu.be/R04w02qG26o</a>
</p>

Do more with LocalVocal:
- [RealTime Translation](https://youtu.be/4llyfNi9FGs) 
- [Translate Caption any Application](https://youtu.be/qen7NC8kbEQ)
- [Real-time Translation with DeepL](https://youtu.be/ryWBIEmVka4)
- [Real-time Translation with OpenAI](https://youtu.be/Q34LQsx-nlg)
- [ChatGPT + Text-to-speech](https://youtu.be/4BTmoKr0YMw)
- [POST Captions to YouTube](https://youtu.be/E7HKbO6CP_c)
- [Local LLM Real-time Translation](https://youtu.be/ZMNILPWDkDw)
- [Usage Tutorial](https://youtu.be/5XqTMqpui3Q)

Current Features:
- Transcribe audio to text in real time in 100 languages
- Display captions on screen using text sources
- Send captions to a .txt or .srt file (to read by external sources or video playback) with and without aggregation option
- Sync'ed captions with OBS recording timestamps
- Send captions on a RTMP stream to e.g. YouTube, Twitch
- Bring your own Whisper model (any GGML)
- Translate captions in real time to major languages (with cloud prviders, Whisper built-in translation as well as NMT models)
- CUDA, hipBLAS (AMD ROCm), Apple Arm64, AVX & SSE acceleration support
- Filter out or replace any part of the produced captions
- Partial transcriptions for a streaming-captions experience
- 100s of fine-tuned Whisper models for dozens of languages from HuggingFace

## Download
Check out the [latest releases](https://github.com/locaal-ai/obs-localvocal/releases) for downloads and install instructions.

### Available Versions

LocalVocal is available in multiple versions to cater to different hardware configurations and operating systems. Below is a brief explanation of the different versions you can download:

- **Windows** (please ensure you have the [latest MSVC runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe) installed)
  - **generic**: This version runs on all systems. See [Generic variants](#generic-variants) for more details
  - **NVidia**: This version is optimized for systems with NVIDIA GPUs. See [NVidia optimized variants](#nvidia-optimized-variants) for more details
  - **AMD**: This version is optimized for systems with AMD GPUs. See [AMD optimized variants](#amd-optimized-variants) for more details
- **MacOS**
  - **Intel (x86_64)**: This version is for Mac computers with Intel processors. See [MacOS variants](#mac-os-variants)
  - **Apple Silicon (arm64)**: This version is optimized for Mac computers with Apple Silicon (M1, M2, etc.) processors. See [MacOS variants](#mac-os-variants)
- **Linux x86_64**: This version is for Linux systems with x86_64 architecture.
  - **generic**: This version runs on all systems. See [Generic variants](#generic-variants) for more details
  - **NVidia**: This version is optimized for systems with NVIDIA GPUs. See [NVidia optimized variants](#nvidia-optimized-variants) for more details
  - **AMD**: This version is optimized for systems with AMD GPUs. See [AMD optimized variants](#amd-optimized-variants) for more details

Make sure to download the version that matches your system's hardware and operating system for the best performance.

Whisper backends are now loaded dynamically when the plugin starts, which has 2 major benefits:

* **Better CPU performance and compatibility** - Whisper can automatically select the best CPU backend that works on your system out of all the ones available. This means that the plugin can now make full use of newer CPUs with more features, as well as making it usable on even older hardware than before (prior to v0.5.0 it was assumed that users would have at least AVX2 capable CPUs)
* **More stability** - If a backend is present that cannot be used on your system, either due to unavailable CPU features, missing dependencies, or something else, it will simply not be loaded instead of causing a crash

To ensure the plugin works "out-of-the-box", it is configured by default to use the CPU only (this is also the case for users upgrading from versions older than v0.5.0). This is to avoid immediate crashes on startup if for any reason your GPU cannot be used by one of the Whisper backends (e.g. the Metal backend on Apple just crashes if it is unable to allocate a buffer to load a model into)

If you want to use GPU acceleration, please ensure you go into the plugin settings and select your desired GPU acceleration backend

#### Generic variants

These variants should run well on any system regardless of hardware configuration. They contain the following Whispercpp backends:

* CPU
  * Generic x86_64
  * Generic x86_64 with SSE4.2
  * Sandy Bridge (CPU with SSE4.2, AVX)
  * Haswell (CPU with SSE4.2, AVX, F16C, AVX2, BMI2, FMA)
  * Sky Lake (CPU with SSE4.2, AVX, F16C, AVX2, BMI2, FMA, AVX512)
  * Ice Lake (CPU with SSE4.2, AVX, F16C, AVX2, BMI2, FMA, AVX512, AVX512_VBMI AVX512_VNNI)
  * Alder Lake (CPU with SSE4.2, AVX, F16C, AVX2, BMI2, FMA, AVX_VNNI)
  * Sapphire Rapids (CPU with SSE4.2, AVX, F16C, AVX2, BMI2, FMA, AVX512, AVX512_VBMI AVX512_VNNI, AVX512_BF16, AMX_TITLE, AMX_INT8)
* OpenBLAS - Used in conjunction with a CPU backend to accelerate processing speed
* Vulkan - Standard cross-platform graphics library allowing for GPU accelerated processing on GPUs that aren't supported by CUDA or ROCm. Can also work with integrated GPUs)
  * May need the Vulkan runtime on Windows which can be downloaded at https://sdk.lunarg.com/sdk/download/1.4.328.1/windows/VulkanRT-X64-1.4.328.1-Installer.exe
* OpenCL (currently Linux only) - Industry standard parallel compute library that may be faster than Vulkan on supported GPUs

#### NVidia optimized variants

These variants contain all the backends from the generic variant, plus a CUDA backend that provides accelerated performance on supported NVidia GPUS. If the OpenCL backend is available on your platform, it also uses the CUDA OpenCL library instead of the generic one.

Make sure you have the latest NVidia GPU drivers installed and you will likely also need the [CUDA toolkit v12.8.0](https://developer.nvidia.com/cuda-12-8-0-download-archive) or newer.

If installing on Linux, to avoid installing the entire CUDA toolkit if you don't need it you can just install either the `cuda-runtime-12.8` package to get all the runtime libs and drivers, or the `cuda-libaries-12-8` package to just get the runtime libraries.

#### AMD optimized variants

These variants contain all the backends from the generic variant, plus a hipblas backend using AMD's ROCm framework that accelerates computation on [supported AMD GPUs](https://rocm.docs.amd.com/en/docs-6.4.2/compatibility/compatibility-matrix.html)

Please ensure you have a compatible AMD GPU driver installed

#### Mac OS variants

These variants come with the following backends available:
* CPU
  * The same x86_64 variants as listed in [Generic variants](#generic-variants) for Intel CPUs
  * m1, m2/m3, and m4 variants for ARM CPUs
* Accelerate - Used in conjunction with a CPU backend to accelerate processing speed
* Metal - Uses the system's GPU for accelerated processing
* CoreML - Special backend that uses Apple's CoreML instead of Whisper's normal model processing, running on either the Metal or CPU backends

### Models
The plugin ships with the Tiny.en model, and will autonomously download other Whisper models through a dropdown.
There's also an option to select an external GGML Whisper model file if you have it on disk.

If using CoreML on Apple, it will also automatically download the appropriate CoreML encoder model for your selected model.

Get more models from https://ggml.ggerganov.com/ and [HuggingFace](https://huggingface.co/ggerganov/whisper.cpp/tree/main), follow [the instructions on whisper.cpp](https://github.com/ggerganov/whisper.cpp/tree/master/models) to create your own models or download others such as distilled models.

## Building

The plugin was built and tested on Mac OSX (Intel & Apple silicon), Windows (with and without Nvidia CUDA) and Linux.

Start by cloning this repo to a directory of your choice.

### Mac OSX

Using the CI pipeline scripts, locally you would just call the zsh script, which builds for the architecture specified in $MACOS_ARCH (either `x86_64` or `arm64`).

```sh
$ MACOS_ARCH="x86_64" ./.github/scripts/build-macos -c Release
```

#### Install
The above script should succeed and the plugin files (e.g. `obs-localvocal.plugin`) will reside in the `./release/Release` folder off of the root. Copy the `.plugin` file to the OBS directory e.g. `~/Library/Application Support/obs-studio/plugins`.

To get `.pkg` installer file, run for example
```sh
$ ./.github/scripts/package-macos -c Release
```
(Note that maybe the outputs will be in the `Release` folder and not the `install` folder like `pakage-macos` expects, so you will need to rename the folder from `build_x86_64/Release` to `build_x86_64/install`)

### Linux

#### Using pre-compiled variants

1. Clone the repository and if not using Ubuntu install the development versions of these dependencies using your distribution's package manager:

    * libcurl
    * libsimde
    * libssl
    * icu
    * openblas (preferably the OpenMP variant rather than the pthreads variant)
    * OpenCL
    * Vulkan

    Installing ccache is also recommended if you are likely to be building the plugin multiple times

1. Install rust via [rustup](https://rust-lang.org/tools/install/) (recommended), or your distribution's package manager

1. Set the `ACCELERATION` environment variable to one of `generic`, `nvidia`, or `amd` (defaults to `generic` if unset)

    ```sh
    export ACCELERATION="nvidia"
    ```

1. Then from the repo directory build the plugin by running:

    ```sh
    ./.github/scripts/build-linux
    ```

    If you can't use the CI build script for some reason, you can build the plugin as follows

    ```sh
    cmake -B build_x86_64 --preset linux-x86_64 -DCMAKE_INSTALL_PREFIX=./release
    cmake --build build_x86_64 --target install
    ```

1. Installing

    If using Ubuntu and the plugin was previously installed using a .deb package, copy the results to the standard OBS folders on Ubuntu

    ```sh
    sudo cp -R release/RelWithDebInfo/lib/* /usr/lib/
    sudo cp -R release/RelWithDebInfo/share/* /usr/share/
    ```

    Otherwise, follow the official [OBS plugins guide](https://obsproject.com/kb/plugins-guide) and copy the results to your user plugins folder
    ```sh
    mkdir -p ~/.config/obs-studio/plugins/obs-localvocal/bin/64bit
    cp -R release/RelWithDebInfo/lib/x86_64-linux-gnu/obs-plugins/* ~/.config/obs-studio/plugins/obs-localvocal/bin/64bit/
    mkdir -p ~/.config/obs-studio/plugins/obs-localvocal/data
    cp -R release/RelWithDebInfo/share/obs/obs-plugins/obs-localvocal/* ~/.config/obs-studio/plugins/obs-localvocal/data/
    ```

    Note: The lib path in the release folder varies depending on your Linux distribution (e.g. on Gentoo the plugin libraries are found in `release/RelWithDebInfo/lib64/obs-plugins`) but the destination directory to copy them into will always be the same.

#### Building Whispercpp from source along with the plugin

If you can't use the CI build script for some reason, or simply prefer to build the Whispercpp dependency from source along with the plugin, follow the steps above but build the plugin using the following commands:

```sh
cmake -B build_x86_64 --preset linux-x86_64 -DLINUX_SOURCE_BUILD=ON -DCMAKE_INSTALL_PREFIX=./release
cmake --build build_x86_64 --target install
```

When building from source, the Vulkan and OpenCL development libraries are optional and will only be used in the build if they are installed. Similarly if the CUDA or ROCm toolkits are found, they will also be used and the relevant Whisper backends will be enabled.

The default for a full source build is to build both Whisper and the plugin optimized for the host system. To change this behaviour add one or both of the following options to the CMake configure command (the first of the two):

* to build all CPU backends add `-DWHISPER_DYNAMIC_BACKENDS=ON`
* to build all CUDA kernels add `-DWHISPER_BUILD_ALL_CUDA_ARCHITECTURES=ON`

### Windows

Use the CI scripts again, for example:

```powershell
> .github/scripts/Build-Windows.ps1 -Configuration Release
```

The build should exist in the `./release` folder off the root. You can manually install the files in the OBS directory.

```powershell
> Copy-Item -Recurse -Force "release\Release\*" -Destination "C:\Program Files\obs-studio\"
```

#### AWS Transcribe (optional)

AWS Transcribe streaming support is optional and requires an AWS SDK for C++ install that includes `transcribestreaming` and uses a cURL-based HTTP client (needed for streaming on Windows). Configure CMake with either:

* `-DAWS_SDK_ROOT=C:\path\to\aws-sdk-install-prefix` (contains `include/` and `lib/cmake/`), or
* `-DAWSSDK_DIR=C:\path\to\aws-sdk-install-prefix\lib\cmake\AWSSDK`

If you already have the pre-built OBS dependency bundle downloaded (the build scripts fetch it into `.deps/`), you can also have the Windows build script build the AWS SDK for you:

```powershell
> .github/scripts/Build-Windows.ps1 -Configuration Release -BuildAwsSdk
```

If you bundle a CA file as `roots.pem` alongside the plugin, it will be used; otherwise the system trust store is used.

#### Building with CUDA support on Windows

LocalVocal will now build with CUDA support automatically through a prebuilt binary of Whisper.cpp from https://github.com/locaal-ai/locaal-ai-dep-whispercpp. The CMake scripts will download all necessary files.

To build with cuda add `ACCELERATION` as an environment variable (with `cpu`, `hipblas`, or `cuda`) and build regularly

```powershell
> $env:ACCELERATION="cuda"
> .github/scripts/Build-Windows.ps1 -Configuration Release
```


<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=locaal-ai/obs-localvocal&type=Date&theme=dark" />
  <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=locaal-ai/obs-localvocal&type=Date" />
  <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=locaal-ai/obs-localvocal&type=Date" />
</picture>
