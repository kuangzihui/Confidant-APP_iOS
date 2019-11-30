//
//  PNFloderContentViewController.m
//  MyConfidant
//
//  Created by 旷自辉 on 2019/11/21.
//  Copyright © 2019 旷自辉. All rights reserved.
//

#import "PNFloderContentViewController.h"
#import "FingerprintVerificationUtil.h"
#import "UploadFileCell.h"
#import <YBImageBrowser/YBImageBrowser.h>
#import "TZImagePickerController.h"
#import "PNFileOptionView.h"
#import "SystemUtil.h"
#import "NSData+Base64.h"
#import "AESCipher.h"
#import "NSDate+Category.h"
#import "PNFileModel.h"
#import "PNFloderModel.h"

@interface PNFloderContentViewController ()<UITableViewDelegate,UITableViewDataSource,YBImageBrowserDelegate,TZImagePickerControllerDelegate,UINavigationControllerDelegate,
UIImagePickerControllerDelegate>

@property (weak, nonatomic) IBOutlet UITableView *mainTabView;
@property (nonatomic, strong) PNFileOptionView *optionView;
@property (nonatomic, strong) NSMutableArray *dataArray;
@property (nonatomic, strong) PNFloderModel *floderM;
@property (nonatomic, assign) NSInteger selFileCount;
@property (nonatomic, assign) NSInteger finshFileCount;
@end

@implementation PNFloderContentViewController

#pragma mark-------------layz
- (PNFileOptionView *)optionView
{
    if (!_optionView) {
        _optionView = [PNFileOptionView loadPNFileOptionView];
        [_optionView setClickMenuBlock:^(NSInteger tag) {
            if (tag == 10) { // 上传到节点
                
            } else { // 删除
                
            }
        }];
    }
    return _optionView;
}
- (NSMutableArray *)dataArray
{
    if (!_dataArray) {
        _dataArray = [NSMutableArray array];
    }
    return _dataArray;
}

- (IBAction)clickBackAction:(id)sender {
    [self leftNavBarItemPressedWithPop:YES];
}
- (IBAction)clickAddAction:(id)sender {
    [self pushTZImagePickerControllerWithIsSelectImgage:YES];
}
- (IBAction)clickSelAction:(id)sender {
    
}
- (instancetype)initWithFloderM:(PNFloderModel *)floderM
{
    if (self = [super init]) {
        self.floderM = floderM;
    }
    return self;
}
- (void)viewDidLoad {
    
    [super viewDidLoad];
    self.view.backgroundColor = MAIN_GRAY_COLOR;
    
    [FingerprintVerificationUtil checkFloderShow];
    
    _mainTabView.delegate = self;
    _mainTabView.dataSource = self;
    _mainTabView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    [_mainTabView registerNib:[UINib nibWithNibName:UploadFileCellResue bundle:nil] forCellReuseIdentifier:UploadFileCellResue];
    
    // 查询文件夹文件
    [self checkFloderFileList];
}

- (void) checkFloderFileList
{
    NSArray *colums = @[bg_sqlKey(@"fId"),bg_sqlKey(@"Depens"),bg_sqlKey(@"Type"),bg_sqlKey(@"Fname"),bg_sqlKey(@"Size"),bg_sqlKey(@"LastModify"),bg_sqlKey(@"Finfo"),bg_sqlKey(@"FKey"),bg_sqlKey(@"PathId"),bg_sqlKey(@"progressV"),bg_sqlKey(@"uploadStatus")];
    
        NSString *columString = [colums componentsJoinedByString:@","];
          //NSString *sql  = [NSString stringWithFormat:@"select %@ from %@ where %@=%@ order by %@ desc limit 100",columString,EN_FILE_TABNAME,bg_sqlKey(@"PathId"),bg_sqlValue(@(_floderM.fId)),bg_sqlKey(@"updateTime")];
        NSString *sql  = [NSString stringWithFormat:@"select %@ from %@ where %@=%@",columString,EN_FILE_TABNAME,bg_sqlKey(@"PathId"),bg_sqlValue(@(_floderM.fId))];
    
    @weakify_self
    [weakSelf.view showHudInView:weakSelf.view hint:@""];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *results = bg_executeSql(sql, EN_FILE_TABNAME,[PNFileModel class]);
        dispatch_async(dispatch_get_main_queue(), ^{
             [weakSelf.view hideHud];
            if (results) {
                [weakSelf.dataArray addObjectsFromArray:results];
                [weakSelf.mainTabView reloadData];
            }
        });
       
    });
}

