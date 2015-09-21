//
//     Generated by class-dump 3.5 (64 bit).
//
//     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2013 by Steve Nygard.
//

#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSArray, NSDictionary, NSMutableDictionary, NSObject, NSString, SimDeviceNotificationManager, SimServiceConnectionManager;

@interface SimDeviceSet : NSObject <SimDeviceNotifier>
{
    NSString *_setPath;
    NSObject *_devicesQueue;
    NSMutableDictionary *__devicesByUDID;
    NSMutableDictionary *_devicesNotificationRegIDs;
    SimServiceConnectionManager *_connectionManager;
    SimDeviceNotificationManager *_notificationManager;
}

+ (void)resubscribeAllToNotifications;
+ (id)setForSetPath:(id)arg1;
+ (id)defaultSet;
+ (id)defaultSetPath;
@property(retain) SimDeviceNotificationManager *notificationManager; // @synthesize notificationManager=_notificationManager;
@property(retain) SimServiceConnectionManager *connectionManager; // @synthesize connectionManager=_connectionManager;
@property(retain) NSMutableDictionary *devicesNotificationRegIDs; // @synthesize devicesNotificationRegIDs=_devicesNotificationRegIDs;
@property(retain) NSMutableDictionary *_devicesByUDID; // @synthesize _devicesByUDID=__devicesByUDID;
@property(retain) NSObject *devicesQueue; // @synthesize devicesQueue=_devicesQueue;
@property(copy) NSString *setPath; // @synthesize setPath=_setPath;
- (void)handleXPCRequestDeleteDevice:(id)arg1 peer:(id)arg2 device:(id)arg3;
- (void)handleXPCRequestCreateDevice:(id)arg1 peer:(id)arg2;
- (void)handleXPCRequest:(id)arg1 peer:(id)arg2;
- (void)handleXPCNotificationDeviceRemoved:(id)arg1;
- (void)handleXPCNotificationDeviceAdded:(id)arg1;
- (void)handleXPCNotification:(id)arg1;
- (BOOL)deleteDevice:(id)arg1 error:(id *)arg2;
- (void)deleteDeviceAsync:(id)arg1 completionHandler:(void *)arg2;
- (id)createDeviceWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 error:(id *)arg4;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 completionHandler:(void *)arg4;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(void *)arg2;
- (unsigned long long)registerNotificationHandler:(void *)arg1;
- (void)removeDeviceAsync:(id)arg1;
- (void)addDevice:(id)arg1;
- (void)addDeviceAsync:(id)arg1;
- (void)updateDefaultDevices;
- (id)defaultCreatedPlistPath;
@property(readonly, copy) NSArray *availableDevices;
@property(readonly, copy) NSArray *devices;
@property(readonly, copy) NSDictionary *devicesByUDID;
- (id)description;
- (void)dealloc;
- (id)initWithSetPath:(id)arg1;
- (BOOL)subscribeToNotificationsWithError:(id *)arg1;

@end

