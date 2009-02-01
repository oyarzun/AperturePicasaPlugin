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
//	AperturePicasaPlugin.m
//	AperturePicasaPlugin
//
//	Created by Eider Oliveira on 5/12/08.
//
//  The code for having images in NSTableView was borrowed from this sample:
// http://theocacao.com/document.page/497 written by Scott Stevenson.

#import "AperturePicasaPlugin.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>
#import "GData/GDataServiceGooglePicasaWeb.h"
#import "APPicture.h"

#include <Security/Security.h>

@interface AperturePicasaPlugin(PrivateMethods)
- (GDataServiceTicket *)albumFetchTicket;
- (void)setAlbumFetchTicket:(GDataServiceTicket *)ticket;
- (void)fetchAllAlbums;
- (void)_uploadNextImage;
- (BOOL)uploadPhoto:(APPicture *)picture;
- (GDataServiceGooglePicasaWeb *)picasaWebService;
- (GDataFeedPhotoUser *)albumFeed;
- (void)setAlbumFeed:(GDataFeedPhotoUser *)feed;
- (NSError *)albumFetchError;
- (void)setAlbumFetchError:(NSError *)error;  
- (GDataServiceTicket *)albumFetchTicket;
- (void)setAlbumFetchTicket:(GDataServiceTicket *)ticket;
- (NSString *)_localizedStringForKey:(NSString *)key defaultValue:(NSString *)value;
- (void)updateChangeAlbumList;
- (void)adjustTableInterface;
- (void)authenticate; 
- (void)authenticateWithSavedData;
- (void)changeAlbumSelected:(id)sender;
- (void)showAlbumDetailsWindow:(id)sender;
- (void)uploadPhotoData:(NSData *)photoData index:(int)index;

#pragma mark Utilities

// runs through all the images in the given folder
// (using pathForImages) and sets them as the new
// array for imageList. intended to be run in the
// background, so sets up an NSAutoreleasePool.
- (void)threadedReloadImageList;

@end

#define kUserDefaultUsername @"AperturePicasaPluginDefaultUsername"
#define kUserDefaultSaveToKeychain  @"AperturePicasaPluginDefaultSaveToKeychain"
// http://picasaweb.google.com/data/feed/api/all
static const char kPicasaDomain[] = "picasaweb.goole.com";
static const char kPicasaPath[]  = "data/feed/api/all";

@implementation AperturePicasaPlugin

//---------------------------------------------------------
// initWithAPIManager:
//
// This method is called when a plug-in is first loaded, and
// is a good point to conduct any checks for anti-piracy or
// system compatibility. This is also your only chance to
// obtain a reference to Aperture's export manager. If you
// do not obtain a valid reference, you should return nil.
// Returning nil means that a plug-in chooses not to be accessible.
//---------------------------------------------------------

- (id)initWithAPIManager:(id<PROAPIAccessing>)apiManager
{
	if (self = [super init])
	{
    NSLog(@"initWithAPIManager");       

		_apiManager	= apiManager;
		_exportManager = [[_apiManager apiForProtocol:@protocol(ApertureExportManager)] retain];
		if (!_exportManager)
			return nil;
		
		_progressLock = [[NSLock alloc] init];
		
		// Create our temporary directory
		tempDirectoryPath = [[NSString stringWithFormat:@"%@/AperturePicasaPlugin/",
                          NSTemporaryDirectory()] retain];
		
		// If it doesn't exist, create it
		NSFileManager *fileManager = [NSFileManager defaultManager];
		BOOL isDirectory;
		if (![fileManager fileExistsAtPath:tempDirectoryPath isDirectory:&isDirectory])
		{
			[fileManager createDirectoryAtPath:tempDirectoryPath attributes:nil];
		}
		else if (isDirectory) // If a folder already exists, empty it.
		{
			NSArray *contents = [fileManager directoryContentsAtPath:tempDirectoryPath];
			int i;
			for (i = 0; i < [contents count]; i++)
			{
				NSString *tempFilePath =
            [NSString stringWithFormat:@"%@%@", tempDirectoryPath, [contents objectAtIndex:i]];
				[fileManager removeFileAtPath:tempFilePath handler:nil];
			}
		}
		else // Delete the old file and create a new directory
		{
			[fileManager removeFileAtPath:tempDirectoryPath handler:nil];
			[fileManager createDirectoryAtPath:tempDirectoryPath attributes:nil];
		}
    _tableColumnWidth = 172.0;
    _quotaUsage = 0;
    _authenticated = FALSE;
    [self setShouldCancelExport:NO];
    _username = nil;
    _password = nil;
    _projectName = nil;
    _selectedAlbum = nil;
	}
  NSLog(@"Using %@ as temp dir", tempDirectoryPath);
	return self;
}

