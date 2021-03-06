//
//  ZPLibraryAndCollectionViewController.m
//  ZotPad
//
//  Created by Rönkkö Mikko on 11/14/11.
//  Copyright (c) 2011 Mikko Rönkkö. All rights reserved.
//

#import "ZPCore.h"
#import "ZPLibraryAndCollectionListViewController.h"
#import "ZPItemListViewController.h"


#import "ZPAuthenticationDialog.h"
#import "ZPAppDelegate.h"
#import "ZPItemDataDownloadManager.h"
#import "ZPCacheStatusToolbarController.h"
#import "ZPItemList.h"
#import "CMPopTipView.h"
#import "ZPMasterItemListViewController.h"
#import "FRLayeredNavigationController/FRLayeredNavigation.h"
#import "UIViewController+FRLayeredNavigationController.h"

@interface ZPLibraryAndCollectionListViewController()
-(void) _drillIntoIndexPath:(NSIndexPath *)indexPath;
@end

@implementation ZPLibraryAndCollectionListViewController

@synthesize detailViewController = _detailViewController;
@synthesize currentlibraryID = _currentlibraryID;
@synthesize currentCollectionKey = _currentCollectionKey;
@synthesize drilledCollectionIndex, selectedCollectionIndex;

- (id) initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    self.drilledCollectionIndex = -1;
    self.selectedCollectionIndex = -1;
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notifyLibraryWithCollectionsAvailable:) name:ZPNOTIFICATION_LIBRARY_WITH_COLLECTIONS_AVAILABLE object:nil];

    return self;
}

- (void)awakeFromNib
{
    self.clearsSelectionOnViewWillAppear = NO;
    self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    [super awakeFromNib];
}

- (void)didReceiveMemoryWarning
{
    
    //Remove the cache status bar from the toolbar 
    
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
    
    // Release the cache status controller. 
    // TODO: Also release this in the cache controller

}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    

    [super viewDidLoad];
        
    //If the current library is not defined, show a list of libraries
    if(self->_currentlibraryID == LIBRARY_ID_NOT_SET){
        self->_content = [ZPDatabase libraries];
        [self.tableView reloadData];
        //Select the first library if nothing else is selected
        if([self.tableView numberOfRowsInSection:0]>0 && self.tableView.indexPathForSelectedRow == nil){
            self.selectedCollectionIndex = 0;
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionTop];
            //            [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        }
    }
    //If a library is chosen, show collections level collections for that library
    else{
        self->_content = [ZPDatabase collectionsForLibrary:self->_currentlibraryID withParentCollection:self->_currentCollectionKey];
        [self.tableView reloadData];
    }


    self.clearsSelectionOnViewWillAppear = NO;
    
	// Do any additional setup after loading the view, typically from a nib.

}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.detailViewController = (ZPItemListViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];

    
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    //Show tool tip for collections navigation
    
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"hasPresentedCollectionsHelpPopover"]==NULL && ! [ZPPreferences unifiedCollectionsNavigation]){
        
        // Find the first tableViewCell that has a detail disclosure button
        for(NSInteger row = 0; row < [self.tableView numberOfRowsInSection:0]; ++row){
            
            UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
            
            for(UIView* child in [cell subviews]){
                if([child isKindOfClass:[UIButton class]]){
                    CMPopTipView* helpPopUp = [[CMPopTipView alloc] initWithMessage:@"Tap the blue button to open collections"];
                    [helpPopUp presentPointingAtView:child inView:self.tableView animated:YES];
                    [[NSUserDefaults standardUserDefaults] setObject:@"1" forKey:@"hasPresentedCollectionsHelpPopover"];
                    goto done;
                }
            }
        }
    done:;
        
    }
    
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    
    // Return YES for supported orientations
    return YES;
}


#pragma mark - 
#pragma mark Table view data source and delegate methods

- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    DDLogVerbose(@"Rows in library/collection table %i",[self->_content count]);
    return [self->_content count];
}



- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
     NSString *CellIdentifier = @"CollectionCell";
    
    
    // Dequeue or create a cell of the appropriate type.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
	{
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

    }
    
    // Configure the cell.
	ZPZoteroDataObject* node = [self->_content objectAtIndex: indexPath.row];
	if ( [node hasChildren])
	{
        if([ZPPreferences unifiedCollectionsNavigation]){
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        else{
            cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;

        }
	}
	else
	{
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	
    cell.textLabel.text = [node title];
    
    if(cell == NULL || ! [cell isKindOfClass:[UITableViewCell class]]){
        [NSException raise:@"Invalid cell" format:@""];
    }

	return cell;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    //Deselect previous cell
    
    if(self.selectedCollectionIndex != -1){
        if(self.selectedCollectionIndex == self.drilledCollectionIndex){
            //NSLog(@"Graying out cell at row %i",self.drilledCollectionIndex);
            [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.drilledCollectionIndex inSection:0]].selectionStyle = UITableViewCellSelectionStyleGray;
        }
        else{
            //NSLog(@"Deselecting cell at row %i",self.selectedCollectionIndex);
            [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:self.selectedCollectionIndex inSection:0] animated:NO];
        }
    }
    return indexPath;
}

