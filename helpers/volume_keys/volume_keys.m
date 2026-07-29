// volume_keys — makes the F-row volume keys work while output is routed.
//
// macOS gives aggregate devices no hardware volume, so when sonar routing is
// active the volume/mute keys do nothing. This taps those key events and
// applies them to the *real* device underneath the aggregate instead.
//
// The tap only swallows a key while our aggregate is the default output;
// otherwise the event passes straight through and macOS behaves normally
// (including its own volume HUD). Needs Accessibility, which it inherits from
// sketchybar when spawned by it.

#import <Foundation/Foundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <CoreAudio/CoreAudio.h>
#include <IOKit/hidsystem/ev_keymap.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AGGREGATE_UID "com.deevs.sketchybar.output"
#define VOLUME_STEP (1.0f / 16.0f)

static CFStringRef copy_device_string(AudioDeviceID device, AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address = { selector, kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
  CFStringRef value = NULL;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value) != noErr) return NULL;
  return value;
}

static AudioDeviceID default_output(void) {
  AudioObjectPropertyAddress address = { kAudioHardwarePropertyDefaultOutputDevice,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
  AudioDeviceID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
  return device;
}

static AudioDeviceID find_by_uid(CFStringRef uid) {
  AudioObjectPropertyAddress address = { kAudioHardwarePropertyDevices,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr)
    return kAudioObjectUnknown;

  UInt32 count = size / sizeof(AudioDeviceID);
  AudioDeviceID* devices = calloc(count, sizeof(AudioDeviceID));
  if (!devices) return kAudioObjectUnknown;
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) != noErr) {
    free(devices);
    return kAudioObjectUnknown;
  }

  AudioDeviceID found = kAudioObjectUnknown;
  for (UInt32 i = 0; i < count && found == kAudioObjectUnknown; ++i) {
    CFStringRef device_uid = copy_device_string(devices[i], kAudioDevicePropertyDeviceUID);
    if (!device_uid) continue;
    if (CFStringCompare(device_uid, uid, 0) == kCFCompareEqualTo) found = devices[i];
    CFRelease(device_uid);
  }
  free(devices);
  return found;
}

// Real device to act on: the aggregate's main sub-device when routed.
static AudioDeviceID target_device(bool* routed) {
  AudioDeviceID current = default_output();
  AudioDeviceID aggregate = find_by_uid(CFSTR(AGGREGATE_UID));
  *routed = (aggregate != kAudioObjectUnknown && current == aggregate);
  if (!*routed) return current;

  CFStringRef main_uid = copy_device_string(aggregate, kAudioAggregateDevicePropertyMainSubDevice);
  if (!main_uid) return current;
  AudioDeviceID main = find_by_uid(main_uid);
  CFRelease(main_uid);
  return main != kAudioObjectUnknown ? main : current;
}

static bool volume_address(AudioDeviceID device, AudioObjectPropertyAddress* address) {
  const AudioObjectPropertyAddress candidates[3] = {
    { kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain },
    { kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1 },
    { kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 2 },
  };
  for (int i = 0; i < 3; ++i) {
    if (AudioObjectHasProperty(device, &candidates[i])) {
      *address = candidates[i];
      return true;
    }
  }
  return false;
}

// macOS draws its volume HUD from a private XPC service. Since we consume the
// key event, we ask that service to show the same HUD ourselves, so the
// feedback stays exactly what the system would have shown.
@protocol OSDUIHelperProtocol
- (void)showImage:(int)image
      onDisplayID:(CGDirectDisplayID)display
         priority:(unsigned int)priority
    msecUntilFade:(unsigned int)msec
   filledChiclets:(unsigned int)filled
    totalChiclets:(unsigned int)total
           locked:(BOOL)locked;
@end

#define OSD_IMAGE_VOLUME 3
#define OSD_IMAGE_MUTED 4
#define OSD_CHICLETS 16

static id osd_proxy(void) {
  static id proxy = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSXPCConnection* connection =
        [[NSXPCConnection alloc] initWithMachServiceName:@"com.apple.OSDUIHelper" options:0];
    connection.remoteObjectInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(OSDUIHelperProtocol)];
    [connection resume];
    proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError* error) { (void)error; }];
  });
  return proxy;
}

static void show_osd(float level, bool muted) {
  id<OSDUIHelperProtocol> proxy = osd_proxy();
  if (!proxy) return;
  unsigned int filled = (unsigned int)(level * OSD_CHICLETS + 0.5f);
  [proxy showImage:(muted ? OSD_IMAGE_MUTED : OSD_IMAGE_VOLUME)
       onDisplayID:CGMainDisplayID()
          priority:0x1f4
     msecUntilFade:1000
    filledChiclets:muted ? 0 : filled
     totalChiclets:OSD_CHICLETS
            locked:NO];
}

