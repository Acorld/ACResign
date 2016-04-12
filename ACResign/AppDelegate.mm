//
//  AppDelegate.m
//  ACResign
//
//  Created by acorld on 16/4/12.
//  Copyright © 2016年 weidian. All rights reserved.
//

#import "AppDelegate.h"
#import <Security/Security.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

@interface AppDelegate ()

/// 负责解压的task
@property (nonatomic, strong) NSTask *unzipTask;
@property (nonatomic, strong) NSTask *zipTask;


@property (nonatomic, strong) NSTask *fileCopyTask;
@property (nonatomic, strong) NSTask *provisioningTask;
@property (nonatomic, strong) NSTask *codesignTask;
@property (nonatomic, strong) NSTask *generateEntitlementsTask;
@property (nonatomic, strong) NSTask *verifyTask;
@property (nonatomic, strong) NSTask *certTask;

@property (nonatomic, copy) NSString *sourcePath;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy) NSString *frameworksDirPath;
@property (nonatomic, copy) NSString *frameworkPath;
@property (nonatomic, copy) NSString *workingPath;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *fileName;

@property (nonatomic, copy) NSString *entitlementsResult;
@property (nonatomic, copy) NSString *codesigningResult;
@property (nonatomic, copy) NSString *verificationResult;

@property (nonatomic, copy) NSMutableArray *certComboBoxItems;

@end

//key of bundle id in info.plist
static NSString *kKeyBundleIDPlistApp               = @"CFBundleIdentifier";

//key of bundle id in iTunesArtwork plist
static NSString *kKeyBundleIDPlistiTunesArtwork     = @"softwareVersionBundleId";

//payload folder name
static NSString *kPayloadDirName                    = @"Payload";

//Entitlements info key in provision file
static NSString *kProvisionEntitlementsName         = @"Entitlements";

//info.plist file name
static NSString *kInfoPlistFilename                 = @"Info.plist";

//the last selected .dylib file path
static NSString *kACDylibPathKey                    = @"ACDylibPath";

//the last selected provision file path
static NSString *kACProvisionPathKey                = @"ACProvisionPath";

//the last selected certs file index
static NSString *kACCertIndexPathKey                = @"CERT_INDEX";

//the key of app name in app info dictionary
static NSString *kACAppNameKey                      = @"name";

//the key of app path in app info dictionary
static NSString *kACAppFilePathKey                  = @"path";

//the key of to inject dylib path in app info dictionary
static NSString *kACDylibFilePathKey                = @"dylib";

//the key of sign .mobileprovision file path in app info dictionary
static NSString *kACProvisionFilePathKey            = @"mobileprovision";

//the key of Entitlements path in app info dictionary
static NSString *kACEntitlementsPathName            = @"entitlements";

//static instance
static NSFileManager *fileManager_;
static NSMutableArray *dataSource_;
static NSUserDefaults *defaults_;



@interface AppDelegate ()<NSTableViewDelegate,NSTableViewDataSource>

/// draw all app config scrollview
@property (nonatomic, strong) NSScrollView *canvasScrollView;

/// current index in mutil-commands queue
@property (nonatomic, assign) NSInteger currentCommandIndex;

/// main app bundle identifier
@property (nonatomic, copy) NSString *mainAppBundleID;

/// apple watch bundle identifier
@property (nonatomic, copy) NSString *watchAppBundleID;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self initVariables];
    
    [_flurry setAlphaValue:0.5];
    
    
    // Look up available signing certificates
    [self getCerts];
    
    if ([defaults_ valueForKey:kACProvisionPathKey])
        [self.provisionTF setStringValue:[defaults_ valueForKey:kACProvisionPathKey]];
    
    if ([defaults_ valueForKey:kACDylibPathKey])
    {
        [_dylibPatchField setStringValue:[defaults_ valueForKey:kACDylibPathKey]];
    }
    
    if (![fileManager_ fileExistsAtPath:@"/usr/bin/zip"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the zip utility present at /usr/bin/zip"];
        exit(0);
    }
    if (![fileManager_ fileExistsAtPath:@"/usr/bin/unzip"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the unzip utility present at /usr/bin/unzip"];
        exit(0);
    }
    if (![fileManager_ fileExistsAtPath:@"/usr/bin/codesign"]) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"This app cannot run without the codesign utility present at /usr/bin/codesign"];
        exit(0);
    }
}

- (void)initVariables
{
    _currentCommandIndex = 0;
    fileManager_ = [NSFileManager defaultManager];
    NSDictionary *mainApp = @{kACAppNameKey:@"main App",kACAppFilePathKey:@""};
    dataSource_ = [NSMutableArray arrayWithObjects:mainApp, nil];
    defaults_ = [NSUserDefaults standardUserDefaults];

    self.tableView.dataSource = self;
    self.tableView.delegate = self;
}

