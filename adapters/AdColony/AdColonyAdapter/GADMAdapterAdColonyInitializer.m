//
//  Copyright © 2018 Google. All rights reserved.
//

#import "GADMAdapterAdColonyInitializer.h"
#import "GADMAdapterAdColonyHelper.h"

@interface GADMAdapterAdColonyInitializer ()

@property NSSet *configuredZones;
@property NSMutableSet *zonesToBeConfigured;
@property AdColonyAdapterInitState adColonyAdapterInitState;
@property NSArray *callbacks;
@property BOOL hasNewZones;
@property BOOL calledConfigureInLastFiveSeconds;

@end

@implementation GADMAdapterAdColonyInitializer

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static GADMAdapterAdColonyInitializer *instance;
  dispatch_once(&onceToken, ^{
    instance = [[GADMAdapterAdColonyInitializer alloc] init];
  });
  return instance;
}

- (id)init {
  if (self = [super init]) {
    _configuredZones = [NSSet set];
    _zonesToBeConfigured = [NSMutableSet set];
    _callbacks = [NSArray array];
    _adColonyAdapterInitState = INIT_STATE_UNINITIALIZED;
  }
  return self;
}

- (void)initializeAdColonyWithAppId:(NSString *)appId
                              zones:(NSArray *)newZones
                            options:(AdColonyAppOptions *)options
                           callback:(void (^)(NSError *))callback {
  @synchronized(self) {
    if (self.adColonyAdapterInitState == INIT_STATE_INITIALIZING) {
      if (callback) {
        self.callbacks = [self.callbacks arrayByAddingObject:callback];
      }
      return;
    }

    NSSet *newZonesSet;
    if (newZones) {
      newZonesSet = [NSSet setWithArray:newZones];
    }

    _hasNewZones = ![newZonesSet isSubsetOfSet:_configuredZones];

    if (_hasNewZones) {
      [_zonesToBeConfigured setByAddingObjectsFromSet:newZonesSet];
      if (_calledConfigureInLastFiveSeconds) {
        NSError *error = [NSError
            errorWithDomain:@"GADMAdapterAdColonyInitializer"
                       code:0
                   userInfo:@{
                     NSLocalizedDescriptionKey : @"Can't configure a zone within five seconds."
                   }];
        callback(error);
        return;
      } else {
        _adColonyAdapterInitState = INIT_STATE_INITIALIZING;
        [self configureWithAppID:appId zoneIDs:[_zonesToBeConfigured allObjects] options:options];
        [_zonesToBeConfigured removeAllObjects];
      }

    } else {
      if (options) {
        [AdColony setAppOptions:options];
      }

      if (_adColonyAdapterInitState == INIT_STATE_INITIALIZED) {
        if (callback) {
          callback(nil);
        }
      } else if (_adColonyAdapterInitState == INIT_STATE_INITIALIZING) {
        if (callback) {
          [_callbacks arrayByAddingObject:callback];
        }
      }
    }
  }
}

- (void)configureWithAppID:(NSString *)appID
                   zoneIDs:(NSArray *)zoneIDs
                   options:(AdColonyAppOptions *)options {
  GADMAdapterAdColonyInitializer *__weak weakSelf = self;

  NSLogDebug(@"zones: %@", [self.zones allObjects]);
  _calledConfigureInLastFiveSeconds = YES;
  [AdColony
      configureWithAppID:appID
                 zoneIDs:zoneIDs
                 options:options
              completion:^(NSArray<AdColonyZone *> *_Nonnull zones) {
                GADMAdapterAdColonyInitializer *strongSelf = weakSelf;
                @synchronized(strongSelf) {
                  if (zones.count < 1) {
                    strongSelf.adColonyAdapterInitState = INIT_STATE_UNINITIALIZED;
                    NSError *error = [NSError
                        errorWithDomain:@"GADMAdapterAdColonyInitializer"
                                   code:0
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Failed to configure the zoneID."
                               }];
                    for (void (^localCallback)() in strongSelf.callbacks) {
                      localCallback(error);
                    }
                  }

                  strongSelf.adColonyAdapterInitState = INIT_STATE_INITIALIZED;
                  for (void (^localCallback)() in strongSelf.callbacks) {
                    localCallback(nil);
                  }
                  strongSelf.callbacks = [NSArray array];
                }
              }];

  [NSTimer scheduledTimerWithTimeInterval:5.0
                                   target:self
                                 selector:@selector(changeCalledConfigureInLastFiveSeconds:)
                                 userInfo:nil
                                  repeats:NO];
}

- (void)changeCalledConfigureInLastFiveSeconds {
  _calledConfigureInLastFiveSeconds = NO;
}

@end