#pragma mark -----------------tableview deleate ---------------------
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}
- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.dataArray.count;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *headView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SCREEN_WIDTH, 30)];
    headView.backgroundColor = MAIN_GRAY_COLOR;
    UILabel *lblName  =[[UILabel alloc] initWithFrame:CGRectMake(20, 0, 150, 30)];
    lblName.textColor = [UIColor blackColor];
    lblName.font = [UIFont systemFontOfSize:12];
    [headView addSubview:lblName];
    if (section == 0) {
        lblName.text = @"UPLOADING";
    } else {
         lblName.text = @"UPLOADING";
    }
    return headView;
}
- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UploadFileCellHeight;
}
- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UploadFileCell *myCell = [tableView dequeueReusableCellWithIdentifier:UploadFileCellResue];
    
//    if (indexPath.section == 1) {
//         myCell.progress.progress = 0;
//        [myCell.optionBtn setImage:[UIImage imageNamed:@"statusbar_hedo"] forState:UIControlStateNormal];
//    } else {
//        [myCell.optionBtn setImage:[UIImage imageNamed:@"noun_play_b"] forState:UIControlStateNormal];
//    }
    if (indexPath.section == 0) {
         myCell.progress.progress = 0;
        [myCell.optionBtn setImage:[UIImage imageNamed:@"statusbar_hedo"] forState:UIControlStateNormal];
    }
    [myCell setFileM:self.dataArray[indexPath.row]];
    @weakify_self
    [myCell setOptionBlock:^{
        if (indexPath.section == 0) { // 本地文件
             [weakSelf.optionView showOptionEnumView];
        } else { // 上传中文件
            
        }
    }];
    return myCell;
}
- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark ---选择相册
/**
 跳转到选择图片vc
 
 @param isImage 是
 */