- (NSString *)payloadPath{
    return [_workingPath stringByAppendingPathComponent:kPayloadDirName];
}

- (NSString *)appFilePath
{
    NSDictionary *mainApp = [dataSource_ firstObject];
    NSString *path = mainApp[kACAppFilePathKey];
    return path;
}

#pragma mark -UI
#pragma mark -

- (IBAction)dylibBrowseAction:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[kACDylibFilePathKey]];
    
    if ([openDlg runModal] == NSModalResponseOK)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [self.dylibPatchField setStringValue:fileNameOpened];
        
        NSMutableDictionary *selectedDic = [dataSource_[self.tableView.selectedRow] mutableCopy];
        selectedDic[kACDylibFilePathKey] = fileNameOpened;
        [dataSource_ replaceObjectAtIndex:self.tableView.selectedRow withObject:selectedDic];
    }
}

- (IBAction)provisionSelect:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[kACProvisionFilePathKey, @"MOBILEPROVISION"]];
    
    if ([openDlg runModal] == NSModalResponseOK)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [self.provisionTF setStringValue:fileNameOpened];
        
        NSMutableDictionary *selectedDic = [dataSource_[self.tableView.selectedRow] mutableCopy];
        selectedDic[kACProvisionFilePathKey] = fileNameOpened;
        [dataSource_ replaceObjectAtIndex:self.tableView.selectedRow withObject:selectedDic];
    }
}

- (IBAction)closeAboutWindow:(id)sender {
    [self.aboutWindow close];
}

- (IBAction)browse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"ipa", @"IPA"]];
    
    if ([openDlg runModal] == NSModalResponseOK)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_pathField setStringValue:fileNameOpened];
        [self gotoUnzipFile];
    }
}

- (void)disableControls {
    [_pathField setEnabled:FALSE];
    [_browseButton setEnabled:FALSE];
    [_resignButton setEnabled:FALSE];
    [_provisioningBrowseButton setEnabled:NO];
    [self.provisionTF setEnabled:NO];
    [_certComboBox setEnabled:NO];
    [_dylibButton setEnabled:NO];
    
    [_flurry startAnimation:self];
    [_flurry setAlphaValue:1.0];
}

- (void)enableControls {
    [_pathField setEnabled:TRUE];
    [_browseButton setEnabled:TRUE];
    [_resignButton setEnabled:TRUE];
    [_provisioningBrowseButton setEnabled:YES];
    [self.provisionTF setEnabled:YES];
    [_certComboBox setEnabled:YES];
    [_dylibButton setEnabled:YES];
    
    [_flurry stopAnimation:self];
    [_flurry setAlphaValue:0.5];
}


- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    NSInteger count = 0;
    if ([aComboBox isEqual:_certComboBox]) {
        count = [_certComboBoxItems count];
    }
    return count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    id item = nil;
    if ([aComboBox isEqual:_certComboBox]) {
        item = [_certComboBoxItems objectAtIndex:index];
    }
    return item;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return dataSource_.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row;
{
    NSDictionary *app = dataSource_[row];
    return app[kACAppNameKey];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return NO;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row;
{
    [self updateAppConfig:row];
    return YES;
}

#pragma mark - Resign
#pragma mark

- (BOOL)replaceAppSource:(id)config forKey:(NSString *)key atIndex:(NSInteger)index
{
    if (!config || !key || index > dataSource_.count-1) {
        return NO;
    }
    
    NSMutableDictionary *appConfig = [dataSource_[index] mutableCopy];
    appConfig[key] = config;
    [dataSource_ replaceObjectAtIndex:index withObject:appConfig];
    
    return YES;
}

- (NSString *)appConfigForKey:(NSString *)key atIndex:(NSInteger)index
{
    if (!key || index > dataSource_.count-1) {
        return nil;
    }
    
    NSDictionary *appConfig = dataSource_[index];
    NSString *appPath = appConfig[key];
    return appPath;
}

- (void)resetControlsStatus
{
    [self enableControls];
    self.provisionTF.stringValue = @"";
    self.dylibPatchField.stringValue = @"";
    self.dylibPatchField.hidden = YES;
    self.dylibButton.hidden = YES;
    self.appDescLabel.string = @"";
}

- (void)updateAppConfig:(NSInteger)row
{
    [self resetControlsStatus];
    
    NSDictionary *appConfig = dataSource_[row];
    NSString *appPath = appConfig[kACAppFilePathKey];
    self.appDescLabel.string = appPath;
    
    if (row == 0) {
        self.dylibPatchField.hidden = NO;
        self.dylibButton.hidden = NO;
    }
    
    NSString *provisionpath = appConfig[kACProvisionFilePathKey];
    if (provisionpath) {
        self.provisionTF.stringValue = provisionpath;
    }
    
    NSString *dylibPath = appConfig[kACDylibFilePathKey];
    if (dylibPath) {
        self.dylibPatchField.stringValue = dylibPath;
    }
}

- (void)fetchAppPath
{
    [dataSource_ removeAllObjects];
    [self.tableView reloadData];
    [self resetControlsStatus];
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self payloadPath] error:nil];
    
    NSMutableArray *apps = [NSMutableArray new];
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            _appPath = [[self payloadPath] stringByAppendingPathComponent:file];
            [apps insertObject:_appPath atIndex:0];
            break;
        }
    }
    
    NSArray *subPaths = [self appPathsInPath:_appPath];
    [apps addObjectsFromArray:subPaths];
    NSLog(@"apps---->:%@",apps);
    
    [dataSource_ removeAllObjects];
    for (int i = 0; i < apps.count; i++)
    {
        NSString *path = apps[i];
        NSString *name = [path lastPathComponent];
        if (i==0) {
            name = @"Main App";
        }
        
        NSDictionary *app = @{kACAppNameKey:name,kACAppFilePathKey:path};
        [dataSource_ addObject:app];
    }
    
    [self.tableView reloadData];
    
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:YES];
    [self updateAppConfig:0];
}

