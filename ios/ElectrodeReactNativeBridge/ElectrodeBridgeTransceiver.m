//
//  ElectrodeBridgeTransceiver.m
//  ElectrodeReactNativeBridge
//
//  Created by Claire Weijie Li on 3/22/17.
//  Copyright © 2017 Walmart. All rights reserved.
//

#import "ElectrodeBridgeTransceiver.h"
#import "ElectrodeBridgeTransceiver_Internal.h"
#import "ElectrodeEventDispatcher.h"
#import "ElectrodeRequestDispatcher.h"
#import "ElectrodeBridgeTransaction.h"
#import "ElectrodeEventRegistrar.h"
#import "ElectrodeRequestRegistrar.h"


#if __has_include(<React/RCTLog.h>)
#import <React/RCTLog.h>
#elif __has_include("RCTLog.h")
#import "RCTLog.h"
#else
#import "React/RCTLog.h"   // Required when used as a Pod in a Swift project
#endif

#if __has_include(<React/RCTBridge.h>)
#import <React/RCTBridge.h>
#elif __has_include("RCTBridge.h")
#import "RCTBridge.h"
#else
#import "React/RCTBridge.h"   // Required when used as a Pod in a Swift project
#endif


#import "ElectrodeBridgeMessage.h"
#import "ElectrodeBridgeEvent.h"

NS_ASSUME_NONNULL_BEGIN

@interface ElectrodeBridgeTransceiver()

@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) ElectrodeEventDispatcher *eventDispatcher;
@property(nonatomic, strong) ElectrodeRequestDispatcher *requestDispatcher;
@property(nonatomic, copy) NSMutableDictionary<NSString *, ElectrodeBridgeTransaction * > *pendingTransaction;
@property (nonatomic, assign) dispatch_queue_t syncQueue; //this is used to make sure access to pendingTransaction is thread safe.

@end

static dispatch_once_t onceToken;
static ElectrodeRequestRegistrar *requestRegistrar;
static ElectrodeEventRegistrar *eventRegistrar;
static ElectrodeRequestDispatcher *requestDispatcher;
static ElectrodeEventDispatcher *eventDispatcher;
static NSMutableDictionary *pendingTransaction;
static NSMutableArray <id<ConstantsProvider>>* constantsProviders;

@implementation ElectrodeBridgeTransceiver

+(instancetype)sharedInstance {
    return sharedInstance;
}

-(instancetype)init {
    if (self = [super init])
    {
        dispatch_once(&onceToken, ^{
            requestRegistrar = [[ElectrodeRequestRegistrar alloc] init];
            eventRegistrar = [[ElectrodeEventRegistrar alloc] init];
            requestDispatcher = [[ElectrodeRequestDispatcher alloc] initWithRequestRegistrar:requestRegistrar];
            eventDispatcher = [[ElectrodeEventDispatcher alloc] initWithEventRegistrar:eventRegistrar];
            pendingTransaction = [[NSMutableDictionary alloc] init];
            constantsProviders = [[NSMutableArray alloc] init];
        });
        
        _requestDispatcher = requestDispatcher;
        _eventDispatcher = eventDispatcher;
        _pendingTransaction = pendingTransaction;
        
    }
    return self;
}
RCT_EXPORT_MODULE(ElectrodeBridge);
+ (NSArray *)electrodeModules
{
    return @[[[ElectrodeBridgeTransceiver alloc] init]];
}

-(NSArray *) supportedEvents
{
    return @[@"electrode.bridge.message"];
}

#pragma ConstantsProvider implementation

- (NSDictionary<NSString *,id> *)constantsToExport {
    NSMutableDictionary <NSString*, id> *constants = [NSMutableDictionary new];
    if (constantsProviders != nil && [constantsProviders count] > 0) {
        for (id<ConstantsProvider> constant in constantsProviders) {
            [constants addEntriesFromDictionary:[constant constantsToExport]];
        }
        return constants;
    }
    NSLog(@"Constants provider is empty %@", constantsProviders);
    return nil;
}

