# objc_msgSend 方法详解

### 1. 消息机制.
首先有这么一个类: `TYPerson`.

- 它有个 `- (void)eat;`对象方法.

```objc
TYPerson *person = [[TYPerson alloc] init];
[person eat];
```

将上面的代码编译成 c++ 代码之后,`[person eat]` 其底层实现如下: 

```c++
/**
 * 参数一: 方法调用者,是当前的实例对象, 也是消息的接收者
 * 参数二: 方法名, 也是消息的名称
 */
((void (*)(id, SEL))(void *)objc_msgSend)((id)person, sel_registerName("eat"));
```

- 类方法: `+ (void)sleep`

执行`[TYPerson sleep]`之后,其底层实现如下: 

```c++
/**
 * 参数一: 方法调用者,是当前的类对象,也是消息的接收者
 * 参数二: 方法名, 消息的名称
 */
((void (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("TYPerson"), sel_registerName("sleep"));
```

### 2.objc_msgSend 的执行流程?

> 1.消息发送阶段
> 2.动态方法解析阶段
> 3.消息转发阶段


