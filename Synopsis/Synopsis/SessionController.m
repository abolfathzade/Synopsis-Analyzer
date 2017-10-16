//
//  SessionController.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "SessionController.h"

//NSString* const kSynopsisSessionAvailable = @"SynopsisSessionAvailable";
NSString* const kSynopsisSessionProgressUpdate = @"SynopsisSessionProgressUpdate";

@interface SessionController ()
@property (readwrite, strong) IBOutlet NSOutlineView* sessionOutlineView;
@property (readwrite, strong) NSMutableArray<SessionStateWrapper*>* sessionStates;
@end

@implementation SessionController

- (void) awakeFromNib
{
    self.sessionStates = [NSMutableArray new];
    
    // Register for Session notifications - when a session is created or updated, we add it to our tracked sessionStates
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSession:) name:kSynopsisSessionProgressUpdate object:nil];

    NSNib* sessionRowControllerNib = [[NSNib alloc] initWithNibNamed:@"SessionRowController" bundle:[NSBundle mainBundle]];
    [self.sessionOutlineView registerNib:sessionRowControllerNib forIdentifier:@"SessionRow"];

    NSNib* operationRowControllerNib = [[NSNib alloc] initWithNibNamed:@"OperationRowController" bundle:[NSBundle mainBundle]];
    [self.sessionOutlineView registerNib:operationRowControllerNib forIdentifier:@"OperationRow"];
}

- (void) addNewSession:(SessionStateWrapper*)newSessionState
{
    if(newSessionState)
    {
//        [self.sessionOutlineView reloadItem:newSessionState reloadChildren:YES];
        [self.sessionStates addObject:newSessionState];

        NSIndexSet* indexSet = [NSIndexSet indexSetWithIndex:self.sessionStates.count - 1];
        [self.sessionOutlineView insertItemsAtIndexes:indexSet inParent:nil withAnimation:NSTableViewAnimationEffectFade];
        
//        [self.sessionOutlineView reloadData];
    }
}


- (NSArray<SessionStateWrapper*>*)sessions
{
    return [self.sessionStates copy];
}

- (void) updateSession:(NSNotification*)notification
{
    SessionStateWrapper* newSessionState = notification.object;
    
    if(newSessionState)
    {
        [self.sessionOutlineView reloadItem:newSessionState reloadChildren:YES];
    }
}

- (void) updateOperation:(NSNotification*)notification
{
    SessionStateWrapper* newSessionState = notification.object;
    
    if(newSessionState)
    {
        [self.sessionOutlineView reloadItem:newSessionState reloadChildren:YES];
    }
}

#pragma mark - NSOutlineViewDataSource -

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item
{
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        SessionStateWrapper* sessionState = (SessionStateWrapper*)item;
        return sessionState.sessionOperationStates.count;
    }
    
    return self.sessionStates.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item
{
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        SessionStateWrapper* sessionState = (SessionStateWrapper*)item;
        return sessionState.sessionOperationStates[index];
    }
    
    return self.sessionStates[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        return YES;
    }

    return NO;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        return 35.0;
    }
    
    return 40.0;
}

#pragma mark - NSOutlineViewDelegate -

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item
{
    NSView* view = nil;
    
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        view = [self.sessionOutlineView makeViewWithIdentifier:@"SessionRow" owner:self];
    }
    else if([item isKindOfClass:[OperationStateWrapper class]])
    {
        view = [self.sessionOutlineView makeViewWithIdentifier:@"OperationRow" owner:self];
    }
    
    return view;
}

//- (nullable NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
//{
//    return nil;
//}

- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    
}

- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    
}

@end
