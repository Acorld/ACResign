//
//  AppDelegate.h
//  ACResign
//
//  Created by acorld on 16/4/12.
//  Copyright © 2016年 weidian. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (unsafe_unretained) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSWindow *aboutWindow;

@property (unsafe_unretained) IBOutlet NSTextField *pathField;
@property (unsafe_unretained) IBOutlet NSButton    *browseButton;

@property (unsafe_unretained) IBOutlet NSTextField *dylibPatchField;
@property (unsafe_unretained) IBOutlet NSButton *dylibButton;

@property (unsafe_unretained) IBOutlet NSTextField *provisionTF;
@property (unsafe_unretained) IBOutlet NSButton    *provisioningBrowseButton;

@property (unsafe_unretained) IBOutlet NSTableView *tableView;
@property (unsafe_unretained) IBOutlet NSTextField *statusLabel;
@property (unsafe_unretained) IBOutlet NSTextView *appDescLabel;


@property (unsafe_unretained) IBOutlet NSProgressIndicator *flurry;
@property (unsafe_unretained) IBOutlet NSComboBox *certComboBox;
@property (weak) IBOutlet NSView *unzipProgressView;
@property (weak) IBOutlet NSProgressIndicator *unzipProgress;

@property (unsafe_unretained) IBOutlet NSButton    *resignButton;


- (IBAction)resign:(id)sender;
- (IBAction)browse:(id)sender;
- (IBAction)dylibBrowseAction:(id)sender;
- (IBAction)provisionSelect:(id)sender;

//menu item
- (IBAction)closeAboutWindow:(id)sender;

@end

