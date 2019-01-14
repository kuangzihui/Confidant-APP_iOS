// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#import "OCTSubmanagerFilesImpl.h"
#import "OCTSubmanagerFilesProgressSubscriber.h"
#import "OCTTox.h"
#import "OCTToxConstants.h"
#import "OCTFileDownloadOperation.h"
#import "OCTFileUploadOperation.h"
#import "OCTRealmManager.h"
#import "OCTLogging.h"
#import "OCTMessageAbstract.h"
#import "OCTMessageFile.h"
#import "OCTFriend.h"
#import "OCTChat.h"
#import "OCTFileStorageProtocol.h"
#import "OCTFilePathInput.h"
#import "OCTFilePathOutput.h"
#import "OCTFileDataInput.h"
#import "OCTFileDataOutput.h"
#import "OCTFileTools.h"
#import "OCTSettingsStorageObject.h"
#import "NSError+OCTFile.h"
#import "ChatListDataUtil.h"
#import "SystemUtil.h"
#import "ToxPullFileTimerUtil.h"

#if TARGET_OS_IPHONE
@import MobileCoreServices;
#endif

static NSString *const kDownloadsTempDirectory = @"me.dvor.objcTox.downloads";

static NSString *const kProgressSubscribersKey = @"kProgressSubscribersKey";
static NSString *const kMessageIdentifierKey = @"kMessageIdentifierKey";

@interface OCTSubmanagerFilesImpl ()

@property (strong, nonatomic, readonly) NSOperationQueue *queue;

@property (strong, nonatomic, readonly) NSObject *filesCleanupLock;
@property (assign, nonatomic) BOOL filesCleanupInProgress;

@end

@implementation OCTSubmanagerFilesImpl
@synthesize dataSource = _dataSource;

#pragma mark -  Lifecycle

- (instancetype)init
{
    self = [super init];

    if (! self) {
        return nil;
    }

    _queue = [NSOperationQueue new];
    _filesCleanupLock = [NSObject new];

    return self;
}

- (void)dealloc
{
    [self.dataSource.managerGetNotificationCenter removeObserver:self];
}

- (void)configure
{
    [self.dataSource.managerGetNotificationCenter addObserver:self
                                                     selector:@selector(friendConnectionStatusChangeNotification:)
                                                         name:kOCTFriendConnectionStatusChangeNotification
                                                       object:nil];
    [self.dataSource.managerGetNotificationCenter addObserver:self
                                                     selector:@selector(userAvatarWasUpdatedNotification)
                                                         name:kOCTUserAvatarWasUpdatedNotification
                                                       object:nil];
    [self.dataSource.managerGetNotificationCenter addObserver:self
                                                     selector:@selector(scheduleFilesCleanup)
                                                         name:kOCTScheduleFileTransferCleanupNotification
                                                       object:nil];

    NSLog(@"cancelling pending files...");
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"fileType == %d OR fileType == %d OR fileType == %d",
                              OCTMessageFileTypeWaitingConfirmation, OCTMessageFileTypeLoading, OCTMessageFileTypePaused];

    [realmManager updateObjectsWithClass:[OCTMessageFile class] predicate:predicate updateBlock:^(OCTMessageFile *file) {
        file.fileType = OCTMessageFileTypeCanceled;
        NSLog(@"cancelling file %@", file);
    }];

    NSLog(@"cancelling pending files... done");

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *downloads = [self downloadsTempDirectory];
    NSLog(@"clearing downloads temp directory %@\ncontents %@",
               downloads,
               [fileManager contentsOfDirectoryAtPath:downloads error:nil]);
    [fileManager removeItemAtPath:downloads error:nil];

    [self scheduleFilesCleanup];
}

#pragma mark -  Public

- (void)sendData:(nonnull NSData *)data
    withFileName:(nonnull NSString *)fileName
          toChat:(nonnull OCTChat *)chat
    failureBlock:(nullable void (^)(NSError *__nonnull error))failureBlock
{
    NSParameterAssert(data);
    NSParameterAssert(fileName);
    NSParameterAssert(chat);

    NSString *filePath = [OCTFileTools createNewFilePathInDirectory:[self uploadsDirectory] fileName:fileName];

    if (! [data writeToFile:filePath atomically:NO]) {
        NSLog(@"cannot save data to uploads directory.");
        if (failureBlock) {
            failureBlock([NSError sendFileErrorCannotSaveFileToUploads]);
        }
        return;
    }

   // [self sendFileAtPath:filePath moveToUploads:NO toChat:chat failureBlock:failureBlock];
}

