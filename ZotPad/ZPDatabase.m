//
//  ZPDatabase.m
//  ZotPad
//
//  This class contains all database operations.
//
//  Created by Rönkkö Mikko on 12/16/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "ZPDatabase.h"

//Data objects
#import "ZPZoteroLibrary.h"
#import "ZPZoteroCollection.h"
#import "ZPZoteroItem.h"

//DB library
#import "../FMDB/src/FMDatabase.h"
#import "../FMDB/src/FMResultSet.h"


@implementation ZPDatabase

static ZPDatabase* _instance = nil;

-(id)init
{
    self = [super init];
    
    _debugDatabase = FALSE;
    
	NSString *dbPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"zotpad.sqlite"];
    
    
    NSError* error;
    
    _database = [FMDatabase databaseWithPath:dbPath];
    [_database open];
    [_database setTraceExecution:_debugDatabase];
    [_database setLogsErrors:_debugDatabase];
    
    //Read the database structure from file and create the database
    
    NSStringEncoding encoding;
    
    NSString *sqlFile = [NSString stringWithContentsOfFile:[[NSBundle mainBundle]
                                                            pathForResource:@"database"
                                                            ofType:@"sql"] usedEncoding:&encoding error:&error];
    
    NSArray *sqlStatements = [sqlFile componentsSeparatedByString:@";"];
    
    NSEnumerator *e = [sqlStatements objectEnumerator];
    id sqlString;
    while (sqlString = [e nextObject]) {
        [_database executeUpdate:sqlString];
    }
    
    
	return self;
}

/*
 Singleton accessor
 */

+(ZPDatabase*) instance {
    if(_instance == NULL){
        _instance = [[ZPDatabase alloc] init];
    }
    return _instance;
}

-(void) addOrUpdateLibraries:(NSArray*)libraries{
    
    @synchronized(self){
        [_database executeUpdate:@"DELETE FROM groups"];
    
    
        NSEnumerator* e = [libraries objectEnumerator];
    
        ZPZoteroLibrary* library;
    
        while ( library = (ZPZoteroLibrary*) [e nextObject]) {
        
            NSNumber* libraryID = [NSNumber numberWithInt:library.libraryID];
            [_database executeUpdate:@"INSERT INTO groups (groupID, name) VALUES (?, ?)",libraryID,library.name];
        }  
    }
}


-(void) addOrUpdateCollections:(NSArray*)collections forLibrary:(NSInteger)libraryID{

    NSMutableArray* collectionKeys;
    
    @synchronized(self){
        FMResultSet* resultSet=[_database executeQuery:@"SELECT key FROM collections WHERE libraryID = ?",[NSNumber numberWithInt:libraryID]];
        
        collectionKeys =[[NSMutableArray alloc] init];
        
        while([resultSet next]){
            [collectionKeys addObject:[resultSet stringForColumnIndex:0]];
        }
        [resultSet close];
    }
    
    NSEnumerator* e2 = [collections objectEnumerator];
    
    ZPZoteroCollection* collection;
    while( collection =(ZPZoteroCollection*)[e2 nextObject]){
        
        //Insert or update
        NSInteger count= [collectionKeys count];
        [collectionKeys removeObject:collection.collectionKey];
        
        NSNumber* libraryIDobj = NULL;
        if(libraryID == 1) libraryIDobj = [NSNumber numberWithInt:libraryID];
        
        @synchronized(self){
            if(count == [collectionKeys count]){
                
                [_database executeUpdate:@"INSERT INTO collections (collectionName, key, libraryID, parentCollectionKey) VALUES (?,?,?,?)",collection.name,collection.collectionKey,libraryIDobj,collection.parentCollectionKey];
            }
            else{
                [_database executeUpdate:@"UPDATE collections SET collectionName=?, libraryID=?, parentCollectionKey=? WHERE key=?",collection.name,libraryIDobj,collection.parentCollectionKey ,collection.collectionKey];
            }
        }
        
    }
    
    // Delete collections that no longer exist
    
    NSEnumerator* e3 = [collectionKeys objectEnumerator];
    
    NSString* key;
    while( key =(NSString*)[e3 nextObject]){
        @synchronized(self){
            [_database executeUpdate:@"DELETE FROM collections WHERE key=?",key];
        }
    }
    
    // Resolve parent IDs based on parent keys
    // A nested subquery is needed to rename columns because SQLite does not support table aliases in update statement

    // TODO: Refactor so that collectionKeys are used instead of collectionIDs
    
    @synchronized(self){
        [_database executeUpdate:@"UPDATE collections SET parentCollectionID = (SELECT A FROM (SELECT collectionID as A, key AS B FROM collections) WHERE B=parentCollectionKey)"];
    }
    

}