- (NSArray *)appPathsInPath:(NSString *)path
{
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    NSMutableArray *apps = [NSMutableArray new];
    for (NSString *file in dirContents) {
        NSString *subPath = [path stringByAppendingPathComponent:file];
        
        //只处理是目录的文件
        BOOL isDir;
        [fileManager_ fileExistsAtPath:subPath isDirectory:&isDir];
        if (isDir) {
            
            //fecth .app or .appex file
            NSString *extension = [[file pathExtension] lowercaseString];
            if ([extension isEqualToString:@"app"]
                || [extension isEqualToString:@"appex"])
            {
                [apps addObject:subPath];
            }else {
                //ignore
            }
            
            //查找下一个目录
            NSArray *subPaths = [self appPathsInPath:subPath];
            [apps addObjectsFromArray:subPaths];
        }
    }
    
    return apps;
}

- (void)checkUnzip:(NSTimer *)timer {
    if ([_unzipTask isRunning] == 0) {
        [timer invalidate];
        _unzipTask = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self payloadPath]]) {
            [_statusLabel setStringValue:@"Read app info success!"];
            
            //stop loading ui
            [self.unzipProgressView removeFromSuperview];
            [self.unzipProgress stopAnimation:self];
            
            [self enableControls];
            
            [self fetchAppPath];
            
        } else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Unzip failed"];
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
        }
    }
}

- (void)gotoUnzipFile
{
    _codesigningResult = nil;
    _verificationResult = nil;
    
    _sourcePath = [_pathField stringValue];
    _workingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"com.acorld.app"];
    
    if ([_certComboBox objectValue]) {
        // anything else extension file
        if ([[[_sourcePath pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
            NSLog(@"Setting up working directory in %@",_workingPath);
            [_statusLabel setStringValue:@"Set working dir"];
            
            [[NSFileManager defaultManager] removeItemAtPath:_workingPath error:nil];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:_workingPath withIntermediateDirectories:TRUE attributes:nil error:nil];
            
            if (_sourcePath && [_sourcePath length] > 0) {
                NSLog(@"Unzipping %@",_sourcePath);
                [_statusLabel setStringValue:@"Unzipping original app"];
            }
            
            _unzipTask = [[NSTask alloc] init];
            [_unzipTask setLaunchPath:@"/usr/bin/unzip"];
            [_unzipTask setArguments:[NSArray arrayWithObjects:@"-o", _sourcePath, @"-d", _workingPath, nil]];
            
            //unzip progress ui
            [self.window.contentView addSubview:self.unzipProgressView];
            [self.unzipProgress startAnimation:self];
            
            [self disableControls];
            
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkUnzip:) userInfo:nil repeats:TRUE];
            
            [_unzipTask launch];
        }
        else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"You must choose an *.ipa or *.xcarchive file"];
            [_statusLabel setStringValue:@"Please try again"];
        }
    } else {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"You must choose an signing certificate from dropdown."];
        [_statusLabel setStringValue:@"Please try again"];
    }
}

- (IBAction)resign:(id)sender {
    //Save cert name
    [defaults_ setValue:[NSNumber numberWithInteger:[_certComboBox indexOfSelectedItem]] forKey:kACCertIndexPathKey];
    [defaults_ setValue:[self.provisionTF stringValue] forKey:@"MOBILEPROVISION_PATH"];
    [defaults_ setValue:[_dylibPatchField stringValue] forKey:kACDylibPathKey];
    [defaults_ synchronize];
    
    [self disableControls];
    [self doProvisioning];
}