- (void)sendFileAtPath:(nonnull NSString *)filePath
         moveToUploads:(BOOL)moveToUploads parames:(NSDictionary *) parames
               toFriendId:(int)friendNumber failureBlock:(nullable void (^)(NSError * _Nonnull))failureBlock
{
    NSLog(@"friendNumber = %d",AppD.currentRouterNumber);
    NSParameterAssert(filePath);
   // NSParameterAssert(friendNumber);

    NSString *fileName = [filePath lastPathComponent];
    NSError *error;
    
    if (moveToUploads) {
        NSString *toPath = [OCTFileTools createNewFilePathInDirectory:[self uploadsDirectory] fileName:fileName];

        if (! [[NSFileManager defaultManager] moveItemAtPath:filePath toPath:toPath error:&error]) {
            NSLog(@"cannot move file to uploads %@", error);
            if (failureBlock) {
                failureBlock([NSError sendFileErrorCannotSaveFileToUploads]);
            }
            return;
        }

        filePath = toPath;
    }

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];

    if (! attributes) {
        NSLog(@"cannot read file %@", filePath);
        if (failureBlock) {
            failureBlock([NSError sendFileErrorCannotReadFile]);
        }
        return;
    }

    OCTToxFileSize fileSize = [attributes[NSFileSize] longLongValue];
   

    OCTToxFileNumber fileNumber = [[self.dataSource managerGetTox] fileSendWithFriendNumber:friendNumber
                                                                                       kind:OCTToxFileKindData
                                                                                   fileSize:fileSize
                                                                                     fileId:nil
                                                                                   fileName:fileName
                                                                                      error:&error];

    if (fileNumber == kOCTToxFileNumberFailure) {
        NSLog(@"cannot send file %@", error);
        if (failureBlock) {
            failureBlock([NSError sendFileErrorFromToxFileSendError:error.code]);
        }
        return;
    }
    NSLog(@"filepath = %@ fileNumber = %d",filePath,fileNumber);
    if (parames) {
        [[ChatListDataUtil getShareObject].fileParames setObject:parames forKey:[NSString stringWithFormat:@"%d",fileNumber]];
    }
    //OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];
    /*OCTMessageAbstract *message = [realmManager addMessageWithFileNumber:fileNumber
                                                                fileType:OCTMessageFileTypeWaitingConfirmation
                                                                fileSize:fileSize
                                                                fileName:fileName
                                                                filePath:filePath
                                                                 fileUTI:[self fileUTIFromFileName:fileName]
                                                                    chat:chat
                                                                  sender:nil];*/
    OCTMessageAbstract *message = [[OCTMessageAbstract alloc] init];
    message.uniqueIdentifier = [filePath lastPathComponent];
    NSDictionary *userInfo = [self fileOperationUserInfoWithMessage:message];
    OCTFilePathInput *input = [[OCTFilePathInput alloc] initWithFilePath:filePath];

    OCTFileUploadOperation *operation = [[OCTFileUploadOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                          fileInput:input
                                                                       friendNumber:friendNumber
                                                                         fileNumber:fileNumber
                                                                           fileSize:fileSize
                                                                           userInfo:userInfo
                                                                      progressBlock:[self fileProgressBlockWithMessage:message]
                                                                     etaUpdateBlock:[self fileEtaUpdateBlockWithMessage:message]
                                                                       successBlock:[self fileSuccessBlockWithMessage:message]
                                                                       failureBlock:[self   fileFailureBlockWithMessage:message
                                                                                                       userFailureBlock:failureBlock]];

    [self.queue addOperation:operation];
}

- (void)acceptFileTransfer:(OCTMessageAbstract *)message
              failureBlock:(nullable void (^)(NSError *__nonnull error))failureBlock
{
    if (! message.senderUniqueIdentifier) {
        NSLog(@"specified wrong message: no sender. %@", message);
        if (failureBlock) {
            failureBlock([NSError acceptFileErrorWrongMessage:message]);
        }
        return;
    }

    if (! message.messageFile) {
        NSLog(@"specified wrong message: no messageFile. %@", message);
        if (failureBlock) {
            failureBlock([NSError acceptFileErrorWrongMessage:message]);
        }
        return;
    }

    if (message.messageFile.fileType != OCTMessageFileTypeWaitingConfirmation) {
        NSLog(@"specified wrong message: wrong file type, should be WaitingConfirmation. %@", message);
        if (failureBlock) {
            failureBlock([NSError acceptFileErrorWrongMessage:message]);
        }
        return;
    }

    OCTFilePathOutput *output = [[OCTFilePathOutput alloc] initWithTempFolder:[self downloadsTempDirectory]
                                                                 resultFolder:[self downloadsDirectory]
                                                                     fileName:message.messageFile.fileName];

    NSDictionary *userInfo = [self fileOperationUserInfoWithMessage:message];

    OCTFriend *friend = [[self.dataSource managerGetRealmManager] objectWithUniqueIdentifier:message.senderUniqueIdentifier
                                                                                       class:[OCTFriend class]];

    OCTFileDownloadOperation *operation = [[OCTFileDownloadOperation alloc]
                                           initWithTox:self.dataSource.managerGetTox
                                              fileOutput:output
                                            friendNumber:friend.friendNumber
                                              fileNumber:message.messageFile.internalFileNumber
                                                fileSize:message.messageFile.fileSize
                                                userInfo:userInfo
                                           progressBlock:[self fileProgressBlockWithMessage:message]
                                          etaUpdateBlock:[self fileEtaUpdateBlockWithMessage:message]
                                            successBlock:[self fileSuccessBlockWithMessage:message]
                                            failureBlock:[self   fileFailureBlockWithMessage:message
                                                                            userFailureBlock:failureBlock]];

    [self.queue addOperation:operation];

    [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
        file.fileType = OCTMessageFileTypeLoading;
        [file internalSetFilePath:output.resultFilePath];
    }];
}

