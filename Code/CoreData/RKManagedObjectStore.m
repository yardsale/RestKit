//
//  RKManagedObjectStore.m
//  RestKit
//
//  Created by Blake Watters on 9/22/09.
//  Copyright 2009 Two Toasters
//  
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//  http://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "RKManagedObjectStore.h"
#import "RKAlert.h"
#import "NSManagedObject+ActiveRecord.h"
#import "NSDictionary+RKAdditions.h"
#import "RKLog.h"
#import "RKDirectory.h"

// Set Logging Component
#undef RKLogComponent
#define RKLogComponent lcl_cRestKitCoreData

NSString* const RKManagedObjectStoreDidFailSaveNotification = @"RKManagedObjectStoreDidFailSaveNotification";
static NSString* const RKManagedObjectStoreThreadDictionaryContextKey = @"RKManagedObjectStoreThreadDictionaryContextKey";
static NSString* const RKManagedObjectStoreThreadDictionaryEntityCacheKey = @"RKManagedObjectStoreThreadDictionaryEntityCacheKey";

@interface RKManagedObjectStore (Private)
- (id)initWithStoreFilename:(NSString *)storeFilename inDirectory:(NSString *)nilOrDirectoryPath usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel delegate:(id)delegate;
- (void)createPersistentStoreCoordinator;
- (void)createStoreIfNecessaryUsingSeedDatabase:(NSString*)seedDatabase;
- (NSManagedObjectContext*)newManagedObjectContext;
@end

@implementation RKManagedObjectStore

@synthesize delegate = _delegate;
@synthesize storeFilename = _storeFilename;
@synthesize pathToStoreFile = _pathToStoreFile;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectCache = _managedObjectCache;
@synthesize storeDurability = _storeDurability;

+ (RKManagedObjectStore*)objectStoreWithStoreFilename:(NSString*)storeFilename {
    return [self objectStoreWithStoreFilename:storeFilename usingSeedDatabaseName:nil managedObjectModel:nil delegate:nil];
}

+ (RKManagedObjectStore*)objectStoreWithStoreFilename:(NSString *)storeFilename usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel delegate:(id)delegate {
    return [[[self alloc] initWithStoreFilename:storeFilename inDirectory:nil usingSeedDatabaseName:nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:nilOrManagedObjectModel delegate:delegate] autorelease];
}

+ (RKManagedObjectStore*)objectStoreWithStoreFilename:(NSString *)storeFilename inDirectory:(NSString *)directory usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel delegate:(id)delegate {
    return [[[self alloc] initWithStoreFilename:storeFilename inDirectory:directory usingSeedDatabaseName:nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:nilOrManagedObjectModel delegate:delegate] autorelease];
}

+ (RKManagedObjectStore*)objectStoreWithStoreFilename:(NSString *)storeFilename inDirectory:(NSString *)directory usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel storeDurability:(RKStoreDurability)storeDurability delegate:(id)delegate {
    return [[[self alloc] initWithStoreFilename:storeFilename inDirectory:directory usingSeedDatabaseName:nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:nilOrManagedObjectModel storeDurability:storeDurability delegate:delegate] autorelease];
}

- (id)initWithStoreFilename:(NSString*)storeFilename {
	return [self initWithStoreFilename:storeFilename inDirectory:nil usingSeedDatabaseName:nil managedObjectModel:nil delegate:nil];
}

- (id)initWithStoreFilename:(NSString *)storeFilename inDirectory:(NSString *)nilOrDirectoryPath usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel delegate:(id)delegate {
    return [self initWithStoreFilename:storeFilename inDirectory:nilOrDirectoryPath usingSeedDatabaseName:nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:nilOrManagedObjectModel storeDurability:RKStoreDurabilityNormal delegate:delegate];
}