- (void)injectApp:(NSString *)appPath dylibPath:(NSString *)dylibPath
{
    if (dylibPath.length)
    {
        if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath])
        {
            NSString *targetPath = [appPath stringByAppendingPathComponent:[dylibPath lastPathComponent]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath])
            {
                [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
            }
            
            NSString *result = [self doTask:@"/bin/cp" arguments:[NSArray arrayWithObjects:dylibPath, targetPath, nil]];
            if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath])
            {
                [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[@"Failed to copy dylib file: " stringByAppendingString:result ? result : @""]];
                [_statusLabel setStringValue:[@"Failed to copy dylib file: " stringByAppendingString:result ? result : @""]];
                return;
            }
        }
        
        // Find executable
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *exeName = [info objectForKey:@"CFBundleExecutable"];
        if (exeName == nil)
        {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Inject failed: No CFBundleExecutable on %@", infoPath]];
            [_statusLabel setStringValue:[NSString stringWithFormat:@"Inject failed: No CFBundleExecutable on %@", infoPath]];
            return;
        }
        NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
        [self injectMachO:exePath dylibPath:dylibPath];
    }
}

- (NSString *)doTask:(NSString *)path arguments:(NSArray *)arguments
{
    return [self doTask:path arguments:arguments currentDirectory:nil];
}

- (NSString *)doTask:(NSString *)path arguments:(NSArray *)arguments currentDirectory:(NSString *)currentDirectory
{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = path;
    task.arguments = arguments;
    if (currentDirectory) task.currentDirectoryPath = currentDirectory;
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    NSString *result = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    
    return result;
}

- (void)injectMachO:(NSString *)exePath dylibPath:(NSString *)dylibPath
{
    int fd = open(exePath.UTF8String, O_RDWR, 0777);
    if (fd < 0)
    {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Inject failed: failed to open %@", exePath]];
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Inject failed: failed to open %@", exePath]];
        return;
    }
    else
    {
        uint32_t magic;
        read(fd, &magic, sizeof(magic));
        if (magic == MH_MAGIC || magic == MH_MAGIC_64)
        {
            lseek(fd, 0, SEEK_SET);
            [self injectArchitecture:fd dylibPath:dylibPath exePath:exePath];
        }
        else if (magic == FAT_MAGIC || magic == FAT_CIGAM)
        {
            struct fat_header header;
            lseek(fd, 0, SEEK_SET);
            read(fd, &header, sizeof(fat_header));
            int nArch = header.nfat_arch;
            if (magic == FAT_CIGAM) nArch = [self bigEndianToSmallEndian:header.nfat_arch];
            
            struct fat_arch arch;
            NSMutableArray *offsetArray = [NSMutableArray array];
            for (int i = 0; i < nArch; i++)
            {
                memset(&arch, 0, sizeof(fat_arch));
                read(fd, &arch, sizeof(fat_arch));
                int offset = arch.offset;
                if (magic == FAT_CIGAM) offset = [self bigEndianToSmallEndian:arch.offset];
                [offsetArray addObject:[NSNumber numberWithUnsignedInt:offset]];
            }
            
            for (NSNumber *offsetNum in offsetArray)
            {
                lseek(fd, [offsetNum unsignedIntValue], SEEK_SET);
                [self injectArchitecture:fd dylibPath:dylibPath exePath:exePath];
            }
        }
        
        close(fd);
    }
}