// On iPad the item list is always shown if library and collection list is visible

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    
    /*
     When a row is selected, set the detail view controller's library and collection and refresh
     */
    ZPZoteroDataObject* node = [self->_content objectAtIndex: indexPath.row];
    
    if(node.libraryID != [ZPItemList instance].libraryID){
        [[NSNotificationCenter defaultCenter] postNotificationName:ZPNOTIFICATION_ACTIVE_LIBRARY_CHANGED
                                                            object:[NSNumber numberWithInt:node.libraryID]];
    }
        
    [ZPItemList instance].libraryID = [node libraryID];
    
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ZPNOTIFICATION_ACTIVE_COLLECTION_CHANGED
                                                            object:node.key];

    [ZPItemList instance].collectionKey = [node key];
    
    
    
    if (self.detailViewController != NULL) {

        //Clear search when changing collection. This is how Zotero behaves
        [self.detailViewController clearSearch];
        [self.detailViewController configureView];
    }

    /*
     Update selections and possibly drill down
     */
    
    
    self.selectedCollectionIndex = indexPath.row;

    
    // If there are subcollections, drill down.

    if([ZPPreferences layeredCollectionsNavigation]){
        if(node.hasChildren && [ZPPreferences unifiedCollectionsNavigation]){
            [self _drillIntoIndexPath:indexPath];
        }
        else{
            
            
            //Hide the side panel
            // Hide the side panel that might be visible if iPad is in portrait orientation
            
            if (self.detailViewController.masterPopoverController != nil) {
                [self.detailViewController.masterPopoverController dismissPopoverAnimated:YES];
            }

            //Pop everything on top of this
            [self.layeredNavigationController popToViewController:self
                                                         animated: YES];
            if(self.drilledCollectionIndex != self.selectedCollectionIndex){
                [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.drilledCollectionIndex inSection:0]].selected = FALSE;
            }
            self.drilledCollectionIndex = -1;
        }
        
        //Select with blue
        [aTableView cellForRowAtIndexPath:indexPath].selectionStyle = UITableViewCellSelectionStyleBlue;
        
        //Mark all other selections with grey
        
        for(ZPLibraryAndCollectionListViewController* controller in self.layeredNavigationController.viewControllers){
            if(controller!=self){
                //Grey out previously selected paths
                if(controller.drilledCollectionIndex == controller.selectedCollectionIndex){
                    controller.selectedCollectionIndex = -1;
                    [controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:controller.drilledCollectionIndex inSection:0 ]].selectionStyle = UITableViewCellSelectionStyleGray;
                }
                else if(controller.selectedCollectionIndex != -1){
                    [controller.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:controller.selectedCollectionIndex inSection:0 ] animated:NO];
                    controller.selectedCollectionIndex = -1;
                }
            }
        }
    }


    //iPhone

    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {

        UINavigationController* rootNavigationController = (UINavigationController*)[UIApplication sharedApplication].delegate.window.rootViewController;
        [rootNavigationController.topViewController performSegueWithIdentifier:@"PushItemList" sender:NULL];
    }
}

-(void) tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath{
    
    //Select with gray if not selected
    UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];

    if(!cell.selected){
        cell.selected = TRUE;;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    [self _drillIntoIndexPath:indexPath];
}

-(void) _drillIntoIndexPath:(NSIndexPath *)indexPath{
    
    ZPZoteroDataObject* node = [self->_content objectAtIndex: indexPath.row];

    ZPLibraryAndCollectionListViewController* subController = [self.storyboard instantiateViewControllerWithIdentifier:@"LibraryAndCollectionList"];
    subController.currentlibraryID=[node libraryID];
    subController.currentCollectionKey=[node key];

    
    //For some reason the view lifecycle methods are not called
    if([ZPPreferences layeredCollectionsNavigation]){
        [subController loadView];
        [subController viewDidLoad];
        [subController viewWillAppear:NO];
        [subController viewDidAppear:NO];
    }
    subController.detailViewController = self.detailViewController;
    
    if([ZPPreferences layeredCollectionsNavigation]){
        
        [self.layeredNavigationController pushViewController:subController
                                                   inFrontOf:self
                                                maximumWidth:YES
                                                    animated: YES];
        
        subController.layeredNavigationItem.hasChrome = FALSE;

        
        
    }
    else{
        [self.navigationController pushViewController:subController animated:YES];
    }

    //Clear the previously drilled index path
    if(self.drilledCollectionIndex != -1 && self.drilledCollectionIndex != self.selectedCollectionIndex){
        [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:self.drilledCollectionIndex inSection:0 ]animated:NO];
    }
    
    //Set the new drilled index path
    UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if(! cell.selected){
        cell.selected = TRUE;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    self.drilledCollectionIndex = indexPath.row;
}