- (BOOL)sendCancelFileNumber:(int )fileNumber error:(NSError **)error
{
  return  [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:AppD.currentRouterNumber control:OCTToxFileControlCancel error:nil];
}

- (BOOL)cancelFileTransfer:(OCTMessageAbstract *)message error:(NSError **)error
{
    if (! message.messageFile) {
        NSLog(@"specified wrong message: no messageFile. %@", message);
        if (error) {
            *error = [NSError fileTransferErrorWrongMessage:message];
        }
        return NO;
    }

    OCTFriend *friend = [self friendForMessage:message];

    [self.dataSource.managerGetTox fileSendControlForFileNumber:message.messageFile.internalFileNumber
                                                   friendNumber:friend.friendNumber
                                                        control:OCTToxFileControlCancel
                                                          error:nil];

    OCTFileBaseOperation *operation = [self operationWithFileNumber:message.messageFile.internalFileNumber
                                                       friendNumber:friend.friendNumber];
    [operation cancel];

    [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
        file.fileType = OCTMessageFileTypeCanceled;
    }];

    return YES;
}

- (void)retrySendingFile:(nonnull OCTMessageAbstract *)message
            failureBlock:(nullable void (^)(NSError *__nonnull error))failureBlock
{
    NSParameterAssert(message);

    if (! message.messageFile || (message.messageFile.fileType != OCTMessageFileTypeCanceled)) {
        NSLog(@"specified wrong message: no messageFile. %@", message);
        if (failureBlock) {
            failureBlock([NSError fileTransferErrorWrongMessage:message]);
        }
        return;
    }

    NSString *fileName = message.messageFile.fileName;
    NSString *filePath = [message.messageFile filePath];

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];

    if (! attributes) {
        NSLog(@"cannot read file %@", filePath);
        if (failureBlock) {
            failureBlock([NSError sendFileErrorCannotReadFile]);
        }
        return;
    }

    OCTToxFileSize fileSize = [attributes[NSFileSize] longLongValue];
    OCTFriend *friend = [self friendForMessage:message];
    NSError *error;

    OCTToxFileNumber fileNumber = [[self.dataSource managerGetTox] fileSendWithFriendNumber:friend.friendNumber
                                                                                       kind:OCTToxFileKindData
                                                                                   fileSize:fileSize
                                                                                     fileId:nil
                                                                                   fileName:fileName
                                                                                      error:&error];

    if (fileNumber == kOCTToxFileNumberFailure) {
        NSLog(@"cannot send file %@", error);
        if (failureBlock) {
            failureBlock([NSError sendFileErrorFromToxFileSendError:error.code]);
        }
        return;
    }

    [self updateMessageFile:message withBlock:^(OCTMessageFile *messageFile) {
        messageFile.internalFileNumber = fileNumber;
        messageFile.fileType = OCTMessageFileTypeWaitingConfirmation;
        messageFile.fileSize = fileSize;
    }];

    NSDictionary *userInfo = [self fileOperationUserInfoWithMessage:message];
    OCTFilePathInput *input = [[OCTFilePathInput alloc] initWithFilePath:filePath];

    OCTFileUploadOperation *operation = [[OCTFileUploadOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                          fileInput:input
                                                                       friendNumber:friend.friendNumber
                                                                         fileNumber:fileNumber
                                                                           fileSize:fileSize
                                                                           userInfo:userInfo
                                                                      progressBlock:[self fileProgressBlockWithMessage:message]
                                                                     etaUpdateBlock:[self fileEtaUpdateBlockWithMessage:message]
                                                                       successBlock:[self fileSuccessBlockWithMessage:message]
                                                                       failureBlock:[self   fileFailureBlockWithMessage:message
                                                                                                       userFailureBlock:failureBlock]];

    [self.queue addOperation:operation];
}

