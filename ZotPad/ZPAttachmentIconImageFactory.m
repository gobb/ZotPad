//
//  ZPAttachmentPreviewViewController.m
//  ZotPad
//
//  Created by Mikko Rönkkö on 17.4.2012.
//  Copyright (c) 2012 Mikko Rönkkö. All rights reserved.
//

#import "ZPCore.h"

#import "ZPAttachmentIconImageFactory.h"
#import <QuartzCore/QuartzCore.h>
#import <zlib.h>
#import "TestFlight.h"


#define CHUNK 16384



@interface ZPAttachmentIconImageFactory ()

-(void) _captureWebViewContent:(UIWebView*) webView forCacheKey:(NSString*) cacheKey;
+(void) _uncompressSVGZ:(NSString*)name;
+(void) _showPDFPreview:(UIImage*) image inImageView:(UIImageView*) view;

@end

//TODO: This is commented out because there is currently no mechanism to expire items form the cache when files are changed on the disk
//static NSCache* _previewCache; 

static NSCache* _fileIconCache; 
static NSMutableDictionary* _viewsWaitingForImage; 
static NSMutableDictionary* _viewsThatAreRendering; 
static ZPAttachmentIconImageFactory* _webViewDelegate;

@implementation ZPAttachmentIconImageFactory


+ (void)initialize{
    
//    _previewCache = [[NSCache alloc] init];
//    [_previewCache setCountLimit:20];
    _fileIconCache = [[NSCache alloc] init];
    [_fileIconCache setCountLimit:20];
    _viewsWaitingForImage = [[NSMutableDictionary alloc] init ];
    _viewsThatAreRendering = [[NSMutableDictionary alloc] init ];
    _webViewDelegate = [[ZPAttachmentIconImageFactory alloc] init];
}


