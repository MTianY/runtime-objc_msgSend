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

#### 2.1 消息发送阶段

通过 runtime 源码,搜索`objc_msgSend`, 在文件`objc-msg-arm64.s` 下.找到 `objc_msgSend`方法的入口.由汇编语言实现的:

##### ENTRY _ objc_msgSend

```c
ENTRY _objc_msgSend
	UNWIND _objc_msgSend, NoFrame
	MESSENGER_START

   // x0 寄存器,里面放的消息接收者
	cmp	x0, #0			// nil check and tagged pointer check
	
	// 当 le 条件成立的时候,就会跳到 LNilOrTagged
	// 如果不成立,按顺序往下走.会来到 CacheLookup NORMAL 这里.
	b.le	LNilOrTagged		//  (MSB tagged pointer looks negative)
	ldr	x13, [x0]		// x13 = isa
	and	x16, x13, #ISA_MASK	// x16 = class	
LGetIsaDone:

   // 缓存查找
	CacheLookup NORMAL		// calls imp or objc_msgSend_uncached

LNilOrTagged:
	b.eq	LReturnZero		// nil check

	// tagged
	mov	x10, #0xf000000000000000
	cmp	x0, x10
	b.hs	LExtTag
	adrp	x10, _objc_debug_taggedpointer_classes@PAGE
	add	x10, x10, _objc_debug_taggedpointer_classes@PAGEOFF
	ubfx	x11, x0, #60, #4
	ldr	x16, [x10, x11, LSL #3]
	b	LGetIsaDone

LExtTag:
	// ext tagged
	adrp	x10, _objc_debug_taggedpointer_ext_classes@PAGE
	add	x10, x10, _objc_debug_taggedpointer_ext_classes@PAGEOFF
	ubfx	x11, x0, #52, #8
	ldr	x16, [x10, x11, LSL #3]
	b	LGetIsaDone
	
LReturnZero:
	// x0 is already zero
	mov	x1, #0
	movi	d0, #0
	movi	d1, #0
	movi	d2, #0
	movi	d3, #0
	MESSENGER_END_NIL
	
	// 相当于 return
	ret

	END_ENTRY _objc_msgSend
```

##### CacheLookup NORMAL	

CacheLookup 是一个宏.

```c++
.macro CacheLookup
	// x1 = SEL, x16 = isa
	ldp	x10, x11, [x16, #CACHE]	// x10 = buckets, x11 = occupied|mask
	and	w12, w1, w11		// x12 = _cmd & mask
	add	x12, x10, x12, LSL #4	// x12 = buckets + ((_cmd & mask)<<4)

	ldp	x9, x17, [x12]		// {x9, x17} = *bucket
1:	cmp	x9, x1			// if (bucket->sel != _cmd)
	b.ne	2f			//     scan more
	
	// 在缓存中找打了,直接调用
	CacheHit $0			// call or return imp
	
	// 没有找到的话,进去看下 CheckMiss 做了什么事情.
2:	// not hit: x12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0
	cmp	x12, x10		// wrap if bucket == buckets
	b.eq	3f
	ldp	x9, x17, [x12, #-16]!	// {x9, x17} = *--bucket
	b	1b			// loop

3:	// wrap: x12 = first bucket, w11 = mask
	add	x12, x12, w11, UXTW #4	// x12 = buckets+(mask<<4)

	// Clone scanning loop to miss instead of hang when cache is corrupt.
	// The slow path may detect any corruption and halt later.

	ldp	x9, x17, [x12]		// {x9, x17} = *bucket
1:	cmp	x9, x1			// if (bucket->sel != _cmd)
	b.ne	2f			//     scan more
	CacheHit $0			// call or return imp
	
2:	// not hit: x12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0
	cmp	x12, x10		// wrap if bucket == buckets
	b.eq	3f
	ldp	x9, x17, [x12, #-16]!	// {x9, x17} = *--bucket
	b	1b			// loop

3:	// double wrap
	JumpMiss $0
	
.endmacro
```

##### CheckMiss

```c++
.macro CheckMiss
	// miss if bucket->sel == 0
.if $0 == GETIMP
	cbz	x9, LGetImpMiss
	
	// 之前传进来的 NORMAL. 所以下面调用 cbz	x9, __objc_msgSend_uncached
	// 继续看一下 __objc_msgSend_uncached 方法内部
.elseif $0 == NORMAL
	cbz	x9, __objc_msgSend_uncached
.elseif $0 == LOOKUP
	cbz	x9, __objc_msgLookup_uncached
.else
.abort oops
.endif
.endmacro
```

