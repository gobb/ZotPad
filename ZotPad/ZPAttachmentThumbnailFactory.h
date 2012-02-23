//
//  ZPAttacchmentThumbnailFactory.h
//  ZotPad
//
//  Created by Rönkkö Mikko on 2/23/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZPZoteroAttachment.h"

@interface ZPAttachmentThumbnailFactory : NSObject

+(ZPAttachmentThumbnailFactory*) instance;
-(UIImage*) getFiletypeImage:(ZPZoteroAttachment*)attachment height:(NSInteger)height width:(NSInteger)width;

@end
