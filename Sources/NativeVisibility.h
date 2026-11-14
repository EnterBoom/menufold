#import <Foundation/Foundation.h>

BOOL MFNativeVisibilityAvailable(void);
void MFActivateVisibility(NSArray<NSString *> *allowedBundles,
    void (^completion)(id assertion, NSError *error));
void MFReleaseVisibility(id assertion);
