//
//  NTURLSesssionTracker.m
//  breakWork
//
//  Created by sgcy on 2018/6/29.
//  Copyright © 2018年 sgcy. All rights reserved.
//

#import "NTURLSesssionTracker.h"
#import <objc/runtime.h>
#import "NTDataKeeper.h"

@interface _NSURLSessionProxy : NSProxy

@property (nonatomic, weak) id target;

- (instancetype)initWithTarget:(id)target;

@end

@implementation _NSURLSessionProxy

- (instancetype)initWithTarget:(id)target
{
    self.target = target;
    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if ([NSStringFromSelector(aSelector) isEqualToString:@"URLSession:task:didFinishCollectingMetrics:"]) {
        return YES;
    }else if ([NSStringFromSelector(aSelector) isEqualToString:@"URLSession:task:didCompleteWithError:"]){
        return YES;
    }
    return [self.target respondsToSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    if (!self.target) {
        return [NSMethodSignature signatureWithObjCTypes:"v@"];
    }
    return [self.target methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if (!self.target) {
        return;
    }
    if ([self.target respondsToSelector:invocation.selector]) {
        [invocation invokeWithTarget:self.target];
    }
    if (@available(iOS 10.0, *)) {
        if ([NSStringFromSelector(invocation.selector) isEqualToString:@"URLSession:task:didFinishCollectingMetrics:"]) {
            __unsafe_unretained NSURLSessionTaskMetrics *metrics;
            [invocation getArgument:&metrics atIndex:4];
            [[NTDataKeeper shareInstance] trackSessionMetrics:metrics];
        }
    }else{
        if ([NSStringFromSelector(invocation.selector) isEqualToString:@"URLSession:task:didCompleteWithError:"]) {
            __unsafe_unretained NSURLSessionTask *task;
            [invocation getArgument:&task atIndex:3];
            SEL selector = NSSelectorFromString([@"_timin" stringByAppendingString:@"gData"]);
            NSDictionary *timingData = [task performSelector:selector];
            [[NTDataKeeper shareInstance] trackTimingData:timingData request:task.currentRequest];
        }
    }
}

@end

@implementation NSURLSession(tracker)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(sessionWithConfiguration:delegate:delegateQueue:);
        SEL swizzledSelector = @selector(swizzledSessionWithConfiguration:delegate:delegateQueue:);
        
        Method originalMethod = class_getClassMethod(class, originalSelector);
        Method swizzledMethod = class_getClassMethod(class, swizzledSelector);
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

+ (NSURLSession *)swizzledSessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(nullable id <NSURLSessionDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue
{
    if (delegate) {
        NSString *selectorName = [[@"set_c" stringByAppendingString:@"ollectsT"] stringByAppendingString:@"imingData:"];
        SEL selector = NSSelectorFromString(selectorName);
        if ([configuration respondsToSelector:selector]) { //该 selector 是 iOS 9 以下才有的，测试发现 14.2 已经移除
            [configuration performSelector:selector withObject:@(YES)];
        }
        
        _NSURLSessionProxy *proxy = [[_NSURLSessionProxy alloc] initWithTarget:delegate];
        objc_setAssociatedObject(delegate ,@"_NSURLSessionProxy" ,proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return [self swizzledSessionWithConfiguration:configuration delegate:(id<NSURLSessionDelegate>)proxy delegateQueue:queue];
    }else{
        return [self swizzledSessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
    }
    
}

@end