- (id)initWithStoreFilename:(NSString *)storeFilename inDirectory:(NSString *)nilOrDirectoryPath usingSeedDatabaseName:(NSString *)nilOrNameOfSeedDatabaseInMainBundle managedObjectModel:(NSManagedObjectModel*)nilOrManagedObjectModel storeDurability:(RKStoreDurability)storeDurability delegate:(id)delegate {
    self = [self init];
	if (self) {
		_storeFilename = [storeFilename retain];
		_storeDurability = storeDurability;
		
		if (nilOrDirectoryPath == nil) {
			nilOrDirectoryPath = [RKDirectory applicationDataDirectory];
		} else {
			BOOL isDir;
			NSAssert1([[NSFileManager defaultManager] fileExistsAtPath:nilOrDirectoryPath isDirectory:&isDir] && isDir == YES, @"Specified storage directory exists", nilOrDirectoryPath);
		}
		_pathToStoreFile = [[nilOrDirectoryPath stringByAppendingPathComponent:_storeFilename] retain];
		
        if (nilOrManagedObjectModel == nil) {
            // NOTE: allBundles permits Core Data setup in unit tests
			nilOrManagedObjectModel = [NSManagedObjectModel mergedModelFromBundles:[NSBundle allBundles]];
        }
		_managedObjectModel = [nilOrManagedObjectModel retain];
		
        if (nilOrNameOfSeedDatabaseInMainBundle) {
            [self createStoreIfNecessaryUsingSeedDatabase:nilOrNameOfSeedDatabaseInMainBundle];
        }
		
        _delegate = delegate;
        
		[self createPersistentStoreCoordinator];
	}
    
	return self;
}

- (void)clearThreadLocalStorage {
    // Clear out our Thread local information
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
    if ([threadDictionary objectForKey:RKManagedObjectStoreThreadDictionaryContextKey]) {
        [threadDictionary removeObjectForKey:RKManagedObjectStoreThreadDictionaryContextKey];
    }
    if ([threadDictionary objectForKey:RKManagedObjectStoreThreadDictionaryEntityCacheKey]) {
        [threadDictionary removeObjectForKey:RKManagedObjectStoreThreadDictionaryEntityCacheKey];
    }
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clearThreadLocalStorage];
    
	[_storeFilename release];
	_storeFilename = nil;
	[_pathToStoreFile release];
	_pathToStoreFile = nil;
    
    [_managedObjectModel release];
	_managedObjectModel = nil;
    [_persistentStoreCoordinator release];
	_persistentStoreCoordinator = nil;
	[_managedObjectCache release];
	_managedObjectCache = nil;
    
	[super dealloc];
}

/**
 Performs the save action for the application, which is to send the save:
 message to the application's managed object context.
 */
- (NSError*)save {
	NSManagedObjectContext* moc = [self managedObjectContext];
	NSError *error;
	@try {
		if (![moc save:&error]) {
			if (self.delegate != nil && [self.delegate respondsToSelector:@selector(managedObjectStore:didFailToSaveContext:error:exception:)]) {
				[self.delegate managedObjectStore:self didFailToSaveContext:moc error:error exception:nil];
			}

			NSDictionary* userInfo = [NSDictionary dictionaryWithObject:error forKey:@"error"];
			[[NSNotificationCenter defaultCenter] postNotificationName:RKManagedObjectStoreDidFailSaveNotification object:self userInfo:userInfo];

			if ([[error domain] isEqualToString:@"NSCocoaErrorDomain"]) {
				NSDictionary *userInfo = [error userInfo];
				NSArray *errors = [userInfo valueForKey:@"NSDetailedErrors"];
				if (errors) {
					for (NSError *detailedError in errors) {
						NSDictionary *subUserInfo = [detailedError userInfo];
						RKLogError(@"Core Data Save Error\n \
							  NSLocalizedDescription:\t\t%@\n \
							  NSValidationErrorKey:\t\t\t%@\n \
							  NSValidationErrorPredicate:\t%@\n \
							  NSValidationErrorObject:\n%@\n",
							  [subUserInfo valueForKey:@"NSLocalizedDescription"], 
							  [subUserInfo valueForKey:@"NSValidationErrorKey"], 
							  [subUserInfo valueForKey:@"NSValidationErrorPredicate"], 
							  [subUserInfo valueForKey:@"NSValidationErrorObject"]);
					}
				}
				else {
					RKLogError(@"Core Data Save Error\n \
							   NSLocalizedDescription:\t\t%@\n \
							   NSValidationErrorKey:\t\t\t%@\n \
							   NSValidationErrorPredicate:\t%@\n \
							   NSValidationErrorObject:\n%@\n", 
							   [userInfo valueForKey:@"NSLocalizedDescription"],
							   [userInfo valueForKey:@"NSValidationErrorKey"], 
							   [userInfo valueForKey:@"NSValidationErrorPredicate"], 
							   [userInfo valueForKey:@"NSValidationErrorObject"]);
				}
			} 
			return error;
		}
	}
	@catch (NSException* e) {
		if (self.delegate != nil && [self.delegate respondsToSelector:@selector(managedObjectStore:didFailToSaveContext:error:exception:)]) {
			[self.delegate managedObjectStore:self didFailToSaveContext:moc error:nil exception:e];
		}
		else {
			@throw;
		}
	}
	return nil;
}

