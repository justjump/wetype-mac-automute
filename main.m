#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

/**
 * WeType AutoMute Daemon for macOS
 *
 * Automatically fades out background audio (music, video, etc.) when WeChat Keyboard
 * (or any app) activates voice input / microphone, and smoothly fades back in on release.
 *
 * Designed to fix WeChat Keyboard's failure to mute audio over Bluetooth (AirPods / headphones).
 *
 * Author: LeoCMS Developer / justjump
 * License: MIT
 */

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

static void fastFadeOut(void) {
    int cur = getCurrentVolume();
    if (cur > 0) {
        savedVolume = cur;
    }
    // Fast non-linear 4-step curve (~80ms total)
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
    // Elegant 5-step smooth curve (~150ms total)
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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        savedVolume = getCurrentVolume();
        printf("[wetype-automute] Started. Initial output volume: %d\n", savedVolume);
        fflush(stdout);
        
        while (1) {
            BOOL active = checkAnyInputRunning();
            if (active && !isMuted) {
                isMuted = YES;
                fastFadeOut();
            } else if (!active && isMuted) {
                smoothFadeIn();
                isMuted = NO;
            }
            usleep(25000); // 25ms polling loop (negligible CPU ~0.05%)
        }
    }
    return 0;
}