- (void)injectArchitecture:(int)fd dylibPath:(NSString *)dylibPath exePath:(NSString *)exePathForInfoOnly
{
    off_t archPoint = lseek(fd, 0, SEEK_CUR);
    struct mach_header header;
    read(fd, &header, sizeof(header));
    if (header.magic != MH_MAGIC && header.magic != MH_MAGIC_64)
    {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Inject failed: Invalid executable %@", exePathForInfoOnly]];
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Inject failed: Invalid executable %@", exePathForInfoOnly]];
    }
    else
    {
        if (header.magic == MH_MAGIC_64)
        {
            int delta = sizeof(mach_header_64) - sizeof(mach_header);
            lseek(fd, delta, SEEK_CUR);
        }
        
        char *buffer = (char *)malloc(header.sizeofcmds + 2048);
        read(fd, buffer, header.sizeofcmds);
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath])
        {
            dylibPath = [@"@executable_path" stringByAppendingPathComponent:[dylibPath lastPathComponent]];
        }
        const char *dylib = dylibPath.UTF8String;
        struct dylib_command *p = (struct dylib_command *)buffer;
        struct dylib_command *last = NULL;
        for (uint32_t i = 0; i < header.ncmds; i++, p = (struct dylib_command *)((char *)p + p->cmdsize))
        {
            if (p->cmd == LC_LOAD_DYLIB || p->cmd == LC_LOAD_WEAK_DYLIB)
            {
                char *name = (char *)p + p->dylib.name.offset;
                if (strcmp(dylib, name) == 0)
                {
                    NSLog(@"Already Injected: %@ with %s", exePathForInfoOnly, dylib);
                    close(fd);
                    return;
                }
                last = p;
            }
        }
        
        if ((char *)p - buffer != header.sizeofcmds)
        {
            NSLog(@"LC payload not mismatch: %@", exePathForInfoOnly);
        }
        
        if (last)
        {
            struct dylib_command *inject = (struct dylib_command *)((char *)last + last->cmdsize);
            char *movefrom = (char *)inject;
            uint32_t cmdsize = sizeof(*inject) + (uint32_t)strlen(dylib) + 1;
            cmdsize = (cmdsize + 0x10) & 0xFFFFFFF0;
            char *moveout = (char *)inject + cmdsize;
            for (int i = (int)(header.sizeofcmds - (movefrom - buffer) - 1); i >= 0; i--)
            {
                moveout[i] = movefrom[i];
            }
            memset(inject, 0, cmdsize);
            inject->cmd = LC_LOAD_DYLIB;
            inject->cmdsize = cmdsize;
            inject->dylib.name.offset = sizeof(dylib_command);
            inject->dylib.timestamp = 2;
            inject->dylib.current_version = 0x00010000;
            inject->dylib.compatibility_version = 0x00010000;
            strcpy((char *)inject + inject->dylib.name.offset, dylib);
            
            header.ncmds++;
            header.sizeofcmds += inject->cmdsize;
            lseek(fd, archPoint, SEEK_SET);
            write(fd, &header, sizeof(header));
            
            lseek(fd, archPoint + ((header.magic == MH_MAGIC_64) ? sizeof(mach_header_64) : sizeof(mach_header)), SEEK_SET);
            write(fd, buffer, header.sizeofcmds);
        }
        else
        {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:[NSString stringWithFormat:@"Inject failed: No valid LC_LOAD_DYLIB %@", exePathForInfoOnly]];
            [_statusLabel setStringValue:[NSString stringWithFormat:@"Inject failed: No valid LC_LOAD_DYLIB %@", exePathForInfoOnly]];
        }
        
        free(buffer);
    }
}

- (uint32_t)bigEndianToSmallEndian:(uint32_t)bigEndian
{
    uint32_t smallEndian = 0;
    unsigned char *small = (unsigned char *)&smallEndian;
    unsigned char *big = (unsigned char *)&bigEndian;
    for (int i=0; i<4; i++)
    {
        small[i] = big[3-i];
    }
    return smallEndian;
}


- (BOOL)doITunesMetadataBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_workingPath error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            infoPlistPath = [_workingPath stringByAppendingPathComponent:file];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistiTunesArtwork newBundleID:newBundleID plistOutOptions:NSPropertyListXMLFormat_v1_0];
    
}

- (BOOL)doAppBundleIDChange:(NSString *)newBundleID {
    NSString *appPath = [self appConfigForKey:kACAppFilePathKey atIndex:_currentCommandIndex];
    NSString *infoPlistPath = [appPath stringByAppendingPathComponent:kInfoPlistFilename];
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistApp newBundleID:newBundleID plistOutOptions:NSPropertyListBinaryFormat_v1_0];
}

- (BOOL)changeBundleIDForFile:(NSString *)filePath bundleIDKey:(NSString *)bundleIDKey newBundleID:(NSString *)newBundleID plistOutOptions:(NSPropertyListWriteOptions)options {
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        plist = [[NSMutableDictionary alloc] initWithContentsOfFile:filePath];
        
        //WatchKit App Info.plist中的WKCompanionAppBundleIdentifier配置项必须与iOS App的Info.plist中的CFBundleIdentifier保持一致。
        if (plist[@"WKCompanionAppBundleIdentifier"] && _mainAppBundleID) {
            [plist setObject:_mainAppBundleID forKey:@"WKCompanionAppBundleIdentifier"];
            _watchAppBundleID = newBundleID;
        }else {
            //WatchKit App扩展配置文件Info.plist中的NSExtensionAttributes配置项WKAppBundleIdentifier必须和其通用配置文件中的属性CFBundleIdentifier保持一致；
            NSDictionary *extension = plist[@"NSExtension"];
            if (extension.count) {
                NSDictionary *attri = extension[@"NSExtensionAttributes"];
                if (attri.count) {
                    if (attri[@"WKAppBundleIdentifier"] && _watchAppBundleID) {
                        
                        NSMutableDictionary *mEX = [extension mutableCopy];
                        NSMutableDictionary *mAttri = [attri mutableCopy];
                        [mAttri setObject:_watchAppBundleID forKey:@"WKAppBundleIdentifier"];
                        [mEX setObject:mAttri forKey:@"NSExtensionAttributes"];
                        plist[@"NSExtension"] = mEX;
                    }
                }
            }
            
        }
        
        [plist setObject:newBundleID forKey:bundleIDKey];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:(NSPropertyListFormat)options options:kCFPropertyListImmutable error:nil];
        
        return [xmlData writeToFile:filePath atomically:YES];
        
    }
    
    return NO;
}


