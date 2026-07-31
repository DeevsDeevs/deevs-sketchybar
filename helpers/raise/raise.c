#include <Carbon/Carbon.h>

// Raises a terminal window and selects one of its tabs, for the herdr widget.
//
//   raise <pid>              activate that process
//   raise <pid> --tabs       print its tab titles, one per line
//   raise <pid> --tab <n>    activate, then select tab n (1-based)
//
// This exists for speed. The same work through osascript costs ~126ms per call
// and the click needs three of them; going straight at the accessibility API is
// a few milliseconds, which is the difference between a click that feels
// instant and one that does not.

static AXUIElementRef tab_group_of(AXUIElementRef app) {
  AXUIElementRef window = NULL;
  if (AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute,
                                    (CFTypeRef *)&window) != kAXErrorSuccess) {
    CFArrayRef windows = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXWindowsAttribute,
                                      (CFTypeRef *)&windows) != kAXErrorSuccess)
      return NULL;
    if (CFArrayGetCount(windows) == 0) { CFRelease(windows); return NULL; }
    window = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(windows, 0));
    CFRelease(windows);
  }

  CFArrayRef children = NULL;
  AXError err = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute,
                                              (CFTypeRef *)&children);
  CFRelease(window);
  if (err != kAXErrorSuccess) return NULL;

  AXUIElementRef found = NULL;
  for (CFIndex i = 0; i < CFArrayGetCount(children); i++) {
    AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
    CFStringRef role = NULL;
    if (AXUIElementCopyAttributeValue(child, kAXRoleAttribute,
                                      (CFTypeRef *)&role) != kAXErrorSuccess)
      continue;
    bool is_tabs = CFStringCompare(role, kAXTabGroupRole, 0) == kCFCompareEqualTo;
    CFRelease(role);
    if (is_tabs) { found = (AXUIElementRef)CFRetain(child); break; }
  }
  CFRelease(children);
  return found;
}

static CFArrayRef tabs_of(AXUIElementRef app) {
  AXUIElementRef group = tab_group_of(app);
  if (!group) return NULL;
  CFArrayRef tabs = NULL;
  AXUIElementCopyAttributeValue(group, kAXChildrenAttribute, (CFTypeRef *)&tabs);
  CFRelease(group);
  return tabs;
}

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  pid_t pid = (pid_t)atoi(argv[1]);
  if (pid <= 0) return 1;

  AXUIElementRef app = AXUIElementCreateApplication(pid);
  if (!app) return 1;

  if (argc >= 3 && strcmp(argv[2], "--tabs") == 0) {
    CFArrayRef tabs = tabs_of(app);
    if (!tabs) return 1;
    for (CFIndex i = 0; i < CFArrayGetCount(tabs); i++) {
      CFStringRef title = NULL;
      if (AXUIElementCopyAttributeValue((AXUIElementRef)CFArrayGetValueAtIndex(tabs, i),
                                        kAXTitleAttribute,
                                        (CFTypeRef *)&title) != kAXErrorSuccess) {
        printf("\n");
        continue;
      }
      char buf[1024];
      if (CFStringGetCString(title, buf, sizeof(buf), kCFStringEncodingUTF8))
        printf("%s\n", buf);
      else
        printf("\n");
      CFRelease(title);
    }
    CFRelease(tabs);
    CFRelease(app);
    return 0;
  }

  // Frontmost first: selecting a tab in a background app leaves you where you were.
  ProcessSerialNumber psn;
  if (GetProcessForPID(pid, &psn) == noErr)
    SetFrontProcessWithOptions(&psn, kSetFrontProcessFrontWindowOnly);

  if (argc >= 4 && strcmp(argv[2], "--tab") == 0) {
    CFIndex want = (CFIndex)atoi(argv[3]) - 1;
    CFArrayRef tabs = tabs_of(app);
    if (tabs) {
      if (want >= 0 && want < CFArrayGetCount(tabs))
        AXUIElementPerformAction(
            (AXUIElementRef)CFArrayGetValueAtIndex(tabs, want), kAXPressAction);
      CFRelease(tabs);
    }
  }

  // Titles survive tabs being reordered, so the caller caches one of those rather
  // than a position. Exits non-zero when it is gone, which is the signal to go
  // and find the tab again.
  if (argc >= 4 && strcmp(argv[2], "--tab-titled") == 0) {
    CFArrayRef tabs = tabs_of(app);
    if (!tabs) { CFRelease(app); return 1; }
    CFStringRef want = CFStringCreateWithCString(NULL, argv[3], kCFStringEncodingUTF8);
    int rc = 1;
    for (CFIndex i = 0; i < CFArrayGetCount(tabs); i++) {
      AXUIElementRef tab = (AXUIElementRef)CFArrayGetValueAtIndex(tabs, i);
      CFStringRef title = NULL;
      if (AXUIElementCopyAttributeValue(tab, kAXTitleAttribute,
                                        (CFTypeRef *)&title) != kAXErrorSuccess)
        continue;
      bool hit = CFStringCompare(title, want, 0) == kCFCompareEqualTo;
      CFRelease(title);
      if (hit) {
        AXUIElementPerformAction(tab, kAXPressAction);
        rc = 0;
        break;
      }
    }
    CFRelease(want);
    CFRelease(tabs);
    CFRelease(app);
    return rc;
  }

  CFRelease(app);
  return 0;
}
