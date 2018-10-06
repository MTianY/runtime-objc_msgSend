//
//  TYPerson.m
//  runtime-objc_msgSend Part
//
//  Created by 马天野 on 2018/9/23.
//  Copyright © 2018年 Maty. All rights reserved.
//

#import "TYPerson.h"
#import <objc/runtime.h>
#import "TYStudent.h"

struct method_t {
    SEL sel;
    char *types;
    IMP imp;
};

@implementation TYPerson

//void test_C (id self , SEL _cmd) {
//    NSLog(@"消息接收者:%@---- 函数: %@",self, NSStringFromSelector(_cmd));
//}
//
//- (void)eat {
//    NSLog(@"%s",__func__);
//}
//
//+ (void)sleep {
//    NSLog(@"%s",__func__);
//}
//
//+ (BOOL)resolveInstanceMethod:(SEL)sel {
//
//    if (sel == @selector(playGame)) {
//        class_addMethod(self, sel, (IMP)test_C, "v16@0:8");
//    }
//    
//    return [super resolveInstanceMethod:sel];
//}

//+ (BOOL)resolveInstanceMethod:(SEL)sel {
//
//    if (sel == @selector(playGame)) {
//        Method method = class_getInstanceMethod(self, @selector(eat));
//        class_addMethod(self, sel, method_getImplementation(method), method_getTypeEncoding(method));
//        return YES;
//
//
//    }
//
//    return [super resolveInstanceMethod:sel];
//}

//+ (BOOL)resolveInstanceMethod:(SEL)sel {
//
//    NSLog(@"进入到动态方法解析阶段");
//
//    if (sel == @selector(playGame)) {
//        // 拿到一个其他的对象方法
////        Method newMethod = class_getInstanceMethod(self, @selector(eat));
//        struct method_t *newMethod = (struct method_t*)class_getInstanceMethod(self, @selector(eat));
////        // 动态添加这个新方法
//        class_addMethod(self, sel, newMethod->imp, newMethod->types);
//
//        return YES;
//    }
//
//    return [super resolveInstanceMethod:sel];
//}

#pragma mark - 消息转发
- (id)forwardingTargetForSelector:(SEL)aSelector {
    if (aSelector == @selector(playGame)) {
//        return [TYStudent new];
        return nil;
    }
    return [super forwardingTargetForSelector:aSelector];
}

// 如果上面返回 nil, 则会来到这个方法,要求返回一个方法签名
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    
    if (aSelector == @selector(playGame)) {
        return [NSMethodSignature signatureWithObjCTypes:"v16@0:8"];
    }
    return [super methodSignatureForSelector:aSelector];
}

/**
 如果上面的方法返回了一个合理的方法签名,则会调用下面这个方法

 @param anInvocation 封装了一个方法调用,包括: 方法调用者 | 方法名 | 方法参数
 方法调用者: anInvocation.target
 方法名 :anInvocation.selector
 参数: [anInvocation getArgument:NULL atIndex:0]
 */
- (void)forwardInvocation:(NSInvocation *)anInvocation {
    // 传进来一个新的方法调用者,调用方法
    [anInvocation invokeWithTarget:[TYStudent new]];
}

@end
