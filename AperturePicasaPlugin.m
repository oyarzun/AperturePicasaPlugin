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
#import "GData/GDataServiceGooglePhotos.h"
#import "APPicture.h"

#include <Security/Security.h>

#ifdef DEBUG
	#define DebugLog( s, ... ) NSLog( @"<%s : (%d)> %@",__FUNCTION__, __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
	#define DebugLog( s, ... ) 
#endif


@interface AperturePicasaPlugin(PrivateMethods)
- (GDataServiceTicket *)albumFetchTicket;
- (void)setAlbumFetchTicket:(GDataServiceTicket *)ticket;
- (void)fetchAllAlbums;
- (void)_uploadNextImage;
- (BOOL)uploadPhoto:(APPicture *)picture;
- (GDataServiceGooglePhotos *)photoService;
- (GDataFeedPhotoUser *)albumFeed;
- (void)setAlbumFeed:(GDataFeedBase *)feed;
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
// array for imageList. Sets all data except thumbnail

- (void)reloadImageList;

// Runs through all the images given by _exportManager
// and sets the thumbnails in the imaglist created
// by reloadImageList. intended to be run in the
// background, so sets up an NSAutoreleasePool.
- (void)threadLoadThumbNails;

// Create the directory at path, creating the parent directories if necessary.
// Shows a modal error message in case of error.
- (BOOL)createDirectory:(NSString *) path;

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

- (BOOL)createDirectory:(NSString *)path
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSError *createError;
  if ([fileManager createDirectoryAtPath:path 
              withIntermediateDirectories:TRUE
                               attributes:nil
                                    error:&createError])
    return YES;
  NSString *errorMessage = [self _localizedStringForKey:@"createDirectoryFormat" 
                                           defaultValue:@"There was an error creating directory."];
  NSString *informativeText = [createError localizedDescription];
  DebugLog(@"Error: %@: %@", errorMessage, informativeText);
  NSAlert *alert = [NSAlert alertWithMessageText:errorMessage defaultButton:[self _localizedStringForKey:@"OK" defaultValue:@"OK"]
                                 alternateButton:nil otherButton:nil informativeTextWithFormat:informativeText];
  [alert setAlertStyle:NSCriticalAlertStyle];
  [alert runModal];      
  [createError release];
  return NO;
}