//Extract data from item and write to database

-(void) writeItemCreatorsToDatabase:(ZPZoteroItem*)item;
-(void) writeItemFieldsToDatabase:(ZPZoteroItem*)item;


// Methods for retrieving data from the data layer
- (NSArray*) libraries{
    NSMutableArray *returnArray = [[NSMutableArray alloc] init];
    
    
	ZPZoteroLibrary* thisLibrary = [[ZPZoteroLibrary alloc] init];
    [thisLibrary setLibraryID : 1];
	[thisLibrary setTitle: @"My Library"];
    
    //Check if there are collections in my library
    @synchronized(self){
        FMResultSet* resultSet = [_database executeQuery:@"SELECT collectionID FROM collections WHERE libraryID IS NULL LIMIT 1"];
        BOOL hasChildren  =[resultSet next];
        
        [thisLibrary setHasChildren:hasChildren];
        [returnArray addObject:thisLibrary];
        [resultSet close];
        
	}
    
    //Group libraries
    @synchronized(self){
        
        FMResultSet* resultSet = [_database executeQuery:@"SELECT groupID, name, groupID IN (SELECT DISTINCT libraryID from collections) AS hasChildren FROM groups"];
		
        
        while([resultSet next]) {
            
            NSInteger libraryID = [resultSet intForColumnIndex:0];
            NSString* name = [resultSet stringForColumnIndex:1];
            BOOL hasChildren = [resultSet boolForColumnIndex:2];
            
            ZPZoteroLibrary* thisLibrary = [[ZPZoteroLibrary alloc] init];
            [thisLibrary setLibraryID : libraryID];
            [thisLibrary setName: name];
            [thisLibrary setHasChildren:hasChildren];
            
            [returnArray addObject:thisLibrary];
        }
        [resultSet close];
        
    }
	return returnArray;
}

- (NSArray*) collections : (NSInteger)currentLibraryID currentCollection:(NSInteger)currentCollectionID {
	
    
    NSString* libraryCondition;
    NSString* collectionCondition;
    
    //My library is coded as 1 in ZotPad and is NULL in the database.
    
    if(currentLibraryID == 1){
        libraryCondition = @"libraryID IS NULL";
    }
    else{
        libraryCondition = [NSString stringWithFormat:@"libraryID = %i",currentLibraryID];
    }
    
    if(currentCollectionID == 0){
        //Collection key is used here insted of collection ID because it is more reliable.
        collectionCondition= @"parentCollectionKey IS NULL";
    }
    else{
        collectionCondition = [NSString stringWithFormat:@"parentCollectionID = %i",currentCollectionID];
    }
    
    NSMutableArray* returnArray;
    
	@synchronized(self){
        FMResultSet* resultSet = [_database executeQuery:[NSString stringWithFormat:@"SELECT collectionID, collectionName, collectionID IN (SELECT DISTINCT parentCollectionID FROM collections WHERE %@) AS hasChildren FROM collections WHERE %@ AND %@",libraryCondition,libraryCondition,collectionCondition]];
        
        
        
        returnArray = [[NSMutableArray alloc] init];
        
        while([resultSet next]) {
            
            NSInteger collectionID = [resultSet intForColumnIndex:0];
            NSString *name = [resultSet stringForColumnIndex:1];
            BOOL hasChildren = [resultSet intForColumnIndex:2];
            
            ZPZoteroCollection* thisCollection = [[ZPZoteroCollection alloc] init];
            [thisCollection setLibraryID : currentLibraryID];
            [thisCollection setCollectionID : collectionID];
            [thisCollection setName : name];
            [thisCollection setHasChildren:hasChildren];
            
            [returnArray addObject:thisCollection];
            
        }
        [resultSet close];
        
        
	}
    
	return returnArray;
}

- (ZPZoteroItem*) getItemByKey: (NSString*) key;

//Add more data to an existing item. By default the getItemByKey do not populate fields or creators to save database operations
- (void) getFieldsForItemKey: (NSString*) key;
- (void) getCreatorsForItemKey: (NSString*) key;

- (NSString*) collectionKeyFromCollectionID:(NSInteger) collectionID;

// Methods for writing data to database
-(void) addItemToDatabase:(ZPZoteroItem*)item;

@end