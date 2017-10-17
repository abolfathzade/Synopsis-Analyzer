//
//  SessionController.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "SessionController.h"
#import "OperationRowView.h"
#import "SessionRowView.h"

@interface SessionController ()
@property (readwrite, strong) IBOutlet NSOutlineView* sessionOutlineView;
@property (readwrite, strong) NSMutableArray<SessionStateWrapper*>* sessionStates;

@end

@implementation SessionController

- (void) awakeFromNib
{
    self.sessionStates = [NSMutableArray new];
    
    NSNib* sessionRowControllerNib = [[NSNib alloc] initWithNibNamed:@"SessionRowView" bundle:[NSBundle mainBundle]];
    [self.sessionOutlineView registerNib:sessionRowControllerNib forIdentifier:@"SessionRowView"];

    NSNib* operationRowControllerNib = [[NSNib alloc] initWithNibNamed:@"OperationRowView" bundle:[NSBundle mainBundle]];
    [self.sessionOutlineView registerNib:operationRowControllerNib forIdentifier:@"OperationRowView"];
    
    self.sessionOutlineView.autoresizesOutlineColumn = NO;
    self.sessionOutlineView.indentationMarkerFollowsCell = NO;
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
        return 27.0;
    }
    
    return 49.0;
}

#pragma mark - NSOutlineViewDelegate -

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item
{
    if([item isKindOfClass:[SessionStateWrapper class]])
    {
        SessionStateWrapper* sessionState = (SessionStateWrapper*)item;
        SessionRowView* view = [self.sessionOutlineView makeViewWithIdentifier:@"SessionRowView" owner:nil];
        [view setSessionState:sessionState];
        [view beginSessionStateListening];
        return view;
    }

    else if([item isKindOfClass:[OperationStateWrapper class]])
    {
        OperationStateWrapper* operationState = (OperationStateWrapper*)item;
        OperationRowView* view = [self.sessionOutlineView makeViewWithIdentifier:@"OperationRowView" owner:nil];
        [view setOperationState:operationState];
        [view beginOperationStateListening];
        
        return view;
    }
    
    return nil;
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
    id view = [rowView viewAtColumn:0];

    if([view isKindOfClass:[SessionRowView class]])
    {
        SessionRowView* operationRowView = (SessionRowView*)view;
        [operationRowView endSessionStateListening];
    }

    if([view isKindOfClass:[OperationRowView class]])
    {
        OperationRowView* operationRowView = (OperationRowView*)view;
        [operationRowView endOperationStateListening];
    }
}


@end
