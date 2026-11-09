#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, void (^completion)(BOOL isPlaying));

static BOOL isMuted = NO;
static int savedVolume = 40;

static int getCurrentVolume(void) {
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:@"output volume of (get volume settings)"];
    NSAppleEventDescriptor *desc = [as executeAndReturnError:nil];
    if (desc) {
        return (int)[desc int32Value];
    }
    return 40;
}

static void setVolume(int vol) {
    NSString *cmd = [NSString stringWithFormat:@"set volume output volume %d", vol];
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:cmd];
    [as executeAndReturnError:nil];
}

static BOOL isMediaPlaying(void) {
    __block int result = -1;
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(BOOL isPlaying) {
        result = isPlaying ? 1 : 0;
    });
    
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:0.04];
    while (result == -1 && [timeout timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:timeout];
    }
    return (result == 1);
}

static void fastFadeOut(void) {
    int cur = getCurrentVolume();
    if (cur > 0) {
        savedVolume = cur;
    }
    int step1 = (int)(savedVolume * 0.65);
    int step2 = (int)(savedVolume * 0.35);
    int step3 = (int)(savedVolume * 0.10);
    
    setVolume(step1);
    usleep(18000);
    setVolume(step2);
    usleep(18000);
    setVolume(step3);
    usleep(18000);
    setVolume(0);
}

static void smoothFadeIn(void) {
    int target = savedVolume > 5 ? savedVolume : 40;
    int step1 = (int)(target * 0.15);
    int step2 = (int)(target * 0.40);
    int step3 = (int)(target * 0.65);
    int step4 = (int)(target * 0.85);
    
    setVolume(step1);
    usleep(25000);
    setVolume(step2);
    usleep(25000);
    setVolume(step3);
    usleep(25000);
    setVolume(step4);
    usleep(25000);
    setVolume(target);
}

static BOOL checkAnyInputRunning(void) {
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus err = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size);
    if (err != noErr) return NO;
    
    UInt32 count = size / sizeof(AudioDeviceID);
    AudioDeviceID devices[count];
    err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, devices);
    if (err != noErr) return NO;
    
    for (UInt32 i = 0; i < count; i++) {
        AudioDeviceID dev = devices[i];
        
        AudioObjectPropertyAddress stmAddr = {
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeInput,
            kAudioObjectPropertyElementMain
        };
        UInt32 stmSize = 0;
        AudioObjectGetPropertyDataSize(dev, &stmAddr, 0, NULL, &stmSize);
        if (stmSize > 0) {
            AudioObjectPropertyAddress runAddr = {
                kAudioDevicePropertyDeviceIsRunningSomewhere,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            UInt32 isRunning = 0;
            UInt32 rSize = sizeof(isRunning);
            AudioObjectGetPropertyData(dev, &runAddr, 0, NULL, &rSize, &isRunning);
            if (isRunning != 0) {
                return YES;
            }
        }
    }
    return NO;
}

int main() {
    @autoreleasepool {
        savedVolume = getCurrentVolume();
        while (1) {
            BOOL active = checkAnyInputRunning();
            if (active && !isMuted) {
                // Check if any media (music/video) is actually playing right now
                if (isMediaPlaying()) {
                    isMuted = YES;
                    fastFadeOut();
                }
            } else if (!active && isMuted) {
                smoothFadeIn();
                isMuted = NO;
            }
            usleep(25000); // 25ms polling
        }
    }
    return 0;
}