+(void) renderFileTypeIconForAttachment:(ZPZoteroAttachment*) attachment intoImageView:(UIImageView*) fileImage {
    
    NSString* mimeType =[attachment.contentType stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    
    CGRect frame = fileImage.bounds;
    NSInteger width = (NSInteger)roundf(frame.size.width);
    NSInteger height = (NSInteger)roundf(frame.size.height);
    
    NSString* emblem = @"";
    BOOL useEmblem=FALSE;
    if(attachment.linkMode == LINK_MODE_LINKED_URL){
        emblem =@"emblem-symbolic-link";
        useEmblem = TRUE;
    }else if( attachment.linkMode == LINK_MODE_LINKED_FILE && ! [ZPPreferences downloadLinkedFilesWithDropbox]){
        emblem =@"emblem-locked";
        useEmblem = TRUE;
    }
    
    NSString* cacheKey = [mimeType stringByAppendingFormat:@"%@-%ix%i",emblem,width,height];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath = [paths objectAtIndex:0];
    BOOL isDir = NO;
    NSError *error;
    if (! [[NSFileManager defaultManager] fileExistsAtPath:cachePath isDirectory:&isDir] && isDir == NO) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:NO attributes:nil error:&error];
    }

    
    BOOL emblemOnly = FALSE;
    //If we are rendering a file type with emblem, check that the emblem and file type have been rendered alone first
    if(useEmblem && ! [[NSFileManager defaultManager] fileExistsAtPath:[cachePath stringByAppendingPathComponent:[emblem stringByAppendingFormat:@"-%ix%i.png",width,height]]]){
        cacheKey = [emblem stringByAppendingFormat:@"-%ix%i",width,height];
        emblemOnly = TRUE;
    }
    else if(useEmblem && ! [[NSFileManager defaultManager] fileExistsAtPath:[cachePath stringByAppendingPathComponent:[mimeType stringByAppendingFormat:@"-%ix%i.png",width,height]]]){
        cacheKey = [mimeType stringByAppendingFormat:@"-%ix%i",width,height];
        useEmblem = FALSE;
    }

    
    //    DDLogVerbose(@"Getting icon for %@",cacheKey);
    
    NSObject* cacheImage = NULL;
    BOOL render = false;
    @synchronized(_fileIconCache){
        cacheImage = [_fileIconCache objectForKey:cacheKey];
        if(cacheImage == NULL){
            [_fileIconCache setObject:[NSNull null] forKey:cacheKey];
            render = TRUE;
            
        }
        
    }
    
    //Check if we are currently rendering this and if we still need to keep rendering
    if(cacheImage == [NSNull null]){
        @synchronized(_viewsThatAreRendering){
            UIView* renderingView = [_viewsThatAreRendering objectForKey:cacheKey];
            //If the previous rendering view is no longer on screen
            if(renderingView != NULL && !(renderingView.superview)){
                render = TRUE;
            }
        }
    }
    
    //No image in cache, and we are not currently rendering one either
    
    if(render){
        //If a file exists on disk, use that
        

        if([[NSFileManager defaultManager] fileExistsAtPath:[cachePath stringByAppendingPathComponent:[cacheKey stringByAppendingString:@".png"]]]){
            UIImage* image = [UIImage imageWithContentsOfFile:[cachePath stringByAppendingPathComponent:[cacheKey stringByAppendingString:@".png"]]];
            @synchronized(_fileIconCache){
                [_fileIconCache setObject:image forKey:cacheKey];
            }
            fileImage.image = image;
            
        }
        //Else start rendering
        else{
            
            //Only render in main thread
            
            if([NSThread isMainThread]){
                
                UIWebView* webview = nil;
                
                //Workaround for difficult to catch
                @try{
                    webview = [[UIWebView alloc] initWithFrame:frame];
                }
                @catch (NSException *exception) {
                    DDLogError(@"Caught exception when rendering icon %@ %@: %@",cacheKey, [exception name], [exception reason]);
                }
                
                if(webview != nil){                    
                    if([[NSFileManager defaultManager] fileExistsAtPath:[[[NSBundle mainBundle] resourcePath]
                                                                         stringByAppendingPathComponent:[mimeType stringByAppendingString:@".svgz"]]]){
                        
                        
                        [self _uncompressSVGZ:mimeType];
                        
                        NSString* content;
                        
                        //Render the emblem
                        if(useEmblem){
                            [self _uncompressSVGZ:emblem];
                            
                            //Render the uncompressed file using a HTML file as a wrapper
                            if(emblemOnly)
                                content = [NSString stringWithFormat:@"<html><body onload=\"document.location='zotpad:%@'\"><div style=\"position: absolute; z-index:100\"><img src=\"%@.svg\" width=%i height=%i></div></body></html>",cacheKey,emblem,width/4,height/4];

                            else                               
                                content = [NSString stringWithFormat:@"<html><body onload=\"document.location='zotpad:%@'\"><div style=\"position: absolute; z-index:100\"><img src=\"%@.svg\" width=%i height=%i></div><img src=\"%@.svg\" width=%i height=%i></body></html>",cacheKey,emblem,width/4,height/4,mimeType,width,height];
                        }
                        else{
                            content = [NSString stringWithFormat:@"<html><body onload=\"document.location='zotpad:%@'\"><img src=\"%@.svg\" width=%i height=%i></body></html>",cacheKey,mimeType,width,height];
                        }
                        
                        NSURL *baseURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
                        
                        webview.delegate=_webViewDelegate;
                        
                        [webview loadData:[content dataUsingEncoding:NSUTF8StringEncoding] MIMEType:@"text/html" textEncodingName:NULL baseURL:baseURL];
                        
                        [fileImage addSubview:webview];
                        
                        @synchronized(_viewsThatAreRendering){
                            [_viewsThatAreRendering setObject:webview forKey:cacheKey];
                        }
                    }
                    //We do not have a file type icon for this.
                    else{
                        if([ZPPreferences reportErrors]){
                            [TestFlight passCheckpoint:[NSString stringWithFormat:@"Unknown mime type %@",mimeType]];
                        }
                    }
         
                }
            }
            else{
                DDLogVerbose(@"Attempted to render file type icon in a background thread");
            }
        }
    }
                           
    //IF the cache image is NSNull, this tells us that we are rendering an image currently
    else if(cacheImage == [NSNull null]){
        
        @synchronized(_viewsWaitingForImage){
            NSMutableArray* array= [_viewsWaitingForImage objectForKey:cacheKey];
            if(array == NULL){
                array = [[NSMutableArray alloc] init ];
                [_viewsWaitingForImage setObject:array forKey:cacheKey];
            }
            [array addObject:fileImage];
        }
    }
    //We have a cached image
    else{
        fileImage.image = (UIImage*) cacheImage;
    }
}

