//
//     Generated by class-dump 3.5 (64 bit).
//
//     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2013 by Steve Nygard.
//

#import <Foundation/Foundation.h>

@interface NSError (DVTFoundationClassAdditions)
+ (id)dvt_errorWithDomain:(id)arg1 errorCode:(long long)arg2 message:(id)arg3 recoverySuggestion:(id)arg4 recoveryOptions:(id)arg5 andRecoveryBlock:(CDUnknownBlockType)arg6;
+ (id)dvt_errorWithDomain:(id)arg1 errorCode:(long long)arg2 message:(id)arg3 recoverySuggestion:(id)arg4;
+ (id)dvt_errorWithPOSIXErrorCode:(int)arg1;
+ (id)dvt_errorWithPOSIXErrorCode:(int)arg1 messageFormat:(id)arg2;
+ (id)dvt_errorWithDomain:(id)arg1 errorCode:(int)arg2 messageFormat:(id)arg3;
+ (id)dvt_errorWithDomain:(id)arg1 errorCode:(int)arg2 messageFormat:(id)arg3 arguments:(struct __va_list_tag [1])arg4;
- (BOOL)dvt_hasDomain:(id)arg1 errorCode:(long long)arg2;
- (id)dvt_errorByInjectingUserInfoObjects:(id)arg1;
- (id)dvt_errorByInjectingUserInfoObject:(id)arg1 forKey:(id)arg2;
- (id)dvt_errorBySettingRecoveryOptions:(id)arg1 andRecoveryBlock:(CDUnknownBlockType)arg2;
@end

