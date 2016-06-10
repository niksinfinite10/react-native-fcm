#import "RNFIRMessaging.h"

#import "RCTBridge.h"
#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTUtils.h"
@import Photos;
@import FirebaseMessaging;

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

#define UIUserNotificationTypeAlert UIRemoteNotificationTypeAlert
#define UIUserNotificationTypeBadge UIRemoteNotificationTypeBadge
#define UIUserNotificationTypeSound UIRemoteNotificationTypeSound
#define UIUserNotificationTypeNone  UIRemoteNotificationTypeNone
#define UIUserNotificationType      UIRemoteNotificationType

#endif


NSString *const FCMNotificationReceived = @"FCMNotificationReceived";


@implementation RNFIRMessaging

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (NSDictionary<NSString *, id> *)constantsToExport
{
  NSDictionary<NSString *, id> *initialNotification = [_bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] copy];
  
  NSString *initialAction = [[initialNotification objectForKey:@"aps"] objectForKey:@"category"];
  return @{@"initialData": RCTNullIfNil(initialNotification), @"initialAction": RCTNullIfNil(initialAction)};
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationReceived:)
                                               name:FCMNotificationReceived
                                             object:nil];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(disconnectFCM)
                                               name:UIApplicationDidEnterBackgroundNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(connectToFCM)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(onTokenRefresh)
   name:kFIRInstanceIDTokenRefreshNotification object:nil];

}

- (void)connectToFCM
{
  [[FIRMessaging messaging] connectWithCompletion:^(NSError * _Nullable error) {
    if (error != nil) {
      NSLog(@"Unable to connect to FCM. %@", error);
    } else {
      NSLog(@"Connected to FCM.");
    }
  }];
}

- (void)disconnectFCM
{
  [[FIRMessaging messaging] disconnect];
  NSLog(@"Disconnected from FCM");
}

RCT_REMAP_METHOD(getFCMToken,
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  resolve([[FIRInstanceID instanceID] token]);
}

- (void) onTokenRefresh
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"FCMTokenRefreshed" body:[[FIRInstanceID instanceID] token]];
}

RCT_EXPORT_METHOD(requestPermissions)
{
    if (RCTRunningInAppExtension()) {
        return;
    }
    
    UIUserNotificationType types = UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
    
    UIApplication *app = RCTSharedApplication();
    if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *notificationSettings =
        [UIUserNotificationSettings settingsForTypes:(NSUInteger)types categories:nil];
        [app registerUserNotificationSettings:notificationSettings];
    } else {
        [app registerForRemoteNotificationTypes:(NSUInteger)types];
    }
}

RCT_REMAP_METHOD(UploadFileToFirebase,
                 : (NSString*) localFile
                 : (NSString*) contentType
                 : (NSString*) bucket
                 : (NSString*) key
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
  NSURL *url = [[NSURL alloc] initWithString:localFile];
  PHFetchResult* assets = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil];
  PHAsset *asset = [assets firstObject];
  [asset requestContentEditingInputWithOptions:nil
                             completionHandler:^(PHContentEditingInput *contentEditingInput,
                                                 NSDictionary *info) {
                               NSURL *imageFile = contentEditingInput.fullSizeImageURL;
                               

  FIRStorage *storage = [FIRStorage storage];
  // Create a storage reference from our storage service
  FIRStorageReference *storageRef = [storage referenceForURL:bucket];

  
  // Create a reference to the file you want to upload
  //NSString *storageLocation = [@"images/" stringByAppendingString:key];
  FIRStorageReference *riversRef = [storageRef child:key];
  
  // Upload the file to the path "images/rivers.jpg"
  FIRStorageUploadTask *uploadTask = [riversRef putFile:imageFile metadata:nil completion:^(FIRStorageMetadata *metadata, NSError *error) {
    if (error != nil) {
      // Uh-oh, an error occurred!
      NSLog(@"Error in Uploading File to Firebase", error);
      reject(@"Error", @"Failed upload file to firebase", error);
    } else {
      // Metadata contains file metadata such as size, content-type, and download URL.
      NSURL *downloadURL = metadata.downloadURL;
      NSLog(@"Successfully uploaded File to Firebase", metadata);
      resolve(@ {@"downloadURL": downloadURL});
    }
  }];
  
  FIRStorageHandle observer = [uploadTask observeStatus:FIRStorageTaskStatusProgress
                                                handler:^(FIRStorageTaskSnapshot *snapshot) {
                                                  
                                                  float progress = (float) snapshot.progress.totalUnitCount / snapshot.progress.completedUnitCount;
                                                  [self.bridge.eventDispatcher sendAppEventWithName:@"FirebaseUploadProgressChanged" body: @{ @"progress": [NSNumber numberWithFloat:progress], @"key": key}];
                                                  
                                                }];
                             }];
  
}


RCT_EXPORT_METHOD(subscribeToTopic: (NSString*) topic)
{
  [[FIRMessaging messaging] subscribeToTopic:topic];
}

RCT_EXPORT_METHOD(unsubscribeFromTopic: (NSString*) topic)
{
  [[FIRMessaging messaging] unsubscribeFromTopic:topic];
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:FCMNotificationReceived
                                              body:notification.userInfo];
}

@end
