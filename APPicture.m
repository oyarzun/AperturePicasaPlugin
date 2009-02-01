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
//  APPicture.m
//  AperturePicasaPlugin
//
//  Created by Eider Oliveira on 15/12/08.
//

#import "APPicture.h"


@implementation APPicture
- (id)init
{
  if (self = [super init])
  {
    [self setTitle:@"APPicture"];
    [self setDescription:@""];
    [self setDefaultThumbnail:nil];
    [self setPath:nil];
  }
  return self;
}

- (void)dealloc
{
  [self setTitle:nil];
  [self setDescription:nil];
  [self setDefaultThumbnail:nil];
  [self setPath:nil];
  
  [super dealloc];
}


#pragma mark -
#pragma mark Accessors

- (NSString*)title
{
  return _title;
}

- (void)setTitle:(NSString*)aValue
{
  //NSLog(@"Setting title: %@", aValue);
  NSString* oldTitle = _title;
  _title = [aValue copy];
  [oldTitle release];
}

- (NSString*)description
{
  return _description;
}

- (void)setDescription:(NSString*)aValue
{
  //NSLog(@"Setting description: %@", aValue);
  NSString* oldDescription = _description;
  _description = [aValue copy];
  [oldDescription release];
}

- (NSImage*)defaultThumbnail
{
  return _defaultThumbnail;
}

- (void)setDefaultThumbnail:(NSImage*)aValue
{
  NSImage* oldDefaultThumbnail = _defaultThumbnail;
  _defaultThumbnail = [aValue retain];
  [oldDefaultThumbnail release];
}

- (NSArray*)keywords 
{
  return _keywords;  
}

- (void)setKeywords:(NSArray*)aValue
{
  NSLog(@"Setting keywords: %@", [aValue description]);
  NSArray *oldKeywords = _keywords;
  _keywords = [aValue copy];
  [oldKeywords release];
}

- (BOOL)uploadExifInformation
{
  return _uploadExifInformation;
}
- (void)setUploadExifInformation:(BOOL)aValue
{
  _uploadExifInformation = TRUE;
}

- (void)setData:(NSData*)aValue
{
  NSData *oldValue = _data;
  _data = [aValue copy];
  [oldValue release];
}
// autoload data, if necessary
- (NSData*)data
{
  if (_data == nil && _path != nil) {
    _data = [NSData dataWithContentsOfFile:_path];
  }
  return _data;
}

- (void)setPath:(NSString*)aValue
{
  NSString *oldValue = _path;
  _path = [aValue copy];
  [oldValue release];
}
- (NSString*)path
{
  return _path;
}

@end
