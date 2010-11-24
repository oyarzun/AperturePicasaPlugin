// Copyright 2008 Eider Oliveira
//
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
//	AperturePicasaPlugin.h
//	AperturePicasaPlugin
//
//	Created by Eider Oliveira on 5/12/08.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "ApertureExportManager.h"
#import "ApertureExportPlugIn.h"
#import <GData/GData.h>
#import "GData/GDataFeedPhotoAlbum.h"
#import "GData/GDataFeedPhoto.h"

@interface AperturePicasaPlugin : NSObject <ApertureExportPlugIn>
{
	// The cached API Manager object, as passed to the -initWithAPIManager: method.
	id _apiManager; 
	
	// The cached Aperture Export Manager object - you should fetch this from the API Manager during -initWithAPIManager:
	NSObject<ApertureExportManager, PROAPIObject> *_exportManager; 
	
	// The lock used to protect all access to the ApertureExportProgress structure
	NSLock *_progressLock;
	
	// Top-level objects in the nib are automatically retained - this array
	// tracks those, and releases them
	NSArray *_topLevelNibObjects;
	
	// The structure used to pass all progress information back to Aperture
	ApertureExportProgress exportProgress;

	// Outlets main plugin user interface
	IBOutlet NSView *settingsView;
	IBOutlet NSView *firstView;
	IBOutlet NSView *lastView;
  IBOutlet NSPopUpButton *albumPopup;
  
  // Outles of authentication sheet.
	IBOutlet NSWindow *authenticationWindow;
  IBOutlet NSTextField *usernameField;
	IBOutlet NSSecureTextField *passwordField;
  IBOutlet NSButton *cancelAuthenticationButton;
  IBOutlet NSButton *connectButton;

  // Outlets to the connection sheet.
	IBOutlet NSWindow *connectionWindow;
	IBOutlet NSProgressIndicator *connectionProgressIndicator;
	IBOutlet NSTextField *connectionStatusField;
	IBOutlet NSButton *connectionCancelButton;
  IBOutlet NSTableView *imageTableView;
  
  // Outlets to the album creation sheet;
  IBOutlet NSWindow *albumDetailsWindow;
  IBOutlet NSTextField *albumTitleTextField;
  IBOutlet NSButton *createAlbumButton;
  IBOutlet NSTextView *albumDescriptionTextView;
  IBOutlet NSTextField *albumLocationTextField;
  IBOutlet NSButton *albumPublicButton;

  // List of images being imported.
  NSMutableArray *_imageList;
  
  // Export and user status.
  BOOL _loadingImages;
  BOOL _authenticated;
  BOOL _cancelled;
  BOOL _addToKeychain;
  
  // Minimum width to fit images + border.
  CGFloat _tableColumnWidth;
  
  // Directory were images are temporarily kept.
	NSString *tempDirectoryPath;
  
  // User information
  NSString *_username;
  NSString *_password;
  
  // Picasa data
  GDataFeedPhotoUser *mUserAlbumFeed; // user feed of album entries
  GDataServiceTicket *mAlbumFetchTicket;
  NSError *mAlbumFetchError;
  NSString *mAlbumImageURLString;
  NSString *_projectName;
  int _quotaUsage;
	GDataEntryPhotoAlbum *_selectedAlbum;
  
	// Upload tracking.
	NSMutableArray *exportedImages;	
  int _uploadedCount;
}

// Actions
- (IBAction)cancelConnection:(id)sender;
- (IBAction)cancelAuthentication:(id)sender;

// Rename this action to savePasswordToKeychain
- (IBAction)connectToPicasa:(id)sender;

- (IBAction)createAlbum:(id)sender;
- (IBAction)cancelCreateAlbum:(id)sender;
- (IBAction)switchUser:(id)sender;

// the getter returns an NSMutableArray but the setter
// takes a regular NSArray. That allows us to accept
// either kind of array as input.
- (NSMutableArray*)imageList;
- (void)setImageList:(NSArray*)aValue;

// a simple BOOL which states if we're busy loading images.
// from a folder. this is what the spinner's animate property
// is bound to.
- (BOOL)loadingImages;
- (void)setLoadingImages:(BOOL)newLoadingImages;

- (NSString*)username;
- (void)setUsername:(NSString*)aValue;

- (int)quotaUsage;
- (void)setQuotaUsage:(int)aValue;

- (BOOL)authenticated;
- (void)setAuthenticated:(BOOL)aAvalue;
- (BOOL)shouldCancelExport;
- (void)setShouldCancelExport:(BOOL)shouldCancel;

// Delegates
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(int)row;
- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification;
- (BOOL)addToKeychain;
- (void)setAddToKeychain:(BOOL)aValue;
@end