- (NSManagedObjectContext*)newManagedObjectContext {
	NSManagedObjectContext* managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:self.persistentStoreCoordinator];
	[managedObjectContext setUndoManager:nil];
	[managedObjectContext setMergePolicy:NSOverwriteMergePolicy];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(objectsDidChange:)
												 name:NSManagedObjectContextObjectsDidChangeNotification
											   object:managedObjectContext];
	return managedObjectContext;
}

- (void)createStoreIfNecessaryUsingSeedDatabase:(NSString*)seedDatabase {
    if (NO == [[NSFileManager defaultManager] fileExistsAtPath:self.pathToStoreFile]) {
        NSString* seedDatabasePath = [[NSBundle mainBundle] pathForResource:seedDatabase ofType:nil];
        NSAssert1(seedDatabasePath, @"Unable to find seed database file '%@' in the Main Bundle, aborting...", seedDatabase);
        RKLogInfo(@"No existing database found, copying from seed path '%@'", seedDatabasePath);
		
		NSError* error;
        if (![[NSFileManager defaultManager] copyItemAtPath:seedDatabasePath toPath:self.pathToStoreFile error:&error]) {
			if (self.delegate != nil && [self.delegate respondsToSelector:@selector(managedObjectStore:didFailToCopySeedDatabase:error:)]) {
				[self.delegate managedObjectStore:self didFailToCopySeedDatabase:seedDatabase error:error];
			} else {
				RKLogError(@"Encountered an error during seed database copy: %@", [error localizedDescription]);
			}
        }
        NSAssert1([[NSFileManager defaultManager] fileExistsAtPath:seedDatabasePath], @"Seed database not found at path '%@'!", seedDatabasePath);
    }
}

- (void)createPersistentStoreCoordinator {
    NSAssert(self.storeDurability > RKStoreDurabilityNotSpecified, @"Must specify a store durability.");

	NSURL *storeUrl = [NSURL fileURLWithPath:self.pathToStoreFile];
	
	NSError *error;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_managedObjectModel];

    // Performance-tuned pragmas
    NSDictionary *pragmaOptions;
    NSString *storeType;

    switch (self.storeDurability) {
        case RKStoreDurabilityOff:
            storeType = NSInMemoryStoreType;
            pragmaOptions = nil; // SQLite only
            break;
        case RKStoreDurabilityLow:
            storeType = NSSQLiteStoreType;
            pragmaOptions = [NSDictionary dictionaryWithKeysAndObjects:
                             @"synchronous", @"OFF",
                             @"fullfsync", @"0",
                             nil];
            break;
        case RKStoreDurabilityNormal:
            storeType = NSSQLiteStoreType;
            pragmaOptions = [NSDictionary dictionaryWithKeysAndObjects:
                             @"synchronous", @"NORMAL",
                             @"fullfsync", @"0",
                             nil];
            break;
        case RKStoreDurabilityMaximum:
            storeType = NSSQLiteStoreType;
            pragmaOptions = [NSDictionary dictionaryWithKeysAndObjects:
                             @"synchronous", @"FULL",
                             @"fullfsync", @"1",
                             nil];
            break;
    }

	// Allow inferred migration from the original version of the application.
	NSDictionary *options = [NSDictionary dictionaryWithKeysAndObjects:
							 NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES],
							 NSInferMappingModelAutomaticallyOption, [NSNumber numberWithBool:YES],
                             NSSQLitePragmasOption, pragmaOptions,
                             nil];
	
	if (![_persistentStoreCoordinator addPersistentStoreWithType:storeType configuration:nil URL:storeUrl options:options error:&error]) {
		if (self.delegate != nil && [self.delegate respondsToSelector:@selector(managedObjectStore:didFailToCreatePersistentStoreCoordinatorWithError:)]) {
			[self.delegate managedObjectStore:self didFailToCreatePersistentStoreCoordinatorWithError:error];
		} else {
			NSAssert(NO, @"Managed object store failed to create persistent store coordinator: %@", error);
		}
    }
}