- (BOOL)pauseFileTransfer:(BOOL)pause message:(nonnull OCTMessageAbstract *)message error:(NSError **)error
{
    if (! message.messageFile) {
        NSLog(@"specified wrong message: no messageFile. %@", message);
        if (error) {
            *error = [NSError fileTransferErrorWrongMessage:message];
        }
        return NO;
    }

    OCTToxFileControl control;
    OCTMessageFileType type;
    OCTMessageFilePausedBy pausedBy = message.messageFile.pausedBy;

    if (pause) {
        BOOL pausedByFriend = message.messageFile.pausedBy & OCTMessageFilePausedByFriend;

        if ((message.messageFile.fileType != OCTMessageFileTypeLoading) && ! pausedByFriend) {
            NSLog(@"message in wrong state %ld", (long)message.messageFile.fileType);
            return YES;
        }

        control = OCTToxFileControlPause;
        type = OCTMessageFileTypePaused;
        pausedBy |= OCTMessageFilePausedByUser;
    }
    else {
        BOOL pausedByUser = message.messageFile.pausedBy & OCTMessageFilePausedByUser;
        if ((message.messageFile.fileType != OCTMessageFileTypePaused) && ! pausedByUser) {
            NSLog(@"message in wrong state %ld", (long)message.messageFile.fileType);
            return YES;
        }

        control = OCTToxFileControlResume;
        pausedBy &= ~OCTMessageFilePausedByUser;

        type = (pausedBy == OCTMessageFilePausedByNone) ? OCTMessageFileTypeLoading : OCTMessageFileTypePaused;
    }

    OCTFriend *friend = [self friendForMessage:message];

    [self.dataSource.managerGetTox fileSendControlForFileNumber:message.messageFile.internalFileNumber
                                                   friendNumber:friend.friendNumber
                                                        control:control
                                                          error:nil];

    [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
        file.fileType = type;
        file.pausedBy = pausedBy;
    }];

    return YES;
}

- (BOOL)addProgressSubscriber:(nonnull id<OCTSubmanagerFilesProgressSubscriber>)subscriber
              forFileTransfer:(nonnull OCTMessageAbstract *)message
                        error:(NSError **)error
{
    if (! message.messageFile) {
        if (error) {
            *error = [NSError fileTransferErrorWrongMessage:message];
        }
        return NO;
    }

    OCTFriend *friend = [self friendForMessage:message];

    OCTFileBaseOperation *operation = [self operationWithFileNumber:message.messageFile.internalFileNumber
                                                       friendNumber:friend.friendNumber];

    if (! operation) {
        return YES;
    }

    NSString *identifier = operation.userInfo[kMessageIdentifierKey];
    if (! [identifier isEqualToString:message.uniqueIdentifier]) {
        return YES;
    }

    [subscriber submanagerFilesOnProgressUpdate:operation.progress message:message];
    [subscriber submanagerFilesOnEtaUpdate:operation.eta bytesPerSecond:operation.bytesPerSecond message:message];

    NSHashTable *progressSubscribers = operation.userInfo[kProgressSubscribersKey];
    [progressSubscribers addObject:subscriber];

    return YES;
}

- (BOOL)removeProgressSubscriber:(nonnull id<OCTSubmanagerFilesProgressSubscriber>)subscriber
                 forFileTransfer:(nonnull OCTMessageAbstract *)message
                           error:(NSError **)error
{
    if (! message.messageFile) {
        if (error) {
            *error = [NSError fileTransferErrorWrongMessage:message];
        }
        return NO;
    }

    OCTFriend *friend = [self friendForMessage:message];

    OCTFileBaseOperation *operation = [self operationWithFileNumber:message.messageFile.internalFileNumber
                                                       friendNumber:friend.friendNumber];

    if (! operation) {
        return YES;
    }

    NSString *identifier = operation.userInfo[kMessageIdentifierKey];
    if (! [identifier isEqualToString:message.uniqueIdentifier]) {
        return YES;
    }

    NSHashTable *progressSubscribers = operation.userInfo[kProgressSubscribersKey];
    [progressSubscribers removeObject:subscriber];

    return YES;
}

#pragma mark -  OCTToxDelegate

- (void)     tox:(OCTTox *)tox fileReceiveControl:(OCTToxFileControl)control
    friendNumber:(OCTToxFriendNumber)friendNumber
      fileNumber:(OCTToxFileNumber)fileNumber
{
    NSLog(@"fileReceiveControl============");
//    OCTFileBaseOperation *operation = [self operationWithFileNumber:fileNumber friendNumber:friendNumber];
//
//    NSString *identifier = operation.userInfo[kMessageIdentifierKey];
//    OCTMessageAbstract *message;
//
//    if (!identifier) {
//        message = [self.dataSource.managerGetRealmManager objectWithUniqueIdentifier:identifier
//                                                                               class:[OCTMessageAbstract class]];
//    }
//
//    switch (control) {
//        case OCTToxFileControlResume: {
//            [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
//                file.pausedBy &= ~OCTMessageFilePausedByFriend;
//                file.fileType = (file.pausedBy == OCTMessageFilePausedByNone) ? OCTMessageFileTypeLoading : OCTMessageFileTypePaused;
//            }];
//            break;
//        }
//        case OCTToxFileControlPause: {
//            [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
//                file.pausedBy |= OCTMessageFilePausedByFriend;
//                file.fileType = OCTMessageFileTypePaused;
//            }];
//            break;
//        }
//        case OCTToxFileControlCancel: {
//            [operation cancel];
//
//            [self updateMessageFile:message withBlock:^(OCTMessageFile *file) {
//                file.fileType = OCTMessageFileTypeCanceled;
//            }];
//            break;
//        }
//    }
}