- (void)doProvisioning {
    
    NSString *appPath = [self appConfigForKey:kACAppFilePathKey atIndex:_currentCommandIndex];
    NSString *provisionPath = [self appConfigForKey:kACProvisionFilePathKey atIndex:_currentCommandIndex];
    
    if (!appPath
        || ![fileManager_ fileExistsAtPath:appPath]
        || !provisionPath
        || ![fileManager_ fileExistsAtPath:provisionPath] ) {
        [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"provision file don't exsit"];
        [self enableControls];
        [_statusLabel setStringValue:@"Ready"];
        return;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
        NSLog(@"Found embedded.mobileprovision, deleting.");
        [[NSFileManager defaultManager] removeItemAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
    }
    
    NSString *targetPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    
    _provisioningTask = [[NSTask alloc] init];
    [_provisioningTask setLaunchPath:@"/bin/cp"];
    [_provisioningTask setArguments:[NSArray arrayWithObjects:provisionPath, targetPath, nil]];
    
    [_provisioningTask launch];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkProvisioning:) userInfo:nil repeats:TRUE];
}

- (void)checkProvisioning:(NSTimer *)timer {
    if ([_provisioningTask isRunning] == 0) {
        
        [timer invalidate];
        _provisioningTask = nil;
        
        NSDictionary *appConfig = dataSource_[_currentCommandIndex];
        NSString *currentAppPath = appConfig[kACAppFilePathKey];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[currentAppPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
            
            NSDictionary *provisioningDic = [self getEntilementsDicForProvisionFile:[currentAppPath stringByAppendingPathComponent:@"embedded.mobileprovision"]];
            NSLog(@"provisioningDic：%@",provisioningDic);
            
            NSDictionary *entitlements = provisioningDic[kProvisionEntitlementsName];
            if (!entitlements) {
                
                [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"entitlements don't exsit in provision"];
                [self enableControls];
                [_statusLabel setStringValue:@"Ready"];
                return;
            }
            
            // MARK: Acorld ----> Step Generate entitlements file
            //save entitlements in workpath
            NSString *entitlementsFile = [_workingPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Entitlements.plist",[self fileNameForPath:currentAppPath]]];
            NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:kCFPropertyListImmutable error:nil];
            [xmlData writeToFile:entitlementsFile atomically:YES];
            [self replaceAppSource:entitlementsFile forKey:kACEntitlementsPathName atIndex:_currentCommandIndex];
            
            // MARK: Acorld ----> Step Replace bundle id
            NSString *appIdentifier = entitlements[@"application-identifier"];
            NSRange range = [appIdentifier rangeOfString:@"."];
            NSString *bundleid = [appIdentifier substringFromIndex:NSMaxRange(range)];
            NSLog(@"replace app:%@ bundleid:%@",[currentAppPath lastPathComponent],bundleid);
            [self doAppBundleIDChange:bundleid];
            
            if (_currentCommandIndex == 0) {
                _mainAppBundleID = bundleid;
                //replace iTunesMetadata.plist bundle id
                [self doITunesMetadataBundleIDChange:bundleid];
            }
            
            //判断签名是否
            if (_currentCommandIndex!=dataSource_.count-1) {
                _currentCommandIndex ++;
                [self doProvisioning];
                return;
            }
            
            _currentCommandIndex = NSIntegerMax;
            NSLog(@"Provisioning completed.");
            [_statusLabel setStringValue:@"Provisioning completed"];
            
            // MARK: Acorld ----> Step check entitlements exsit
            [self doEntitlementsFixing];
        } else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Provisioning failed"];
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
        }
    }
}

- (void)doEntitlementsFixing
{
    [_statusLabel setStringValue:@"Check entitlements"];
    
    for (int i = 0; i < dataSource_.count; i++)
    {
        NSString *entitlementPath = [self appConfigForKey:kACEntitlementsPathName atIndex:i];
        if (![fileManager_ fileExistsAtPath:entitlementPath]) {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"entitlements check failed"];
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
            return;
        }
    }
    
    // MARK: Acorld ----> Step codesign
    [self doCodeSigning];
}