+(void) _uncompressSVGZ:(NSString *)filePath{
    
    //Uncompress the image
    NSString* sourceFile = [[[NSBundle mainBundle] resourcePath] 
                            stringByAppendingPathComponent:[filePath stringByAppendingString:@".svgz"]];
    
    NSString* tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:[filePath stringByAppendingString:@".svg"]];
    
    gzFile file = gzopen([sourceFile UTF8String], "rb");
    
    FILE *dest = fopen([tempFile UTF8String], "w");
    
    unsigned char buffer[CHUNK];
    
    int uncompressedLength;
    
    while ((uncompressedLength = gzread(file, buffer, CHUNK)) ) {
        // got data out of our file
        if(fwrite(buffer, 1, uncompressedLength, dest) != uncompressedLength || ferror(dest)) {
            DDLogVerbose(@"Error uncompressing SVG image at path %@", filePath);
        }
    }
    
    fclose(dest);
    gzclose(file);  
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
	NSString *requestString = [[request URL] absoluteString];
    NSArray* components = [requestString componentsSeparatedByString:@":"];
	if ([[components objectAtIndex:0] isEqualToString:@"zotpad"]) {
        [self _captureWebViewContent:webView forCacheKey:[components objectAtIndex:1]];
        
		return NO;
	}
    
	return YES;
}


-(void) _captureWebViewContent:(UIWebView *)webview forCacheKey:(NSString*) cacheKey;{
    
    
    //If the view is still visible, capture the content
    if (webview.window && webview.superview) {
        
        CGSize size = webview.bounds.size;
        
        if ([UIScreen instancesRespondToSelector:@selector(scale)] && [[UIScreen mainScreen] scale] == 2.0f) {
            UIGraphicsBeginImageContextWithOptions(size, NO, 2.0f);
        } else {
            UIGraphicsBeginImageContextWithOptions(size, NO, 1.0f);
        }
        
        [webview.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        // Write image to PNG
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cachePath = [paths objectAtIndex:0];
        BOOL isDir = NO;
        NSError *error;
        if (! [[NSFileManager defaultManager] fileExistsAtPath:cachePath isDirectory:&isDir] && isDir == NO) {
            [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:NO attributes:nil error:&error];
        }
        
        
        NSData* imageData = UIImagePNGRepresentation(image);
        
        //Create a blank image and compare to check that the image that we got is not blank.
        
        if ([UIScreen instancesRespondToSelector:@selector(scale)] && [[UIScreen mainScreen] scale] == 2.0f) {
            UIGraphicsBeginImageContextWithOptions(size, NO, 2.0f);
        } else {
            UIGraphicsBeginImageContext(size);
        }
        
        UIWebView* blankView = [[UIWebView alloc] initWithFrame:webview.frame];
        [blankView loadHTMLString:@"<html></html>" baseURL:NULL];
        [blankView.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *blankImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        if([UIImagePNGRepresentation(blankImage) isEqualToData:imageData]){
            @synchronized(_fileIconCache){

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC*0.5),
                               dispatch_get_current_queue(), ^{
                    [self _captureWebViewContent:webview forCacheKey:cacheKey];
                });

                return;
            }
            
        }
        else{
            NSRange emblemRange = [cacheKey rangeOfString:@"emblem-symbolic-link"];
            if(emblemRange.location == NSNotFound){
                emblemRange = [cacheKey rangeOfString:@"emblem-locked"];
            }
            
            //This is an emblem and mime combination and needs to be compared against emblem and mime icons
            
            if(emblemRange.location != NSNotFound && emblemRange.location>0){
                
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                NSString *cachePath = [paths objectAtIndex:0];
                
                if([imageData isEqualToData:[NSData dataWithContentsOfFile:[ cachePath stringByAppendingPathComponent:[[cacheKey substringFromIndex:emblemRange.location] stringByAppendingString:@".png"]]]] ||
                   [imageData isEqualToData:[NSData dataWithContentsOfFile:[ cachePath stringByAppendingPathComponent:[[cacheKey stringByReplacingCharactersInRange:emblemRange withString:@""] stringByAppendingString:@".png"]]]]){

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC*0.5),
                                   dispatch_get_current_queue(), ^{
                                       [self _captureWebViewContent:webview forCacheKey:cacheKey];
                                   });
                    
                    return;
                }
            }
            
            
            [imageData writeToFile:[cachePath stringByAppendingPathComponent:[cacheKey stringByAppendingString:@".png"]] atomically:YES];
            
            [(UIImageView*) webview.superview setImage:image];
            [webview removeFromSuperview];
            
            
            @synchronized(_fileIconCache){
                [_fileIconCache setObject:image forKey:cacheKey];
            }
            @synchronized(_viewsWaitingForImage){
                NSMutableArray* array= [_viewsWaitingForImage objectForKey:cacheKey];
                if(array != NULL){
                    [_viewsWaitingForImage removeObjectForKey:cacheKey];
                    for(UIImageView* view in array){
                        
                        
                        view.image = image;
                    }
                }
            }
        }
    }
    else{
        @synchronized(_fileIconCache){
            
            [_fileIconCache removeObjectForKey:cacheKey];
        }
        
    }
    
    @synchronized(_viewsThatAreRendering){
        [_viewsThatAreRendering removeObjectForKey:webview];
    }

    
}

