// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
//  IOSProtocolClass.m
//  JreEmulation
//
//  Created by Keith Stanger on 8/16/13.
//

#import "IOSProtocolClass.h"
#import "IOSReflection.h"
#import "java/lang/reflect/Method.h"
#import "java/lang/reflect/Modifier.h"
#import "objc/runtime.h"

@interface IOSProtocolClass () {
  Protocol *protocol_;
  _Atomic(IOSObjectArray *) interfaces_;
}
@end

@implementation IOSProtocolClass

static Class GetBackingClass(Protocol *protocol) {
  return objc_lookUpClass(protocol_getName(protocol));
}

@synthesize objcProtocol = protocol_;

- (instancetype)initWithProtocol:(Protocol *)protocol {
  if ((self = [super initWithMetadata:JreFindMetadata(GetBackingClass(protocol))])) {
    protocol_ = RETAIN_(protocol);
  }
  return self;
}

static jboolean ConformsToProtocol(IOSClass *cls, IOSProtocolClass *protocol) {
  if (!cls) {
    return false;
  }
  if (cls == protocol) {
    return true;
  }
  IOSObjectArray *interfaces = [cls getInterfacesInternal];
  for (int i = 0; i < interfaces->size_; i++) {
    IOSClass *interface = interfaces->buffer_[i];
    if (interface == protocol || ConformsToProtocol(interface, protocol)) {
      return true;
    }
  }
  return ConformsToProtocol([cls getSuperclass], protocol);
}

- (jboolean)isInstance:(id)object {
  return ConformsToProtocol([object getClass], self);
}

- (NSString *)description {
  return [NSString stringWithFormat:@"interface %@", [self getName]];
}

- (NSString *)getName {
  NSString *name = JreClassQualifiedName([self getMetadata]);
  return name ? name : NSStringFromProtocol(protocol_);
}

- (NSString *)getSimpleName {
  const J2ObjcClassInfo *metadata = [self getMetadata];
  return metadata ? JreClassTypeName(metadata) : NSStringFromProtocol(protocol_);
}

- (NSString *)objcName {
  return NSStringFromProtocol(protocol_);
}

- (NSString *)metadataName {
  return [NSString stringWithFormat:@"L%@;", NSStringFromProtocol(protocol_)];
}

// Returns the class with the same name as the protocol, if it exists.
- (Class) objcClass {
  return GetBackingClass(protocol_);
}

- (int)getModifiers {
  const J2ObjcClassInfo *metadata = [self getMetadata];
  if (metadata) {
    return metadata->modifiers
        & (JavaLangReflectModifier_INTERFACE | JavaLangReflectModifier_interfaceModifiers());
  }
  return JavaLangReflectModifier_PUBLIC | JavaLangReflectModifier_INTERFACE |
      JavaLangReflectModifier_ABSTRACT | JavaLangReflectModifier_STATIC;
}

- (jboolean)isAssignableFrom:(IOSClass *)cls {
  return ConformsToProtocol(cls, self);
}

- (jboolean)isInterface {
  return true;
}

- (JavaLangReflectMethod *)findMethodWithTranslatedName:(NSString *)objcName
                                        checkSupertypes:(jboolean)checkSupertypes {
  unsigned int count;
  JavaLangReflectMethod *result = nil;
  struct objc_method_description *descriptions =
      protocol_copyMethodDescriptionList(protocol_, true, true, &count);
  for (unsigned int i = 0; i < count; i++) {
    struct objc_method_description *methodDesc = &descriptions[i];
    SEL sel = methodDesc->name;
    if ([objcName isEqualToString:NSStringFromSelector(sel)]) {
      NSMethodSignature *signature = JreSignatureOrNull(methodDesc);
      if (signature) {
        const J2ObjcMethodInfo *methodMetadata =
            JreFindMethodInfo([self getMetadata], objcName);
        result = [JavaLangReflectMethod methodWithMethodSignature:signature
                                                         selector:sel
                                                            class:self
                                                         isStatic:false
                                                         metadata:methodMetadata];
      }
      break;
    }
  }
  free(descriptions);
  if (!result) {
    // Search backing class, if any.
    Class backingClass = objc_getClass(protocol_getName(protocol_));
    if (backingClass) {
      const char *name = [objcName UTF8String];
      Method method = JreFindClassMethod(backingClass, name);
      if (method) {
        NSMethodSignature *signature = JreSignatureOrNull(method_getDescription(method));
        if (signature) {
          const J2ObjcClassInfo *metadata = [self getMetadata];
          const J2ObjcMethodInfo *methodData =
              JreFindMethodInfo([self getMetadata], objcName);
          result = [JavaLangReflectMethod methodWithMethodSignature:signature
                                                           selector:method_getName(method)
                                                              class:self
                                                           isStatic:true
                                                           metadata:methodData];
        }
      }
    }
  }
  if (!result && checkSupertypes) {
    // Search super-interfaces.
    for (IOSClass *cls in [self getInterfacesInternal]) {
      if (cls != self) {
        result = [cls findMethodWithTranslatedName:objcName checkSupertypes:checkSupertypes];
        if (result) {
          break;
        }
      }
    }
  }
  return result;
}

- (IOSObjectArray *)getInterfacesInternal {
  IOSObjectArray *result = __c11_atomic_load(&interfaces_, __ATOMIC_ACQUIRE);
  if (!result) {
    @synchronized(self) {
      result = __c11_atomic_load(&interfaces_, __ATOMIC_RELAXED);
      if (!result) {
        unsigned int count;
        Protocol **protocolList = protocol_copyProtocolList(protocol_, &count);
        result = IOSClass_NewInterfacesFromProtocolList(protocolList, count);
        __c11_atomic_store(&interfaces_, result, __ATOMIC_RELEASE);
        free(protocolList);
      }
    }
  }
  return result;
}

#if ! __has_feature(objc_arc)
- (void)dealloc {
  [protocol_ release];
  [super dealloc];
}
#endif

@end
