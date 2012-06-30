//
//  ZPPreviewController.m
//  ZotPad
//
//  Created by Mikko Rönkkö on 23.6.2012.
//  Copyright (c) 2012 Helsiki University of Technology. All rights reserved.
//

#import "ZPCore.h"
#import "ZPDatabase.h"
#import "ZPPreviewController.h"
#import "ZPAttachmentFileInteractionController.h"

//Unzipping and base64 decoding
#import "ZipArchive.h"
#import "QSStrings.h"

@interface ZPPreviewControllerDelegate : NSObject <QLPreviewControllerDataSource, QLPreviewControllerDelegate>{
    NSMutableArray* _previewItems;
}

- (void) addAttachmentToQuicklook:(ZPZoteroAttachment *)attachment;
- (NSInteger) startIndex;

@end

@implementation ZPPreviewControllerDelegate

-(id) init{
    self = [super init];
    _previewItems = [[NSMutableArray alloc] init];
    return self;
    
}

- (void) addAttachmentToQuicklook:(ZPZoteroAttachment *)attachment{
    
    // Imported URLs need to be unzipped
    if([attachment.linkMode intValue] == LINK_MODE_IMPORTED_URL && [attachment.contentType isEqualToString:@"text/html"]){
        
        //TODO: Make sure that this tempdir is cleaned at some point (Maybe refactor this into ZPZoteroAttachment)
        
        NSString* tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:attachment.key];
        
        if([[NSFileManager defaultManager] fileExistsAtPath:tempDir]){
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:tempDir 
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        ZipArchive* zipArchive = [[ZipArchive alloc] init];
        [zipArchive UnzipOpenFile:attachment.fileSystemPath];
        [zipArchive UnzipFileTo:tempDir overWrite:YES];
        [zipArchive UnzipCloseFile];
        
        //List the unzipped files and decode them
        
        NSArray* files = [[NSFileManager defaultManager]contentsOfDirectoryAtPath:tempDir error:NULL];
        
        for (NSString* file in files){
            // The filenames end with %ZB64, which needs to be removed
            NSString* toBeDecoded = [file substringToIndex:[file length] - 5];
            NSData* decodedData = [QSStrings decodeBase64WithString:toBeDecoded] ;
            NSString* decodedFilename = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            
            [[NSFileManager defaultManager] moveItemAtPath:[tempDir stringByAppendingPathComponent:file] toPath:[tempDir stringByAppendingPathComponent:decodedFilename] error:NULL];
            
        }
    }
    [_previewItems addObject:attachment];
}

- (NSInteger) startIndex{
    return [_previewItems count]-1;
    
}

#pragma mark - Quick Look data source methods

- (NSInteger) numberOfPreviewItemsInPreviewController: (QLPreviewController *) controller 
{
    return [_previewItems count];
}


- (id <QLPreviewItem>) previewController: (QLPreviewController *) controller previewItemAtIndex: (NSInteger) index{
    return [_previewItems objectAtIndex:index];
}


// Should URL be opened
- (BOOL)previewController:(QLPreviewController *)controller shouldOpenURL:(NSURL *)url forPreviewItem:(id <QLPreviewItem>)item{
    return YES;
}

@end


@implementation ZPPreviewController

static ZPPreviewControllerDelegate* _sharedDelegate;

+(void) initialize{
    _sharedDelegate = [[ZPPreviewControllerDelegate alloc] init];
}

-(id) init{
    self=[super init];
    return self;
}

-(id) initWithAttachment:(ZPZoteroAttachment*)attachment sourceView:(UIView*)view{
    
    self = [super init];
    
    _source = view;

    [_sharedDelegate addAttachmentToQuicklook:attachment];

    self.delegate = _sharedDelegate;
    self.dataSource = _sharedDelegate;
    [self setCurrentPreviewItemIndex:[_sharedDelegate startIndex]];

    // Mark this file as recently viewed. This will be done also in the case
    // that the file cannot be downloaded because the fact that user tapped an
    // item is still relevant information for the cache controller
    
    
    [[ZPDatabase instance] updateViewedTimestamp:attachment];
    
    
    return self;
}


+(void) displayQuicklookWithAttachment:(ZPZoteroAttachment*)attachment sourceView:(UIView*)view{
    
    if([attachment.linkMode intValue] == LINK_MODE_LINKED_URL){
        NSString* urlString = [[(ZPZoteroItem*)[ZPZoteroItem dataObjectWithKey:attachment.parentItemKey] fields] objectForKey:@"url"];
        
        //Links will be opened with safari.
        NSURL* url = [NSURL URLWithString: urlString];
        [[UIApplication sharedApplication] openURL:url];
    }
    
    //This should never be shown, but it is implemented just to be sure 
    
    else if(! attachment.fileExists){
        UIAlertView *message = [[UIAlertView alloc] initWithTitle:@"File not found"
                                                          message:[NSString stringWithFormat:@"The file %@ was not found on ZotPad.",attachment.filename]
                                                         delegate:nil
                                                cancelButtonTitle:@"Cancel"
                                                otherButtonTitles:nil];
        
        [message show];
    }
    else {
        
        ZPPreviewController* quicklook = [[ZPPreviewController alloc] initWithAttachment:attachment sourceView:view];
        
        UIViewController* root = [UIApplication sharedApplication].delegate.window.rootViewController;

        //Find the top most view controller.
        
        while(root.presentedViewController){
            root = root.presentedViewController;
        }
        [root presentModalViewController:quicklook animated:YES];
        
    }
    
}

-(void) viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    UIBarButtonItem* button = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(actionButtonPressed:)];
    
    [[self navigationItem] setRightBarButtonItem:button];
}

- (IBAction) actionButtonPressed:(id)sender{
    
    ZPZoteroAttachment* currentAttachment = (ZPZoteroAttachment*) self.currentPreviewItem;
    if(_attachmentInteractionController == NULL)  _attachmentInteractionController = [[ZPAttachmentFileInteractionController alloc] init];
    [_attachmentInteractionController setAttachment:currentAttachment];
    
    [_attachmentInteractionController presentOptionsMenuFromBarButtonItem:sender];
}

#pragma mark - Quick Look delegate methods

//Needed to provide zoom effect

- (CGRect)previewController:(QLPreviewController *)controller frameForPreviewItem:(id <QLPreviewItem>)item inSourceView:(UIView **)view{
*view = _source;
CGRect frame = _source.frame;
return frame; 
} 


- (UIImage *)previewController:(QLPreviewController *)controller transitionImageForPreviewItem:(id <QLPreviewItem>)item contentRect:(CGRect *)contentRect{
if([_source isKindOfClass:[UIImageView class]]) return [(UIImageView*) _source image];
else{
    UIImageView* imageView = (UIImageView*) [_source viewWithTag:1];
    return imageView.image;
}
}




@end