+(void) _showPDFPreview:(UIImage*) image inImageView:(UIImageView*) imageView{
    
    CGRect frame = [self getDimensionsForImageView:imageView.superview withImage:image];
    imageView.frame = frame;
    imageView.center = imageView.superview.center;
    imageView.layer.borderWidth = 2.0f;
    imageView.layer.borderColor = [UIColor blackColor].CGColor;
    [imageView setBackgroundColor:[UIColor whiteColor]]; 
    
    imageView.image=image;
    
    //Set the old bacground transparent
    imageView.superview.layer.borderColor = [UIColor clearColor].CGColor;
    imageView.superview.backgroundColor = [UIColor clearColor]; 
    
}

+(CGRect) getDimensionsForImageView:(UIView*) imageView withImage:(UIImage*) image{   
    
    float scalingFactor = MIN(imageView.frame.size.height/image.size.height,imageView.frame.size.width/image.size.width);
    
    float newWidth = image.size.width*scalingFactor;
    float newHeight = image.size.height*scalingFactor;

    return CGRectMake(0,0,newWidth,newHeight);
    
}

+(void) renderPDFPreviewForFileAtPath:(NSString*) filePath intoImageView:(UIImageView*) fileImage{
    
    if([NSThread isMainThread]){
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND,0), ^{
            [ZPAttachmentIconImageFactory renderPDFPreviewForFileAtPath:filePath intoImageView:fileImage];
        });

    }
    else{
        //
        // Renders a first page of a PDF as an image
        //
        // Source: http://stackoverflow.com/questions/5658993/creating-pdf-thumbnail-in-iphone
        //
        
        
        NSURL *pdfUrl = [NSURL fileURLWithPath:filePath];
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge_retained CFURLRef)pdfUrl);
        
        
        CGPDFPageRef pageRef = CGPDFDocumentGetPage(document, 1);
        CGRect pageRect = CGPDFPageGetBoxRect(pageRef, kCGPDFCropBox);
        
        UIGraphicsBeginImageContext(pageRect.size);
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        //If something goes wrong, we might get an empty context
        if (context != NULL) {

            CGContextTranslateCTM(context, CGRectGetMinX(pageRect),CGRectGetMaxY(pageRect));
            CGContextScaleCTM(context, 1, -1);  
            CGContextTranslateCTM(context, -(pageRect.origin.x), -(pageRect.origin.y));
            CGContextDrawPDFPage(context, pageRef);
            
            UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            if(image != NULL){
                //        [_previewCache setObject:image forKey:filePath];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _showPDFPreview:image inImageView:fileImage];
                });
            } 
        }
    }
}

@end