- (void)dealloc
{
	// Release the top-level objects from the nib.
	[_topLevelNibObjects makeObjectsPerformSelector:@selector(release)];
	[_topLevelNibObjects release];
	
    // Clean up the temporary files
	[[NSFileManager defaultManager] removeFileAtPath:tempDirectoryPath handler:nil];
	[tempDirectoryPath release];
  
  // Picasa data
  [mAlbumFetchTicket release];
  
	[_progressLock release];
	[_exportManager release];
  [_projectName release];
	
	[super dealloc];
}


#pragma mark -
// UI Methods
#pragma mark UI Methods

- (NSView *)settingsView
{
	if (nil == settingsView) {
    // Load the nib using NSNib, and retain the array of top-level objects so we
    // can release them properly in dealloc
    NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
    NSNib *myNib = [[NSNib alloc] initWithNibNamed:@"AperturePicasaPlugin" bundle:myBundle];
    if ([myNib instantiateNibWithOwner:self topLevelObjects:&_topLevelNibObjects])  {
      [_topLevelNibObjects retain];
    }
    [myNib release];
  }
	return settingsView;
}

- (NSView *)firstView
{
	return firstView;
}

- (NSView *)lastView
{
	return lastView;
}

- (void)willBeActivated
{
	// Nothing to do here
  NSLog(@"willBeActivacted for %d images", [_exportManager imageCount]);
  [self setLoadingImages:YES];
  [self adjustTableInterface];
  [NSThread detachNewThreadSelector:@selector(threadedReloadImageList) toTarget:self withObject:nil];
  [self performSelectorOnMainThread:@selector(authenticateWithSavedData)
                         withObject: nil waitUntilDone: NO];
}

- (void)willBeDeactivated
{
	// Nothing to do here
  NSLog(@"willBeDeactivacted");
}

- (float)tableView:(NSTableView *)tableView heightOfRow:(int)row
{
  NSSize imgSize = [[[[self imageList] objectAtIndex:row] defaultThumbnail] size];
  // If img gets resized, let's get the scaled valued.
  if (imgSize.width == _tableColumnWidth || imgSize.width == 0.0) {
    // No scale needed.
    return imgSize.height;
  }
  return _tableColumnWidth * imgSize.height / imgSize.width;
}

- (void)adjustTableInterface {
  NSSize size = [imageTableView intercellSpacing];
  size.height += 20;
  size.width += 20;
  [imageTableView setIntercellSpacing:size];
  _tableColumnWidth = [[[imageTableView tableColumns] objectAtIndex:0] width];
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
  NSLog(@"Selected picture = %@", [[[self imageList] objectAtIndex:[imageTableView selectedRow]] title]);
}

#pragma mark
// Aperture UI Controls
#pragma mark Aperture UI Controls

- (BOOL)allowsOnlyPlugInPresets
{
	return NO;	
}

- (BOOL)allowsMasterExport
{
	return NO;	
}

- (BOOL)allowsVersionExport
{
	return YES;	
}

- (BOOL)wantsFileNamingControls
{
	return NO;	
}

- (void)exportManagerExportTypeDidChange
{
	// Nothing to do here - this plug-in doesn't show the user any information about the selecte
  // images, so there's no need to see if the count or properties changed here.
}


#pragma mark -
// Save Path Methods
#pragma mark Save/Path Methods

- (BOOL)wantsDestinationPathPrompt
{
	// We have already destermined a temporary destination for our images and we delete them as soon as
	// we're done with them, so the user should not select a location.
	return NO;
}

- (NSString *)destinationPath
{
	return tempDirectoryPath;
}

- (NSString *)defaultDirectory
{
	// Since this plug-in is not asking Aperture to present an open/save dialog,
	// this method should never be called.
	return nil;
}


#pragma mark -
// Export Process Methods
#pragma mark Export Process Methods

- (void)exportManagerShouldBeginExport
{
  // Before telling Aperture to begin generating picture data, test the connection using the
  // user-entered values
  NSLog(@"exportManagerShouldBeginExport to album %@", [_selectedAlbum title]);
  if (_authenticated && _selectedAlbum) {
    [_exportManager shouldBeginExport];
  } else {
    NSString *errorMessage = @"Cannot export images";
    NSString *informativeText = @"";
    if (!_authenticated) {
      informativeText = @"You should provide a password to be able to upload photos";
    } else {
      // No album selected
      informativeText = @"You should choose an album to upload photos to";
    }
    NSAlert *alert = [NSAlert alertWithMessageText:errorMessage
                                     defaultButton:[self _localizedStringForKey:@"OK"
                                                                   defaultValue:@"OK"]
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:informativeText];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert runModal];
  }
  
}

- (void)exportManagerWillBeginExportToPath:(NSString *)path
{
	// Nothing to do here. We could test the path argument and confirm that it's the same path we passe
  // but that's not really necessary.
  NSLog(@"exportManagerWillBeginExportToPath: %@", path);
}

