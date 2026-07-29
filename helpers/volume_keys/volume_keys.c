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
    notify_bar(0);
  } else {
    AudioObjectPropertyAddress address;
    Float32 value = 0;
    UInt32 vsize = sizeof(value);
    if (volume_address(device, &address) &&
        AudioObjectGetPropertyData(device, &address, 0, NULL, &vsize, &value) == noErr) {
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

  // System-defined events carry the media key in data1 (field 149).
  int64_t data1 = CGEventGetIntegerValueField(event, 149);
  int key_code = (int)((data1 & 0xFFFF0000) >> 16);
  int key_flags = (int)(data1 & 0x0000FFFF);
  int key_state = (key_flags & 0xFF00) >> 8;
  bool key_down = (key_state == 0x0A);
  if (!key_down) return NULL; // swallow the release too

  CGEventFlags flags = CGEventGetFlags(event);
  bool fine = (flags & kCGEventFlagMaskShift) && (flags & kCGEventFlagMaskAlternate);

  switch (key_code) {
    case NX_KEYTYPE_SOUND_UP:   adjust_volume(1, fine);  return NULL;
    case NX_KEYTYPE_SOUND_DOWN: adjust_volume(-1, fine); return NULL;
    case NX_KEYTYPE_MUTE:       toggle_mute();           return NULL;
    default:                    return event;
  }
}

int main(void) {
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