- (void)     tox:(OCTTox *)tox fileChunkRequestForFileNumber:(OCTToxFileNumber)fileNumber
    friendNumber:(OCTToxFriendNumber)friendNumber
        position:(OCTToxFileSize)position
          length:(size_t)length
{
    OCTFileBaseOperation *operation = [self operationWithFileNumber:fileNumber friendNumber:friendNumber];

    if ([operation isKindOfClass:[OCTFileUploadOperation class]]) {
    
        BOOL isCancel = NO;
        NSDictionary *parames = [[ChatListDataUtil getShareObject].fileParames objectForKey:[NSString stringWithFormat:@"%d",fileNumber]];
        if (parames) {
            NSString *cancelValue = [[ChatListDataUtil getShareObject].fileCancelParames objectForKey:parames[@"FileId"]];
            if ([[NSString getNotNullValue:cancelValue] isEqualToString:@"1"]) {
                isCancel = YES;
            }
        }
        [(OCTFileUploadOperation *)operation chunkRequestWithPosition:position length:length cancel:isCancel];
    }
    else {
        NSLog(@"operation not found with fileNumber %d friendNumber %d", fileNumber, friendNumber);
        [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlCancel error:nil];
    }
    
    NSLog(@"length = %zu",length);
    if (length == 0) {
        NSLog(@"file 发送成功-----------%d",fileNumber);
        NSDictionary *parames = [[ChatListDataUtil getShareObject].fileParames objectForKey:[NSString stringWithFormat:@"%d",fileNumber]];
        if (parames) {
           NSString *cancelValue = [[ChatListDataUtil getShareObject].fileCancelParames objectForKey:parames[@"FileId"]];
            if (![[NSString getNotNullValue:cancelValue] isEqualToString:@"1"]) {
                 [SendRequestUtil sendToxSendFileWithParames:parames];
            } 
        }
    }
}

- (void)     tox:(OCTTox *)tox fileReceiveForFileNumber:(OCTToxFileNumber)fileNumber
    friendNumber:(OCTToxFriendNumber)friendNumber
            kind:(OCTToxFileKind)kind
        fileSize:(OCTToxFileSize)fileSize
        fileName:(NSString *)fileName
{
    
    if (!fileName) {
        return;
    }
    
    // 告诉对方可以开始发送
    [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlResume error:nil];
    
    NSLog(@"---接受到tox文件。文件number = %d name = %@",fileNumber,fileName);
    
    [[ChatListDataUtil getShareObject].fileNameParames setObject:fileName forKey:[NSString stringWithFormat:@"%d",fileNumber]];
    
    ToxPullFileTimerUtil *toxpull = [[ToxPullFileTimerUtil alloc] init];
    toxpull.date = [NSDate date];
    toxpull.fileKey = [NSString stringWithFormat:@"%d",fileNumber];
    [[ChatListDataUtil getShareObject].pullTimerDic setObject:toxpull forKey:[NSString stringWithFormat:@"%d",fileNumber]];
    
    switch (kind) {
        case OCTToxFileKindData:
            [self dataFileReceiveForFileNumber:fileNumber
                                  friendNumber:friendNumber
                                          kind:kind
                                      fileSize:fileSize
                                      fileName:fileName];
            break;
        case OCTToxFileKindAvatar:
            [self avatarFileReceiveForFileNumber:fileNumber
                                    friendNumber:friendNumber
                                            kind:kind
                                        fileSize:fileSize
                                        fileName:fileName];
            break;
    }
}

- (void)     tox:(OCTTox *)tox fileReceiveChunk:(NSData *)chunk
      fileNumber:(OCTToxFileNumber)fileNumber
    friendNumber:(OCTToxFriendNumber)friendNumber
        position:(OCTToxFileSize)position length:(size_t)length
{
 
    // 更新本次接受时间
   ToxPullFileTimerUtil *timeUtil = [[ChatListDataUtil getShareObject].pullTimerDic objectForKey:[NSString stringWithFormat:@"%d",fileNumber]];
    if (timeUtil) {
        timeUtil.date = [NSDate date];
    }
    
    NSString *fileName = [[ChatListDataUtil getShareObject].fileNameParames objectForKey:[NSString stringWithFormat:@"%d",fileNumber]];
    if (fileName) {
        NSArray *array = [fileName componentsSeparatedByString:@":"];
        NSLog(@"---接受到的文件 length = %zu",length);
        if (length == 0) {
            NSLog(@"---接受到的文件完成");
            NSDictionary *resultDic = @{[NSString stringWithFormat:@"%d",fileNumber]:array};
            [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlCancel error:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:REVER_FILE_PULL_SUCCESS_NOTI object:resultDic];
        } else {
            if (array && array.count > 0) {
                // 异步写入文件
                NSString *filePath = [[SystemUtil getTempBaseFilePath:array[0]] stringByAppendingPathComponent:array[1]];
                filePath = [filePath stringByAppendingString:[NSString stringWithFormat:@"%d",fileNumber]];
                NSLog(@"-----filePath = %@",filePath);
                if (position == 0) {
                    NSLog(@"position == 0");
                    if ([SystemUtil filePathisExist:filePath]) {
                        [SystemUtil removeDocmentFilePath:filePath];
                    }
                }
                [SystemUtil writeDataToFileWithFilePath:filePath withData:chunk];
            }
        }
    }
    
    
    
//    OCTFileBaseOperation *operation = [self operationWithFileNumber:fileNumber friendNumber:friendNumber];
//
//    if ([operation isKindOfClass:[OCTFileDownloadOperation class]]) {
//        [(OCTFileDownloadOperation *)operation receiveChunk:chunk position:position];
//    }
//    else {
//        NSLog(@"operation not found with fileNumber %d friendNumber %d", fileNumber, friendNumber);
//        [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlCancel error:nil];
//    }
//    if (operation.finished)
//    {
//
//    }
}