- (void)doCodeSigning {
    
    //desc order
    if (_currentCommandIndex == NSIntegerMax) {
        _currentCommandIndex = dataSource_.count-1;
    }
    
    if (_currentCommandIndex < 0) {
        //finish
        return;
    }
    
    NSString *appPath = [self appConfigForKey:kACAppFilePathKey atIndex:_currentCommandIndex];
    NSLog(@"Found: %@",appPath);
    [_statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",[appPath lastPathComponent]]];
    
    if (_currentCommandIndex == 0) {
        // MARK: Acorld ----> Step Inject dylib
        //check inject .dylib
        NSString *dylibPath = [self appConfigForKey:kACDylibFilePathKey atIndex:_currentCommandIndex];
        if (dylibPath) {
            
            [self injectApp:appPath dylibPath:dylibPath];
        }
    }
    
    // MARK: Acorld ----> Step Start Codesign...
    NSString *entitlementsPath = [self appConfigForKey:kACEntitlementsPathName atIndex:_currentCommandIndex];
    [self signFile:appPath entitlements:entitlementsPath];
}

- (void)signFile:(NSString*)filePath  entitlements:(NSString *)entitlementsPath{
    NSLog(@"Codesigning %@", filePath);
    [_statusLabel setStringValue:[NSString stringWithFormat:@"Codesigning %@",filePath]];
    
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", [_certComboBox objectValue], nil];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", filePath];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    [infoDict removeObjectForKey:@"CFBundleResourceSpecification"];
    [infoDict writeToFile:infoPath atomically:YES];
    [arguments addObject:@"--no-strict"]; // http://stackoverflow.com/a/26204757
    
    //code sign entitlements.plist
    if (entitlementsPath.length) {
        [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", entitlementsPath]];
    }
    
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:filePath, nil]];
    
    _codesignTask = [[NSTask alloc] init];
    [_codesignTask setLaunchPath:@"/usr/bin/codesign"];
    [_codesignTask setArguments:arguments];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCodesigning:) userInfo:nil repeats:TRUE];
    
    
    NSPipe *pipe=[NSPipe pipe];
    [_codesignTask setStandardOutput:pipe];
    [_codesignTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [_codesignTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchCodesigning:)
                             toTarget:self withObject:handle];
}

- (void)watchCodesigning:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        _codesigningResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    }
}

- (void)checkCodesigning:(NSTimer *)timer {
    if ([_codesignTask isRunning] == 0) {
        [timer invalidate];
        _codesignTask = nil;
        
        NSLog(@"Codesigning done");
        [_statusLabel setStringValue:@"Codesigning completed"];
        
        // MARK: Acorld ----> Step Verify codesign
        [self doVerifySignature];
    }
}

- (void)doVerifySignature {
    NSString *appPath = [self appConfigForKey:kACAppFilePathKey atIndex:_currentCommandIndex];
    if (appPath) {
        _verifyTask = [[NSTask alloc] init];
        [_verifyTask setLaunchPath:@"/usr/bin/codesign"];
        [_verifyTask setArguments:[NSArray arrayWithObjects:@"-v", appPath, nil]];
        
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkVerificationProcess:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Verifying %@",appPath);
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Verifying %@",[appPath lastPathComponent]]];
        
        NSPipe *pipe=[NSPipe pipe];
        [_verifyTask setStandardOutput:pipe];
        [_verifyTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [_verifyTask launch];
        
        [NSThread detachNewThreadSelector:@selector(watchVerificationProcess:)
                                 toTarget:self withObject:handle];
    }
}

- (void)watchVerificationProcess:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        _verificationResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    }
}

- (void)checkVerificationProcess:(NSTimer *)timer {
    if ([_verifyTask isRunning] == 0) {
        
        NSString *appPath = [self appConfigForKey:kACAppFilePathKey atIndex:_currentCommandIndex];
        [timer invalidate];
        _verifyTask = nil;
        if ([_verificationResult length] == 0) {
            NSLog(@"Verification done");
            [_statusLabel setStringValue:[NSString stringWithFormat:@"Verification %@ completed!",[appPath lastPathComponent]]];
            
            // MARK: Acorld ----> Step start new codesign
            if (_currentCommandIndex > 0) {
                _currentCommandIndex --;
                [self doCodeSigning];
                return;
            }
            
            // MARK: Acorld ----> Step zip
            [self doZip];
        } else {
            NSString *error = [[_codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:_verificationResult];
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:[NSString stringWithFormat:@"Signing failed %@",[appPath lastPathComponent]] AndMessage:error];
            [self enableControls];
            [_statusLabel setStringValue:@"Please try again"];
        }
    }
}

- (void)doZip {
    NSString *mainAppPath = [self appConfigForKey:kACAppFilePathKey atIndex:0];
    if (mainAppPath) {
        NSArray *destinationPathComponents = [_sourcePath pathComponents];
        NSString *destinationPath = @"";
        
        for (int i = 0; i < ([destinationPathComponents count]-1); i++) {
            destinationPath = [destinationPath stringByAppendingPathComponent:[destinationPathComponents objectAtIndex:i]];
        }
        
        _fileName = [_sourcePath lastPathComponent];
        _fileName = [_fileName substringToIndex:([_fileName length] - ([[_sourcePath pathExtension] length] + 1))];
        _fileName = [_fileName stringByAppendingString:@"-resigned"];
        _fileName = [_fileName stringByAppendingPathExtension:@"ipa"];
        
        destinationPath = [destinationPath stringByAppendingPathComponent:_fileName];
        
        NSLog(@"Dest: %@",destinationPath);
        
        _zipTask = [[NSTask alloc] init];
        [_zipTask setLaunchPath:@"/usr/bin/zip"];
        [_zipTask setCurrentDirectoryPath:_workingPath];
        [_zipTask setArguments:[NSArray arrayWithObjects:@"-qry", destinationPath, @".", nil]];
        
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkZip:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Zipping %@", destinationPath);
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Saving %@",_fileName]];
        
        [_zipTask launch];
    }
}