- (void)pushTZImagePickerControllerWithIsSelectImgage:(BOOL) isImage {
    
    TZImagePickerController *imagePickerVc = [[TZImagePickerController alloc] initWithMaxImagesCount:1 columnNumber:3 delegate:self pushPhotoPickerVc:YES];
    // imagePickerVc.navigationBar.translucent = NO;
    
#pragma mark - 五类个性化设置，这些参数都可以不传，此时会走默认设置
    imagePickerVc.isSelectOriginalPhoto = NO;
    imagePickerVc.allowTakePicture = NO; // 在内部显示拍照按钮
    imagePickerVc.allowTakeVideo = NO;   // 在内部显示拍视频按
    imagePickerVc.videoMaximumDuration = 15; // 视频最大拍摄时间
    [imagePickerVc setUiImagePickerControllerSettingBlock:^(UIImagePickerController *imagePickerController) {
        imagePickerController.videoQuality = UIImagePickerControllerQualityTypeHigh;
    }];
    
    
    imagePickerVc.iconThemeColor = [UIColor colorWithRed:31 / 255.0 green:185 / 255.0 blue:34 / 255.0 alpha:1.0];
    imagePickerVc.showPhotoCannotSelectLayer = YES;
    imagePickerVc.cannotSelectLayerColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    [imagePickerVc setPhotoPickerPageUIConfigBlock:^(UICollectionView *collectionView, UIView *bottomToolBar, UIButton *previewButton, UIButton *originalPhotoButton, UILabel *originalPhotoLabel, UIButton *doneButton, UIImageView *numberImageView, UILabel *numberLabel, UIView *divideLine) {
        [doneButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    }];
    
    // 3. 设置是否可以选择视频/图片/原图
    imagePickerVc.allowPickingVideo = YES;
    imagePickerVc.allowPickingImage = YES;
    imagePickerVc.allowPickingOriginalPhoto = YES;
    imagePickerVc.allowPickingGif = NO;
    imagePickerVc.allowPickingMultipleVideo = YES; //是否可以多选视频
    
    // 4. 照片排列按修改时间升序
    imagePickerVc.sortAscendingByModificationDate = YES;
    imagePickerVc.maxImagesCount = 9;
    imagePickerVc.alwaysEnableDoneBtn = YES;
    
    imagePickerVc.showSelectBtn = NO;
    imagePickerVc.allowCrop = NO;
    imagePickerVc.needCircleCrop = NO;
    
    imagePickerVc.statusBarStyle = UIStatusBarStyleLightContent;
    // 设置是否显示图片序号
    imagePickerVc.showSelectedIndex = NO;
    
#pragma mark - 到这里为止
    
    // You can get the photos by block, the same as by delegate.
    // 你可以通过block或者代理，来得到用户选择的照片.
    @weakify_self
    [imagePickerVc setDidFinishPickingPhotosHandle:^(NSArray<UIImage *> *photos, NSArray *assets, BOOL isSelectOriginalPhoto) {
        if (assets && assets.count > 0) {
            weakSelf.selFileCount = assets.count;
            weakSelf.finshFileCount = 0;
            [weakSelf.view showHudInView:weakSelf.view hint:Uploading_Str];
            [assets enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                PHAsset *asset = obj;
                NSString *fName = [asset valueForKey:@"filename"];
                NSLog(@"filename = %@",fName);
                if (asset.mediaType == 1) { // 图片
                    UIImage *img = photos[idx];
                    NSData *imgData = UIImageJPEGRepresentation(img,1.0);
                    if (imgData.length/(1024*1024) > 100) {
                        [AppD.window showHint:@"Image cannot be larger than 100MB"];
                        weakSelf.selFileCount--;
                        if (idx == assets.count-1) {
                            [weakSelf.view hideHud];
                        }
                    } else {
                        [weakSelf sendImgageWithImage:img imgData:imgData imgName:fName];
                    }
                    
                } else if (asset.mediaType == 2) { // 视频
                    [weakSelf getPHAssetVedioWithOverImg:photos[idx] phAsset:asset fName:fName isLast:idx == assets.count-1];
                }
            }];
        }
        /**
         * 该方法是异步执行的，不会阻塞当前线程，而且执行完后会来到
         * completionHandler 的 block 中。
         */
        //            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        //                [PHAssetChangeRequest deleteAssets:assets];
        //            } completionHandler:^(BOOL success, NSError * _Nullable error) {
        //                NSLog(@"----success----");
        //            }];
        
       
    }];
   
    [self presentViewController:imagePickerVc animated:YES completion:nil];
}

/**
 通过资源获取图片的数据
 @param mAsset 资源文件
 */
- (void)fetchImageWithAsset:(PHAsset*)mAsset {
    [[PHImageManager defaultManager] requestImageDataForAsset:mAsset options:nil resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        // 直接得到最终的 NSData 数据
        
    }];
}

/**
 得到选中的图片并发送

 @param img 图片
 @param imgData 图片data
 */
- (void) sendImgageWithImage:(UIImage *) img imgData:(NSData *) imgData imgName:(NSString *) imgName
{
   
    // 生成32位对称密钥
    NSString *msgKey = [SystemUtil get32AESKey];
    NSData *symmetData =[msgKey dataUsingEncoding:NSUTF8StringEncoding];
    NSString *symmetKey = [symmetData base64EncodedString];
    // 自己公钥加密对称密钥
    NSString *srcKey =[LibsodiumUtil asymmetricEncryptionWithSymmetry:symmetKey enPK:[EntryModel getShareObject].publicKey];
    
    NSData *msgKeyData =[[msgKey substringToIndex:16] dataUsingEncoding:NSUTF8StringEncoding];
    imgData = aesEncryptData(imgData,msgKeyData);
    
    PNFileModel *fileM = [[PNFileModel alloc] init];
    fileM.PathId = _floderM.fId;
    fileM.fId = [NSDate getTimestampFromDate:[NSDate date]];
    fileM.Fname = imgName;
    fileM.Size = imgData.length;
    fileM.FKey = srcKey;
    fileM.fileData = imgData;
    fileM.Depens = 1;
    fileM.Type = 1;
    fileM.Finfo = [NSString stringWithFormat:@"%f*%f",img.size.width,img.size.height];
    fileM.bg_tableName = EN_FILE_TABNAME;
    
    @weakify_self
    [fileM bg_saveAsync:^(BOOL isSuccess) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.finshFileCount ++;
            if (weakSelf.finshFileCount == weakSelf.selFileCount) {
                [weakSelf.view hideHud];
            }
            if (isSuccess) {
                [weakSelf.dataArray addObject:fileM];
                [weakSelf.mainTabView reloadData];
            }
        });
    }];
}