- (BOOL)exportManagerShouldExportImageAtIndex:(unsigned)index
{
	// This plug-in doesn't exclude any images for any reason, so it always returns YES here.
  NSLog(@"exportManagerShouldExportImageAtIndex: %d", index);
	return YES;
}

- (void)exportManagerWillExportImageAtIndex:(unsigned)index
{
	// Nothing to do here - this is just a confirmation that we returned YES above. We could
	// check to make sure we get confirmation messages for every picture.
  //NSLog(@"exportManagerWillExportImageAtIndex: %d", index);
}

- (BOOL)exportManagerShouldWriteImageData:(NSData *)imageData toRelativePath:(NSString *)path forImageAtIndex:(unsigned)index
{
#if 0
  APPicture *picture = [[self imageList] objectAtIndex:index];
  [picture setData:imageData];
  [self uploadPhoto:picture];
	// Increment the current progress
	[self lockProgress];
	exportProgress.currentValue++;
	[self unlockProgress];
	return NO;	
#else
  return YES;
#endif
}

- (void)exportManagerDidWriteImageDataToRelativePath:(NSString *)relativePath
                                     forImageAtIndex:(unsigned)index
{
  unsigned imageCount = [_exportManager imageCount];
	if (!exportedImages)
	{
		exportedImages = [[NSMutableArray alloc] initWithCapacity: imageCount];
	}
  NSLog(@"exportManagerDidWriteImageDataToRelativePath: %@, %d/%d", relativePath, index, imageCount);
	
	// Save the paths of all the images that Aperture has exported
	NSString *imagePath = [NSString stringWithFormat:@"%@%@", tempDirectoryPath, relativePath];
  APPicture *picture = [[self imageList] objectAtIndex:index];
  [picture setPath:imagePath];
	[exportedImages addObject:picture];
	
	// Increment the current progress
	[self lockProgress];
	exportProgress.currentValue++;
	[self unlockProgress];
}

- (void)exportManagerDidFinishExport
{
	// You must call [_exportManager shouldFinishExport] before Aperture will put away the progress window and complete the export.
	// NOTE: You should assume that your plug-in will be deallocated immediately following this call. Be sure you have cleaned up
	// any callbacks or running threads before calling.
	// Now that Aperture has written all the images to disk for us, we will begin uploading them one-by-one. 
	// There are alternative strategies for uploading - sending the data as soon as Aperture gives it to us, or running several
	// simultaneous uploads. But the solution that lets Aperture write them all to disk first, and then uploads them one-by-one is 
	// the simplest for this example.
	
	// Set up our progress to count uploaded bytes instead of images
	[self lockProgress];
  _uploadedCount = 0;
	exportProgress.currentValue = 0;
	[exportProgress.message autorelease];
	exportProgress.message = [[self _localizedStringForKey:@"uploadingImages"
                                            defaultValue:@"Step 2 of 2: Uploading Images..."] retain];
	[self unlockProgress];
	
	// Begin uploading
  [self _uploadNextImage];
}

- (void)exportManagerShouldCancelExport
{
	// You must call [_exportManager shouldCancelExport] here or elsewhere before Aperture will cancel the export process
	// NOTE: You should assume that your plug-in will be deallocated immediately following this call. Be sure you have cleaned up
	// any callbacks or running threads before calling.
  [self setShouldCancelExport:YES];
}

#pragma mark -

#pragma mark Utilities

- (void)threadedReloadImageList
{
  // since this method should be run in a seperate background
  // thread, we need to create our own NSAutoreleasePool, then
  // release it at the end.
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
  // the list of images we'll loaded from this directory
  NSMutableArray* imageList = [[NSMutableArray alloc] init];
  
  // loop through each file name at this location
  int imageCount = [_exportManager imageCount];
  
  for (int i = 0; i < imageCount && [self shouldCancelExport] == NO; i++) {
    NSDictionary* image_dict = [_exportManager propertiesForImageAtIndex:i];
    NSDictionary* image_properties = [image_dict objectForKey:kExportKeyIPTCProperties];
    
    NSImage* thumbnail = [image_dict objectForKey:kExportKeyThumbnailImage];
    if ([thumbnail isValid])
    {
      // drawing the entire, full-sized picture every time the table view
      // scrolls is way too slow, so instead will draw a thumbnail version
      // into a separate NSImage, which acts as a cache
      
      // create a new APPicture
      APPicture* picture = [[APPicture alloc] init];
      
      // set the path of the on-disk picture and our cache instance
      NSString* caption = [image_properties objectForKey:@"Caption/Abstract"];
      if (caption && [caption length] > 0) {
        [picture setDescription:caption];
      } else {
        [picture setDescription:[image_dict objectForKey:kExportKeyVersionName]];
      }
      [picture setTitle:[image_dict objectForKey:kExportKeyVersionName]];

      // Use the project name as a hint for the album name
      if (_projectName == nil) {
        _projectName = [[image_dict objectForKey:kExportKeyProjectName] retain];
      }
      NSString* keywords_string = [image_properties objectForKey:@"Keywords"];
      NSArray* keywords_array = [keywords_string componentsSeparatedByString:@", "];
      [picture setKeywords:keywords_array];
      [picture setDefaultThumbnail:thumbnail];
      
      // add to the APPicture array
      [imageList addObject:picture];
      
      // adding an object to an array retains it, so we can release our reference.
      [picture release];
    } else {
      NSLog(@"Version %@ isn't found an picture", [image_dict objectForKey:kExportKeyVersionName]);
    }
//    
//    // now release the dictionary we received.
//    [image_dict release];        
  }
  
  
  if ([self shouldCancelExport] == NO) {
    // we want to actually set the new value in the main thread, to
    // avoid any mix-ups with Cocoa Bindings
    [self performSelectorOnMainThread: @selector(setImageList:)
                           withObject: imageList
                        waitUntilDone: NO];
  }
  
  [imageList release];
  
  // remember to release the pool    
  [pool release];
}