- (void)addConstantsProvider:(id<ConstantsProvider>)constantsProvider {
    @synchronized (self) {
        [constantsProviders addObject:constantsProvider];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma ElectrodeNativeBridge implementation
- (void)sendRequest: (ElectrodeBridgeRequest *)request
  completionHandler: (ElectrodeBridgeResponseCompletionHandler) completion
{
    [self handleRequest:request completionHandler:completion];
}

-(NSUUID *)registerRequestCompletionHandlerWithName: (NSString *) name completionHandler:(nonnull ElectrodeBridgeRequestCompletionHandler)completion {
    NSUUID *uUID = [self.requestDispatcher.requestRegistrar registerRequestCompletionHandlerWithName:name completion:completion];
    return uUID;
}

-(void)resetRegistrar {
    [self.requestDispatcher.requestRegistrar reset];
}

-(void)sendEvent: (ElectrodeBridgeEvent *)event {
    NSLog(@"ElectrodeBridgeTransceiver: emit event named: %@, id: %@", event.name, event.messageId);
    [self notifyNativeEventListenerWithEvent:event];
    [self notifyReactNativeEventListenerWithEvent:event];
}

-(NSUUID *)addEventListenerWithName: (NSString *)name eventListener: (id<ElectrodeBridgeEventListener>) eventListener {
    NSLog(@"%@, Adding eventListener %@ for event %@", NSStringFromClass([self class]), eventListener, name);
    NSUUID *uUID = [self.eventDispatcher.eventRegistrar registerEventListener:name eventListener:eventListener];
    return uUID;
}
#pragma ElectrodeReactBridge

RCT_EXPORT_METHOD(sendMessage:(NSDictionary *)bridgeMessage)
{
    NSLog(@"Received message from JS(data=%@)", bridgeMessage);
    NSString *typeString = (NSString *)[bridgeMessage objectForKey:kElectrodeBridgeMessageType];
    ElectrodeMessageType type = [ElectrodeBridgeMessage typeFromString:typeString];
    switch (type) {
        case ElectrodeMessageTypeRequest:
        {
            ElectrodeBridgeRequest *request = [ElectrodeBridgeRequest createRequestWithData:bridgeMessage];
            [self handleRequest:request completionHandler:nil];
            break;
        }
            
        case ElectrodeMessageTypeResponse:
        {
            ElectrodeBridgeResponse *response = [ElectrodeBridgeResponse createResponseWithData:bridgeMessage];
            if (response != nil) {
                [self handleResponse:response];
            } else {
                [NSException raise:@"invalue resonse" format:@"cannot construct a response from data"];
            }
            break;
        }
        case ElectrodeMessageTypeEvent:
        {
            ElectrodeBridgeEvent *event = [ElectrodeBridgeEvent createEventWithData:bridgeMessage];
            if (event != nil) {
                [self notifyNativeEventListenerWithEvent:event];
            } else {
                [NSException raise:@"invalue event" format:@"cannot construct an event from data"];
                
            }
            break;
        }
        case ElectrodeMessageTypeUnknown:
        default:
            [NSException raise:@"invalue message" format:@"cannot construct any message from data"];
            break;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma private methods

-(void)emitMessage:(ElectrodeBridgeMessage * _Nonnull)bridgeMessage
{
    NSLog(@"Sending bridgeMessage(%@) to JS", bridgeMessage);
    [self sendEventWithName:@"electrode.bridge.message" body:[bridgeMessage toDictionary]];
}

-(void)notifyReactNativeEventListenerWithEvent: (ElectrodeBridgeEvent *) event {
    [self emitMessage:event];
}

-(void)notifyNativeEventListenerWithEvent: (ElectrodeBridgeEvent *)event {
    [self.eventDispatcher dispatchEvent:event];
}

-(void)handleRequest:(ElectrodeBridgeRequest *)request
  completionHandler: (ElectrodeBridgeResponseCompletionHandler _Nullable) completion
{
    [self logRequest:request];
    
    if (completion == nil && !request.isJsInitiated) {
        [NSException raise:@"invalid operation" format:@"A response lister is required for a native initiated request"];
    }
    

    ElectrodeBridgeTransaction *transaction = [self createTransactionWithRequest:request completionHandler:completion];
    if ([self.requestDispatcher canHandlerRequestWithName:request.name] ) {
        [self dispatchRequestToNativeHandlerForTransaction:transaction];
    } else if (!request.isJsInitiated) { //GOTCHA: Make sure not send a request back to JS if it's initiated on JS side
        [self dispatchRequestToReactHandlerForTransaction:transaction];
    }else {
        NSLog(@"No handler available to handle request(%@)", request);
        id<ElectrodeFailureMessage> failureMessage = [ElectrodeBridgeFailureMessage createFailureMessageWithCode:@"ENOHANDLER" message:@"No registered request handler found"];
        ElectrodeBridgeResponse *response = [ElectrodeBridgeResponse createResponseForRequest:request withResponseData:nil withFailureMessage:failureMessage];
        [self handleResponse:response];
    }
}

-(ElectrodeBridgeTransaction *)createTransactionWithRequest: (ElectrodeBridgeRequest *)request
     completionHandler: (ElectrodeBridgeResponseCompletionHandler) completion
{
    ElectrodeBridgeTransaction *transaction = [[ElectrodeBridgeTransaction alloc] initWithRequest:request completionHandler:completion];
    
    @synchronized (self) {
        [self.pendingTransaction setObject:transaction forKey:request.messageId];
        if ([request timeoutMs] != kElectrodeBridgeRequestNoTimeOut) {
            [self startTimeOutCheckForTransaction:transaction];
        }
    }
    
    return transaction;
}

-(void)startTimeOutCheckForTransaction: (ElectrodeBridgeTransaction *)transaction
{
    // Add the timeout handler
    __weak ElectrodeBridgeTransceiver *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(transaction.request.timeoutMs * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        ElectrodeBridgeResponseCompletionHandler completionBlock = transaction.completion;
        if (completionBlock)
        {
            id<ElectrodeFailureMessage> failureMessage = [ElectrodeBridgeFailureMessage createFailureMessageWithCode:@"TIMEOUT" message:@"transaction timed out for request"];
            ElectrodeBridgeResponse *response = [ElectrodeBridgeResponse createResponseForRequest:transaction.request withResponseData:nil withFailureMessage:failureMessage];
            [weakSelf handleResponse:response];
        } else {
            NSLog(@"Empty failure block. Time out may not be handled property");
        }
    });
}

-(void)dispatchRequestToNativeHandlerForTransaction: (ElectrodeBridgeTransaction *)transaction
{
    NSLog(@"Sending request(%@) to native handler", transaction.request);
    ElectrodeBridgeRequest *request = transaction.request;
    __weak ElectrodeBridgeTransceiver *weakSelf = self;
        
    [self.requestDispatcher dispatchRequest:request completionHandler:^(id _Nullable data, id<ElectrodeFailureMessage> _Nullable failureMessage) {
        if (failureMessage != nil) {
            ElectrodeBridgeResponse *response = [ElectrodeBridgeResponse createResponseForRequest:request
                                                                                 withResponseData:nil
                                                                               withFailureMessage:failureMessage];
            [weakSelf handleResponse:response];
        } else {
            ElectrodeBridgeResponse *response = [ElectrodeBridgeResponse createResponseForRequest:request
                                                                                 withResponseData:data
                                                                               withFailureMessage:nil];
            [weakSelf handleResponse:response];
        }
    }];
}

-(void)dispatchRequestToReactHandlerForTransaction:(ElectrodeBridgeTransaction *)transaction
{
    NSLog(@"Sending request(%@) over to JS handler because there is no local request handler available", transaction.request);
    [self emitMessage:transaction.request];
}

-(void)handleResponse:(ElectrodeBridgeResponse *)response
{
    NSLog(@"hanlding bridge response: %@", response);
    ElectrodeBridgeTransaction *transaction;
    @synchronized (self) {
        transaction = (ElectrodeBridgeTransaction *) [self.pendingTransaction objectForKey:response.messageId];
    }
    if (transaction != nil) {
        transaction.response = response;
        [self completeTransaction:transaction];
    } else {
        NSLog(@"Response(%@) will be ignored because the transcation for this request has been removed from the queue. Perhaps it's already timed-out or completed.", response);
    }
    
}

-(void)completeTransaction:(ElectrodeBridgeTransaction *)transaction
{
    if(transaction.response == nil) {
        [NSException raise:@"invalid transaction" format:@"Cannot complete transaction, a transaction can only be completed with a valid response"];
    }
    NSLog(@"completing transaction(id=%@", transaction.transactionId);
    
    [self.pendingTransaction removeObjectForKey:transaction.transactionId];
    
    ElectrodeBridgeResponse *response = transaction.response;
    [self logResponse:response];
    
    if(transaction.isJsInitiated) {
        NSLog(@"Completing transaction by emitting event back to JS since the request is initiated from JS side");
        [self emitMessage:response];
    } else {
        if (transaction.completion == nil) {
            [NSException raise:@"invalid transaction" format:@"Should never reach here. A response listener should always be set for a local transaction"];
        } else {
            if(response.failureMessage != nil) {
                
                NSLog(@"Completing transaction by issuing a failure call back to local response listener");
                dispatch_async(dispatch_get_main_queue(), ^{
                    transaction.completion(nil, response.failureMessage);
                });
            } else {
                    NSLog(@"Completing transaction by issuing a success call back to local response listener");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        transaction.completion(response.data, nil);
                    });
            }
        }
    }
}

-(void)logRequest: (ElectrodeBridgeRequest *)request {
    NSLog(@"--> --> --> --> --> Request(%@)", request);
}

-(void)logResponse: (ElectrodeBridgeResponse *)response {
    NSLog(@"<-- <-- <-- <-- <-- Response(%@)", response);
}

+ (void)registerReactNativeReadyListener: (ElectrodeBridgeReactNativeReadyListner) listner
{
    if(isReactNativeReady) {
        if (listner) {
            listner(sharedInstance);
        }
    }
    
    reactNativeReadyListener = [listner copy];
}

- (void)onReactNativeInitialized
{
    isReactNativeReady = YES;
    sharedInstance = self;
    if (reactNativeReadyListener) {
        reactNativeReadyListener(self);
    }
}
+ (void)registerReactTransceiverReadyListner: (ElectrodeBridgeReactNativeReadyListner) listener
{
    if(isTransceiverReady) {
        if (listener) {
            listener(sharedInstance);
        }
    }
    reactNativeTransceiver = listener;
}

- (void) onTransceiverModuleInitialized {
    isTransceiverReady = YES;
    sharedInstance = self;
    if (reactNativeTransceiver) {
        reactNativeTransceiver(self);
    }
}

@end
NS_ASSUME_NONNULL_END