/**
 得到选择的视频
 
 @param coverImage 视频封面图
 @param phAsset phasset
 */
- (void) getPHAssetVedioWithOverImg:(UIImage *) coverImage phAsset:(PHAsset *)phAsset fName:(NSString *) fName isLast:(BOOL) isLast
{
    PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
    options.version = PHVideoRequestOptionsVersionOriginal;
    @weakify_self
    [[PHImageManager defaultManager] requestAVAssetForVideo:phAsset options:options resultHandler:^(AVAsset *avAsset, AVAudioMix *audioMix, NSDictionary *info) {
        if ([avAsset isKindOfClass:[AVURLAsset class]]) {
            AVURLAsset* urlAsset = (AVURLAsset*)avAsset;
            NSNumber *size;
            [urlAsset.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            CGFloat sizeMB = [size floatValue]/(1024.0*1024.0);
            if (sizeMB <= 100) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf extractedVideWithAsset:urlAsset evImage:coverImage fName:fName];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [AppD.window showHint:@"Video cannot be larger than 100MB"];
                    weakSelf.selFileCount--;
                    if (isLast) {
                        [weakSelf.view hideHud];
                    }
                });
            }
        }}];
}

/**
 导出视频并发送
 @param asset asset
 @param evImage 封面图
 */
- (void)extractedVideWithAsset:(AVURLAsset *)asset evImage:(UIImage *) evImage fName:(NSString *) fName
{
    NSData *attData = [NSData dataWithContentsOfURL:asset.URL];
   // NSString *attName = [asset.URL lastPathComponent];
    
    // 生成32位对称密钥
    NSString *msgKey = [SystemUtil get32AESKey];
    NSData *symmetData =[msgKey dataUsingEncoding:NSUTF8StringEncoding];
    NSString *symmetKey = [symmetData base64EncodedString];
    // 自己公钥加密对称密钥
    NSString *srcKey =[LibsodiumUtil asymmetricEncryptionWithSymmetry:symmetKey enPK:[EntryModel getShareObject].publicKey];
    
    NSData *msgKeyData =[[msgKey substringToIndex:16] dataUsingEncoding:NSUTF8StringEncoding];
    attData = aesEncryptData(attData,msgKeyData);
    
    PNFileModel *fileM = [[PNFileModel alloc] init];
    fileM.PathId = _floderM.fId;
    fileM.fId = [NSDate getTimestampFromDate:[NSDate date]];
    fileM.Fname = fName;
    fileM.Size = attData.length;
    fileM.Type = 4;
    fileM.FKey = srcKey;
    fileM.fileData = attData;
    fileM.Depens = 1;
    fileM.Finfo = [NSString stringWithFormat:@"%f*%f",evImage.size.width,evImage.size.height];
    fileM.bg_tableName = EN_FILE_TABNAME;
    
    @weakify_self
    [fileM bg_saveAsync:^(BOOL isSuccess) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.finshFileCount ++;
            if (weakSelf.finshFileCount == weakSelf.selFileCount) {
                [weakSelf.view hideHud];
            }
            if (isSuccess) {
                [weakSelf.dataArray addObject:fileM];
                [weakSelf.mainTabView reloadData];
            }
        });
    }];
   
}
@end