#pragma mark -
	// Progress Methods
#pragma mark Progress Methods

- (ApertureExportProgress *)progress
{
	return &exportProgress;
}

- (void)lockProgress
{
	
	if (!_progressLock)
		_progressLock = [[NSLock alloc] init];
		
	[_progressLock lock];
}

- (void)unlockProgress
{
	[_progressLock unlock];
}

#pragma mark -
// Actions
#pragma mark Actions/Selectors

- (IBAction)cancelConnection:(id)sender
{
  NSLog(@"cancelConnection %@", [sender description]);
	[NSApp endSheet:connectionWindow];
	[connectionWindow orderOut:self];
  [self setShouldCancelExport:YES];
  [self exportManagerShouldCancelExport];
}

- (void)authenticateWithSavedData
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults] ; 
  NSString *username = [defaults stringForKey:kUserDefaultUsername];
  if (username && [username length]) {
    [usernameField setStringValue:username];
    [self setUsername:username];
    NSLog(@"Got saved username: %@", username);
  }
  BOOL saveToKeychain = [defaults boolForKey:kUserDefaultSaveToKeychain];
  
  char *keychainPassword = "";
  UInt32 keychainPasswordLength = 0;
  // Try to get the password from the keychain
  if (saveToKeychain &&
      SecKeychainFindInternetPassword(NULL, strlen(kPicasaDomain), kPicasaDomain, 0, NULL,
                                      [username cStringLength], [username UTF8String], 
                                      strlen(kPicasaPath), kPicasaPath, 0, kSecProtocolTypeHTTP,
                                      kSecAuthenticationTypeDefault, &keychainPasswordLength,
                                      (void*)&keychainPassword, NULL) == noErr) {
    _password = [NSString stringWithCString:keychainPassword length:keychainPasswordLength];
    [passwordField setStringValue:_password];
    SecKeychainItemFreeContent(NULL, keychainPassword);
    [self setAddToKeychain:TRUE]; 
    NSLog(@"Found %d bytes of password", keychainPasswordLength);
  }
  if ([username length] == 0 || keychainPasswordLength == 0) {
    [self authenticate];
  } else {
    [self connectToPicasa:self];
  }
}

- (void)authenticate
{
  [NSApp beginSheet:authenticationWindow
     modalForWindow:[_exportManager window]
      modalDelegate:self
     didEndSelector:nil
        contextInfo:nil];
}

- (IBAction)cancelAuthentication:(id)sender
{
  NSLog(@"cancelAuthentication %@", [sender description]);
	[NSApp endSheet:authenticationWindow];
	[authenticationWindow orderOut:self];
  _cancelled = TRUE;
  [self exportManagerShouldCancelExport];
}

- (IBAction)connectToPicasa:(id)sender
{
	[NSApp endSheet:authenticationWindow];
	[authenticationWindow orderOut:self];
  NSLog(@"connectToPicasa %@", [sender description]);
  [self setUsername:[usernameField stringValue]];
  _password = [[passwordField stringValue] copy];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults] ; 
  [defaults setObject:_username forKey:kUserDefaultUsername];
  if ([self addToKeychain]) {
    [defaults setBool:TRUE forKey:kUserDefaultSaveToKeychain];
    
    OSStatus result = SecKeychainAddInternetPassword(NULL, strlen(kPicasaDomain), kPicasaDomain,
                                                     0, NULL, [_username length],
                                                     [_username UTF8String], 
                                                     strlen(kPicasaPath), kPicasaPath, 0,
                                                     kSecProtocolTypeHTTP,
                                                     kSecAuthenticationTypeDefault,
                                                     [_password cStringLength],
                                                     (void*)[_password cString], NULL);
    NSLog(@"Adding to keychain result %d", result);
  }
    
  [self fetchAllAlbums];
}