#pragma mark -  NSNotification

- (void)friendConnectionStatusChangeNotification:(NSNotification *)notification
{
    OCTFriend *friend = notification.object;

    if (! friend) {
        NSLog(@"no friend received in notification %@, exiting", notification);
        return;
    }

    [self sendAvatarToFriend:friend];
}

- (void)userAvatarWasUpdatedNotification
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"connectionStatus != %d", OCTToxConnectionStatusNone];
    RLMResults *onlineFriends = [self.dataSource.managerGetRealmManager objectsWithClass:[OCTFriend class] predicate:predicate];

    for (OCTFriend *friend in onlineFriends) {
        [self sendAvatarToFriend:friend];
    }
}

#pragma mark -  Private

- (void)scheduleFilesCleanup
{
    @synchronized(self.filesCleanupLock) {
        if (self.filesCleanupInProgress) {
            return;
        }
        self.filesCleanupInProgress = YES;
    }

    NSLog(@"cleanup: starting files cleanup");

    NSString *uploads = [self uploadsDirectory];
    NSString *downloads = [self downloadsDirectory];

    __weak OCTSubmanagerFilesImpl *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];

        NSMutableSet *allFiles = [NSMutableSet new];

        NSError *error;
        NSArray<NSString *> *uploadsContents = [fileManager contentsOfDirectoryAtPath:uploads error:&error];
        if (uploadsContents) {
            for (NSString *file in uploadsContents) {
                [allFiles addObject:[uploads stringByAppendingPathComponent:file]];
            }
        }
        else {
            NSLog(@"cleanup: cannot read contents of uploads directory %@, error %@", uploads, error);
        }

        NSArray<NSString *> *downloadsContents = [fileManager contentsOfDirectoryAtPath:downloads error:&error];
        if (downloadsContents) {
            for (NSString *file in downloadsContents) {
                [allFiles addObject:[downloads stringByAppendingPathComponent:file]];
            }
        }
        else {
            NSLog(@"cleanup: cannot read contents of download directory %@, error %@", downloads, error);
        }

        NSLog(@"cleanup: total number of files %lu", (unsigned long)allFiles.count);
        OCTToxFileSize freedSpace = 0;

        for (NSString *path in allFiles) {
            __strong OCTSubmanagerFilesImpl *strongSelf = weakSelf;
            if (! strongSelf) {
                NSLog(@"cleanup: submanager was killed, quiting");
            }

            __block BOOL exists = NO;

            dispatch_sync(dispatch_get_main_queue(), ^{
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"internalFilePath == %@",
                                          [path stringByAbbreviatingWithTildeInPath]];

                OCTRealmManager *realmManager = strongSelf.dataSource.managerGetRealmManager;
                RLMResults *results = [realmManager objectsWithClass:[OCTMessageFile class] predicate:predicate];

                exists = (results.count > 0);
            });

            if (exists) {
                continue;
            }

            NSLog(@"cleanup: found unbounded file, removing it. Path %@", path);

            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
            if (! attributes) {
                NSLog(@"cleanup: cannot read file at path %@, error %@", path, error);
            }

            if ([fileManager removeItemAtPath:path error:&error]) {
                freedSpace += [attributes[NSFileSize] longLongValue];
            }
            else {
                NSLog(@"cleanup: cannot remove file at path %@, error %@", path, error);
            }
        }

        NSLog(@"cleanup: done. Freed %lld bytes.", freedSpace);

        __strong OCTSubmanagerFilesImpl *strongSelf = weakSelf;
        @synchronized(strongSelf.filesCleanupLock) {
            strongSelf.filesCleanupInProgress = NO;
        }
    });
}

- (OCTFileBaseOperation *)operationWithFileNumber:(OCTToxFileNumber)fileNumber friendNumber:(OCTToxFriendNumber)friendNumber
{
    NSString *operationId = [OCTFileBaseOperation operationIdFromFileNumber:fileNumber friendNumber:friendNumber];

    for (OCTFileBaseOperation *operation in [self.queue operations]) {
        if ([operation.operationId isEqualToString:operationId]) {
            return operation;
        }
    }

    return nil;
}

