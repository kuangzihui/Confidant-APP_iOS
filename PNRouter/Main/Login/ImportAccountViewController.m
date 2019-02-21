//
//  ImportAccountViewController.m
//  PNRouter
//
//  Created by Jelly Foo on 2019/2/20.
//  Copyright © 2019 旷自辉. All rights reserved.
//

#import "ImportAccountViewController.h"
#import "QRViewController.h"
#import "LibsodiumUtil.h"
#import "UserModel.h"
#import "NSString+Base64.h"

@interface ImportAccountViewController ()

@end

@implementation ImportAccountViewController
- (void)viewWillAppear:(BOOL)animated
{
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleDefault;
    [super viewWillAppear:animated];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}
- (IBAction)scannerAction:(id)sender {
    [self scannerOldCoder];
}
- (IBAction)backAction:(id)sender {
    [self leftNavBarItemPressedWithPop:YES];
}

- (void) scannerOldCoder
{
    @weakify_self
    QRViewController *vc = [[QRViewController alloc] initWithCodeQRCompleteBlock:^(NSString *codeValue) {
        if (codeValue != nil && codeValue.length > 0) {
            NSArray *codeValues = [codeValue componentsSeparatedByString:@","];
            NSString *type = codeValues[0];
            if ([[NSString getNotNullValue:type] isEqualToString:@"type_3"]) {
                [LibsodiumUtil changeUserPrivater:codeValues[1]];
                NSString *name = [codeValues[2] base64DecodedString];
                [UserModel createUserLocalWithName:name];
                [AppD setRootLogin];
            } else {
                [weakSelf.view showHint:@"format error."];
            }
        }
    }];
    [self presentModalVC:vc animated:YES];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end