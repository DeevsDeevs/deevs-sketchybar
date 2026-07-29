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
  CFDictionarySetValue(description, CFSTR(kAudioAggregateDeviceIsPrivateKey), kCFBooleanTrue);

  AudioDeviceID aggregate = kAudioObjectUnknown;
  OSStatus status = AudioHardwareCreateAggregateDevice(description, &aggregate);

  CFRelease(description);
  CFRelease(sub_devices);
  CFRelease(main_entry);
  CFRelease(loopback_entry);

  if (status != noErr) return kAudioObjectUnknown;
  return aggregate;
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

static void set_output_device_from_arg(const char* arg) {
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
  if (device_uid && loopback_uid) {
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
    fprintf(stderr, "Usage: %s list | set <device-id>\n", argv[0]);
    return 1;
  }

  if (strcmp(argv[1], "list") == 0) {
    print_output_devices();
    return 0;
  }

  if (strcmp(argv[1], "set") == 0 && argc == 3) {
    set_output_device_from_arg(argv[2]);
    return 0;
  }

  fprintf(stderr, "Usage: %s list | set <device-id>\n", argv[0]);
  return 1;
}