- (void)changeAlbumSelected:(id)sender {
  // move the selected photo to the album represented by the sender menu item
  NSMenuItem *menuItem = sender;
  GDataEntryPhotoAlbum *albumEntry = [menuItem representedObject];
  NSLog(@"selected album: %@", [sender description]);
  if (albumEntry) {
    _selectedAlbum = albumEntry;
  }
}

- (void)showAlbumDetailsWindow:(id)sender {

  // Set a useful default.
  [albumTitleTextField setStringValue:_projectName];

  [NSApp beginSheet:albumDetailsWindow
     modalForWindow:[_exportManager window]
      modalDelegate:self
     didEndSelector:nil
        contextInfo:nil];
}

- (IBAction)cancelCreateAlbum:(id)sender
{
  NSLog(@"cancelCreateAlbum %@", [sender description]);
	[NSApp endSheet:albumDetailsWindow];
	[albumDetailsWindow orderOut:self];
}

#pragma mark -
// Private Methods
#pragma mark Picasa Interface

- (GDataServiceGooglePicasaWeb *)picasaWebService {
  static GDataServiceGooglePicasaWeb* service = nil;
  
  if (!service) {
    [GDataHTTPFetcher setIsLoggingEnabled:true];
    service = [[GDataServiceGooglePicasaWeb alloc] init];
    
    [service setUserAgent:@"AperturePicasaPlugin-1.0"];
    [service setShouldCacheDatedData:YES];
    [service setServiceShouldFollowNextLinks:YES];
    NSArray *modes = [NSArray arrayWithObjects:
                      NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
    [service setRunLoopModes:modes];
  }
  // update the username/password each time the service is requested
  if ([_username length] && [_password length]) {
    [service setUserCredentialsWithUsername:_username password:_password];
  } else {
    [service setUserCredentialsWithUsername:nil password:nil];
  }
  
  return service;
}

- (void)fetchAllAlbums
{
  [self setAlbumFeed:nil];
  [self setAlbumFetchError:nil];
  [self setAlbumFetchTicket:nil];
	// The goal of this method is to attempt to validate the user's values by 
	// connecting to the server and getting a directory listing. In addition
	// to validating the user's input, we also save the list of files on the server
	// and warn the user if they are going to overwrite any files.
	
	// Put up a progress sheet and set the appropriate values
	[connectionProgressIndicator startAnimation:self];
	[connectionStatusField setStringValue:
   [self _localizedStringForKey:@"connectionString"
                   defaultValue:@"Connecting to Picasa Server..."]];
	[NSApp beginSheet:connectionWindow
     modalForWindow:[_exportManager window]
      modalDelegate:self
     didEndSelector:nil
        contextInfo:nil];
	
  GDataServiceGooglePicasaWeb *service = [self picasaWebService];
  NSURL *feedURL = [GDataServiceGooglePicasaWeb picasaWebFeedURLForUserID:_username
                                                                  albumID:nil
                                                                albumName:nil
                                                                  photoID:nil
                                                                     kind:nil
                                                                   access:nil];
  NSLog(@"Album Feed url: %@", [feedURL description]);
  GDataServiceTicket *ticket;
  // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
  // be running. Retain ourself so we can return from the callbacks and clean up correctly.
  [self retain]; 
  ticket = [service fetchPicasaWebFeedWithURL:feedURL
                                     delegate:self
                            didFinishSelector:@selector(albumListFetchTicket:finishedWithFeed:)
                              didFailSelector:@selector(albumListFetchTicket:failedWithError:)];

  [self setAlbumFetchTicket:ticket];
}

// finished album list successfully
- (void)albumListFetchTicket:(GDataServiceTicket *)ticket
            finishedWithFeed:(GDataFeedPhotoUser *)object {
  [self release]; // Remove the retained.
	// Put away the sheet
	[NSApp endSheet:connectionWindow];
	[connectionWindow orderOut:self];
  
  [self setAlbumFeed:object];
  [self setAlbumFetchError:nil];    
  [self setAlbumFetchTicket:nil];
  
  // load the Change Album pop-up button with the
  // album entries
  // TODO(eider): Create a list to hold all album entries
  [self updateChangeAlbumList];
  
  // Set our progress before beginning export activity
  [self lockProgress];
  exportProgress.totalValue = [_exportManager imageCount];
  exportProgress.currentValue = 0;
  exportProgress.indeterminateProgress = NO;
  exportProgress.message = [[self _localizedStringForKey:@"preparingImages"
                                            defaultValue:@"Step 1/2: Preparing Images..."] retain];
  [self unlockProgress];
  
  // we may have got an public access.
  [self setAuthenticated:([[passwordField stringValue] length] > 0)];
} 

// failed
- (void)albumListFetchTicket:(GDataServiceTicket *)ticket
             failedWithError:(NSError *)error {
  [self release]; // Remove the retained.
	// Put away the sheet
	[NSApp endSheet:connectionWindow];
	[connectionWindow orderOut:self];
  
  [self setAlbumFeed:nil];
  [self setAlbumFetchError:error];    
  [self setAlbumFetchTicket:nil];
  
  NSString *errorMessage = [NSString stringWithFormat:[self _localizedStringForKey:@"albumListFetchFormat" defaultValue:@"There was an error fetching albums."]];
  NSString *informativeText = [error localizedDescription];
  NSLog(@"Error: %@: %@", errorMessage, informativeText);
  NSAlert *alert = [NSAlert alertWithMessageText:errorMessage defaultButton:[self _localizedStringForKey:@"OK" defaultValue:@"OK"]
                                 alternateButton:nil otherButton:nil informativeTextWithFormat:informativeText];
  [alert setAlertStyle:NSCriticalAlertStyle];
  [alert runModal];
  // Try again!
  [self authenticate];
}

- (void)updateChangeAlbumList {
  GDataFeedPhotoUser *feed = [self albumFeed];
  unsigned long long quotaUsed = [[feed quotaUsed] unsignedLongLongValue];
  unsigned long long quotaLimit = [[feed quotaLimit] unsignedLongLongValue];
  if (!quotaLimit) quotaLimit = 1;
  unsigned long long quotaPct = (quotaUsed*100/quotaLimit);
  NSLog(@"quota used %ld quota limit %qu = %qu", quotaUsed, quotaLimit, quotaPct);
  [self setQuotaUsage:quotaPct];
  [self setUsername:[feed username]];
  
  NSArray *entries = [feed entries];

  // replace all menu items in the button with the titles and pointers
  // of the feed's entries, but preserve the title
  
  NSString *title = nil;
  if (_selectedAlbum) {
    title = [[_selectedAlbum title] stringValue];
  }  else {
    title = @"Select Album";
  }
  
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:title] autorelease];
  [menu addItemWithTitle:title action:nil keyEquivalent:@""];
  [[menu addItemWithTitle:@"Create new album"
                   action:@selector(showAlbumDetailsWindow:)
            keyEquivalent:@""] setTarget:self];
  
  [albumPopup setMenu:menu];
  
  for (int idx = 0; idx < [entries count]; idx++) {
    GDataEntryPhotoAlbum *albumEntry = [entries objectAtIndex:idx];
    
    title = [[albumEntry title] stringValue];
    NSMenuItem *item = [menu addItemWithTitle:title
                                       action:@selector(changeAlbumSelected:)
                                keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:albumEntry];
  }
  NSLog(@"Album list has %d elements", [albumPopup numberOfItems]);
}

