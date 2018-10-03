//
//  main.m
//  runtime-objc_msgSend Part
//
//  Created by 马天野 on 2018/9/23.
//  Copyright © 2018年 Maty. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TYPerson.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        TYPerson *person = [[TYPerson alloc] init];
//        [person eat];
        // ((void (*)(id, SEL))(void *)objc_msgSend)((id)person, sel_registerName("eat"));
//        [TYPerson sleep];
        // ((void (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("TYPerson"), sel_registerName("sleep"));
        [person playGame];
    }
    return 0;
}
