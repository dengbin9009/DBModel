//
//  NSObject+DBModel.m
//  DBModel
//
//  Created by DaBin on 2017/7/10.
//  Copyright © 2017年 DaBin. All rights reserved.
//

#import "NSObject+DBModel.h"
#import "DBValueTransformer.h"
#import <objc/message.h>
#import "DBClassInfo.h"

@implementation NSObject (DBModel)

+ (instancetype)DB_modelWithJson:(id)json{
    NSDictionary *dic = [self DB_dictionaryWithJson:json];
    return [self DB_modelWithDictionary:dic];
}

+ (instancetype)DB_modelWithDictionary:(NSDictionary *)dictionary{
    if ( !dictionary || ![dictionary isKindOfClass:[NSDictionary class]] ) return nil;
    Class Cls = [self class];
    NSObject *model = [Cls new];
    [model DB_modelSetPropertyWithDictionary:dictionary];
    return model;
}

+ (NSArray *)DB_arrayModelWithJson:(id)json{
    NSArray *arr = [self DB_arrayWithJson:json];
    return [self DB_arrayModelWithArray:arr];
}

+ (NSArray *)DB_arrayModelWithArray:(NSArray *)array{
    if ( !array || ![array isKindOfClass:[NSArray class]] ) return nil;
    NSMutableArray *modelArray = [NSMutableArray new];
    for (NSInteger index=0; index<array.count; index++) {
        NSObject *aObject = array[index];
        if ( [aObject isKindOfClass:[NSDictionary class]] ) {
            Class Cls = [self class];
            NSObject *model = [Cls new];
            [model DB_modelSetPropertyWithDictionary:(NSDictionary *)aObject];
            if ( model ) {
                [modelArray addObject:model];
            }
        }
    }
    return modelArray;
}

+ (NSDictionary *)DB_dictionaryWithJson:(id)json{
    NSDictionary *dic = [NSObject DB_objectWithJson:json];
    if ( [dic isKindOfClass:[NSDictionary class]] ) {
        return dic;
    }
    else if ( [dic isKindOfClass:[NSArray class]] ){
        DBModelLog(@"正在尝试将一个Array类型的JSON转化为Dictionary，转化失败");
    }
    else{
        DBModelLog(@"暂不支持这种JSON格式");
    }
    return nil;
}

+ (NSArray *)DB_arrayWithJson:(id)json{
    NSArray *arr = [NSObject DB_objectWithJson:json];
    if ( [arr isKindOfClass:[NSArray class]] ) {
        return arr;
    }
    else if ( [arr isKindOfClass:[NSArray class]] ){
        DBModelLog(@"正在尝试将一个Dictionary类型的JSON转化为Array，转化失败");
    }
    else{
        DBModelLog(@"暂不支持这种JSON格式");
    }
    return nil;
}

+ (id)DB_objectWithJson:(id)json{
    if ( DB_isNull(json) ) return nil;
    NSData *jsonData = nil;
    if ( [json isKindOfClass:[NSData class]] ) {
        jsonData = json;
    }
    else if ( [json isKindOfClass:[NSString class]] ) {
        jsonData = [(NSString *)json dataUsingEncoding:NSUTF8StringEncoding];
    }
    else if ( [json isKindOfClass:[NSArray class]] ) {
        return json;
    }
    NSError *error = nil;
    id JSONObject = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
    return JSONObject;
}