- (IBAction)createAlbum:(id)sender
{
	[NSApp endSheet:albumDetailsWindow];
	[albumDetailsWindow orderOut:self];
  NSLog(@"createAlbum: %@", [sender description]);
  GDataEntryPhotoAlbum *newEntry = [GDataEntryPhotoAlbum albumEntry];
  // get the feed URL for the album we're inserting the photo into
  NSURL *feedURL = [[[self albumFeed] feedLink] URL];
  NSLog(@"url: %@", [feedURL description]);
  [newEntry setTitleWithString:[albumTitleTextField stringValue]];
  [newEntry setSummaryWithString:[albumDescriptionTextView string]];
  if ([albumPublicButton state] == NSOnState) {
    [newEntry setAccess:kGDataPhotoAccessPublic];
  } else {
    [newEntry setAccess:kGDataPhotoAccessPrivate];
  }
  [newEntry setLocation:[albumLocationTextField stringValue]];

  NSLog(@"getting picasa service");
  
  GDataServiceGooglePicasaWeb *service = [self picasaWebService];
  
  NSLog(@"opening ticket");
  // insert the entry into the album feed
  GDataServiceTicket *ticket;
  // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
  // be running. Retain ourself so we can return from the callbacks and clean up correctly.
  [self retain]; 
  ticket = [service fetchPicasaWebEntryByInsertingEntry:newEntry
                                             forFeedURL:feedURL
                                               delegate:self
                                      didFinishSelector:@selector(addAlbumTicket:finishedWithEntry:)
                                        didFailSelector:@selector(addAlbumTicket:failedWithError:)];
  
}
  
// Successfully added album
- (void)addAlbumTicket:(GDataServiceTicket *)ticket
     finishedWithEntry:(GDataEntryPhotoAlbum *)albumEntry
{
  [self release]; // Remove the retained.
  NSLog(@"album created!!!");
  // tell the user that the add worked
  NSBeginAlertSheet(@"Success", nil, nil, nil,
                    [_exportManager window], nil, nil,
                    nil, nil, @"Added album %@.", 
                    [[albumEntry title] stringValue]);
  _selectedAlbum = [albumEntry retain];
  [self updateChangeAlbumList];
} 
  
