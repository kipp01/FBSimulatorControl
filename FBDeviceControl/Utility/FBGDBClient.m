/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBGDBClient.h"

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

// We can replicate what Xcode does by logging the lldb output by setting in ~/.lldbinit `log enable -f /tmp/gdb_remote_packets.log gdb-remote packets`

static NSString *const Terminator = @"#";

static char fromHex(unichar c1, unichar c2)
{
  int value = 0;
  if (c1 <= '9') {
    value = c1 - '0';
  } else {
    value = c1 - 'a' + 10;
  }
  value <<= 4;
  if (c2 <= '9') {
    value |= c2 - '0';
  } else {
    value |= c2 - 'a' + 10;
  }
  return (char) value;
}

static NSData *wrapCommandInSums(NSString *input)
{
  NSInteger checksum = 0;
  for (NSUInteger index = 0; index < input.length; index++) {
    checksum += [input characterAtIndex:index];
  }
  NSString *output = [NSString stringWithFormat:@"$%@#%02lx", input, (checksum & 0xff)];
  return [output dataUsingEncoding:NSASCIIStringEncoding];
}

static NSString *hexEncode(NSString *input)
{
  NSMutableString *output = [NSMutableString string];
  for (NSUInteger index = 0; index < input.length; index++) {
    unichar character = [input characterAtIndex:index];
    [output appendFormat:@"%02x", character];
  }
  return output;
}

static NSString *hexDecode(NSString *input)
{
  NSMutableString *output = [NSMutableString string];
  for (NSUInteger index = 0; index < (input.length / 2); index++) {
    char character = fromHex([input characterAtIndex:(index * 2)], [input characterAtIndex:((index * 2) +1 )]);
    [output appendFormat:@"%c", character];
  }
  return output;
}

static NSString *launchStringWithArguments(NSArray<NSString *> *arguments)
{
  NSMutableString *string = [NSMutableString stringWithString:@"A"];
  for (NSUInteger index = 0; index < arguments.count; index++) {
    NSString *argument = arguments[index];
    NSString *hex = hexEncode(argument);
    [string appendFormat:@"%lu,%lu,%@", (unsigned long)hex.length, (unsigned long)index, hex];
  }
  return string;
}

static NSArray<NSString *> *environmentCommands(NSDictionary<NSString *, NSString *> *environment)
{
  NSMutableArray<NSString *> *commands = [NSMutableArray array];
  for (NSString *key in environment) {
    NSString *value = environment[key];
    [commands addObject:[NSString stringWithFormat:@"QEnvironment:%@=%@", key, value]];
  }
  return commands;
}

static NSString *trimResponse(NSString *response)
{
  NSError *error = NULL;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9a-f$\\+]" options:NSRegularExpressionAnchorsMatchLines error:&error];
  NSCAssert(regex, @"Could not create regex %@", error);
  return [regex stringByReplacingMatchesInString:response options:NSMatchingAnchored range:NSMakeRange(0, response.length) withTemplate:@""];
}

static NSDictionary<NSString *, NSString *> *keyValuePairs(NSString *response)
{
  NSArray<NSString *> *pairs = [response componentsSeparatedByString:@";"];
  NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];
  for (NSString *pair in pairs) {
    NSArray<NSString *> *tuple = [pair componentsSeparatedByString:@":"];
    if (tuple.count < 2) {
      continue;
    }
    NSString *key = tuple[0];
    NSString *value = tuple[1];
    dictionary[key] = value;
  }
  return dictionary;
}

static NSNumber *processIdentifierFromResponse(NSString *response, NSError **error)
{
  NSDictionary<NSString *, NSString *> *pairs = keyValuePairs(response);
  NSString *pidHex = pairs[@"pid"];
  if (!pidHex) {
    return [[FBDeviceControlError
      describeFormat:@"Could not obtain pid from %@", response]
      fail:error];
  }
  NSScanner *scanner = [NSScanner scannerWithString:pidHex];
  unsigned int value = 0;
  if (![scanner scanHexInt:&value])
  {
    return [[FBDeviceControlError
      describeFormat:@"Could not coerce %@ from a hex int", pidHex]
      fail:error];
  }

  return @(value);
}

@interface FBGDBClient () <FBDataConsumer>

@property (nonatomic, strong, readonly) id<FBDataConsumer> writer;
@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) id<FBConsumableBuffer> buffer;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *exitCodeFuture;

@property (nonatomic, strong, nullable, readonly) id<FBDataConsumer> stdoutConsumer;
@property (nonatomic, strong, nullable, readonly) id<FBDataConsumer> stderrConsumer;

@end

@implementation FBGDBClient

#pragma mark Initializers

+ (FBFuture<FBGDBClient *> *)clientForServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:connection.socket closeOnDealloc:NO];
  id<FBDataConsumer> writer = [FBFileWriter asyncWriterWithFileHandle:fileHandle error:&error];
  if (!writer) {
    return [FBFuture futureWithError:error];
  }
  id<FBConsumableBuffer> outputBuffer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer> output = [FBCompositeDataConsumer consumerWithConsumers:@[
    outputBuffer,
    [FBLoggingDataConsumer consumerWithLogger:[logger withName:@"RECV"]],
  ]];
  FBFileReader *reader = [FBFileReader readerWithFileHandle:fileHandle consumer:output logger:nil];
  return [[reader
    startReading]
    onQueue:queue map:^(id _) {
      return [[self alloc] initWithWriter:writer reader:reader buffer:outputBuffer queue:queue logger:logger];
    }];
}


