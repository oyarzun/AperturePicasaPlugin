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
//  APPicture.h
//  AperturePicasaPlugin
//
//  Created by Eider Oliveira on 15/12/08.

#import <Cocoa/Cocoa.h>

@interface APPicture : NSObject {
  NSString* _title;
  NSString* _description;
  NSString* _keywords;
  NSImage* _defaultThumbnail;
  BOOL _uploadExifInformation;
  NSData *_data;
  NSString *_path;
}

#pragma mark Accessors

- (NSString*)title;
- (void)setTitle:(NSString*)aValue;

- (NSString*)description;
- (void)setDescription:(NSString*)aValue;

- (NSImage*)defaultThumbnail;
- (void)setDefaultThumbnail:(NSImage*)aValue;

- (NSString*)keywords;
- (void)setKeywords:(NSString*)aValue;

- (BOOL)uploadExifInformation;
- (void)setUploadExifInformation:(BOOL)aValue;

- (void)setData:(NSData*)aValue;
- (NSData*)data;

- (void)setPath:(NSString*)aValue;
- (NSString*)path;
@end
