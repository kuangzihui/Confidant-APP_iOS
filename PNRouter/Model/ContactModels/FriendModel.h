//
//  FriendModel.h
//  PNRouter
//
//  Created by 旷自辉 on 2018/9/13.
//  Copyright © 2018年 旷自辉. All rights reserved.
//


#import <BGFMDB/BGFMDB.h>

@interface FriendModel : BBaseModel

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *remarks;
@property (nonatomic, copy) NSString *company;
@property (nonatomic, copy) NSString *Mails;
@property (nonatomic, copy) NSString *publicKey;
@property (nonatomic, copy) NSString *signPublicKey;
@property (nonatomic, copy) NSString *position;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *owerId;
@property (nonatomic, copy) NSString *msg;
@property (nonatomic, strong) NSDate *requestTime;
@property (nonatomic , assign) NSInteger dealStaus; // 0:同意  1：已同意  2：过期  3：等待
@property (nonatomic , assign) NSInteger onLineStatu;
@property (nonatomic ,assign) BOOL isSelect;

@property (nonatomic, strong) NSString *RouteId;
@property (nonatomic, strong) NSString *RouteName;
@property (nonatomic, strong) NSString *Index;
@property (nonatomic) BOOL isUnRead;

@property (nonatomic ,assign) BOOL isGroup;
@property (nonatomic ,assign) BOOL noFriend;

//+ (NSString *)getSignPublicKeyWithToxId:(NSString *)toxId;

@end