- (instancetype)initWithWriter:(id<FBDataConsumer>)writer reader:(FBFileReader *)reader buffer:(id<FBConsumableBuffer>)buffer queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writer = writer;
  _reader = reader;
  _buffer = buffer;
  _queue = queue;
  _logger = logger;
  _exitCodeFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)sendEnvironment:(NSDictionary<NSString *, NSString *> *)environment
{
  return [self sendMultiUntilOK:environmentCommands(environment)];
}

- (FBFuture<NSNull *> *)sendArguments:(NSArray<NSString *> *)arguments
{
  return [self sendUntilOK:launchStringWithArguments(arguments)];
}

- (FBFuture<NSNumber *> *)processInfo
{
  return [[self
    sendAndGetResponse:@"qProcessInfo"]
    onQueue:self.queue fmap:^(NSString *response) {
      NSError *error = nil;
      NSNumber *pid = processIdentifierFromResponse(response, &error);
      if (!pid) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:pid];
    }];
}

- (FBFuture<NSNull *> *)noAckMode
{
  NSData *ack = [@"+" dataUsingEncoding:NSASCIIStringEncoding];
  [self _sendRaw:ack];
  return [[self
    sendUntilOK:@"QStartNoAckMode"]
    onQueue:self.queue map:^(id _) {
      [self _sendRaw:ack];
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)launchSuccess
{
  return [self sendUntilOK:@"qLaunchSuccess"];
}

- (void)sendContinue
{
  return [self sendNow:@"c"];
}

- (FBFuture<NSNull *> *)consumeStdOut:(id<FBDataConsumer>)stdOut stdErr:(id<FBDataConsumer>)stdErr
{
  return [FBFuture onQueue:self.queue resolveValue:^(NSError **error) {
    return [self.buffer consume:self onQueue:self.queue untilTerminal:[Terminator dataUsingEncoding:NSASCIIStringEncoding] error:error] ? NSNull.null : nil;
  }];
}

- (FBFuture<NSNumber *> *)exitCode
{
  return self.exitCodeFuture;
}

+ (NSString *)hexDecode:(NSString *)input
{
  return hexDecode(input);
}

+ (NSString *)hexEncode:(NSString *)input
{
  return hexEncode(input);
}

#pragma mark Private

- (FBFuture<NSNull *> *)sendUntilOK:(NSString *)command
{
  return [[self
    sendAndGetResponse:command]
    onQueue:self.queue fmap:^(NSString *response) {
      if (![response isEqualToString:@"OK"]) {
        return [[FBDeviceControlError
          describeFormat:@"Response '%@' is not equal to 'OK'", response]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSString *> *)sendAndGetResponse:(NSString *)command
{
  [self sendNow:command];
  return [[self.buffer
    consumeAndNotifyWhen:[Terminator dataUsingEncoding:NSASCIIStringEncoding]]
    onQueue:self.queue map:^(NSData *data) {
      NSString *response = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
      return trimResponse(response);
    }];
}

- (FBFuture<NSNull *> *)sendMultiUntilOK:(NSArray<NSString *> *)commands
{
  if (commands.count == 0) {
    return [FBFuture futureWithResult:NSNull.null];
  }
  NSString *command = [commands firstObject];
  return [[self
    sendUntilOK:command]
    onQueue:self.queue fmap:^(id _) {
      NSArray<NSString *> *next = [commands subarrayWithRange:NSMakeRange(1, commands.count - 1)];
      return [self sendMultiUntilOK:next];
    }];
}

- (void)sendNow:(NSString *)command
{
  [self.logger logFormat:@"SEND: %@", command];
  [self _sendRaw:wrapCommandInSums(command)];
}

- (void)_sendRaw:(NSData *)data
{
  [self.writer consumeData:data];
}

#pragma mark FBDataConsumer Implementation

- (void)consumeData:(NSData *)data
{
  NSString *packet = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
  NSScanner *scanner = [NSScanner scannerWithString:packet];
  if (![scanner scanUpToString:@"$" intoString:nil] || ![scanner scanString:@"$" intoString:nil]) {
    return;
  }
  if ([scanner scanString:@"O" intoString:nil]) {
    NSString *output = hexDecode([scanner.string substringFromIndex:scanner.scanLocation]);
    NSData *payload = [output dataUsingEncoding:NSUTF8StringEncoding];
    [self.stdoutConsumer consumeData:payload];
  } else if ([scanner scanString:@"W" intoString:nil]) {
    unsigned int signal = 0;
    [scanner scanHexInt:&signal];
    [self.exitCodeFuture resolveWithResult:@(signal)];
  }
}

- (void)consumeEndOfFile
{

}

@end
