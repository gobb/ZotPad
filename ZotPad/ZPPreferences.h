//
//  ZPPreferences.h
//  ZotPad
//
//  Created by Rönkkö Mikko on 12/17/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZPPreferences : NSObject{
    NSInteger _metadataCacheLevel;
    BOOL _smartCache;
}

+(ZPPreferences*) instance;
-(BOOL) cacheAllLibraries;
-(BOOL) cacheActiveLibrary;
-(BOOL) cacheActiveCollection;
-(BOOL) smartCache;

@end