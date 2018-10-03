//
//  TYPerson.m
//  runtime-objc_msgSend Part
//
//  Created by 马天野 on 2018/9/23.
//  Copyright © 2018年 Maty. All rights reserved.
//

#import "TYPerson.h"
#import <objc/runtime.h>

struct method_t {
    SEL sel;
    char *types;
    IMP imp;
};

@implementation TYPerson

void test_C (id self , SEL _cmd) {
    NSLog(@"消息接收者:%@---- 函数: %@",self, NSStringFromSelector(_cmd));
}

- (void)eat {
    NSLog(@"%s",__func__);
}

+ (void)sleep {
    NSLog(@"%s",__func__);
}

+ (BOOL)resolveInstanceMethod:(SEL)sel {
    
    if (sel == @selector(playGame)) {
        class_addMethod(self, sel, (IMP)test_C, "v16@0:8");
    }
    
    return [super resolveInstanceMethod:sel];
}

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

@end
