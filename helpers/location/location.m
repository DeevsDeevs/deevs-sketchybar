// Prints "<lat> <lon>" for the machine's current location, so the weather chip
// needs no coordinates in config.lua — which is committed to a public repo.
//
// CoreLocation will not talk to a bare binary: authorization is per app bundle,
// so this is built into location.app and the Makefile signs it. With the status
// still undetermined, requestLocation() fails immediately instead of prompting —
// requestWhenInUseAuthorization() has to come first and the answer arrives on
// the delegate, not inline.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

static void emit(const char *text) {
    const char *path = getenv("LOC_OUT");
    FILE *out = path ? fopen(path, "w") : stdout;
    if (!out) out = stdout;
    fputs(text, out);
    if (out != stdout) fclose(out);
}

@interface Locator : NSObject <CLLocationManagerDelegate>
@end

@implementation Locator

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    switch (manager.authorizationStatus) {
        case kCLAuthorizationStatusNotDetermined:
            return; // still waiting on the user
        case kCLAuthorizationStatusRestricted:
        case kCLAuthorizationStatusDenied:
            emit("");
            exit(1);
        default:
            [manager requestLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *fix = locations.lastObject;
    if (!fix) return;
    char line[64];
    snprintf(line, sizeof(line), "%.4f %.4f\n",
             fix.coordinate.latitude, fix.coordinate.longitude);
    emit(line);
    exit(0);
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    emit("");
    exit(1);
}

@end

int main(void) {
    @autoreleasepool {
        if (!CLLocationManager.locationServicesEnabled) {
            emit("");
            return 1;
        }
        CLLocationManager *manager = [CLLocationManager new];
        Locator *delegate = [Locator new];
        manager.delegate = delegate;
        // Kilometre accuracy is plenty for a weather grid point, and it lets
        // CoreLocation answer from its cache instead of waking the GPS/wifi scan.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer;

        if (manager.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
            [manager requestWhenInUseAuthorization];
        } else {
            [manager requestLocation];
        }

        // The prompt is modal and the user may ignore it; never hang a helper the
        // bar is waiting on.
        [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:NO block:^(NSTimer *t) {
            emit("");
            exit(2);
        }];
        [NSRunLoop.currentRunLoop run];
    }
    return 3;
}
