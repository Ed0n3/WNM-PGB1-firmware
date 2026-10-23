#include <rtaudio/rtaudio_c.h>
#include <stdio.h>
#include <stddef.h>

// Use the C interface to support current RtAudio releases and avoid sharing
// C++ objects across the compiler and the Windows library distribution.
static rtaudio_t audio = NULL;
void wnm_rtaudio_callback(void *outbuf, unsigned int frames);

static int callback(void *outbuf, void *, unsigned int frames, double,
                    rtaudio_stream_status_t, void *) {
    wnm_rtaudio_callback(outbuf, frames);
    return 0;
}

int wnm_rtaudio_cleanup(void) {
    if (audio) {
        if (rtaudio_is_stream_running(audio)) rtaudio_stop_stream(audio);
        if (rtaudio_is_stream_open(audio)) rtaudio_close_stream(audio);
        rtaudio_destroy(audio);
        audio = NULL;
    }
    return 0;
}

int wnm_rtaudio_init(unsigned int sample_rate, unsigned int frames) {
    wnm_rtaudio_cleanup();
#if _WIN32
    const rtaudio_api_t api = RTAUDIO_API_WINDOWS_WASAPI;
#elif __MACH__
    const rtaudio_api_t api = RTAUDIO_API_MACOSX_CORE;
#else
    const rtaudio_api_t api = RTAUDIO_API_LINUX_PULSE;
#endif
    audio = rtaudio_create(api);
    if (!audio || rtaudio_device_count(audio) == 0) {
        wnm_rtaudio_cleanup();
        return 1;
    }
    rtaudio_stream_parameters_t output = {0};
    output.device_id = rtaudio_get_default_output_device(audio);
    output.num_channels = 2;
    if (rtaudio_open_stream(audio, &output, NULL, RTAUDIO_FORMAT_SINT16,
                            sample_rate, &frames, callback, NULL, NULL,
                            NULL) != 0 || rtaudio_start_stream(audio) != 0) {
        fprintf(stderr, "RtAudio: %s\n", rtaudio_error(audio));
        wnm_rtaudio_cleanup();
        return 1;
    }
    return 0;
}