- (void)deletePersistantStoreUsingSeedDatabaseName:(NSString *)seedFile {
	NSURL* storeURL = [NSURL fileURLWithPath:self.pathToStoreFile];
	
	NSError* error;
    if ([[NSFileManager defaultManager] fileExistsAtPath:storeURL.path]) {
        if (![[NSFileManager defaultManager] removeItemAtPath:storeURL.path error:&error]) {
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(managedObjectStore:didFailToDeletePersistentStore:error:)]) {
                [self.delegate managedObjectStore:self didFailToDeletePersistentStore:self.pathToStoreFile error:error];
            }
            else {
                NSAssert(NO, @"Managed object store failed to delete persistent store : %@", error);
            }
        }
    } else {
        RKLogWarning(@"Asked to delete persistent store but no store file exists at path: %@", storeURL.path);
    }
	
	[_persistentStoreCoordinator release];
	_persistentStoreCoordinator = nil;
	
	[self clearThreadLocalStorage];
	
	if (seedFile) {
        [self createStoreIfNecessaryUsingSeedDatabase:seedFile];
    }

	[self createPersistentStoreCoordinator];
}

- (void)deletePersistantStore {
	[self deletePersistantStoreUsingSeedDatabaseName:nil];
}

/**
 *
 *	Override managedObjectContext getter to ensure we return a separate context
 *	for each NSThread.
 *
 */
-(NSManagedObjectContext*)managedObjectContext {
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
	NSManagedObjectContext* backgroundThreadContext = [threadDictionary objectForKey:RKManagedObjectStoreThreadDictionaryContextKey];
	if (!backgroundThreadContext) {
		backgroundThreadContext = [self newManagedObjectContext];
		[threadDictionary setObject:backgroundThreadContext forKey:RKManagedObjectStoreThreadDictionaryContextKey];
		[backgroundThreadContext release];

		[[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mergeChanges:)
													 name:NSManagedObjectContextDidSaveNotification
												   object:backgroundThreadContext];
	}
	return backgroundThreadContext;
}

- (void)mergeChangesOnMainThreadWithNotification:(NSNotification*)notification {
	assert([NSThread isMainThread]);
	[self.managedObjectContext performSelectorOnMainThread:@selector(mergeChangesFromContextDidSaveNotification:)
												withObject:notification
											 waitUntilDone:YES];
}

- (void)mergeChanges:(NSNotification *)notification {
	// Merge changes into the main context on the main thread
	[self performSelectorOnMainThread:@selector(mergeChangesOnMainThreadWithNotification:) withObject:notification waitUntilDone:YES];
}

- (void)objectsDidChange:(NSNotification*)notification {
	NSDictionary* userInfo = notification.userInfo;
	NSSet* insertedObjects = [userInfo objectForKey:NSInsertedObjectsKey];
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
	
	for (NSManagedObject* object in insertedObjects) {
		if ([object respondsToSelector:@selector(primaryKeyProperty)]) {
			Class theClass = [object class];
			NSString* primaryKey = [theClass performSelector:@selector(primaryKeyProperty)];
			id primaryKeyValue = [object valueForKey:primaryKey];
			
			NSMutableDictionary* classCache = [threadDictionary objectForKey:theClass];
			if (classCache && primaryKeyValue && [classCache objectForKey:primaryKeyValue] == nil) {
				[classCache setObject:object forKey:primaryKeyValue];
			}
		}
	}
}

#pragma mark -
#pragma mark Helpers

- (NSManagedObject*)objectWithID:(NSManagedObjectID*)objectID {
	return [self.managedObjectContext objectWithID:objectID];
}

- (NSArray*)objectsWithIDs:(NSArray*)objectIDs {
	NSMutableArray* objects = [[NSMutableArray alloc] init];
	for (NSManagedObjectID* objectID in objectIDs) {
		[objects addObject:[self.managedObjectContext objectWithID:objectID]];
	}
	NSArray* objectArray = [NSArray arrayWithArray:objects];
	[objects release];
	
	return objectArray;
}

