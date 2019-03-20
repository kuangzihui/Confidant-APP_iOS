//
//  GroupInfoModel.m
//  PNRouter
//
//  Created by 旷自辉 on 2019/3/18.
//  Copyright © 2019 旷自辉. All rights reserved.
//

#import "GroupInfoModel.h"
#import "UserModel.h"

@implementation GroupInfoModel

- (void)setGAdmin:(NSString *)GAdmin {
    _GAdmin = GAdmin;
    UserModel *userM = [UserModel getUserModel];
    _isOwner = [userM.userId isEqualToString:GAdmin]?YES:NO;
}

@end