static void notify_bar(int percent) {
  char command[128];
  snprintf(command, sizeof(command),
           "sketchybar --trigger volume_change INFO=%d >/dev/null 2>&1 &", percent);
  system(command);
}

static void adjust_volume(int direction, bool fine) {
  bool routed = false;
  AudioDeviceID device = target_device(&routed);
  AudioObjectPropertyAddress address;
  if (device == kAudioObjectUnknown || !volume_address(device, &address)) return;

  Float32 value = 0;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value) != noErr) return;

  Float32 step = fine ? VOLUME_STEP / 4.0f : VOLUME_STEP;
  value += step * (Float32)direction;
  if (value < 0.0f) value = 0.0f;
  if (value > 1.0f) value = 1.0f;
  AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(value), &value);

  AudioObjectPropertyAddress mute = { kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput,
                                      kAudioObjectPropertyElementMain };
  if (value > 0.0f && AudioObjectHasProperty(device, &mute)) {
    UInt32 off = 0;
    AudioObjectSetPropertyData(device, &mute, 0, NULL, sizeof(off), &off);
  }

  show_osd(value, false);
  notify_bar((int)(value * 100.0f + 0.5f));
}

static void toggle_mute(void) {
  bool routed = false;
  AudioDeviceID device = target_device(&routed);
  AudioObjectPropertyAddress mute = { kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput,
                                      kAudioObjectPropertyElementMain };
  if (device == kAudioObjectUnknown || !AudioObjectHasProperty(device, &mute)) return;

  UInt32 muted = 0;
  UInt32 size = sizeof(muted);
  if (AudioObjectGetPropertyData(device, &mute, 0, NULL, &size, &muted) != noErr) return;
  muted = muted ? 0 : 1;
  AudioObjectSetPropertyData(device, &mute, 0, NULL, sizeof(muted), &muted);

  if (muted) {
    show_osd(0.0f, true);
    notify_bar(0);
  } else {
    AudioObjectPropertyAddress address;
    Float32 value = 0;
    UInt32 vsize = sizeof(value);
    if (volume_address(device, &address) &&
        AudioObjectGetPropertyData(device, &address, 0, NULL, &vsize, &value) == noErr) {
      show_osd(value, false);
      notify_bar((int)(value * 100.0f + 0.5f));
    }
  }
}

static CGEventRef on_event(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* context) {
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    CGEventTapEnable((CFMachPortRef)context, true);
    return event;
  }
  if (type != NX_SYSDEFINED) return event;

  // Only meddle while our aggregate is the output; otherwise macOS handles it.
  bool routed = false;
  target_device(&routed);
  if (!routed) return event;

  // Only aux-control events (the F-row media keys) carry a key in data1.
  if (CGEventGetIntegerValueField(event, 151) != NX_SUBTYPE_AUX_CONTROL_BUTTONS) return event;

  int64_t data1 = CGEventGetIntegerValueField(event, 149);
  int key_code = (int)((data1 & 0xFFFF0000) >> 16);

  // Decide on the key FIRST: everything that is not a volume key — brightness,
  // playback, mission control, keyboard backlight — must pass through
  // untouched, presses and releases alike.
  if (key_code != NX_KEYTYPE_SOUND_UP && key_code != NX_KEYTYPE_SOUND_DOWN
      && key_code != NX_KEYTYPE_MUTE) {
    return event;
  }

  int key_flags = (int)(data1 & 0x0000FFFF);
  bool key_down = ((key_flags & 0xFF00) >> 8) == 0x0A;
  if (!key_down) return NULL; // swallow the matching release

  CGEventFlags flags = CGEventGetFlags(event);
  bool fine = (flags & kCGEventFlagMaskShift) && (flags & kCGEventFlagMaskAlternate);

  switch (key_code) {
    case NX_KEYTYPE_SOUND_UP:   adjust_volume(1, fine);  break;
    case NX_KEYTYPE_SOUND_DOWN: adjust_volume(-1, fine); break;
    case NX_KEYTYPE_MUTE:       toggle_mute();           break;
  }
  return NULL;
}

int main(int argc, char** argv) {
  if (argc > 1 && strcmp(argv[1], "--test-osd") == 0) {
    show_osd(0.5f, false);
    [NSThread sleepForTimeInterval:1.5];
    return 0;
  }

  CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                       kCGEventTapOptionDefault,
                                       CGEventMaskBit(NX_SYSDEFINED), on_event, NULL);
  if (!tap) {
    fprintf(stderr, "event tap failed (needs Accessibility)\n");
    return 1;
  }
  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
  CGEventTapEnable(tap, true);
  CFRunLoopRun();
  return 0;
}