- (void)createDirectoryIfNeeded:(NSString *)path
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    BOOL isDirectory;
    BOOL exists = [fileManager fileExistsAtPath:path isDirectory:&isDirectory];

    if (exists && ! isDirectory) {
        [fileManager removeItemAtPath:path error:nil];
        exists = NO;
    }

    if (! exists) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSString *)downloadsDirectory
{
    id<OCTFileStorageProtocol> fileStorage = self.dataSource.managerGetFileStorage;

    NSString *path = fileStorage.pathForDownloadedFilesDirectory;
    [self createDirectoryIfNeeded:path];

    return path;
}

- (NSString *)uploadsDirectory
{
    id<OCTFileStorageProtocol> fileStorage = self.dataSource.managerGetFileStorage;

    NSString *path = fileStorage.pathForUploadedFilesDirectory;
    [self createDirectoryIfNeeded:path];

    return path;
}

- (NSString *)downloadsTempDirectory
{
    id<OCTFileStorageProtocol> fileStorage = self.dataSource.managerGetFileStorage;

    NSString *path = [fileStorage.pathForTemporaryFilesDirectory stringByAppendingPathComponent:kDownloadsTempDirectory];
    [self createDirectoryIfNeeded:path];

    return path;
}

- (NSString *)fileUTIFromFileName:(NSString *)fileName
{
    NSString *extension = [fileName pathExtension];

    if (! extension) {
        return nil;
    }

    return (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL);
}

- (void)updateMessageFile:(OCTMessageAbstract *)message withBlock:(void (^)(OCTMessageFile *))block
{
    if (! message) {
        NSLog(@"no message to update");
        return;
    }

    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    [realmManager updateObject:message.messageFile withBlock:block];

    // Workaround to force Realm to update OCTMessageAbstract when OCTMessageFile was updated.
    [realmManager updateObject:message withBlock:^(OCTMessageAbstract *message) {
        message.dateInterval = message.dateInterval;
    }];
}

- (OCTFileBaseOperationProgressBlock)fileProgressBlockWithMessage:(OCTMessageAbstract *)message
{
    return ^(OCTFileBaseOperation *__nonnull operation) {
               NSHashTable *progressSubscribers = operation.userInfo[kProgressSubscribersKey];

               for (id<OCTSubmanagerFilesProgressSubscriber> subscriber in progressSubscribers) {
                   [subscriber submanagerFilesOnProgressUpdate:operation.progress message:message];
               }
    };
}

- (OCTFileBaseOperationProgressBlock)fileEtaUpdateBlockWithMessage:(OCTMessageAbstract *)message
{
    return ^(OCTFileBaseOperation *__nonnull operation) {
               NSHashTable *progressSubscribers = operation.userInfo[kProgressSubscribersKey];

               for (id<OCTSubmanagerFilesProgressSubscriber> subscriber in progressSubscribers) {
                   [subscriber submanagerFilesOnEtaUpdate:operation.eta
                                           bytesPerSecond:operation.bytesPerSecond
                                                  message:message];
               }
    };
}

- (OCTFileBaseOperationSuccessBlock)fileSuccessBlockWithMessage:(OCTMessageAbstract *)message
{
   // __weak OCTSubmanagerFilesImpl *weakSelf = self;

    return ^(OCTFileBaseOperation *__nonnull operation) {
//               __strong OCTSubmanagerFilesImpl *strongSelf = weakSelf;
//               [strongSelf updateMessageFile:message withBlock:^(OCTMessageFile *file) {
//
//            file.fileType = OCTMessageFileTypeReady;
//        }];
    };
}

- (OCTFileBaseOperationFailureBlock)fileFailureBlockWithMessage:(OCTMessageAbstract *)message
                                               userFailureBlock:(void (^)(NSError *))userFailureBlock
{
    //__weak OCTSubmanagerFilesImpl *weakSelf = self;

    return ^(OCTFileBaseOperation *__nonnull operation, NSError *__nonnull error) {
             //  __strong OCTSubmanagerFilesImpl *strongSelf = weakSelf;
        
        
        if (userFailureBlock) {
            userFailureBlock(error);
        }
//        [strongSelf updateMessageFile:message withBlock:^(OCTMessageFile *file) {
//            file.fileType = OCTMessageFileTypeCanceled;
//
//            if (userFailureBlock) {
//                userFailureBlock(error);
//            }
//
//        }];
    };
}

- (NSDictionary *)fileOperationUserInfoWithMessage:(OCTMessageAbstract *)message
{
    return @{
               kProgressSubscribersKey : [NSHashTable weakObjectsHashTable],
               kMessageIdentifierKey : message.uniqueIdentifier,
    };
}

