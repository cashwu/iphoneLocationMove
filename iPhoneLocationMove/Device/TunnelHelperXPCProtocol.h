#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TunnelHelperXPCProtocol

- (void)startTunnelWithDeviceID:(NSString *)deviceID
                 idempotencyKey:(NSUUID *)idempotencyKey
                          reply:(void (^)(NSData *data))reply
    NS_SWIFT_NAME(startTunnel(deviceID:idempotencyKey:withReply:))
    __attribute__((swift_async(none)));

- (void)stopTunnelWithLeaseID:(NSUUID *)leaseID
                        reply:(void (^)(NSData *data))reply
    NS_SWIFT_NAME(stopTunnel(leaseID:withReply:))
    __attribute__((swift_async(none)));

- (void)statusWithLeaseID:(NSUUID *)leaseID
                    reply:(void (^)(NSData *data))reply
    NS_SWIFT_NAME(status(leaseID:withReply:))
    __attribute__((swift_async(none)));

- (void)reconcileWithReply:(void (^)(NSData *data))reply
    NS_SWIFT_NAME(reconcile(withReply:))
    __attribute__((swift_async(none)));

@end

NS_ASSUME_NONNULL_END