#pragma mark -
#pragma mark Notified methods

-(void) notifyLibraryWithCollectionsAvailable:(NSNotification*) notification{
    
    ZPZoteroLibrary* library = notification.object;


    //If this is a library that we are not showing now, just return;
    
    if(_currentlibraryID == LIBRARY_ID_NOT_SET || _currentlibraryID == library.libraryID){
        if([NSThread isMainThread]){
            
            //Loop over the existing content to see if we need to refresh the content of the cells that are already showing
            
            ZPZoteroDataObject* shownObject;
            NSInteger index=-1;
            
            for(shownObject in _content){
                index++;
                
                UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
                //Check accessory button
                BOOL noAccessory = cell.accessoryType == UITableViewCellAccessoryNone;
                if(shownObject.hasChildren && noAccessory){
                    if([ZPPreferences unifiedCollectionsNavigation]){
                        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    }
                    else{
                        cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
                    }
                }
                else if(!shownObject.hasChildren && ! noAccessory){
                    cell.accessoryType = UITableViewCellAccessoryNone;
                }
                
                //Check title
                
                if(![cell.textLabel.text isEqualToString:shownObject.title]){
                    cell.textLabel.text = shownObject.title;
                }
            }
            
            //Then check if we need to insert, delete, or move cells
            
            NSArray* newContent;
            
            if(_currentlibraryID == LIBRARY_ID_NOT_SET){
                newContent = [ZPDatabase libraries];
            }
            else if(_currentlibraryID == library.libraryID){
                newContent = [ZPDatabase collectionsForLibrary:self->_currentlibraryID withParentCollection:self->_currentCollectionKey];
            }
            
            NSMutableArray* deleteArray = [[NSMutableArray alloc] init ];
            NSMutableArray* insertArray = [[NSMutableArray alloc] init ];
            
            NSMutableArray* shownContent = [NSMutableArray arrayWithArray:_content];
            
            index=-1;
            ZPZoteroDataObject* newObject;
            
            //First check which need to be inserted
            for(newObject in newContent){
                index++;
                
                NSInteger oldIndexOfNewObject= [shownContent indexOfObject:newObject];
                
                if(oldIndexOfNewObject == NSNotFound){
                    [insertArray addObject:[NSIndexPath indexPathForRow:index inSection:0]];
                    [shownContent insertObject:newObject atIndex:index];
                }
            }
            
            //Then check which need to be deleted
            
            index=-1;
            
            for(shownObject in [NSArray arrayWithArray:shownContent]){
                index++;
                NSInteger newIndexOfOldObject= [newContent indexOfObject:shownObject];
                
                if(newIndexOfOldObject == NSNotFound){
                    //If the new object does not exist in th old array, insert it
                    [deleteArray addObject:[NSIndexPath indexPathForRow:index inSection:0]];
                    [shownContent removeObjectAtIndex:index];
                }
            }

            
            ZPZoteroDataObject* dataObj;
            
            //NSLog(@"Libraries / collections before update");
            for(dataObj in _content){
                //NSLog(@"%@",dataObj.title);
            }
            
            
            if(([insertArray count] !=0) || ([deleteArray count] > 0)){
            
                [self.tableView beginUpdates];
                
                if([insertArray count]>0){
                    [self.tableView insertRowsAtIndexPaths:insertArray withRowAnimation:UITableViewRowAnimationAutomatic];
                    //NSLog(@"Inserting rows into indices");
                    NSIndexPath* temp;
                    for(temp in insertArray){
                        DDLogVerbose(@"%i",temp.row);
                    }
                    
                }
                if([deleteArray count]>0){
                    [self.tableView deleteRowsAtIndexPaths:deleteArray withRowAnimation:UITableViewRowAnimationAutomatic];
                    //NSLog(@"Deleting rows from indices");
                    NSIndexPath* temp;
                    for(temp in insertArray){
                        DDLogVerbose(@"%i",temp.row);
                    }
                }
                
                _content = shownContent;
                
                //NSLog(@"Libraries / collections after update");
                
                for(dataObj in _content){
                    //NSLog(@"%@",dataObj.title);
                }
                
                [self.tableView endUpdates];
                
                if(_currentlibraryID == LIBRARY_ID_NOT_SET){
                    if([self.tableView numberOfRowsInSection:0]>0){
                        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionTop];
//                        [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                    }
                }
            }
            /*
             */
            
            //TODO: Figure out a way to keep the activity view spinning until the last library is loaded.
            //[_activityIndicator stopAnimating];
            
        }
        else{
            [self performSelectorOnMainThread:@selector( notifyLibraryWithCollectionsAvailable:) withObject:notification waitUntilDone:YES];
        }
    }
}


@end
