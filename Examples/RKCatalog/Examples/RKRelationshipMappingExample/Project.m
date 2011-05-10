//
//  Project.m
//  RKCatalog
//
//  Created by Blake Watters on 4/21/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import "Project.h"

@implementation Project

@synthesize projectID = _projectID;
@synthesize name = _name;
@synthesize description = _description;
@synthesize user = _user;
@synthesize tasks = _tasks;

//+ (NSDictionary*)elementToPropertyMappings {
//    return [NSDictionary dictionaryWithKeysAndObjects:
//            @"id", @"projectID",
//            @"name", @"name",
//            @"description", @"description", 
//            nil];
//}
//
//+ (NSDictionary*)elementToRelationshipMappings {
//    return [NSDictionary dictionaryWithKeysAndObjects:
//            @"user", @"user",
//            @"tasks", @"tasks",
//            nil];
//}

@end
