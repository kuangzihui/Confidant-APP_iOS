//
//  RouterAliasViewController.m
//  PNRouter
//
//  Created by Jelly Foo on 2019/2/20.
//  Copyright © 2019 旷自辉. All rights reserved.
//

#import "RouterAliasViewController.h"
#import "AccountManagementViewController.h"
#import "SocketMessageUtil.h"

@interface RouterAliasViewController ()

@property (weak, nonatomic) IBOutlet UIView *headerView;
@property (weak, nonatomic) IBOutlet UITextField *aliasTF;

@end

@implementation RouterAliasViewController

- (void)addObserve {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetRouterNameSuccess:) name:ResetRouterName_Success_Noti object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [self renderView];
}

#pragma mark - Operation
- (void)renderView {
    _headerView.layer.cornerRadius = _headerView.width/2.0;
    _headerView.layer.masksToBounds = YES;
}

- (void)sendResetRouterName {
    [SocketMessageUtil sendUpdateRourerNickName:_aliasTF.text];
}

#pragma mark - Action
- (IBAction)backAction:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)nextAction:(id)sender {
    if (!_aliasTF.text || _aliasTF.text.length <= 0) {
        [AppD.window showHint:@"Please input router alias"];
        return;
    }
    
    [self sendResetRouterName];
}

#pragma mark - Transition
- (void)jumpToAccountManagement {
    AccountManagementViewController *vc = [[AccountManagementViewController alloc] init];
    vc.RouterId = _RouterId;
    vc.Qrcode = _Qrcode;
    vc.IdentifyCode = _IdentifyCode;
    vc.UserSn = _UserSn;
    vc.RouterPW = _RouterPW;
    vc.routerAlias = _aliasTF.text?:@"";
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Noti
- (void)resetRouterNameSuccess:(NSNotification *)noti {
//    NSDictionary *receiveDic = noti.object;
//    NSDictionary *paramsDic = receiveDic[@"params"];
    [self jumpToAccountManagement];
}

@end