##### __objc_msgSend_uncached

```c++
STATIC_ENTRY __objc_msgSend_uncached
	UNWIND __objc_msgSend_uncached, FrameWithNoSaves

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band x16 is the class to search
	
	// 找方法
	MethodTableLookup
	br	x17

	END_ENTRY __objc_msgSend_uncached
```

##### MethodTableLookup

```c++
.macro MethodTableLookup
	
	// push frame
	stp	fp, lr, [sp, #-16]!
	mov	fp, sp

	// save parameter registers: x0..x8, q0..q7
	sub	sp, sp, #(10*8 + 8*16)
	stp	q0, q1, [sp, #(0*16)]
	stp	q2, q3, [sp, #(2*16)]
	stp	q4, q5, [sp, #(4*16)]
	stp	q6, q7, [sp, #(6*16)]
	stp	x0, x1, [sp, #(8*16+0*8)]
	stp	x2, x3, [sp, #(8*16+2*8)]
	stp	x4, x5, [sp, #(8*16+4*8)]
	stp	x6, x7, [sp, #(8*16+6*8)]
	str	x8,     [sp, #(8*16+8*8)]

	// receiver and selector already in x0 and x1
	mov	x2, x16
	
	// 调用 __class_lookupMethodAndLoadCache3
	// __class_lookupMethodAndLoadCache3 方法会返回找到的 imp 方法地址.
	bl	__class_lookupMethodAndLoadCache3

	// imp in x0
	mov	x17, x0
	
	// restore registers and return
	ldp	q0, q1, [sp, #(0*16)]
	ldp	q2, q3, [sp, #(2*16)]
	ldp	q4, q5, [sp, #(4*16)]
	ldp	q6, q7, [sp, #(6*16)]
	ldp	x0, x1, [sp, #(8*16+0*8)]
	ldp	x2, x3, [sp, #(8*16+2*8)]
	ldp	x4, x5, [sp, #(8*16+4*8)]
	ldp	x6, x7, [sp, #(8*16+6*8)]
	ldr	x8,     [sp, #(8*16+8*8)]

	mov	sp, fp
	ldp	fp, lr, [sp], #16

.endmacro
```

##### ._class_lookupMethodAndLoadCache3

```c++
/***********************************************************************
* _class_lookupMethodAndLoadCache.
* Method lookup for dispatchers ONLY. OTHER CODE SHOULD USE lookUpImp().
* This lookup avoids optimistic cache scan because the dispatcher 
* already tried that.
**********************************************************************/
IMP _class_lookupMethodAndLoadCache3(id obj, SEL sel, Class cls)
{        
    return lookUpImpOrForward(cls, sel, obj, 
                              YES/*initialize*/, NO/*cache*/, YES/*resolver*/);
}
```

##### lookUpImpOrForward