- (id)initWithAPIManager:(id<PROAPIAccessing>)apiManager
{
	tempDirectoryPath= NULL;
	if (self = [super init])
	{
    DebugLog(@"initWithAPIManager");       

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
      if (![self createDirectory:tempDirectoryPath]) 
        return nil;
		}
		else if (isDirectory) // If a folder already exists, empty it.
		{
			NSArray *contents = [fileManager contentsOfDirectoryAtPath:tempDirectoryPath error:NULL];
			int i;
			for (i = 0; i < [contents count]; i++)
			{
				NSString *tempFilePath =
            [NSString stringWithFormat:@"%@%@", tempDirectoryPath, [contents objectAtIndex:i]];
				[fileManager removeItemAtPath:tempFilePath error:NULL];
			}
		}
		else // Delete the old file and create a new directory
		{
			[fileManager removeItemAtPath:tempDirectoryPath error:NULL];
      if (![self createDirectory:tempDirectoryPath])
        return nil;
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
	
#ifdef DEBUG
	if(tempDirectoryPath != NULL)
		DebugLog(@"Using %@ as temp dir", tempDirectoryPath);
	else
		DebugLog(@"Using NULL as temp dir");
#endif	
	return self;
}

- (void)dealloc
{
	// Release the top-level objects from the nib.
	[_topLevelNibObjects makeObjectsPerformSelector:@selector(release)];
	[_topLevelNibObjects release];
	
    // Clean up the temporary files
	[[NSFileManager defaultManager] removeItemAtPath:tempDirectoryPath error:NULL];
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
	DebugLog(@"willBeActivacted for %d images", [_exportManager imageCount]);
	[self setLoadingImages:YES];
	[self adjustTableInterface];

	// We have to load the metadata from the main thread because otherwise Aperture only give us metadata for 
	// images whose metadata has been recently viewed in Aperture. We first load the image metadata minus
	// thumbnails since loading thumbnails is slow and we want the user to be able to start working asap.
	// We then add the thumbnails in a background thread.
	
		// First load the list with all metadata except thumbnails from the main thread:
	[self reloadImageList];
		// Then add the Thumbnails in a separate thread
  [NSThread detachNewThreadSelector:@selector(threadLoadThumbNails) toTarget:self withObject:nil];

  [self performSelectorOnMainThread:@selector(authenticateWithSavedData)
                         withObject: nil waitUntilDone: NO];
}

- (void)willBeDeactivated
{
	// Nothing to do here
  DebugLog(@"willBeDeactivacted");
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(int)row
{
  NSSize imgSize = [[[[self imageList] objectAtIndex:row] defaultThumbnail] size];
  // If img gets resized, let's get the scaled valued.
  if (imgSize.width == _tableColumnWidth || imgSize.width == (CGFloat)0.0) {
    // No scale needed.
    return imgSize.height;
  }
  return _tableColumnWidth * imgSize.height / imgSize.width;
}

- (void)adjustTableInterface {
  NSSize size = [imageTableView intercellSpacing];
  size.height += (CGFloat)20.0;
  size.width += (CGFloat)20.0;
  [imageTableView setIntercellSpacing:size];
  _tableColumnWidth = [[[imageTableView tableColumns] objectAtIndex:0] width];
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
  DebugLog(@"Selected picture = %@", [[[self imageList] objectAtIndex:[imageTableView selectedRow]] title]);
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
  DebugLog(@"exportManagerShouldBeginExport to album %@", [_selectedAlbum title]);
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
  DebugLog(@"exportManagerWillBeginExportToPath: %@", path);
}

- (BOOL)exportManagerShouldExportImageAtIndex:(unsigned)index
{
	// This plug-in doesn't exclude any images for any reason, so it always returns YES here.
  DebugLog(@"exportManagerShouldExportImageAtIndex: %d", index);
	return YES;
}

- (void)exportManagerWillExportImageAtIndex:(unsigned)index
{
	// Nothing to do here - this is just a confirmation that we returned YES above. We could
	// check to make sure we get confirmation messages for every picture.
  //DebugLog(@"exportManagerWillExportImageAtIndex: %d", index);
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
  DebugLog(@"exportManagerDidWriteImageDataToRelativePath: %@, %d/%d", relativePath, index, imageCount);
	
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

-(void)threadLoadThumbNails
{
	// since this method should be run in a seperate background
	// thread, we need to create our own NSAutoreleasePool, then
	// release it at the end.
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
      
  // loop through each file name at this location
  int imageCount = [_exportManager imageCount];
  for (int i = 0; i < imageCount && [self shouldCancelExport] == NO; i++) {
    NSImage* thumbnail = [_exportManager thumbnailForImageAtIndex:i size: kExportThumbnailSizeThumbnail];
    if ([thumbnail isValid])
    {
      // drawing the entire, full-sized picture every time the table view
      // scrolls is way too slow, so instead will draw a thumbnail version
      // into a separate NSImage, which acts as a cache

			// Since performSelectorOnMainThread takes one argument and we need to send two we put our args in a dictionary.
			// The key is the index for the image and the value is the thumbnail
      NSDictionary * dict = [NSDictionary dictionaryWithObject: thumbnail forKey: [NSNumber numberWithInt: i]];
		
			// sync up with the mainnthread and set the thumbnail
      [self performSelectorOnMainThread: @selector(setThumbNailFromDict:)
                             withObject: dict
                          waitUntilDone: NO];      
    } else {
      DebugLog(@"Could not get thumbnail for image with index %d.", i);
    }
  }
	[self performSelectorOnMainThread: @selector(setDoneLoadingThumbnails:)
                        withObject: nil
                        waitUntilDone: NO];      
  
  // remember to release the pool    
  [pool release];
}

- (void)reloadImageList
{
		// Some size for our placeholder image
	const NSSize kThumbnailSize = {172, 172};
	
	// the list of images we'll loaded from this directory
	NSMutableArray* imageList = [[NSMutableArray alloc] init];

	// loop through each file name at this location
	int imageCount = [_exportManager imageCount];
		
		// We create a placeholder thumbnail. We will replace this with the actual thumbnail
		// from a backgound thread
	NSImage * placeHolderThumbNail = [[NSImage alloc] initWithSize: kThumbnailSize];
	[placeHolderThumbNail setBackgroundColor: [NSColor darkGrayColor]];

	for (int i = 0; i < imageCount && [self shouldCancelExport] == NO; i++) {
		NSDictionary* image_dict = [_exportManager propertiesWithoutThumbnailForImageAtIndex:i];
		NSDictionary* image_properties = [image_dict objectForKey:kExportKeyIPTCProperties];

		if ([placeHolderThumbNail isValid])
		{
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

			[picture setDefaultThumbnail:placeHolderThumbNail];

			// add to the APPicture array
			[imageList addObject:picture];

			// adding an object to an array retains it, so we can release our reference.
			[picture release];
		} else {
			DebugLog(@"Version %@ isn't found an picture", [image_dict objectForKey:kExportKeyVersionName]);
		}
		//    
		// now release the dictionary we received.
		// [image_dict release];        
	}

	if ([self shouldCancelExport] == NO) {
		[self setImageList: imageList];
	}

	[placeHolderThumbNail release];
	[imageList release];
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
  DebugLog(@"cancelConnection %@", [sender description]);
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
    DebugLog(@"Got saved username: %@", username);
  }
  BOOL saveToKeychain = [defaults boolForKey:kUserDefaultSaveToKeychain];
  
  char *keychainPassword = NULL;
  UInt32 keychainPasswordLength = 0;
  // Try to get the password from the keychain
  if (saveToKeychain &&
      SecKeychainFindInternetPassword(NULL, strlen(kPicasaDomain), kPicasaDomain, 0, NULL,
                                      [username lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                      [username UTF8String], 
                                      strlen(kPicasaPath), kPicasaPath, 0, kSecProtocolTypeHTTP,
                                      kSecAuthenticationTypeDefault, &keychainPasswordLength,
                                      (void*)&keychainPassword, NULL) == noErr) {
    DebugLog(@"Found %d bytes of password", keychainPasswordLength);
    _password = [NSString stringWithFormat:@"%*.*s", keychainPasswordLength, keychainPasswordLength, keychainPassword];
    //DebugLog(@"Password: %@", _password);
    if (_password && [_password length]) {
      [passwordField setStringValue:_password];
      [self setAddToKeychain:TRUE]; 
    } else {
      DebugLog(@"Failed converting cstring password to  nsstring");
      keychainPasswordLength = 0;  // consider it failure.
    }
    SecKeychainItemFreeContent(NULL, keychainPassword);
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
  DebugLog(@"cancelAuthentication %@", [sender description]);
	[NSApp endSheet:authenticationWindow];
	[authenticationWindow orderOut:self];
  _cancelled = TRUE;
  [self exportManagerShouldCancelExport];
}

- (IBAction)connectToPicasa:(id)sender
{
	[NSApp endSheet:authenticationWindow];
	[authenticationWindow orderOut:self];
  DebugLog(@"connectToPicasa %@", [sender description]);
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
                                                     [_password lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                     (void*)[_password UTF8String], NULL);
    DebugLog(@"Adding to keychain result %d", result);
  }
    
  [self fetchAllAlbums];
}

- (void)changeAlbumSelected:(id)sender {
  // move the selected photo to the album represented by the sender menu item
  NSMenuItem *menuItem = sender;
  GDataEntryPhotoAlbum *albumEntry = [menuItem representedObject];
  DebugLog(@"selected album: %@", [sender description]);
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
	DebugLog(@"cancelCreateAlbum %@", [sender description]);
	[NSApp endSheet:albumDetailsWindow];
	[albumDetailsWindow orderOut:self];
}

- (IBAction)switchUser:(id)sender;
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults] ; 
	[defaults removeObjectForKey:kUserDefaultUsername];

	[defaults removeObjectForKey:kUserDefaultSaveToKeychain];

	[self authenticate];
}
#pragma mark -
// Private Methods
#pragma mark Picasa Interface

- (GDataServiceGooglePhotos *)photoService {
  static GDataServiceGooglePhotos* service = nil;
  
  if (!service) {
    [GDataHTTPFetcher setIsLoggingEnabled:false];
    service = [[GDataServiceGooglePhotos alloc] init];
    
    [service setUserAgent:@"AperturePicasaPlugin-1.1"];
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
	
  GDataServiceGooglePhotos *service = [self photoService];
  NSURL *feedURL = [GDataServiceGooglePhotos photoFeedURLForUserID:_username
                                                                  albumID:nil
                                                                albumName:nil
                                                                  photoID:nil
                                                                     kind:nil
                                                                   access:nil];
  DebugLog(@"Album Feed url: %@", [feedURL description]);
  GDataServiceTicket *ticket;
  // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
  // be running. Retain ourself so we can return from the callbacks and clean up correctly.
  [self retain]; 
  ticket = [service fetchFeedWithURL:feedURL
                            delegate:self
                   didFinishSelector:@selector(albumListFetchTicket:finishedWithFeed:error:)];

  [self setAlbumFetchTicket:ticket];
}

// finished album list successfully
- (void)albumListFetchTicket:(GDataServiceTicket *)ticket
            finishedWithFeed:(GDataFeedBase *)feed 
                       error:(NSError *)error {
  [self release]; // Remove the retained.
	// Put away the sheet
	[NSApp endSheet:connectionWindow];
	[connectionWindow orderOut:self];
  
  [self setAlbumFeed:feed];
  [self setAlbumFetchError:error];    
  [self setAlbumFetchTicket:nil];
  
  if (!error) {
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
  } else {
    NSString *errorMessage = [self _localizedStringForKey:@"albumListFetchFormat" defaultValue:@"There was an error fetching albums."];
    NSString *informativeText = [error localizedDescription];
    DebugLog(@"Error: %@: %@", errorMessage, informativeText);
    NSAlert *alert = [NSAlert alertWithMessageText:errorMessage defaultButton:[self _localizedStringForKey:@"OK" defaultValue:@"OK"]
                                   alternateButton:nil otherButton:nil informativeTextWithFormat:informativeText];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert runModal];
    // Try again!
    [self authenticate];
  }
} 

- (void)updateChangeAlbumList {
  GDataFeedPhotoUser *feed = [self albumFeed];
  unsigned long long quotaUsed = [[feed quotaUsed] unsignedLongLongValue];
  unsigned long long quotaLimit = [[feed quotaLimit] unsignedLongLongValue];
  if (!quotaLimit) quotaLimit = 1;
  unsigned long long quotaPct = (quotaUsed*100/quotaLimit);
  DebugLog(@"quota used %ld quota limit %qu = %qu", quotaUsed, quotaLimit, quotaPct);
  [self setQuotaUsage:quotaPct];
  //[self setUsername:[feed username]];
  
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
  DebugLog(@"Album list has %d elements", [albumPopup numberOfItems]);
}

- (IBAction)createAlbum:(id)sender
{
	[NSApp endSheet:albumDetailsWindow];
	[albumDetailsWindow orderOut:self];
  DebugLog(@"createAlbum: %@", [sender description]);
  GDataEntryPhotoAlbum *newEntry = [GDataEntryPhotoAlbum albumEntry];
  // get the feed URL for the album we're inserting the photo into
  NSURL *feedURL = [[[self albumFeed] feedLink] URL];
  DebugLog(@"url: %@", [feedURL description]);
  [newEntry setTitleWithString:[albumTitleTextField stringValue]];
  [newEntry setSummaryWithString:[albumDescriptionTextView string]];
  if ([albumPublicButton state] == NSOnState) {
    [newEntry setAccess:kGDataPhotoAccessPublic];
  } else {
    [newEntry setAccess:kGDataPhotoAccessPrivate];
  }
  [newEntry setLocation:[albumLocationTextField stringValue]];

  DebugLog(@"getting picasa service");
  
  GDataServiceGooglePhotos *service = [self photoService];
  
  DebugLog(@"opening ticket");
  // insert the entry into the album feed
  
  // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
  // be running. Retain ourself so we can return from the callbacks and clean up correctly.
  [self retain]; 
  
   [service fetchEntryByInsertingEntry:newEntry
                                    forFeedURL:feedURL
                                      delegate:self
                             didFinishSelector:@selector(addAlbumTicket:finishedWithEntry:error:)];
  
}
  
// Successfully added album
- (void)addAlbumTicket:(GDataServiceTicket *)ticket
     finishedWithEntry:(GDataEntryPhotoAlbum *)albumEntry
                 error:(NSError *)error
{
  [self release]; // Remove the retained.
  if (albumEntry) {
    DebugLog(@"album created!!!");
    // tell the user that the add worked
    NSBeginAlertSheet(@"Success", nil, nil, nil,
                      [_exportManager window], nil, nil,
                      nil, nil, @"Added album %@.", 
                      [[albumEntry title] stringValue]);
    _selectedAlbum = [albumEntry retain];
    [self updateChangeAlbumList];
  } else {
  DebugLog(@"album creation failed!!!");
  NSBeginAlertSheet(@"Add failed", nil, nil, nil,
                    [_exportManager window], nil, nil,
                    nil, nil, @"Album add failed: %@", error);
  }
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
    DebugLog(@"uploadNextImage: %d images to go", [exportedImages count]);
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
  DebugLog(@"Loading picture %@ at %@", [picture title], [picture path]);
  if ([picture data]) {
    // make a new entry for the photo
    GDataEntryPhoto *newEntry = [GDataEntryPhoto photoEntry];
      
    // set a title, description, and timestamp
	// If we do not want to set the description we still need to call setPhotoDescriptionWithString 
	// with an empty string otherwise the caption will get picked up from the IPTC in the image
	[newEntry setPhotoDescriptionWithString: [picture uploadDescription]  ? [picture description] : @""];    
    [newEntry setTimestamp:[GDataPhotoTimestamp timestampWithDate:[NSDate date]]];
    [newEntry setTitleWithString:[picture title]];
    
    // attach the NSData and set the MIME type for the photo
    [newEntry setPhotoData:[picture data]];
    
	NSString *ext = [[picture path] pathExtension];
	//If the file does not for some reason have extension then we'll pass empty mime type for it.
	NSString *mimeType = @"";
	  
	  if(ext){  
		  //Resolve which UTI the system thiks represents the specific file extension.
		  CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,(CFStringRef)ext,NULL);
		  //Convert the UTI to mime type
		  mimeType  = (NSString*)UTTypeCopyPreferredTagWithClass(UTI,kUTTagClassMIMEType);
		  CFRelease(UTI);
	  }  
	  
	DebugLog(@"File mime type is %@", mimeType);
	
    [newEntry setPhotoMIMEType:mimeType];
    
    // get the feed URL for the album we're inserting the photo into
    NSURL *feedURL = [[_selectedAlbum feedLink] URL];
      
    GDataServiceGooglePhotos *service = [self photoService];
    
    // make service tickets call back into our upload progress selector
    SEL progressSel = @selector(uploadProgress:hasDeliveredByteCount:ofTotalByteCount:);
    [service setServiceUploadProgressSelector:progressSel];
    
    // insert the entry into the album feed

    DebugLog(@"inserting picture in %@", [feedURL description]);
    // If Aperture cancels, we immediately tell it to go ahead - but some callbacks may still
    // be running. Retain ourself so we can return from the callbacks and clean up correctly.
    [self retain]; 
    [service fetchEntryByInsertingEntry:newEntry
                                      forFeedURL:feedURL
                                        delegate:self
                               didFinishSelector:@selector(addPhotoTicket:finishedWithEntry:error:)];

	//Not needed anymore by anyone.
	  [mimeType release];
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

- (void)uploadProgress:(GDataServiceTicketBase *)ticket
 hasDeliveredByteCount:(unsigned long long)numberOfBytesWritten
      ofTotalByteCount:(unsigned long long)dataLength {
  DebugLog(@"uploadProgress: %qu/%qu", numberOfBytesWritten, dataLength);
}
  
// photo added successfully
- (void)addPhotoTicket:(GDataServiceTicket *)ticket
     finishedWithEntry:(GDataEntryBase *)photoEntry
                 error:(NSError*) error
{
  [self release]; // Remove the retained.
  // Get the last uploaded picture.
  APPicture *picture = [exportedImages objectAtIndex:0];
      
  if (photoEntry) {
    DebugLog(@"!!!!!!!!Added photo %@", [[photoEntry title] stringValue]);
    
    // We may be run without disk picture writing. if we are saving at disk, exportedImages cound > 0.
    if ([exportedImages count] > 0) {
      GDataServiceGooglePhotos *service = [self photoService];
      NSURL *postURL = [[photoEntry feedLink] URL];
      
      if ([picture uploadKeywords] && [[picture keywords] count] > 0) {
        DebugLog(@"%d keywords to add to %@", [[picture keywords] count], [[photoEntry title] stringValue]);
        for (int i = 0; i < [[picture keywords] count]; ++i) {
          //NSString *keyword = [[picture keywords]componentsJoinedByString:@" "];
          NSString *keyword = [[picture keywords] objectAtIndex:i];
          GDataEntryPhotoTag* tag = [GDataEntryPhotoTag tagEntryWithString:keyword];
          DebugLog(@"Adding %@ to %@", [tag description], [postURL description]);
          // Add tags. Let's ignore the result.
          [service fetchEntryByInsertingEntry:tag
                                   forFeedURL:postURL
                                     delegate:self
                            didFinishSelector:nil];
        }
        
      }
      // Delete the last uploaded file
      NSFileManager *fileManager = [NSFileManager defaultManager];
      NSString *imagePath = [picture path];
      [fileManager removeItemAtPath:imagePath error:NULL];
      [exportedImages removeObjectAtIndex:0];
      
      // Upload the next file, if we are reading from disk.
      [self _uploadNextImage];
    }
  } else {
    DebugLog(@"Added photo %@ failed: %@", [picture title], [error description]);
    // Don't bother showing error message if user has cancelled the operation.aiel
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
} 
  
#pragma mark Setters and Getters

- (GDataFeedPhotoUser *)albumFeed {
  return mUserAlbumFeed; 
}

- (void)setAlbumFeed:(GDataFeedBase *)feed {
  [mUserAlbumFeed autorelease];
  mUserAlbumFeed = (GDataFeedPhotoUser *)[feed retain];
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

-(void)setDoneLoadingThumbnails:(id)obj
{
	[self setLoadingImages: NO];
}

- (void)setThumbNail:(NSImage*) image forImageatIndex:(int) index
{
	[[_imageList objectAtIndex:index] setDefaultThumbnail: image];
	[imageTableView reloadData];
}

- (void)setThumbNailFromDict:(NSDictionary *) dict
{
	NSArray * allKeys = [dict allKeys];

	NSEnumerator * e = [allKeys objectEnumerator];
	NSNumber * onekey = [e nextObject];
		
	while (onekey) {
		NSImage * thumb = [dict objectForKey: onekey];
		[self setThumbNail: thumb forImageatIndex: [onekey intValue]];
		onekey = [e nextObject];
	}
}

- (void)setImageList:(NSArray*)aValue
{
  NSMutableArray* oldImageList = _imageList;
  _imageList = [aValue mutableCopy];
  [oldImageList release];
  
  DebugLog(@"Set %d images in list", [_imageList count]);
  //[self setLoadingImages:NO];
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
  DebugLog(@"*********** Returning quota as %d", _quotaUsage);
  return _quotaUsage;
}

- (void)setQuotaUsage:(int)aValue
{
  DebugLog(@"Setting quota: %d", aValue);
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