// 对一个Model的一个Property赋值
+ (void)DB_modelSetPropertyToModel:(NSObject *)model withClassPropertyInfo:(DBClassPropertyInfo * _Nonnull)propertyInfo object:(id  _Nonnull)object{
    const char *charT = [propertyInfo.type UTF8String];
    unsigned long charLength = strlen(charT);
    if ( charLength<=0 ) return;
    
    const char charType = [propertyInfo.type UTF8String][0];
    NSNumber *objcNum;
    if ( [object isKindOfClass:[NSString class]] ) {
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
        objcNum = [numberFormatter numberFromString:object];
    }
    else if ( [object isKindOfClass:[NSNumber class]] ){
        objcNum = object;
    }
    else{
        objcNum = @(0);
    }
    
    // 判断是否是数值类型
    switch (charType) {
        case _C_ID:{
            // 这里有Number，强制转化为String
            if ( [object isKindOfClass:[NSNumber class]] ) {
                object = [NSString stringWithFormat:@"%@",object];
            }
            else if ( DB_isNull(object) ){
                object = @"<null>";
            }
            if ( DB_isSimpleClass(propertyInfo.cls) ) {
                if ( propertyInfo.isMutable ) {
                    ((void (*)(id, SEL, NSObject *))(void *) objc_msgSend)(model, propertyInfo.setterSel, ((NSObject *)object).mutableCopy);
                }
                else{
                    ((void (*)(id, SEL, NSObject *))(void *) objc_msgSend)(model, propertyInfo.setterSel, object);
                }
            }
            else if ( DB_isDateClass(propertyInfo.cls) ) {
                NSDateFormatter *dateFormatter = nil;
                if ( [[model class] respondsToSelector:@selector(dateFormatterMapperForKey:)] ) {
                    dateFormatter = [(id<DBModelProtocol>)[model class] dateFormatterMapperForKey:propertyInfo.name];
                }
                ((void (*)(id, SEL, NSDate *))(void *) objc_msgSend)(model, propertyInfo.setterSel, DB_dateSetWithObject(object,dateFormatter));
            }
            else if ( DB_isArrayClass(propertyInfo.cls) ) {
                if ( ![object isKindOfClass:[NSArray class]] ) {
                    ((void (*)(id, SEL, NSObject *))(void *) objc_msgSend)(model, propertyInfo.setterSel, @[].mutableCopy);
                    break;
                }
                NSMutableArray *arrayObject = ((NSObject *)object).mutableCopy;
                // 如果有协议则按照协议转换对象，如果没有则直接赋值
                if ( propertyInfo.protocols.count==0 ) {
                    ((void (*)(id, SEL, NSMutableArray *))(void *) objc_msgSend)(model, propertyInfo.setterSel, arrayObject);
                }
                else{
                    Class Cls = NSClassFromString(propertyInfo.protocols.firstObject);
                    NSMutableArray *modelArray = [NSMutableArray new];
                    __block NSMutableArray *blockModelArray = modelArray;
                    for (NSInteger index=0; index<arrayObject.count; index++) {
                        NSObject *aArrayObject = arrayObject[index];
                        if ( [aArrayObject isKindOfClass:[NSDictionary class]] ) {
                            NSObject *aModel = [Cls new];
                            [aModel DB_modelSetPropertyWithDictionary:(NSDictionary *)aArrayObject];
                            if ( aModel ) [modelArray addObject:aModel];
                        }
                        else if ( [aArrayObject isKindOfClass:[NSString class]] ) {
                            [modelArray addObject:aArrayObject];
                        }
                        else{
                            DBModelLog(@"数组：%@有不支持转换的数据",propertyInfo.name);
                        }
                    }
                    ((void (*)(id, SEL, NSMutableArray *))(void *) objc_msgSend)(model, propertyInfo.setterSel, blockModelArray);
                }
            }
            else{
                Class Cls = propertyInfo.cls;
                if ( !Cls ) {
                    DBModelLog(@"属性：%@暂不支持转换",propertyInfo.name);
                    break;
                }
                if ( [object isKindOfClass:[NSDictionary class]] ) {
                    NSObject *aModel = [Cls new];
                    [aModel DB_modelSetPropertyWithDictionary:(NSDictionary *)object];
                    ((void (*)(id, SEL, NSObject *))(void *) objc_msgSend)(model, propertyInfo.setterSel, aModel);
                }
            }
            break;
        }
        case _C_CHR:
            ((void (*)(id, SEL, char))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.charValue);
            break;
        case _C_UCHR:
            ((void (*)(id, SEL, unsigned char))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.unsignedCharValue);
            break;
        case _C_SHT:
            ((void (*)(id, SEL, short))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.shortValue);
            break;
        case _C_USHT:
            ((void (*)(id, SEL, unsigned short))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.unsignedShortValue);
            break;
        case _C_INT:
            ((void (*)(id, SEL, int))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.intValue);
            break;
        case _C_UINT:
            ((void (*)(id, SEL, unsigned int))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.unsignedIntValue);
            break;
        case _C_LNG:
            ((void (*)(id, SEL, long))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.longValue);
            break;
        case _C_ULNG:
            ((void (*)(id, SEL, unsigned long))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.unsignedLongValue);
            break;
        case _C_LNG_LNG:
            ((void (*)(id, SEL, long long))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.longLongValue);
            break;
        case _C_ULNG_LNG:
            ((void (*)(id, SEL, unsigned long long))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.unsignedLongLongValue);
            break;
        case _C_FLT:
            ((void (*)(id, SEL, long long))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.floatValue);
            break;
        case _C_DBL:
            ((void (*)(id, SEL, double))(void *) objc_msgSend)(model, propertyInfo.setterSel, objcNum.doubleValue);
            break;
        case _C_BOOL:
            ((void (*)(id, SEL, BOOL))(void *) objc_msgSend)(model, propertyInfo.setterSel, DB_boolSetWithObject(object));
            break;
        default:
            break;
    }
}