// failure to add photo
- (void)addAlbumTicket:(GDataServiceTicket *)ticket failedWithError:(NSError *)error {
  [self release]; // Remove the retained.
  NSLog(@"album creation failed!!!");
  NSBeginAlertSheet(@"Add failed", nil, nil, nil,
                    [_exportManager window], nil, nil,
                    nil, nil, @"Album add failed: %@", error);
}
  
  
- (void)_uploadNextImage
{
	if (!exportedImages || ([exportedImages count] == 0))
	{
		// There are no more images to upload. We're done.
		[_exportManager shouldFinishExport];
	}
	else if ([self shouldCancelExport] == YES)
	{
		[_exportManager shouldCancelExport];
	}
	else
	{
		// Read in our picture data
    APPicture *picture =  [exportedImages objectAtIndex:0];
    if ([self uploadPhoto:picture] == NO) {
			// Exit when there's an error like this
      NSString *format = [self _localizedStringForKey:@"fileReadErrorFormat"
                                         defaultValue:@"There was an error reading %@."];
			NSString *errorMessage = [NSString stringWithFormat:format, [[picture path] lastPathComponent]];
			NSString *informativeText = @"";
			NSAlert *alert = [NSAlert alertWithMessageText:errorMessage
                                       defaultButton:@"OK"
                                     alternateButton:nil
                                         otherButton:nil
                           informativeTextWithFormat:informativeText];
			[alert setAlertStyle:NSCriticalAlertStyle];
			[alert runModal];
			
			[_exportManager shouldCancelExport];
      return;
    }
    [self lockProgress];
    exportProgress.message = [[NSString stringWithFormat:@"Step 2 of 2: Uploading picture %d / %d",
                               ++_uploadedCount, [_exportManager imageCount]] retain];
    [self unlockProgress];
    
	}
}

- (BOOL)uploadPhoto:(APPicture*)picture {
  NSLog(@"Loading picture %@ at %@", [picture title], [picture path]);
  if ([picture data]) {
    // make a new entry for the photo
    GDataEntryPhoto *newEntry = [GDataEntryPhoto photoEntry];
      
    // set a title, description, and timestamp
    [newEntry setPhotoDescriptionWithString:[picture description]];    
    [newEntry setTimestamp:[GDataPhotoTimestamp timestampWithDate:[NSDate date]]];
    [newEntry setClient:@"Aperture"];
    [newEntry setTitleWithString:[picture title]];
    
    // attach the NSData and set the MIME type for the photo
    [newEntry setPhotoData:[picture data]];
    
    NSString *mimeType = [GDataEntryBase MIMETypeForFileAtPath:[picture path]
                                               defaultMIMEType:@"picture/jpeg"];
    [newEntry setPhotoMIMEType:mimeType];
    
    // get the feed URL for the album we're inserting the photo into
    NSURL *feedURL = [[_selectedAlbum feedLink] URL];
    
    GDataServiceGooglePicasaWeb *service = [self picasaWebService];
    
    // make service tickets call back into our upload progress selector
    SEL progressSel = @selector(uploadProgress:hasDeliveredByteCount:ofTotalByteCount:);
    [service setServiceUploadProgressSelector:progressSel];
    
    // insert the entry into the album feed
    GDataServiceTicket *ticket;
    NSLog(@"inserting picture in %@", [feedURL description]);
    // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
    // be running. Retain ourself so we can return from the callbacks and clean up correctly.
    [self retain]; 
    ticket = [service fetchPicasaWebEntryByInsertingEntry:newEntry
                                               forFeedURL:feedURL
                                                 delegate:self
                                        didFinishSelector:@selector(addPhotoTicket:finishedWithEntry:)
                                          didFailSelector:@selector(addPhotoTicket:failedWithError:)];
    // no need for future tickets to monitor progress
    [service setServiceUploadProgressSelector:nil];
  } else {
    NSString *photoName = [[picture path] lastPathComponent];
    // nil data from photo file.
    NSBeginAlertSheet(@"Cannot get photo file data", nil, nil, nil,
                      [_exportManager window], nil, nil,
                      nil, nil, @"Could not read photo file: %@", photoName);   
    return NO;
  }  
  return YES;
}

- (void)uploadProgress:(GDataProgressMonitorInputStream *)stream
 hasDeliveredByteCount:(unsigned long long)numberOfBytesWritten
      ofTotalByteCount:(unsigned long long)dataLength {
  //NSLog(@"uploadProgress: %qu/%qu", numberOfBytesWritten, dataLength);
  [self lockProgress];
  exportProgress.currentValue = numberOfBytesWritten;
  exportProgress.totalValue = dataLength;
  [self unlockProgress];
}
  
