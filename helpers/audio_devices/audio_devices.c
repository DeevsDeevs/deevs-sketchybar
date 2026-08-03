// audio_devices — list/switch audio output, with automatic loopback routing.
//
// Picking a device builds (or rebuilds) a private multi-output aggregate that
// contains the chosen device *and* BlackHole, then makes that the default
// output. Sound still comes out of the device you picked, while cava can read
// the same signal from BlackHole — so the sonar keeps working across every
// device switch without ever opening Audio MIDI Setup.
//
// Without BlackHole installed it simply sets the device directly.
//
// Usage: audio_devices list | set <device-id>

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AGGREGATE_UID "com.deevs.sketchybar.output"
#define AGGREGATE_NAME "Sketchybar Output"
#define LOOPBACK_MATCH "BlackHole"

static void fail_with_osstatus(const char* context, OSStatus status) {
  fprintf(stderr, "%s failed: %d\n", context, (int)status);
  exit(1);
}

static CFStringRef copy_device_property_string(AudioDeviceID device_id,
                                               AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address = {
    .mSelector = selector,
    .mScope = kAudioObjectPropertyScopeGlobal,
    .mElement = kAudioObjectPropertyElementMain
  };

  CFStringRef value = NULL;
  UInt32 size = sizeof(value);
  OSStatus status = AudioObjectGetPropertyData(device_id, &address, 0, NULL, &size, &value);
  if (status != noErr) return NULL;
  return value;
}

static CFStringRef copy_device_name(AudioDeviceID device_id) {
  return copy_device_property_string(device_id, kAudioObjectPropertyName);
}

static CFStringRef copy_device_uid(AudioDeviceID device_id) {
  return copy_device_property_string(device_id, kAudioDevicePropertyDeviceUID);
}

static bool device_has_output(AudioDeviceID device_id) {
  AudioObjectPropertyAddress address = {
    .mSelector = kAudioDevicePropertyStreams,
    .mScope = kAudioDevicePropertyScopeOutput,
    .mElement = kAudioObjectPropertyElementWildcard
  };

  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(device_id, &address, 0, NULL, &size);
  return status == noErr && size >= sizeof(AudioStreamID);
}

static AudioDeviceID get_default_output_device(void) {
  AudioObjectPropertyAddress address = {
    .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
    .mScope = kAudioObjectPropertyScopeGlobal,
    .mElement = kAudioObjectPropertyElementMain
  };

  AudioDeviceID device_id = kAudioObjectUnknown;
  UInt32 size = sizeof(device_id);
  OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL,
                                               &size, &device_id);
  if (status != noErr) fail_with_osstatus("reading default output device", status);
  return device_id;
}

static void set_default_device(AudioObjectPropertySelector selector, AudioDeviceID device_id) {
  AudioObjectPropertyAddress address = {
    .mSelector = selector,
    .mScope = kAudioObjectPropertyScopeGlobal,
    .mElement = kAudioObjectPropertyElementMain
  };

  UInt32 size = sizeof(device_id);
  OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL,
                                               size, &device_id);
  if (status != noErr) fail_with_osstatus("setting default device", status);
}

static UInt32 copy_all_devices(AudioDeviceID** out) {
  AudioObjectPropertyAddress address = {
    .mSelector = kAudioHardwarePropertyDevices,
    .mScope = kAudioObjectPropertyScopeGlobal,
    .mElement = kAudioObjectPropertyElementMain
  };

  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size);
  if (status != noErr) fail_with_osstatus("reading audio devices size", status);

  UInt32 count = size / sizeof(AudioDeviceID);
  AudioDeviceID* devices = calloc(count, sizeof(AudioDeviceID));
  if (!devices) exit(1);

  status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices);
  if (status != noErr) {
    free(devices);
    fail_with_osstatus("reading audio devices", status);
  }

  *out = devices;
  return count;
}

static bool device_uid_equals(AudioDeviceID device_id, CFStringRef uid) {
  CFStringRef device_uid = copy_device_uid(device_id);
  if (!device_uid) return false;
  bool equal = CFStringCompare(device_uid, uid, 0) == kCFCompareEqualTo;
  CFRelease(device_uid);
  return equal;
}

static AudioDeviceID find_device_by_uid(CFStringRef uid) {
  AudioDeviceID* devices = NULL;
  UInt32 count = copy_all_devices(&devices);
  AudioDeviceID found = kAudioObjectUnknown;

  for (UInt32 i = 0; i < count && found == kAudioObjectUnknown; ++i) {
    if (device_uid_equals(devices[i], uid)) found = devices[i];
  }

  free(devices);
  return found;
}

// First device whose name contains LOOPBACK_MATCH.
static CFStringRef copy_loopback_uid(void) {
  AudioDeviceID* devices = NULL;
  UInt32 count = copy_all_devices(&devices);
  CFStringRef uid = NULL;

  for (UInt32 i = 0; i < count && !uid; ++i) {
    CFStringRef name = copy_device_name(devices[i]);
    if (!name) continue;
    CFRange match = CFStringFind(name, CFSTR(LOOPBACK_MATCH), 0);
    if (match.location != kCFNotFound) uid = copy_device_uid(devices[i]);
    CFRelease(name);
  }

  free(devices);
  return uid;
}