// 对一个NSDictionary类型的Model的所有Property赋值
- (void)DB_modelSetPropertyWithDictionary:(NSDictionary *)dictionary{
    if ( !dictionary || ![dictionary isKindOfClass:[NSDictionary class]] ) return;
    
    __block NSObject *blockModel = self;
    DBClassInfo *classInfo = [DBClassInfo classInfoWithClass:[self class]];
    
    DBClassInfo *curClassInfo = classInfo;
    while (curClassInfo) {
        [curClassInfo.propertyInfos enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull propertyKey, DBClassPropertyInfo * _Nonnull propertyInfo, BOOL * _Nonnull propertyStop) {
            BOOL isValidProperty = YES;
            
            NSArray *blackList = nil;
            if ( [curClassInfo.cls respondsToSelector:@selector(modelPropertyBlackList)] ) {
                blackList = [(id<DBModelProtocol>)curClassInfo.cls modelPropertyBlackList];
            }
            
            NSArray *whiteList = nil;
            if ( [curClassInfo.cls respondsToSelector:@selector(modelPropertyWhiteList)] ) {
                whiteList = [(id<DBModelProtocol>)curClassInfo.cls modelPropertyWhiteList];
            }
            
            NSDictionary *customKeyMapper = nil;
            if ( [curClassInfo.cls respondsToSelector:@selector(customKeyMapper)] ) {
                customKeyMapper = [(id<DBModelProtocol>)curClassInfo.cls customKeyMapper];
            }
            
            if ( blackList && [blackList isKindOfClass:[NSArray class]] && [blackList containsObject:propertyInfo.name] ) isValidProperty = NO;
            if ( whiteList && [whiteList isKindOfClass:[NSArray class]] && ![whiteList containsObject:propertyInfo.name] ) isValidProperty = NO;
            if ( [propertyInfo.protocols containsObject:@"Ignore"] ) isValidProperty = NO;
            
            if ( isValidProperty ) {
                [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull dicKey, id  _Nonnull dicObj, BOOL * _Nonnull dicStop) {
                    
                    __block NSString *blockKey = dicKey;
                    if ( [customKeyMapper isKindOfClass:[NSDictionary class]] ) {
                        [customKeyMapper enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull customMapperKey, id  _Nonnull customMapperObj, BOOL * _Nonnull customMapperStop) {
                            if ( [customMapperKey isEqualToString:dicKey] ) {
                                blockKey = customMapperObj;
                                *customMapperStop = YES;
                            }
                        }];
                    }
                    
                    if ( [blockKey isEqualToString:propertyKey] ) {
                        [NSObject DB_modelSetPropertyToModel:blockModel withClassPropertyInfo:propertyInfo object:dicObj];
                        *dicStop = YES;
                    }
                }];
            }
            
        }];
        curClassInfo = curClassInfo.superClsInfo;
    }
}

@end