- (void)checkZip:(NSTimer *)timer {
    if ([_zipTask isRunning] == 0) {
        [timer invalidate];
        _zipTask = nil;
        NSLog(@"Zipping done");
        [_statusLabel setStringValue:[NSString stringWithFormat:@"Saved %@",_fileName]];
        
        [[NSFileManager defaultManager] removeItemAtPath:_workingPath error:nil];
        
        [self enableControls];
        
        NSString *result = [[_codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:_verificationResult];
        NSLog(@"Codesigning result: %@",result);
    }
}



#pragma mark - Tools
#pragma mark -

- (NSString *)fileNameForPath:(NSString *)path
{
    return [[[path lastPathComponent] componentsSeparatedByString:@"."] firstObject];
}

- (NSDictionary *)getEntilementsDicForProvisionFile:( NSString * _Nonnull )provisionFile
{
    CMSDecoderRef decoder = NULL;
    CFDataRef dataRef = NULL;
    NSString *plistString = nil;
    NSDictionary *plist = nil;
    
    @try {
        CMSDecoderCreate(&decoder);
        NSData *fileData = [NSData dataWithContentsOfFile:provisionFile];
        CMSDecoderUpdateMessage(decoder, fileData.bytes, fileData.length);
        CMSDecoderFinalizeMessage(decoder);
        CMSDecoderCopyContent(decoder, &dataRef);
        plistString = [[NSString alloc] initWithData:(__bridge NSData *)dataRef encoding:NSUTF8StringEncoding];
        plist = [plistString propertyList];
    }
    @catch (NSException *exception) {
        printf("Could not decode file.\n");
    }
    @finally {
        if (decoder) CFRelease(decoder);
        if (dataRef) CFRelease(dataRef);
    }
    
    printf("%s", [plistString UTF8String]);
    
    return plist;
}

#pragma mark - Get certs
#pragma mark -
- (void)getCerts {
    
    NSLog(@"Getting Certificate IDs");
    [_statusLabel setStringValue:@"Getting Cert IDs"];
    
    _certTask = [[NSTask alloc] init];
    [_certTask setLaunchPath:@"/usr/bin/security"];
    [_certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-v", @"-p", @"codesigning", nil]];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCerts:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [_certTask setStandardOutput:pipe];
    [_certTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [_certTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchGetCerts:) toTarget:self withObject:handle];
}

- (void)watchGetCerts:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        NSString *securityResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        // Verify the security result
        if (securityResult == nil || securityResult.length < 1) {
            // Nothing in the result, return
            return;
        }
        NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
        NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
        for (int i = 0; i <= [rawResult count] - 2; i+=2) {
            
            if (rawResult.count - 1 < i + 1) {
                // Invalid array, don't add an object to that position
            } else {
                // Valid object
                [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
            }
        }
        
        _certComboBoxItems = [NSMutableArray arrayWithArray:tempGetCertsResult];
        
        [_certComboBox reloadData];
        
    }
}

- (void)checkCerts:(NSTimer *)timer {
    if ([_certTask isRunning] == 0) {
        [timer invalidate];
        _certTask = nil;
        
        if ([_certComboBoxItems count] > 0) {
            NSLog(@"Get Certs done");
            [_statusLabel setStringValue:@"Signing Certificate IDs extracted"];
            
            if ([defaults_ valueForKey:kACCertIndexPathKey]) {
                
                NSInteger selectedIndex = [[defaults_ valueForKey:kACCertIndexPathKey] integerValue];
                if (selectedIndex != -1) {
                    NSString *selectedItem = [self comboBox:_certComboBox objectValueForItemAtIndex:selectedIndex];
                    [_certComboBox setObjectValue:selectedItem];
                    [_certComboBox selectItemAtIndex:selectedIndex];
                }
                
                [self enableControls];
            }
        } else {
            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Getting Certificate ID's failed"];
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
        }
    }
}

#pragma mark - ...
#pragma mark -
// If the application dock icon is clicked, reopen the window
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    // Make sure the window is visible
    if (![self.window isVisible]) {
        // Window isn't shown, show it
        [self.window makeKeyAndOrderFront:self];
    }
    
    // Return YES
    return YES;
}

#pragma mark - Alert Methods

/* NSRunAlerts are being deprecated in 10.9 */

// Show a critical alert
- (void)showAlertOfKind:(NSAlertStyle)style WithTitle:(NSString *)title AndMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:style];
    [alert runModal];
}

@end