static AudioDeviceID find_our_aggregate(void) {
  return find_device_by_uid(CFSTR(AGGREGATE_UID));
}

// The device our aggregate is actually playing through (its main sub-device),
// so `list` can highlight what the user really chose.
static AudioDeviceID aggregate_main_device(AudioDeviceID aggregate) {
  CFStringRef uid = copy_device_property_string(aggregate, kAudioAggregateDevicePropertyMainSubDevice);
  if (!uid) return kAudioObjectUnknown;
  AudioDeviceID device = find_device_by_uid(uid);
  CFRelease(uid);
  return device;
}

static void destroy_our_aggregate(void) {
  AudioDeviceID existing = find_our_aggregate();
  if (existing != kAudioObjectUnknown) AudioHardwareDestroyAggregateDevice(existing);
}

static CFDictionaryRef create_subdevice_entry(CFStringRef uid, bool drift) {
  CFMutableDictionaryRef entry = CFDictionaryCreateMutable(kCFAllocatorDefault, 2,
                                                           &kCFTypeDictionaryKeyCallBacks,
                                                           &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(entry, CFSTR(kAudioSubDeviceUIDKey), uid);
  int drift_value = drift ? 1 : 0;
  CFNumberRef drift_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &drift_value);
  CFDictionarySetValue(entry, CFSTR(kAudioSubDeviceDriftCompensationKey), drift_number);
  CFRelease(drift_number);
  return entry;
}

// device + loopback in one stacked (multi-output) aggregate, clocked by device.
static AudioDeviceID create_aggregate(CFStringRef device_uid, CFStringRef loopback_uid) {
  CFDictionaryRef main_entry = create_subdevice_entry(device_uid, false);
  CFDictionaryRef loopback_entry = create_subdevice_entry(loopback_uid, true);
  const void* entries[] = { main_entry, loopback_entry };
  CFArrayRef sub_devices = CFArrayCreate(kCFAllocatorDefault, entries, 2, &kCFTypeArrayCallBacks);

  CFMutableDictionaryRef description = CFDictionaryCreateMutable(kCFAllocatorDefault, 6,
                                                                 &kCFTypeDictionaryKeyCallBacks,
                                                                 &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceNameKey), CFSTR(AGGREGATE_NAME));
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceUIDKey), CFSTR(AGGREGATE_UID));
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceSubDeviceListKey), sub_devices);
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceMainSubDeviceKey), device_uid);
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceIsStackedKey), kCFBooleanTrue);
  // Not private: a private aggregate dies with this short-lived process.
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceIsPrivateKey), kCFBooleanFalse);

  AudioDeviceID aggregate = kAudioObjectUnknown;
  OSStatus status = AudioHardwareCreateAggregateDevice(description, &aggregate);

  CFRelease(description);
  CFRelease(sub_devices);
  CFRelease(main_entry);
  CFRelease(loopback_entry);

  if (status != noErr) return kAudioObjectUnknown;
  return aggregate;
}

// Aggregates expose no volume, so volume always targets the real device
// underneath — that keeps a working level control while routing is active.
static AudioDeviceID effective_output_device(void) {
  AudioDeviceID current = get_default_output_device();
  AudioDeviceID aggregate = find_our_aggregate();
  if (aggregate != kAudioObjectUnknown && current == aggregate) {
    AudioDeviceID main = aggregate_main_device(aggregate);
    if (main != kAudioObjectUnknown) return main;
  }
  return current;
}

#define MAX_VOLUME_ELEMENTS 8

// A device exposes either one master control or one per channel, and taking the
// first that exists leaves every other channel untouched: this Sony headset has no
// master, so the left channel followed the bar down to 0 while the right stayed at
// 1.0 and kept playing. Always drive them all.
static UInt32 volume_addresses(AudioDeviceID device, AudioObjectPropertyAddress* out) {
  AudioObjectPropertyAddress master = { kAudioDevicePropertyVolumeScalar,
                                        kAudioDevicePropertyScopeOutput,
                                        kAudioObjectPropertyElementMain };
  if (AudioObjectHasProperty(device, &master)) {
    out[0] = master;
    return 1;
  }

  UInt32 count = 0;
  for (AudioObjectPropertyElement channel = 1;
       channel <= MAX_VOLUME_ELEMENTS && count < MAX_VOLUME_ELEMENTS; ++channel) {
    AudioObjectPropertyAddress candidate = { kAudioDevicePropertyVolumeScalar,
                                             kAudioDevicePropertyScopeOutput, channel };
    if (AudioObjectHasProperty(device, &candidate)) out[count++] = candidate;
  }
  return count;
}

// The loudest channel, so a device left unbalanced by something else still reads as
// what you can actually hear rather than as its quietest side.
static Float32 get_volume(AudioDeviceID device) {
  AudioObjectPropertyAddress addresses[MAX_VOLUME_ELEMENTS];
  UInt32 count = volume_addresses(device, addresses);
  Float32 loudest = -1.0f;
  for (UInt32 i = 0; i < count; ++i) {
    Float32 value = 0;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(device, &addresses[i], 0, NULL, &size, &value) == noErr
        && value > loudest) {
      loudest = value;
    }
  }
  return loudest;
}

