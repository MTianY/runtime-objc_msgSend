//
//  TYPerson.m
//  runtime-objc_msgSend Part
//
//  Created by 马天野 on 2018/9/23.
//  Copyright © 2018年 Maty. All rights reserved.
//

#import "TYPerson.h"

@implementation TYPerson

- (void)eat {
    NSLog(@"%s",__func__);
}

+ (void)sleep {
    NSLog(@"%s",__func__);
}

@end