- (void)sendAvatarToFriend:(OCTFriend *)friend
{
    NSParameterAssert(friend);

    NSData *avatar = self.dataSource.managerGetRealmManager.settingsStorage.userAvatarData;

    if (! avatar) {
        [[self.dataSource managerGetTox] fileSendWithFriendNumber:friend.friendNumber
                                                             kind:OCTToxFileKindAvatar
                                                         fileSize:0
                                                           fileId:nil
                                                         fileName:nil
                                                            error:nil];
        return;
    }

    OCTToxFileSize fileSize = avatar.length;
    NSData *hash = [self.dataSource.managerGetTox hashData:avatar];

    NSError *error;
    OCTToxFileNumber fileNumber = [[self.dataSource managerGetTox] fileSendWithFriendNumber:friend.friendNumber
                                                                                       kind:OCTToxFileKindAvatar
                                                                                   fileSize:fileSize
                                                                                     fileId:hash
                                                                                   fileName:nil
                                                                                      error:&error];

    if (fileNumber == kOCTToxFileNumberFailure) {
        NSLog(@"cannot send file %@", error);
        return;
    }

    OCTFileDataInput *input = [[OCTFileDataInput alloc] initWithData:avatar];

    OCTFileUploadOperation *operation = [[OCTFileUploadOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                          fileInput:input
                                                                       friendNumber:friend.friendNumber
                                                                         fileNumber:fileNumber
                                                                           fileSize:fileSize
                                                                           userInfo:nil
                                                                      progressBlock:nil
                                                                     etaUpdateBlock:nil
                                                                       successBlock:nil
                                                                       failureBlock:nil];

    [self.queue addOperation:operation];
}

- (void)dataFileReceiveForFileNumber:(OCTToxFileNumber)fileNumber
                        friendNumber:(OCTToxFriendNumber)friendNumber
                                kind:(OCTToxFileKind)kind
                            fileSize:(OCTToxFileSize)fileSize
                            fileName:(NSString *)fileName
{
    if (fileSize == 0) {
        NSLog(@"Received file with size 0, ignoring it.");
        [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlCancel error:nil];
        return;
    }

    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];
    NSString *publicKey = [[self.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
    OCTFriend *friend = [realmManager friendWithPublicKey:publicKey];
    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    [realmManager addMessageWithFileNumber:fileNumber
                                  fileType:OCTMessageFileTypeWaitingConfirmation
                                  fileSize:fileSize
                                  fileName:fileName
                                  filePath:nil
                                   fileUTI:[self fileUTIFromFileName:fileName]
                                      chat:chat
                                    sender:friend];
}

- (void)avatarFileReceiveForFileNumber:(OCTToxFileNumber)fileNumber
                          friendNumber:(OCTToxFriendNumber)friendNumber
                                  kind:(OCTToxFileKind)kind
                              fileSize:(OCTToxFileSize)fileSize
                              fileName:(NSString *)fileName
{
    void (^cancelBlock)() = ^() {
        [self.dataSource.managerGetTox fileSendControlForFileNumber:fileNumber friendNumber:friendNumber control:OCTToxFileControlCancel error:nil];
    };

    NSString *publicKey = [[self.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
    OCTFriend *friend = [[self.dataSource managerGetRealmManager] friendWithPublicKey:publicKey];

    if (fileSize == 0) {
        if (friend.avatarData) {
            [[self.dataSource managerGetRealmManager] updateObject:friend withBlock:^(OCTFriend *theFriend) {
                theFriend.avatarData = nil;
            }];
        }

        cancelBlock();
        return;
    }

    if (fileSize > kOCTManagerMaxAvatarSize) {
        NSLog(@"received avatar is too big, ignoring it, size %lld", fileSize);
        cancelBlock();
        return;
    }

    NSData *hash = [self.dataSource.managerGetTox hashData:friend.avatarData];
    NSData *remoteHash = [self.dataSource.managerGetTox fileGetFileIdForFileNumber:fileNumber
                                                                      friendNumber:friendNumber
                                                                             error:nil];

    if (remoteHash && [hash isEqual:remoteHash]) {
        NSLog(@"received same avatar, ignoring it");
        cancelBlock();
        return;
    }

    OCTFileDataOutput *output = [OCTFileDataOutput new];
    __weak OCTSubmanagerFilesImpl *weakSelf = self;

    OCTFileDownloadOperation *operation = [[OCTFileDownloadOperation alloc] initWithTox:self.dataSource.managerGetTox
                                                                             fileOutput:output
                                                                           friendNumber:friendNumber
                                                                             fileNumber:fileNumber
                                                                               fileSize:fileSize
                                                                               userInfo:nil
                                                                          progressBlock:nil
                                                                         etaUpdateBlock:nil
                                                                           successBlock:^(OCTFileBaseOperation *__nonnull operation) {
        __strong OCTSubmanagerFilesImpl *strongSelf = weakSelf;

        NSString *publicKey = [[strongSelf.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
        OCTFriend *friend = [[strongSelf.dataSource managerGetRealmManager] friendWithPublicKey:publicKey];

        [[strongSelf.dataSource managerGetRealmManager] updateObject:friend withBlock:^(OCTFriend *theFriend) {
            theFriend.avatarData = output.resultData;
        }];
    } failureBlock:nil];

    [self.queue addOperation:operation];
}

- (OCTFriend *)friendForMessage:(OCTMessageAbstract *)message
{
    OCTChat *chat = [[self.dataSource managerGetRealmManager] objectWithUniqueIdentifier:message.chatUniqueIdentifier
                                                                                   class:[OCTChat class]];
    return [chat.friends firstObject];
}

@end
