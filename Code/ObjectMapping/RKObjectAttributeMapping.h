//
//  RKObjectElementMapping.h
//  RestKit
//
//  Created by Blake Watters on 4/30/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import <Foundation/Foundation.h>

//typedef enum {
//    RKObjectElementMappingTypeProperty,
//    RKObjectElementMappingTypeRelationship
//} RKObjectElementMappingType;

@class RKObjectAttributeMapping;

RKObjectAttributeMapping* RKObjectAttributeMappingMake(NSString* from, NSString* to);

// Defines the rules for mapping a particular element
// TODO: This is probably a private class that is created via calls to the object mapping?
@interface RKObjectAttributeMapping : NSObject {
    NSString* _sourceKeyPath;
    NSString* _destinationKeyPath;
}

@property (nonatomic, retain) NSString* sourceKeyPath;
@property (nonatomic, retain) NSString* destinationKeyPath;

/*!
 Defines a mapping from one keyPath to another within an object mapping
 */
+ (RKObjectAttributeMapping*)mappingFromKeyPath:(NSString*)sourceKeyPath toKeyPath:(NSString*)destinationKeyPath;

@end