static void print_volume(void) {
  Float32 value = get_volume(effective_output_device());
  if (value < 0) { printf("--\n"); return; }
  printf("%d\n", (int)(value * 100.0f + 0.5f));
}

// Accepts an absolute level or a relative "+5" / "-5".
static void set_volume(const char* arg) {
  AudioDeviceID device = effective_output_device();
  AudioObjectPropertyAddress addresses[MAX_VOLUME_ELEMENTS];
  UInt32 count = volume_addresses(device, addresses);
  if (count == 0) return;

  long requested = strtol(arg, NULL, 10);
  Float32 target;
  if (arg[0] == '+' || arg[0] == '-') {
    Float32 current = get_volume(device);
    if (current < 0) current = 0;
    target = current + (Float32)requested / 100.0f;
  } else {
    target = (Float32)requested / 100.0f;
  }
  if (target < 0.0f) target = 0.0f;
  if (target > 1.0f) target = 1.0f;

  for (UInt32 i = 0; i < count; ++i) {
    AudioObjectSetPropertyData(device, &addresses[i], 0, NULL, sizeof(target), &target);
  }

  // Unmute when raising from zero, so the level actually becomes audible.
  AudioObjectPropertyAddress mute = { kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput,
                                      kAudioObjectPropertyElementMain };
  if (target > 0.0f && AudioObjectHasProperty(device, &mute)) {
    UInt32 off = 0;
    AudioObjectSetPropertyData(device, &mute, 0, NULL, sizeof(off), &off);
  }
}

static void print_output_devices(void) {
  AudioDeviceID* devices = NULL;
  UInt32 count = copy_all_devices(&devices);

  AudioDeviceID current = get_default_output_device();
  AudioDeviceID aggregate = find_our_aggregate();
  if (aggregate != kAudioObjectUnknown && current == aggregate) {
    AudioDeviceID main = aggregate_main_device(aggregate);
    if (main != kAudioObjectUnknown) current = main;
  }

  CFStringRef loopback_uid = copy_loopback_uid();

  for (UInt32 i = 0; i < count; ++i) {
    AudioDeviceID device_id = devices[i];
    if (!device_has_output(device_id)) continue;
    if (device_id == aggregate) continue;                       // our own plumbing
    if (loopback_uid && device_uid_equals(device_id, loopback_uid)) continue;

    CFStringRef name = copy_device_name(device_id);
    if (!name) continue;

    char buffer[1024];
    if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
      printf("%d\t%u\t%s\n", device_id == current ? 1 : 0, (unsigned int)device_id, buffer);
    }
    CFRelease(name);
  }

  if (loopback_uid) CFRelease(loopback_uid);
  free(devices);
}

static void set_output_device_from_arg(const char* arg, bool route) {
  char* end = NULL;
  unsigned long parsed = strtoul(arg, &end, 10);
  if (!arg[0] || !end || *end != '\0') {
    fprintf(stderr, "invalid device id: %s\n", arg);
    exit(1);
  }

  AudioDeviceID device_id = (AudioDeviceID)parsed;
  CFStringRef device_uid = copy_device_uid(device_id);
  CFStringRef loopback_uid = copy_loopback_uid();

  // Rebuilt every time: the chosen device becomes the aggregate's clock.
  destroy_our_aggregate();

  AudioDeviceID target = device_id;
  if (route && device_uid && loopback_uid) {
    AudioDeviceID aggregate = create_aggregate(device_uid, loopback_uid);
    if (aggregate != kAudioObjectUnknown) target = aggregate;
  }

  set_default_device(kAudioHardwarePropertyDefaultOutputDevice, target);
  set_default_device(kAudioHardwarePropertyDefaultSystemOutputDevice, target);

  if (device_uid) CFRelease(device_uid);
  if (loopback_uid) CFRelease(loopback_uid);
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s list | set <device-id> [--route] | volume [level|+N|-N] | unroute\n", argv[0]);
    return 1;
  }

  if (strcmp(argv[1], "list") == 0) {
    print_output_devices();
    return 0;
  }

  if (strcmp(argv[1], "set") == 0 && argc >= 3) {
    bool route = argc >= 4 && strcmp(argv[3], "--route") == 0;
    set_output_device_from_arg(argv[2], route);
    return 0;
  }

  if (strcmp(argv[1], "volume") == 0) {
    if (argc == 2) print_volume();
    else set_volume(argv[2]);
    return 0;
  }

  if (strcmp(argv[1], "unroute") == 0) {
    AudioDeviceID device = effective_output_device();
    destroy_our_aggregate();
    set_default_device(kAudioHardwarePropertyDefaultOutputDevice, device);
    set_default_device(kAudioHardwarePropertyDefaultSystemOutputDevice, device);
    return 0;
  }

  fprintf(stderr, "Usage: %s list | set <device-id> [--route] | volume [level|+N|-N] | unroute\n", argv[0]);
  return 1;
}