// photo added successfully
- (void)addPhotoTicket:(GDataServiceTicket *)ticket finishedWithEntry:(GDataEntryPhoto *)photoEntry
{
  [self release]; // Remove the retained.
  NSLog(@"!!!!!!!!Added photo %@", [[photoEntry title] stringValue]);

  // We may be run without disk picture writing. if we are saving at disk, exportedImages cound > 0.
  if ([exportedImages count] > 0) {
    GDataServiceGooglePicasaWeb *service = [self picasaWebService];
    NSURL *postURL = [[photoEntry feedLink] URL];

    // Get the last uploaded picture.
    APPicture *picture = [exportedImages objectAtIndex:0];

    if ([[picture keywords] count] > 0) {
      NSString *keyword = [[picture keywords]componentsJoinedByString:@","];
      GDataEntryPhotoTag* tag = [GDataEntryPhotoTag tagEntryWithString:keyword];
      NSLog(@"Adding %@ to %@", [tag description], [postURL description]);
      // Add tags. Let's ignore the result.
      [service fetchPicasaWebEntryByInsertingEntry:tag
                                        forFeedURL:postURL
                                          delegate:self
                                 didFinishSelector:nil
                                   didFailSelector:nil];
      
    }
    // Delete the last uploaded file
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *imagePath = [picture path];
    [fileManager removeFileAtPath:imagePath handler:nil];
    [exportedImages removeObjectAtIndex:0];
    
    // Upload the next file, if we are reading from disk.
    [self _uploadNextImage];
  }
} 

// failure to add photo
- (void)addPhotoTicket:(GDataServiceTicket *)ticket failedWithError:(NSError *)error {
  [self release]; // Remove the retained.
  NSLog(@"Added photo %@ failed", error);
  if ([self shouldCancelExport] == NO) {
    APPicture *picture = [exportedImages objectAtIndex:0];
    NSString *format = [self _localizedStringForKey:@"uploadErrorFormat"
                                       defaultValue:@"There was an error uploading %@."];
    NSString *errorMessage = [NSString stringWithFormat:format, [[picture path] lastPathComponent]];
    NSAlert *alert = [NSAlert alertWithMessageText:errorMessage
                                     defaultButton:[self _localizedStringForKey:@"OK"
                                                                   defaultValue:@"OK"]
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:[error description]];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert runModal];
  }
  [_exportManager shouldCancelExport];
}
  
  
#pragma mark Setters and Getters

- (GDataFeedPhotoUser *)albumFeed {
  return mUserAlbumFeed; 
}

- (void)setAlbumFeed:(GDataFeedPhotoUser *)feed {
  [mUserAlbumFeed autorelease];
  mUserAlbumFeed = [feed retain];
}

- (NSError *)albumFetchError {
  return mAlbumFetchError; 
}

- (void)setAlbumFetchError:(NSError *)error {
  [mAlbumFetchError release];
  mAlbumFetchError = [error retain];
}

- (GDataServiceTicket *)albumFetchTicket {
  return mAlbumFetchTicket; 
}

- (void)setAlbumFetchTicket:(GDataServiceTicket *)ticket {
  [mAlbumFetchTicket release];
  mAlbumFetchTicket = [ticket retain];
}

- (NSString *)_localizedStringForKey:(NSString *)key defaultValue:(NSString *)value
{
  NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
  NSString *localizedString = [myBundle localizedStringForKey:key value:value table:@"Localizable"];
  
  return localizedString;
}

- (NSMutableArray*)imageList
{
  return _imageList;
}

- (void)setImageList:(NSArray*)aValue
{
  NSMutableArray* oldImageList = _imageList;
  _imageList = [aValue mutableCopy];
  [oldImageList release];
  
  NSLog(@"Set %d images in list", [_imageList count]);
  [self setLoadingImages:NO];
}

- (BOOL)loadingImages
{
  return _loadingImages;
}

- (void)setLoadingImages:(BOOL)newLoadingImages
{
  _loadingImages = newLoadingImages;
}
      
- (NSString*)username
{
  return _username;
}

- (void)setUsername:(NSString*)aValue
{
  NSString* oldUsername = _username;
  _username = [aValue copy];
  [oldUsername release];
}

- (int)quotaUsage
{
  NSLog(@"*********** Returning quota as %d", _quotaUsage);
  return _quotaUsage;
}

- (void)setQuotaUsage:(int)aValue
{
  NSLog(@"Setting quota: %d", aValue);
  _quotaUsage = aValue;
}

- (BOOL)authenticated
{
  return _authenticated;
}

- (void)setAuthenticated:(BOOL)aValue
{
  _authenticated = aValue;
}

- (BOOL)shouldCancelExport
{
	return _cancelled;
}

- (void)setShouldCancelExport:(BOOL)shouldCancel
{
	_cancelled = shouldCancel;
  if (_cancelled == YES) {
    [_exportManager shouldCancelExport];
  }
}

- (BOOL)addToKeychain
{
  return _addToKeychain;
}

- (void)setAddToKeychain:(BOOL)aValue
{
  _addToKeychain = aValue;  
}

@end