```c++
/***********************************************************************
* lookUpImpOrForward.
* The standard IMP lookup. 
* initialize==NO tries to avoid +initialize (but sometimes fails)
* cache==NO skips optimistic unlocked lookup (but uses cache elsewhere)
* Most callers should use initialize==YES and cache==YES.
* inst is an instance of cls or a subclass thereof, or nil if none is known. 
*   If cls is an un-initialized metaclass then a non-nil inst is faster.
* May return _objc_msgForward_impcache. IMPs destined for external use 
*   must be converted to _objc_msgForward or _objc_msgForward_stret.
*   If you don't want forwarding at all, use lookUpImpOrNil() instead.
**********************************************************************/
IMP lookUpImpOrForward(Class cls, SEL sel, id inst, 
                       bool initialize, bool cache, bool resolver)
{
    IMP imp = nil;
    bool triedResolver = NO;

    runtimeLock.assertUnlocked();

    // Optimistic cache lookup
    // 试一下缓存查找,也许会找到,找到了就返回
    if (cache) {
        imp = cache_getImp(cls, sel);
        if (imp) return imp;
    }

    // runtimeLock is held during isRealized and isInitialized checking
    // to prevent races against concurrent realization.

    // runtimeLock is held during method search to make
    // method-lookup + cache-fill atomic with respect to method addition.
    // Otherwise, a category could be added but ignored indefinitely because
    // the cache was re-filled with the old value after the cache flush on
    // behalf of the category.
    
    /** 翻译:
     * runtimeLock 在检查 isRealized 和 isInitialized 期间,要保留下来.
     * 来阻止并发时的资源抢夺.
     *
     * 在搜索方法这个过程中要保持 runtimeLock.
     * method-loopup 和 cache-fill 关于方法添加时使用 atomic 原子操作.
     * 否则,添加一个 category 会被无限期的忽略
     * 因为代表 category 的缓存刷新后,缓存会被旧值重新填充
     */

    runtimeLock.read();

    if (!cls->isRealized()) {
        // Drop the read-lock and acquire the write-lock.
        // realizeClass() checks isRealized() again to prevent
        // a race while the lock is down.
        
        /**
         * 删除 read-lock 并且获取 write-lock
         * realizeClass() 再次检查 isRealized() 来防止 lock 的失败
         */
        
        runtimeLock.unlockRead();
        runtimeLock.write();

        realizeClass(cls);

        runtimeLock.unlockWrite();
        runtimeLock.read();
    }

    // initialize 我们要找的部分!
    
    // 如果需要初始化(initialize)并且这个类(cls)还没有被初始化
    if (initialize  &&  !cls->isInitialized()) {
        runtimeLock.unlockRead();
        // 那么就调用_class_initialize 方法将其初始化
        _class_initialize (_class_getNonMetaClass(cls, inst));
        runtimeLock.read();
        // If sel == initialize, _class_initialize will send +initialize and 
        // then the messenger will send +initialize again after this 
        // procedure finishes. Of course, if this is not being called 
        // from the messenger then it won't happen. 2778172
    }

    
 retry:    
    runtimeLock.assertReading();

    // Try this class's cache.
    // 再次尝试从缓存中去查找,如果找到了,直接跳到下方的 done: 处.返回 imp(方法地址)
    imp = cache_getImp(cls, sel);
    if (imp) goto done;

    // 如果没有缓存的话,走这里
    // Try this class's method lists.
    {
        // 根据类对象(或元类对象) 及方法名.来找
        Method meth = getMethodNoSuper_nolock(cls, sel);
        // 如果方法存在.
        if (meth) {
            // 填充缓存
            log_and_fill_cache(cls, meth->imp, sel, inst, cls);
            // 取出方法的 imp, 即函数地址 
            imp = meth->imp;
            // 调到 done, 返回 imp
            goto done;
        }
    }

    // Try superclass caches and method lists.
    // 如果上面没有找到,去找其父类的方法列表
    {
        unsigned attempts = unreasonableClassCount();
        for (Class curClass = cls->superclass;
             curClass != nil;
             // 将当前类对象的父类取出来再赋值给 curClass
             curClass = curClass->superclass)
        {
            // Halt if there is a cycle in the superclass chain.
            if (--attempts == 0) {
                _objc_fatal("Memory corruption in class list.");
            }
            
            // Superclass cache.
            imp = cache_getImp(curClass, sel);
            if (imp) {
                if (imp != (IMP)_objc_msgForward_impcache) {
                    // Found the method in a superclass. Cache it in this class.
                    // 找到的话,将父类的方法缓存到消息接收者(最开始那个类)的缓存中去.
                    log_and_fill_cache(cls, imp, sel, inst, curClass);
                    goto done;
                }
                else {
                    // Found a forward:: entry in a superclass.
                    // Stop searching, but don't cache yet; call method 
                    // resolver for this class first.
                    break;
                }
            }
            
            // Superclass method list.
            Method meth = getMethodNoSuper_nolock(curClass, sel);
            if (meth) {
                log_and_fill_cache(cls, meth->imp, sel, inst, curClass);
                imp = meth->imp;
                goto done;
            }
        }
    }

    // No implementation found. Try method resolver once.

    if (resolver  &&  !triedResolver) {
        runtimeLock.unlockRead();
        _class_resolveMethod(cls, sel, inst);
        runtimeLock.read();
        // Don't cache the result; we don't hold the lock so it may have 
        // changed already. Re-do the search from scratch instead.
        triedResolver = YES;
        goto retry;
    }

    // No implementation found, and method resolver didn't help. 
    // Use forwarding.

    imp = (IMP)_objc_msgForward_impcache;
    cache_fill(cls, sel, imp, inst);

 done:
    runtimeLock.unlockRead();
    // 返回 imp 方法地址.最终会返回到上面的 bl	__class_lookupMethodAndLoadCache3 处.
    return imp;
}
```

##### getMethodNoSuper_nolock(Class cls, SEL sel)