- (NSManagedObject*)findOrCreateInstanceOfEntity:(NSEntityDescription*)entity withPrimaryKeyAttribute:(NSString*)primaryKeyAttribute andValue:(id)primaryKeyValue {
    NSAssert(entity, @"Cannot instantiate managed object without a target class");
    NSAssert(primaryKeyAttribute, @"Cannot find existing managed object instance without a primary key attribute");
    NSAssert(primaryKeyValue, @"Cannot find existing managed object by primary key without a value");
	NSManagedObject* object = nil;
    
    // NOTE: We coerce the primary key into a string (if possible) for convenience. Generally
    // primary keys are expressed either as a number of a string, so this lets us support either case interchangeably
    id lookupValue = [primaryKeyValue respondsToSelector:@selector(stringValue)] ? [primaryKeyValue stringValue] : primaryKeyValue;
    NSString* entityName = entity.name;

    NSMutableDictionary* dictionary = [self objectCacheForEntity:entity withPrimaryKeyAttribute:primaryKeyAttribute];
    NSAssert1(dictionary, @"Thread local cache of %@ objects should not be nil", entityName);
    object = [dictionary objectForKey:lookupValue];

    if (object == nil) {
        object = [[[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:self.managedObjectContext] autorelease];
        [dictionary setObject:object forKey:lookupValue];
    }

	return object;
}

- (NSMutableDictionary*)objectCacheForEntity:(NSEntityDescription*)entity withPrimaryKeyAttribute:(NSString*)primaryKeyAttribute;
{
    //
    // Use thread-local storage to build a dictionary in the following format:
    //   threadStorage["RKEntityCacheKey"] = {
    //      entityClassName1: {
    //              primaryKeyCoercedToString1: { ... the object ... },
    //              primaryKeyCoercedToString2: { ... the object ... },
    //      }
    //   }
    //
    // First check for the existence of the cache, and create if necessary.
    // Return => threadStorage["RKEntityCacheKey"][entity.name]
    //

    NSArray* objects = nil;
    NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
    
    if (nil == [threadDictionary objectForKey:RKManagedObjectStoreThreadDictionaryEntityCacheKey]) {
        [threadDictionary setObject:[NSMutableDictionary dictionary] forKey:RKManagedObjectStoreThreadDictionaryEntityCacheKey];
    }

    NSMutableDictionary* entityCache = [threadDictionary objectForKey:RKManagedObjectStoreThreadDictionaryEntityCacheKey];

    if (nil == [entityCache objectForKey:entity.name]) {
        // Note: I tried prefetching all relationships but didn't see any
        // performance increase. Likely application-specific. [ETM]
        NSFetchRequest* fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
        [fetchRequest setEntity:entity];
        [fetchRequest setReturnsObjectsAsFaults:NO];

        objects = [NSManagedObject executeFetchRequest:fetchRequest];
        RKLogInfo(@"Caching all %lu %@ objects to thread local storage", (unsigned long) [objects count], entity.name);

        NSMutableDictionary* primaryKeyToObjectDictionary = [NSMutableDictionary dictionary];

        // Coerce object's primary key to NSString, if possible.
        id testObjectPrimaryKeyValue = [[objects lastObject] valueForKey:primaryKeyAttribute];
        BOOL coerceToString = [testObjectPrimaryKeyValue respondsToSelector:@selector(stringValue)];

        for (id theObject in objects) {
            id attributeValue = [theObject valueForKey:primaryKeyAttribute];
            attributeValue = coerceToString ? [attributeValue stringValue] : attributeValue;
            if (attributeValue) {
                [primaryKeyToObjectDictionary setObject:theObject forKey:attributeValue];
            }
        }
        
        [entityCache setObject:primaryKeyToObjectDictionary forKey:entity.name];
    }
    
    return [entityCache objectForKey:entity.name];
}

- (NSArray*)objectsForResourcePath:(NSString *)resourcePath {
    NSArray* cachedObjects = nil;
    
    if (self.managedObjectCache) {
        NSArray* cacheFetchRequests = [self.managedObjectCache fetchRequestsForResourcePath:resourcePath];
        cachedObjects = [NSManagedObject objectsWithFetchRequests:cacheFetchRequests];
    }
    
    return cachedObjects;
}

@end