```c++
static method_t *
getMethodNoSuper_nolock(Class cls, SEL sel)
{
    runtimeLock.assertLocked();

    assert(cls->isRealized());
    // fixme nil cls? 
    // fixme nil sel?
    
    // 遍历
    // 类对象调用 data() 方法,会返回 struct class_rw_t
    // 然后在 class_rw_t 中拿 methods 去遍历
    for (auto mlists = cls->data()->methods.beginLists(), 
              end = cls->data()->methods.endLists(); 
         mlists != end;
         ++mlists)
    {
        // 搜索方法.
        method_t *m = search_method_list(*mlists, sel);
        if (m) return m;
    }

    return nil;
}
```

##### search_method_list

```c++
/***********************************************************************
* getMethodNoSuper_nolock
* fixme
* Locking: runtimeLock must be read- or write-locked by the caller
**********************************************************************/
static method_t *search_method_list(const method_list_t *mlist, SEL sel)
{
    int methodListIsFixedUp = mlist->isFixedUp();
    int methodListHasExpectedSize = mlist->entsize() == sizeof(method_t);
    
    // 如果排好序了,二分查找
    if (__builtin_expect(methodListIsFixedUp && methodListHasExpectedSize, 1)) {
        // 二分查找
        return findMethodInSortedMethodList(sel, mlist);
    } else {
        // 如果没排序,线性查找
        // Linear search of unsorted method list
        for (auto& meth : *mlist) {
            if (meth.name == sel) return &meth;
        }
    }

#if DEBUG
    // sanity-check negative results
    if (mlist->isFixedUp()) {
        for (auto& meth : *mlist) {
            if (meth.name == sel) {
                _objc_fatal("linear search worked when binary search did not");
            }
        }
    }
#endif

    return nil;
}
```

##### 填充缓存 log_and_fill_cache(Class cls, IMP imp, SEL sel, id receiver, Class implementer)

```c++
/***********************************************************************
* log_and_fill_cache
* Log this method call. If the logger permits it, fill the method cache.
* cls is the method whose cache should be filled. 
* implementer is the class that owns the implementation in question.
**********************************************************************/
static void
log_and_fill_cache(Class cls, IMP imp, SEL sel, id receiver, Class implementer)
{
#if SUPPORT_MESSAGE_LOGGING
    if (objcMsgLogEnabled) {
        bool cacheIt = logMessageSend(implementer->isMetaClass(), 
                                      cls->nameForLogging(),
                                      implementer->nameForLogging(), 
                                      sel);
        if (!cacheIt) return;
    }
#endif
    cache_fill (cls, sel, imp, receiver);
}
```

#### 2.2 图示

![](https://lh3.googleusercontent.com/ZTm9TKEF2-VH1GsuaKLhnmK5DB1ZyjezbIcuCypEoMAVvdc0jNF8vf_g-siCuyJyGJu6dCkJ-Z_S9LRSAS_1865otTMeoyLSGkfbn-6k_RVf9Af7TGb5N3vHYvA1N0VG5Ij8lnwFAJEAwbNJ67hFQE1yiHA9l7eTMK30xxCCG-kZnZcdouORkbl9UWY261yb033RDKv2D5tnOrpH8O-me844jlnIFGGEAjTLejNMxbiAEOvksgB2ujyxKOz-DcvI7ag7hpV24bJ3mYdJNyPai9Gf2Aq3h7SPmXS5uisSG_KiTroX69Mp-MeWF7CSxjp5iUdXqNeXCjLQ4WEUYVAYKFcEwttYFKeG0iorSZkQMxOrjhPszNoTh78u11zVCtRh_4O_Dwi_EuAI4Psedq8kFSzeTh6QrQ5PJt3nMENTYL4QzV3YduGJKjuL4qfM0xACViHKIuv-rBC7orS6rWQx9BRFNSTGZPYarfItpIvEG-Uyu95ix89pv9pyhG5yyx5yS4BIK42-Ut8lNtsLQ9vzOfqWbnomJGr9EPWaTyLwYkJEtR7vCcUkbKKDTKWGPcYcBIB7fw2sxGa2JNrtHWS15sOPeWNgl3TPR7bmbyTsx0hJMrooEvjAhkyv7c3KU38=w924-h606-no)


- 如果是从 `class_rw_t` 中查找方法
    - 如果已经排序了,执行二分查找
    - 如果没有排序,则遍历按顺序查找 
- `receiver` 通过 `isa指针` 找到 `receiverClass`.
- `receiverClass` 通过 `superclass 指针`找到 `superClass` .

