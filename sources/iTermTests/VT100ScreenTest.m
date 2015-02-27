//
//  VT100ScreenTest.m
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import "iTermTests.h"
#import "DVR.h"
#import "DVRDecoder.h"
#import "LineBuffer.h"
#import "PTYNoteViewController.h"
#import "SearchResult.h"
#import "TmuxStateParser.h"
#import "VT100ScreenTest.h"
#import "VT100Screen.h"
#import "iTermSelection.h"

@interface VT100ScreenTest () <iTermSelectionDelegate, VT100ScreenDelegate>
@end

@interface VT100Screen (UnitTest)
// It's only safe to use this on a newly created screen.
- (void)setLineBuffer:(LineBuffer *)lineBuffer;
@end

@implementation VT100Screen (UnitTest)
- (void)setLineBuffer:(LineBuffer *)lineBuffer {
    [linebuffer_ release];
    linebuffer_ = [lineBuffer retain];
}
@end

@implementation VT100ScreenTest {
    VT100Terminal *terminal_;
    iTermSelection *selection_;
    int needsRedraw_;
    int sizeDidChange_;
    BOOL cursorVisible_;
    int triggers_;
    BOOL highlightsCleared_;
    BOOL ambiguousIsDoubleWidth_;
    int updates_;
    BOOL shouldSendContentsChangedNotification_;
    BOOL printingAllowed_;
    NSMutableString *printed_;
    NSMutableString *triggerLine_;
    BOOL canResize_;
    BOOL isFullscreen_;
    VT100GridSize newSize_;
    BOOL syncTitle_;
    NSString *windowTitle_;
    NSString *name_;
    NSMutableArray *dirlog_;
    NSSize newPixelSize_;
    NSString *pasteboard_;
    NSMutableData *pbData_;
    BOOL pasted_;
    NSMutableData *write_;
}

- (void)setup {
    terminal_ = [[[VT100Terminal alloc] init] autorelease];
    selection_ = [[[iTermSelection alloc] init] autorelease];
    selection_.delegate = self;
    needsRedraw_ = 0;
    sizeDidChange_ = 0;
    cursorVisible_ = YES;
    triggers_ = 0;
    highlightsCleared_ = NO;
    ambiguousIsDoubleWidth_ = NO;
    updates_ = 0;
    shouldSendContentsChangedNotification_ = NO;
    printingAllowed_ = YES;
    triggerLine_ = [NSMutableString string];
    canResize_ = YES;
    isFullscreen_ = NO;
    newSize_ = VT100GridSizeMake(0, 0);
    syncTitle_ = YES;
    windowTitle_ = nil;
    name_ = nil;
    dirlog_ = [NSMutableArray array];
    newPixelSize_ = NSMakeSize(0, 0);
    pasteboard_ = nil;
    pbData_ = [NSMutableData data];
    pasted_ = NO;
    write_ = [NSMutableData data];
}

#pragma mark - Convenience methods

- (VT100Screen *)screen {
    VT100Screen *screen = [[[VT100Screen alloc] initWithTerminal:terminal_] autorelease];
    terminal_.delegate = screen;
    return screen;
}

- (void)testInit {
    VT100Screen *screen = [self screen];

    // Make sure the screen is initialized to a positive size with the cursor at the origin
    assert([screen width] > 0);
    assert([screen height] > 0);
    assert(screen.maxScrollbackLines > 0);
    assert([screen cursorX] == 1);
    assert([screen cursorY] == 1);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Append some stuff to it to make sure we can retreive it.
    for (int i = 0; i < [screen height] - 1; i++) {
        [screen terminalAppendString:[NSString stringWithFormat:@"Line %d", i]];
        [screen terminalLineFeed];
        [screen terminalCarriageReturn];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);
    assert([screen numberOfLines] == [screen height]);

    // Make sure it has a functioning line buffer.
    [screen terminalLineFeed];
    assert([screen numberOfLines] == [screen height] + 1);
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);

    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);
    
    assert(screen.dvr);
    [self assertInitialTabStopsAreSetInScreen:screen];
}

- (void)assertInitialTabStopsAreSetInScreen:(VT100Screen *)screen {
    // Make sure tab stops are set up properly.
    [screen terminalCarriageReturn];
    int expected = 9;
    while (expected < [screen width]) {
        [screen terminalAppendTabAtCursor];
        assert([screen cursorX] == expected);
        assert([screen cursorY] == [screen height]);
        expected += 8;
    }
}

- (void)testDestructivelySetScreenWidthHeight {
    VT100Screen *screen = [self screen];
    [screen terminalShowTestPattern];
    // Make sure it's full.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == [screen width]);
    }

    int w = [screen width] + 1;
    int h = [screen height] + 1;
    [screen destructivelySetScreenWidth:w height:h];
    assert([screen width] == w);
    assert([screen height] == h);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Make sure it is as large as it claims to be
    [screen terminalMoveCursorToX:1 y:1];
    char letters[] = "123456";
    int n = 6;
    NSMutableString *expected = [NSMutableString string];
    for (int i = 0; i < w; i++) {
        NSString *toAppend = [NSString stringWithFormat:@"%c", letters[i % n]];
        [expected appendString:toAppend];
        [screen appendStringAtCursor:toAppend];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:expected]);
}

- (VT100Screen *)screenWithWidth:(int)width height:(int)height {
    VT100Screen *screen = [self screen];
    [screen destructivelySetScreenWidth:width height:height];
    return screen;
}

- (void)appendLines:(NSArray *)lines toScreen:(VT100Screen *)screen {
    for (NSString *line in lines) {
        [screen appendStringAtCursor:line];
        [screen terminalCarriageReturn];
        [screen terminalLineFeed];
    }
}

- (void)appendLinesNoNewline:(NSArray *)lines toScreen:(VT100Screen *)screen {
  for (int i = 0; i < lines.count; i++) {
    NSString *line = lines[i];
    [screen appendStringAtCursor:line];
    if (i + 1 != lines.count) {
      [screen terminalCarriageReturn];
      [screen terminalLineFeed];
    }
  }
}

// abcde+
// fgh..!
// ijkl.!
// .....!
// Cursor at first col of last row.
- (VT100Screen *)fiveByFourScreenWithThreeLinesOneWrapped {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    return screen;
}

// abcdefgh
//
// ijkl.!
// mnopq+
// rst..!
// .....!
// Cursor at first col of last row

- (VT100Screen *)fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @"mnopq\n"
            @"rst..\n"
            @"....."]);
    return screen;
}

- (void)showAltAndUppercase:(VT100Screen *)screen {
    VT100Grid *temp = [[[screen currentGrid] copy] autorelease];
    [screen terminalShowAltBuffer];
    for (int y = 0; y < screen.height; y++) {
        screen_char_t *lineIn = [temp screenCharsAtLineNumber:y];
        screen_char_t *lineOut = [screen getLineAtScreenIndex:y];
        for (int x = 0; x < screen.width; x++) {
            lineOut[x] = lineIn[x];
            unichar c = lineIn[x].code;
            if (isalpha(c)) {
                c -= 'a' - 'A';
            }
            lineOut[x].code = c;
        }
        lineOut[screen.width] = lineIn[screen.width];
    }
}

- (void)setSelectionRange:(VT100GridCoordRange)range {
    [selection_ clearSelection];
    VT100GridWindowedRange theRange =
    VT100GridWindowedRangeMake(range, 0, 0);
    iTermSubSelection *theSub =
    [iTermSubSelection subSelectionWithRange:theRange
                                        mode:kiTermSelectionModeCharacter];
    [selection_ addSubSelection:theSub];
}


- (VT100Screen *)screenFromCompactLines:(NSString *)compactLines {
    NSArray *lines = [compactLines componentsSeparatedByString:@"\n"];
    VT100Screen *screen = [self screenWithWidth:[[lines objectAtIndex:0] length]
                                         height:[lines count]];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [screen getLineAtScreenIndex:i++];
        for (int j = 0; j < [line length]; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            if (c == '-') c = DWC_RIGHT;
            if (j == [line length] - 1) {
                if (c == '>') {
                    c = DWC_SKIP;
                    s[j+1].code = EOL_DWC;
                } else {
                    s[j+1].code = EOL_HARD;
                }
            }
            s[j].code = c;
        }
    }
    return screen;
}

- (VT100Screen *)screenFromCompactLinesWithContinuationMarks:(NSString *)compactLines {
    NSArray *lines = [compactLines componentsSeparatedByString:@"\n"];
    VT100Screen *screen = [self screenWithWidth:[[lines objectAtIndex:0] length] - 1
                                         height:[lines count]];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [screen getLineAtScreenIndex:i++];
        for (int j = 0; j < [line length] - 1; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            if (c == '-') {
                c = DWC_RIGHT;
                [screen setMayHaveDoubleWidthCharacters:YES];
            }
            if (j == [line length] - 1) {
                if (c == '>') {
                    [screen setMayHaveDoubleWidthCharacters:YES];
                    c = DWC_SKIP;
                }
            }
            s[j].code = c;
        }
        int j = [line length] - 1;
        switch ([line characterAtIndex:j]) {
            case '!':
                s[j].code = EOL_HARD;
                break;

            case '+':
                s[j].code = EOL_SOFT;
                break;

            case '>':
                [screen setMayHaveDoubleWidthCharacters:YES];
                s[j].code = EOL_DWC;
                break;

            default:
                assert(false);  // bogus continution mark
        }
    }
    return screen;
}

- (NSString *)selectedStringInScreen:(VT100Screen *)screen {
    if (![selection_ hasSelection]) {
        return nil;
    }
    NSMutableString *s = [NSMutableString string];
    [selection_ enumerateSelectedRanges:^(VT100GridWindowedRange range, BOOL *stop, BOOL eol) {
        int sx = range.coordRange.start.x;
        for (int y = range.coordRange.start.y; y <= range.coordRange.end.y; y++) {
            screen_char_t *line = [screen getLineAtIndex:y];
            int x;
            int ex = y == range.coordRange.end.y ? range.coordRange.end.x : [screen width];
            BOOL newline = NO;
            for (x = sx; x < ex; x++) {
                if (line[x].code) {
                    [s appendString:ScreenCharArrayToStringDebug(line + x, 1)];
                } else {
                    newline = YES;
                    [s appendString:@"\n"];
                    break;
                }
            }
            if (line[x].code == EOL_HARD && !newline && y != range.coordRange.end.y) {
                [s appendString:@"\n"];
            }
            sx = 0;
        }
        if (eol) {
            [s appendString:@"\n"];
        }
    }];
    return s;
}

- (void)sendDataToTerminal:(NSData *)data {
    [terminal_.parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 1);
    [terminal_.parser addParsedTokensToVector:&vector];
    assert(CVectorCount(&vector) == 1);
    [terminal_ executeToken:CVectorGetObject(&vector, 0)];
    CVectorDestroy(&vector);
}

- (void)sendEscapeCodes:(NSString *)codes {
    NSString *esc = [NSString stringWithFormat:@"%c", 27];
    NSString *bel = [NSString stringWithFormat:@"%c", 7];
    codes = [codes stringByReplacingOccurrencesOfString:@"^[" withString:esc];
    codes = [codes stringByReplacingOccurrencesOfString:@"^G" withString:bel];
    NSData *data = [codes dataUsingEncoding:NSUTF8StringEncoding];
    [terminal_.parser putStreamData:data.bytes length:data.length];

    CVector vector;
    CVectorCreate(&vector, 1);
    [terminal_.parser addParsedTokensToVector:&vector];
    for (int i = 0; i < CVectorCount(&vector); i++) {
        VT100Token *token = CVectorGetObject(&vector, i);
        [terminal_ executeToken:token];
    }
    CVectorDestroy(&vector);
}

- (NSData *)screenCharLineForString:(NSString *)s {
    NSMutableData *data = [NSMutableData dataWithLength:s.length * sizeof(screen_char_t)];
    int len;
    StringToScreenChars(s,
                        (screen_char_t *)[data mutableBytes],
                        [terminal_ foregroundColorCode],
                        [terminal_ backgroundColorCode],
                        &len,
                        NO,
                        NULL,
                        NULL,
                        NO);
    return data;
}

- (void)assertScreen:(VT100Screen *)screen
   matchesHighlights:(NSArray *)expectedHighlights
         highlightFg:(int)hfg
     highlightFgMode:(ColorMode)hfm
         highlightBg:(int)hbg
     highlightBgMode:(ColorMode)hbm {
    int defaultFg = [terminal_ foregroundColorCode].foregroundColor;
    int defaultBg = [terminal_ foregroundColorCode].backgroundColor;
    for (int i = 0; i < screen.height; i++) {
        screen_char_t *line = [screen getLineAtScreenIndex:i];
        NSString *expected = expectedHighlights[i];
        for (int j = 0; j < screen.width; j++) {
            if ([expected characterAtIndex:j] == 'h') {
                assert(line[j].foregroundColor == hfg &&
                       line[j].foregroundColorMode ==  hfm&&
                       line[j].backgroundColor == hbg &&
                       line[j].backgroundColorMode == hbm);
            } else {
                assert(line[j].foregroundColor == defaultFg &&
                       line[j].foregroundColorMode == ColorModeAlternate &&
                       line[j].backgroundColor == defaultBg &&
                       line[j].backgroundColorMode == ColorModeAlternate);
            }
        }
    }

}

- (void)sendStringToTerminalWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [self sendDataToTerminal:data];
}

#pragma mark - VT100ScreenDelegate

- (void)screenSetColor:(NSColor *)color forKey:(int)key {
}

- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath {
}

- (BOOL)screenShouldPlacePromptAtFirstColumn {
    return YES;
}

- (void)screenSetBackgroundImageFile:(NSString *)filename {
}

- (void)screenSetBadgeFormat:(NSString *)theFormat {
}

- (void)screenSetUserVar:(NSString *)kvp {
}

- (void)screenUpdateDisplay {
    ++updates_;
}

- (BOOL)screenHasView {
    return YES;
}

- (iTermSelection *)screenSelection {
    return selection_;
}

- (void)screenSetSelectionFromX:(int)startX
                          fromY:(int)startY
                            toX:(int)endX
                            toY:(int)endY {
    [selection_ clearSelection];
    VT100GridWindowedRange theRange =
        VT100GridWindowedRangeMake(VT100GridCoordRangeMake(startX, startY, endX, endY), 0, 0);
    iTermSubSelection *theSub =
        [iTermSubSelection subSelectionWithRange:theRange mode:kiTermSelectionModeCharacter];
    [selection_ addSubSelection:theSub];
}

- (void)screenRemoveSelection {
    [selection_ clearSelection];
}

- (void)screenNeedsRedraw {
    needsRedraw_++;
}

- (void)screenSizeDidChange {
    sizeDidChange_++;
}

- (void)screenResizeToWidth:(int)newWidth height:(int)newHeight {
    newSize_ = VT100GridSizeMake(newWidth, newHeight);
}

- (void)screenResizeToPixelWidth:(int)newWidth height:(int)newHeight {
    newPixelSize_ = NSMakeSize(newWidth, newHeight);
}

- (BOOL)screenShouldInitiateWindowResize {
    return canResize_;
}

- (BOOL)screenWindowIsFullscreen {
    return isFullscreen_;
}

- (void)screenTriggerableChangeDidOccur {
    ++triggers_;
    triggerLine_ = [NSMutableString string];
}

- (void)screenSetCursorVisible:(BOOL)visible {
    cursorVisible_ = visible;
}

- (void)screenSetWindowTitle:(NSString *)newTitle {
    windowTitle_ = [[newTitle copy] autorelease];
}

- (void)screenSetName:(NSString *)name {
    name_ = [[name copy] autorelease];
}

- (NSString *)screenNameExcludingJob {
    return @"joblessName";
}

- (NSString *)screenProfileName {
    return @"Default";
}

- (void)screenLogWorkingDirectoryAtLine:(int)line withDirectory:(NSString *)directory {
    [dirlog_ addObject:@[ @(line), directory ? directory : [NSNull null] ]];
}

- (NSRect)screenWindowFrame {
    return NSMakeRect(10, 20, 100, 200);
}

- (NSRect)screenWindowScreenFrame {
    return NSMakeRect(30, 40, 1000, 2000);
}

- (BOOL)screenAllowTitleSetting {
    return YES;
}

- (NSString *)screenCurrentWorkingDirectory {
    return nil;
}

- (void)screenClearHighlights {
    highlightsCleared_ = YES;
}

- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth {
    return ambiguousIsDoubleWidth_;
}

- (BOOL)screenShouldSendContentsChangedNotification {
    return shouldSendContentsChangedNotification_;
}

- (BOOL)screenShouldBeginPrinting {
    return printingAllowed_;
}

- (BOOL)screenShouldSyncTitle {
    return syncTitle_;
}

- (void)screenDidAppendStringToCurrentLine:(NSString *)string {
    [triggerLine_ appendString:string];
}

- (void)screenDidAppendAsciiDataToCurrentLine:(AsciiData *)asciiData {
    [self screenDidAppendStringToCurrentLine:[[[NSString alloc] initWithBytes:asciiData->buffer
                                                                       length:asciiData->length
                                                                     encoding:NSASCIIStringEncoding]
                                              autorelease]];
}

- (void)screenDidReset {
}

- (void)screenPrintString:(NSString *)s {
    if (!printed_) {
        printed_ = [NSMutableString string];
    }
    [printed_ appendString:s];
}

- (void)screenPrintVisibleArea {
    [self screenPrintString:@"(screen dump)"];
}

- (BOOL)screenIsAppendingToPasteboard {
    return pasteboard_ != nil && !pasted_;
}

- (void)screenSetPasteboard:(NSString *)pasteboard {
    pasteboard_ = [[pasteboard copy] autorelease];
}

- (void)screenAppendDataToPasteboard:(NSData *)data {
    [pbData_ appendData:data];
}

- (void)screenCopyBufferToPasteboard {
    pasted_ = YES;
}

- (BOOL)screenShouldSendReport {
    return YES;
}

- (void)screenWriteDataToTask:(NSData *)data {
    [write_ appendData:data];
}

- (void)screenDidChangeNumberOfScrollbackLines {
}

- (int)screenSessionID {
    return 0;
}

- (void)screenSetCursorBlinking:(BOOL)blink {
}

- (void)screenSetCursorType:(ITermCursorType)type {
}

- (NSString *)screenWindowTitle {
    return windowTitle_;
}

- (NSString *)screenDefaultName {
    return @"Default name";
}

- (NSString *)screenName {
    return name_;
}

- (NSPoint)screenWindowTopLeftPixelCoordinate {
    return NSZeroPoint;
}

- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point {
}

- (void)screenMiniaturizeWindow:(BOOL)flag {
}

- (void)screenRaise:(BOOL)flag {
}

- (BOOL)screenWindowIsMiniaturized {
    return NO;
}

- (NSSize)screenSize {
    return NSMakeSize(100, 100);
}

- (void)screenPushCurrentTitleForWindow:(BOOL)flag {
}

- (void)screenPopCurrentTitleForWindow:(BOOL)flag {
}

- (int)screenNumber {
    return 0;
}

- (int)screenTabIndex {
    return 0;
}

- (int)screenViewIndex {
    return 0;
}

- (int)screenWindowIndex {
    return 0;
}

- (void)screenStartTmuxMode {
}

- (void)screenHandleTmuxInput:(VT100Token *)token {
}

- (void)screenModifiersDidChangeTo:(NSArray *)modifiers {
}

- (void)screenShowBellIndicator {
}

- (void)screenSuggestShellIntegrationUpgrade {
}

- (NSSize)screenCellSize {
    return NSMakeSize(10, 10);
}

- (void)screenMouseModeDidChange {
}

- (void)screenFlashImage:(NSString *)identifier {
}

- (void)screenIncrementBadge {
}

- (void)screenSetHighlightCursorLine:(BOOL)highlight {
}

- (void)screenCursorDidMoveToLine:(int)line {
}

- (void)screenSaveScrollPosition {
}

- (void)screenAddMarkOnLine:(int)line {
}

- (void)screenActivateWindow {
}

- (void)screenSetProfileToProfileNamed:(NSString *)value {
}

- (void)screenDidAddNote:(PTYNoteViewController *)note {
}

- (void)screenDidEndEditingNote {
}

- (void)screenWillReceiveFileNamed:(NSString *)name ofSize:(int)size {
}

- (void)screenDidFinishReceivingFile {
}

- (void)screenDidReceiveBase64FileData:(NSString *)data {
}

- (void)screenFileReceiptEndedUnexpectedly {
}

- (void)screenRequestAttention:(BOOL)request isCritical:(BOOL)isCritical {
}

- (iTermColorMap *)screenColorMap {
    return nil;
}

- (void)screenSetCurrentTabColor:(NSColor *)color {
}

- (void)screenSetTabColorGreenComponentTo:(CGFloat)color {
}

- (void)screenSetTabColorBlueComponentTo:(CGFloat)color {
}

- (void)screenSetTabColorRedComponentTo:(CGFloat)color {
}

- (void)screenCurrentHostDidChange:(VT100RemoteHost *)host {
}

- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range {
}

- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range {
}

- (int)selectionViewportWidth {
    return 80;
}

- (BOOL)screenShouldPostTerminalGeneratedAlert {
    return NO;
}

- (BOOL)screenShouldIgnoreBell {
    return NO;
}

- (void)screenPromptDidStartAtLine:(int)line {
}

#pragma mark - iTermSelectionDelegate

- (void)selectionDidChange:(iTermSelection *)selection {
}

- (VT100GridWindowedRange)selectionRangeForParentheticalAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForWordAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForSmartSelectionAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForWrappedLineAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridWindowedRange)selectionRangeForLineAt:(VT100GridCoord)coord {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
}

- (VT100GridRange)selectionRangeOfTerminalNullsOnLine:(int)lineNumber {
    return VT100GridRangeMake(INT_MAX, 0);
}

- (VT100GridCoord)selectionPredecessorOfCoord:(VT100GridCoord)coord {
    assert(false);
}

#pragma mark - Tests

- (void)testResizeWidthRespectsContinuations {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:5];
    screen_char_t *line = [screen.currentGrid screenCharsAtLineNumber:0];
    line[5].backgroundColor = 5;
    [screen resizeWidth:6 height:4];
    line = [screen.currentGrid screenCharsAtLineNumber:0];
    assert(line[0].backgroundColor == 5);
}

- (void)testAppendingWithWraparoundOffSetsContinuation {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:5];
    [screen.terminal setWraparoundMode:NO];
    [screen.terminal setBackgroundColor:5 alternateSemantics:NO];
    [screen appendStringAtCursor:@"0123456789Z"];  // Should become 0123Z
    screen_char_t *line = [screen.currentGrid screenCharsAtLineNumber:0];
    assert(line[5].backgroundColor == 0);
}

- (void)testResizeWidthHeight {
    VT100Screen *screen;

    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, pulling lines out of line buffer
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"gh....\n"
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 5);

    // Starting in primary, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);

    // Same tests as above, but in alt screen. -----------------------------------------------------
    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEFGH.\n"
            @"IJKL.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    // Starting in alt - grows, but we don't pull anything out of the line buffer.
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"IJKL..\n"
            @"MNOPQR\n"
            @"ST....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:1],
                                     [screen width]);
    assert([s isEqualToString:@"def"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:2],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:3],
                                     [screen width]);
    assert([s isEqualToString:@"ijk"]);

    // Starting in primary with selection, it shrinks, but selection stays on screen
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "jk"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 2, 3, 2)];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jk"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top completely
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "abcd"
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 4, 0)];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcd"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top partially
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen shrinks but selection stays on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\ij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top partially
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"IJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top completely
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "abc"
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 3, 0)];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([self selectedStringInScreen:screen] == nil);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEF\n"
            @"GH....\n"
            @"IJKL..\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQ\n"
            @"RST..\n"
            @"UVWXY\n"
            @"Z....\n"
            @"....."]);
    // select everything
    // TODO There's a bug when the selection is at the very end (5,6). It is deselected.
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 6)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQR\n"
            @"ST....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid. Selection goes to very end of screen
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    // select everything
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 5, 6)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ\n"]);
    [screen resizeWidth:6 height:6];
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ\n"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // If lines get pushed into line buffer, excess are dropped
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:1];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);

    // Scroll regions are reset
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [self showAltAndUppercase:screen];
    [screen terminalSetScrollRegionTop:0 bottom:1];
    [screen terminalSetLeftMargin:0 rightMargin:1];
    [screen resizeWidth:3 height:3];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 3, 3)));

    // Selection ending at line with trailing nulls
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "efgh.."
    [self setSelectionRange:VT100GridCoordRangeMake(4, 0, 5, 1)];
    [screen resizeWidth:3 height:3];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"efgh\n"]);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Selection starting at beginning of line of all nulls
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalLineFeed];
     [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    // .....
    // abcde
    // fgh..
    // ijkl.
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 2)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"]);
    [screen resizeWidth:13 height:4];
    // TODO
    // This is kind of questionable. We strip nulls in -convertCurrentSelectionToWidth..., while it
    // would be better to preserve the selection.
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection has to move back because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijklm\n"
            @"nopqr\n" // top line of screen
            @"st...\n"
            @"uvwxy\n"
            @"z....\n"
            @"....."]);
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 2, 2)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nij"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"NOPQRS\n"
            @"T.....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"gh....\n"
            @"ijklmn\n"
            @"opqrst\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // onscreen. The screen grows, moving lines from history into the primary screen. The start of the
    // selection has to move forward because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(1, 2, 2, 3)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jklmNO"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"NO"]);

    // In alt screen with selection that begins and ends onscreen. The screen is grown and some history
    // is deleted.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 4, 2, 4)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // there too. The screen grows, moving lines from history into the primary screen. The
    // selection is lost because none of its characters still exist.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 2, 2, 2)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ij"]);
    [screen resizeWidth:6 height:6];
    assert([self selectedStringInScreen:screen] == nil);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection is exactly at the last character before those that are lost.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 1, 1)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // End is one before previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 5, 0)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);

    // End is two after previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    [self setSelectionRange:VT100GridCoordRangeMake(0, 0, 2, 1)];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefg"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    
    // Starting in primary but with content on the alt screen. It is properly restored.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"nopqr\n"
            @"st...\n"
            @"uvwxy\n"
            @"z....\n"
            @"....."]);
    [self showAltAndUppercase:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"NOPQR\n"
            @"ST...\n"
            @"UVWXY\n"
            @"Z....\n"
            @"....."]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDump] isEqualToString:
            @"NOPQRS\n"
            @"T.....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    [screen terminalShowPrimaryBufferRestoringCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"gh....\n"
            @"ijklmn\n"
            @"opqrst\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);
}

- (void)testRunByTrimmingNullsFromRun {
    // Basic test
    VT100Screen *screen = [self screenFromCompactLines:
                           @"..1234\n"
                           @"56789a\n"
                           @"bc...."];
    VT100GridRun run = VT100GridRunMake(1, 0, 16);
    VT100GridRun trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 2);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 12);

    // Test wrapping nulls around
    screen = [self screenFromCompactLines:
              @"......\n"
              @".12345\n"
              @"67....\n"
              @"......\n"];
    run = VT100GridRunMake(0, 0, 24);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 1);
    assert(trimmed.length == 7);

    // Test all nulls
    screen = [self screenWithWidth:4 height:4];
    run = VT100GridRunMake(0, 0, 4);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.length == 0);

    // Test no nulls
    screen = [self screenFromCompactLines:
              @"1234\n"
              @"5678"];
    run = VT100GridRunMake(1, 0, 6);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 6);
}

- (void)testTerminalResetPreservingPrompt {
    // Test with arg=yes
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 5);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Test with arg=no
    screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:NO];
    assert([[screen compactLineDump] isEqualToString:
            @".....\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testAllCharacterSetPropertiesHaveDefaultValues {
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    // Switch to charset 1
    char shiftOut = 14;
    char shiftIn = 15;
    NSData *data = [NSData dataWithBytes:&shiftOut length:1];
    [self sendDataToTerminal:data];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    [screen terminalResetPreservingPrompt:NO];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    data = [NSData dataWithBytes:&shiftIn length:1];
    [self sendDataToTerminal:data];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testClearBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;

    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen terminalSaveCursor];
    [screen terminalSaveCharsetFlags];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen clearBuffer];
    assert(updates_ == 1);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @".....\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 4)));
    assert(screen.savedCursor.x == 0);
    assert(screen.savedCursor.y == 0);

    // Cursor on last nonempty line
    screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:3];
    [screen clearBuffer];
    assert(updates_ == 2);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"wxyz.\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);


    // Cursor in middle of content
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"rstuv\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);
}

- (void)testClearScrollbackBuffer {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 1, 1)];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnopq\n"
            @"rstuv\n"
            @"wxyz.\n"
            @"....."]);
    [screen clearScrollbackBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"mnopq\n"
            @"rstuv\n"
            @"wxyz.\n"
            @"....."]);
    assert(highlightsCleared_);
    assert(![selection_ hasSelection]);
    assert([screen isAllDirty]);
}

// Most of the work is done by VT100Grid's appendCharsAtCursor, which is heavily tested already.
// This only tests the extra work not included therein.
- (void)testAppendStringAtCursorAscii {
    // Make sure colors and attrs are set properly
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [terminal_ setForegroundColor:5 alternateSemantics:NO];
    [terminal_ setBackgroundColor:6 alternateSemantics:NO];
    [self sendEscapeCodes:@"^[[1m^[[3m^[[4m^[[5m"];  // Bold, italic, blink, underline
    [screen appendStringAtCursor:@"Hello world"];

    assert([[screen compactLineDump] isEqualToString:
            @"Hello\n"
            @" worl\n"
            @"d....\n"
            @"....."]);
    screen_char_t *line = [screen getLineAtScreenIndex:0];
    assert(line[0].foregroundColor == 5);
    assert(line[0].foregroundColorMode == ColorModeNormal);
    assert(line[0].bold);
    assert(line[0].italic);
    assert(line[0].blink);
    assert(line[0].underline);
    assert(line[0].backgroundColor == 6);
    assert(line[0].backgroundColorMode == ColorModeNormal);
}

- (void)testAppendStringAtCursorNonAscii {
    // Make sure colors and attrs are set properly
    VT100Screen *screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [terminal_ setForegroundColor:5 alternateSemantics:NO];
    [terminal_ setBackgroundColor:6 alternateSemantics:NO];
    [self sendEscapeCodes:@"^[[1m^[[3m^[[4m^[[5m"];  // Bold, italic, blink, underline

    unichar chars[] = {
        0x301, //  standalone
        'a',
        0x301, //  a+accent
        'a',
        0x301,
        0x327, //  a+accent+cedilla
        0xD800, //  surrogate pair giving 𐅐
        0xDD50,
        0xff25, //  dwc E
        0xf000, //  item private
        0xfeff, //  zw-spaces..
        0x200b,
        0x200c,
        0x200d,
        'g',
        0x142,  // ambiguous width
    };

    NSMutableString *s = [NSMutableString stringWithCharacters:chars
                                                        length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s];

    screen_char_t *line = [screen getLineAtScreenIndex:0];
    assert(line[0].foregroundColor == 5);
    assert(line[0].foregroundColorMode == ColorModeNormal);
    assert(line[0].bold);
    assert(line[0].italic);
    assert(line[0].blink);
    assert(line[0].underline);
    assert(line[0].backgroundColor == 6);
    assert(line[0].backgroundColorMode == ColorModeNormal);

    NSString *a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    NSString *e = [@"´" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 2) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = ScreenCharToStr(line + 3);
    e = @"𐅐";
    assert([a isEqualToString:e]);

    assert([ScreenCharToStr(line + 4) isEqualToString:@"Ｅ"]);
    assert(line[5].code == DWC_RIGHT);
    assert([ScreenCharToStr(line + 6) isEqualToString:@"?"]);
    assert([ScreenCharToStr(line + 7) isEqualToString:@"g"]);
    assert([ScreenCharToStr(line + 8) isEqualToString:@"ł"]);
    assert(line[9].code == 0);

    // Toggle ambiguousIsDoubleWidth_ and see if it works.
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    ambiguousIsDoubleWidth_ = YES;
    s = [NSMutableString stringWithCharacters:chars
                                       length:sizeof(chars) / sizeof(unichar)];
    [screen appendStringAtCursor:s];

    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"´" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = [@"á" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);
    assert(line[2].code == DWC_RIGHT);

    a = [ScreenCharToStr(line + 3) decomposedStringWithCompatibilityMapping];
    e = [@"á̧" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);
    assert(line[4].code == DWC_RIGHT);
    
    a = ScreenCharToStr(line + 5);
    e = @"𐅐";
    assert([a isEqualToString:e]);

    assert([ScreenCharToStr(line + 6) isEqualToString:@"Ｅ"]);
    assert(line[7].code == DWC_RIGHT);
    assert([ScreenCharToStr(line + 8) isEqualToString:@"?"]);
    assert([ScreenCharToStr(line + 9) isEqualToString:@"g"]);
    assert([ScreenCharToStr(line + 10) isEqualToString:@"ł"]);
    assert(line[11].code == DWC_RIGHT);
    assert(line[12].code == 0);

    // Test modifying character already at cursor with combining mark
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"e"];
    unichar combiningAcuteAccent = 0x301;
    s = [NSMutableString stringWithCharacters:&combiningAcuteAccent length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = [@"é" decomposedStringWithCompatibilityMapping];
    assert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    unichar highSurrogate = 0xD800;
    unichar lowSurrogate = 0xDD50;
    s = [NSMutableString stringWithCharacters:&highSurrogate length:1];
    [screen appendStringAtCursor:s];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];
    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"𐅐";
    assert([a isEqualToString:e]);

    // Test modifying character already at cursor with low surrogate, but it's not a high surrogate.
    ambiguousIsDoubleWidth_ = NO;
    screen = [self screenWithWidth:20 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"g"];
    s = [NSMutableString stringWithCharacters:&lowSurrogate length:1];
    [screen appendStringAtCursor:s];
    line = [screen getLineAtScreenIndex:0];

    a = [ScreenCharToStr(line + 0) decomposedStringWithCompatibilityMapping];
    e = @"g";
    assert([a isEqualToString:e]);

    a = [ScreenCharToStr(line + 1) decomposedStringWithCompatibilityMapping];
    e = @"�";
    assert([a isEqualToString:e]);
}

- (void)testLinefeed {
    // The guts of linefeed is tested in VT100GridTest.
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnop.\n"
            @"....."]);
    [screen terminalSetScrollRegionTop:1 bottom:3];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:3];
    [screen terminalMoveCursorToX:4 y:4];
    [screen linefeed];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fjkl.\n"
            @"inop.\n"
            @"m....\n"
            @"....."]);
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 0);
    assert([screen cursorX] == 4);

    // Now test scrollback
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnop"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"mnop.\n"
            @"....."]);
    [screen terminalMoveCursorToX:4 y:5];
    [screen linefeed];
    [screen linefeed];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @"mnop.\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert([screen scrollbackOverflow] == 1);
    assert([screen totalScrollbackOverflow] == 1);
    assert([screen cursorX] == 4);
    [screen resetScrollbackOverflow];
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 1);
}

- (void)testSetHistory {
    NSArray *lines = @[[self screenCharLineForString:@"abcdefghijkl"],
                       [self screenCharLineForString:@"mnop"],
                       [self screenCharLineForString:@"qrstuvwxyz"],
                       [self screenCharLineForString:@"0123456  "],
                       [self screenCharLineForString:@"ABC   "],
                       [self screenCharLineForString:@"DEFGHIJKL   "],
                       [self screenCharLineForString:@"MNOP  "]];
    VT100Screen *screen = [self screenWithWidth:6 height:4];
    [screen setHistory:lines];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcdef\n"
            @"ghijkl\n"
            @"mnop..\n"
            @"qrstuv\n"
            @"wxyz..\n"
            @"012345\n"
            @"6.....\n"
            @"ABC...!\n"
            @"DEFGHI+\n"
            @"JKL...!\n"
            @"MNOP..!"]);
}

- (void)testSetAltScreen {
    NSArray *lines = @[[self screenCharLineForString:@"abcdefghijkl"],
                       [self screenCharLineForString:@"mnop"],
                       [self screenCharLineForString:@"qrstuvwxyz"],
                       [self screenCharLineForString:@"0123456  "],
                       [self screenCharLineForString:@"ABC   "],
                       [self screenCharLineForString:@"DEFGHIJKL   "],
                       [self screenCharLineForString:@"MNOP  "]];
    VT100Screen *screen = [self screenWithWidth:6 height:4];
    [screen terminalShowAltBuffer];
    [screen setAltScreen:lines];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcdef+\n"
            @"ghijkl!\n"
            @"mnop..!\n"
            @"qrstuv+"]);
}

- (void)testSetTmuxState {
    NSDictionary *stateDict =
      @{
        kStateDictSavedCX: @(2),
        kStateDictSavedCY: @(3),
        kStateDictCursorX: @(4),
        kStateDictCursorY: @(5),
        kStateDictScrollRegionUpper: @(6),
        kStateDictScrollRegionLower: @(7),
        kStateDictCursorMode: @(NO),
        kStateDictTabstops: @[@(4), @(8)]
       };
    VT100Screen *screen = [self screenWithWidth:10 height:10];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    cursorVisible_ = YES;
    [screen setTmuxState:stateDict];
    
    assert(screen.cursorX == 5);
    assert(screen.cursorY == 6);
    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];
    assert(screen.cursorX == 3);
    assert(screen.cursorY == 4);
    assert([[screen currentGrid] topMargin] == 6);
    assert([[screen currentGrid] bottomMargin] == 7);
    assert(!cursorVisible_);
    [screen terminalCarriageReturn];
    [screen terminalAppendTabAtCursor];
    assert(screen.cursorX == 5);
    [screen terminalAppendTabAtCursor];
    assert(screen.cursorX == 9);
}

- (void)testHighlightTextMatchingRegex {
    NSArray *lines = @[@"rerex", @"xrere", @"xxrerexxxx", @"xxrererere"];
    VT100Screen *screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightForegroundColor: [NSColor blueColor],
                                                       kHighlightBackgroundColor: [NSColor redColor] }];
    NSArray *expectedHighlights =
        @[ @"hhhh.",
           @".hhhh",
           @"..hhh",
           @"h....",
           @"..hhh",
           @"hhhhh",
           @"....." ];
    int blue = 16 + 5;
    int red = 16 + 5 * 36;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:blue
      highlightFgMode:ColorModeNormal
           highlightBg:red
       highlightBgMode:ColorModeNormal];
    
    // Leave fg unaffected
    screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightBackgroundColor: [NSColor redColor] }];
    int defaultFg = [terminal_ foregroundColorCode].foregroundColor;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:defaultFg
      highlightFgMode:ColorModeAlternate
           highlightBg:red
       highlightBgMode:ColorModeNormal];
    
    // Leave bg unaffected
    screen = [self screenWithWidth:5 height:7];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:lines toScreen:screen];
    [screen highlightTextMatchingRegex:@"re" colors:@{ kHighlightForegroundColor: [NSColor blueColor] }];
    int defaultBg = [terminal_ foregroundColorCode].backgroundColor;
    [self assertScreen:screen
     matchesHighlights:expectedHighlights
           highlightFg:blue
      highlightFgMode:ColorModeNormal
           highlightBg:defaultBg
       highlightBgMode:ColorModeAlternate];
}

- (void)testSetFromFrame {
    VT100Screen *source = [self fiveByFourScreenWithThreeLinesOneWrapped];
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < source.height; i++) {
        screen_char_t *line = [source getLineAtScreenIndex:i];
        [data appendBytes:line length:(sizeof(screen_char_t) * (source.width + 1))];
    }
    
    DVRFrameInfo info = {
        .width = 5,
        .height = 4,
        .cursorX = 1,  // zero based
        .cursorY = 2,
        .timestamp = 0,
        .frameType = DVRFrameTypeKeyFrame
    };
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    [screen setFromFrame:(screen_char_t *) data.mutableBytes
                     len:data.length
                    info:info];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcde+\n"
            @"fgh..!\n"
            @"ijkl.!\n"
            @".....!"]);
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 3);

    // Try a screen smaller than the frame
    screen = [self screenWithWidth:2 height:2];
    [screen setFromFrame:(screen_char_t *) data.mutableBytes
                     len:data.length
                    info:info];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"ij!\n"
            @"..!"]);
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 1);
}

// Perform a search, append some stuff, and continue searching from the end of scrollback history
// prior to the appending, finding a match in the stuff that was appended. This is what PTYSession
// does for tail-find.
- (void)testAPIsUsedByTailFind {
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz", @"012"] toScreen:screen];
    /* abcde
       fgh..
       ijkl.
       mnopq
       rstuv
       wxyz.
       012..
       .....
     */
    FindContext *ctx = [[[FindContext alloc] init] autorelease];
    ctx.maxTime = 0;
    [screen setFindString:@"wxyz"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:ctx
          multipleResults:YES];
    NSMutableArray *results = [NSMutableArray array];
    assert([screen continueFindAllResults:results
                                inContext:ctx]);
    assert(results.count == 1);
    SearchResult *range = results[0];
    assert(range->startX == 0);
    assert(range->absStartY == 5);
    assert(range->endX == 3);
    assert(range->absEndY == 5);
    
    // Make sure there's nothing else to find
    [results removeAllObjects];
    assert(![screen continueFindAllResults:results
                                 inContext:ctx]);
    assert(results.count == 0);
    
    [screen storeLastPositionInLineBufferAsFindContextSavedPosition];

    // Now add some stuff to the bottom and search again from where we previously stopped.
    [self appendLines:@[@"0123", @"wxyz"] toScreen:screen];
    [screen setFindString:@"wxyz"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:7  // Past bottom of screen
               withOffset:0
                inContext:ctx
          multipleResults:YES];
    [screen restoreSavedPositionToFindContext:ctx];
    results = [NSMutableArray array];
    assert([screen continueFindAllResults:results
                                inContext:ctx]);
    assert(results.count == 1);
    range = results[0];
    assert(range->startX == 0);
    assert(range->absStartY == 8);
    assert(range->endX == 3);
    assert(range->absEndY == 8);

    // Make sure there's nothing else to find
    [results removeAllObjects];
    assert(![screen continueFindAllResults:results
                                 inContext:ctx]);
    assert(results.count == 0);
    
    // Search backwards from the end. This is slower than searching
    // forwards, but most searches are reverse searches begun at the end,
    // so it will get a result sooner.
    FindContext *myFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"mnop"
         forwardDirection:NO
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:[screen numberOfLines] + 1 + [screen totalScrollbackOverflow]
               withOffset:0
                inContext:[screen findContext]
          multipleResults:YES];
    
    [myFindContext copyFromFindContext:[screen findContext]];
    myFindContext.results = nil;
    [screen saveFindContextAbsPos];

    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:[screen findContext]];
    assert(results.count == 1);
    SearchResult *actualResult = results[0];
    SearchResult *expectedResult = [SearchResult searchResultFromX:0 y:3 toX:3 y:3];
    assert([actualResult isEqualToSearchResult:expectedResult]);
    // TODO test the result range
    
    // Do a tail find from the saved position.
    FindContext *tailFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"rst"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:tailFindContext
          multipleResults:YES];
    
    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [screen restoreSavedPositionToFindContext:tailFindContext];
    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:tailFindContext];
    assert(results.count == 0);
    
    // Append a line and then do it again, this time finding the line.
    [screen saveFindContextAbsPos];
    [screen setMaxScrollbackLines:8];
    [self appendLines:@[ @"rst" ]  toScreen:screen];
    tailFindContext = [[[FindContext alloc] init] autorelease];
    [screen setFindString:@"rst"
         forwardDirection:YES
             ignoringCase:NO
                    regex:NO
              startingAtX:0
              startingAtY:0
               withOffset:0
                inContext:tailFindContext
          multipleResults:YES];
    
    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [screen restoreSavedPositionToFindContext:tailFindContext];
    [results removeAllObjects];
    [screen continueFindAllResults:results inContext:tailFindContext];
    assert(results.count == 1);
    actualResult = results[0];
    expectedResult = [SearchResult searchResultFromX:0 y:9 toX:2 y:9];
    assert([actualResult isEqualToSearchResult:expectedResult]);
}

#pragma mark - Tests for PTYTextViewDataSource methods

- (void)testNumberOfLines {
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    assert([screen numberOfLines] == 2);
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz", @"012"] toScreen:screen];
    /*
     abcde
     fgh..
     ijkl.
     mnopq
     rstuv
     wxyz.
     012..
     .....
     */
    assert([screen numberOfLines] == 8);
}

- (void)testCursorXY {
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    assert([screen cursorX] == 1);
    assert([screen cursorY] == 1);
    [screen terminalMoveCursorToX:2 y:3];
    assert([screen cursorX] == 2);
    assert([screen cursorY] == 3);
}

- (void)testGetLineAtIndex {
    VT100Screen *screen = [self screenFromCompactLines:
                           @"abcde>\n"
                           @"F-ghi.\n"];
    [screen terminalMoveCursorToX:6 y:2];
    screen_char_t *line = [screen getLineAtIndex:0];
    assert(line[0].code == 'a');
    assert(line[5].code == DWC_SKIP);
    assert(line[6].code == EOL_DWC);

    // Scroll the DWC_SPLIT off the screen. getLineAtIndex: will restore it, even though line buffers
    // don't store those.
    [self appendLines:@[@"jkl"] toScreen:screen];
    line = [screen getLineAtIndex:0];
    assert(line[0].code == 'a');
    assert(line[5].code == DWC_SKIP);
    assert(line[6].code == EOL_DWC);
}

- (void)testNumberOfScrollbackLines {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:2];
    assert([screen numberOfScrollbackLines] == 0);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 1);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 2);
    [screen terminalLineFeed];
    assert([screen numberOfScrollbackLines] == 2);
}

- (void)testScrollbackOverflow {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:0];
    assert([screen scrollbackOverflow] == 0);
    [screen terminalLineFeed];
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 2);
    assert([screen totalScrollbackOverflow] == 2);
    [screen resetScrollbackOverflow];
    assert([screen scrollbackOverflow] == 0);
    assert([screen totalScrollbackOverflow] == 2);
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 1);
    assert([screen totalScrollbackOverflow] == 3);
}

- (void)testAbsoluteLineNumberOfCursor {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    assert([screen cursorY] == 4);
    assert([screen absoluteLineNumberOfCursor] == 3);
    [screen setMaxScrollbackLines:1];
    [screen terminalLineFeed];
    assert([screen absoluteLineNumberOfCursor] == 4);
    [screen terminalLineFeed];
    assert([screen absoluteLineNumberOfCursor] == 5);
    [screen resetScrollbackOverflow];
    assert([screen absoluteLineNumberOfCursor] == 5);
    [screen clearScrollbackBuffer];
    assert([screen absoluteLineNumberOfCursor] == 4);
}

- (void)assertSearchInScreen:(VT100Screen *)screen
                  forPattern:(NSString *)pattern
            forwardDirection:(BOOL)forward
                ignoringCase:(BOOL)ignoreCase
                       regex:(BOOL)regex
                 startingAtX:(int)startX
                 startingAtY:(int)startY
                  withOffset:(int)offset
              matchesResults:(NSArray *)expected
  callBlockBetweenIterations:(void (^)(VT100Screen *))block {
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resizeWidth:screen.width height:2];
    [[screen findContext] setMaxTime:0];
    [screen setFindString:pattern
         forwardDirection:forward
             ignoringCase:ignoreCase
                    regex:regex
              startingAtX:startX
              startingAtY:startY
               withOffset:offset
                inContext:[screen findContext]
          multipleResults:YES];
    NSMutableArray *results = [NSMutableArray array];
    while ([screen continueFindAllResults:results inContext:[screen findContext]]) {
        if (block) {
            block(screen);
        }
    }
    assert(results.count == expected.count);
    for (int i = 0; i < expected.count; i++) {
        assert([expected[i] isEqualToSearchResult:results[i]]);
    }
}

- (void)assertSearchInScreenLines:(NSString *)compactLines
                       forPattern:(NSString *)pattern
                 forwardDirection:(BOOL)forward
                     ignoringCase:(BOOL)ignoreCase
                            regex:(BOOL)regex
                      startingAtX:(int)startX
                      startingAtY:(int)startY
                       withOffset:(int)offset
                   matchesResults:(NSArray *)expected {
    VT100Screen *screen = [self screenFromCompactLinesWithContinuationMarks:compactLines];
    [self assertSearchInScreen:screen
                    forPattern:pattern
              forwardDirection:forward
                  ignoringCase:ignoreCase
                         regex:regex
                   startingAtX:startX
                   startingAtY:startY
                    withOffset:offset
                matchesResults:expected
    callBlockBetweenIterations:NULL];
}

- (void)testFind {
    NSString *lines =
        @"abcd+\n"
        @"efgc!\n"
        @"de..!\n"
        @"fgx>>\n"
        @"Y-z.!";
    NSArray *cdeResults = @[ [SearchResult searchResultFromX:2 y:0 toX:0 y:1] ];
    // Search forward, wraps around a line, beginning from first char onscreen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];
    
    // Search backward
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:2
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];

    // Search from last char on screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:2
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];

    // Search from null after last char on screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:4
                         withOffset:0
                     matchesResults:cdeResults];
    // Search from middle of screen
    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:2
                         withOffset:0
                     matchesResults:cdeResults];

    [self assertSearchInScreenLines:lines
                         forPattern:@"cde"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:1
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[]];

    // Search ignoring case
    [self assertSearchInScreenLines:lines
                         forPattern:@"CDE"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[]];

    [self assertSearchInScreenLines:lines
                         forPattern:@"CDE"
                   forwardDirection:YES
                       ignoringCase:YES
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];

    // Search with regex
    [self assertSearchInScreenLines:lines
                         forPattern:@"c.e"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:YES
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];

    [self assertSearchInScreenLines:lines
                         forPattern:@"C.E"
                   forwardDirection:YES
                       ignoringCase:YES
                              regex:YES
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:cdeResults];
    
    // Search with offset=1
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:3 y:0 toX:0 y:1],
                                       [SearchResult searchResultFromX:0 y:2 toX:1 y:2] ]];

    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:3
                        startingAtY:0
                         withOffset:1
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:2 toX:1 y:2] ]];

    // Search with offset=-1
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:2
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:2 toX:1 y:2],
                                       [SearchResult searchResultFromX:3 y:0 toX:0 y:1] ]];
    
    [self assertSearchInScreenLines:lines
                         forPattern:@"de"
                   forwardDirection:NO
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:2
                         withOffset:1
                     matchesResults:@[ [SearchResult searchResultFromX:3 y:0 toX:0 y:1] ]];

    // Search matching DWC
    [self assertSearchInScreenLines:lines
                         forPattern:@"Yz"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:0 y:4 toX:2 y:4] ]];

    // Search matching text before DWC_SKIP and after it
    [self assertSearchInScreenLines:lines
                         forPattern:@"xYz"
                   forwardDirection:YES
                       ignoringCase:NO
                              regex:NO
                        startingAtX:0
                        startingAtY:0
                         withOffset:0
                     matchesResults:@[ [SearchResult searchResultFromX:2 y:3 toX:2 y:4] ]];

    // Search that searches multiple blocks
    VT100Screen *screen = [self screenWithWidth:5 height:2];
    LineBuffer *smallBlockLineBuffer = [[[LineBuffer alloc] initWithBlockSize:10] autorelease];
    [screen setLineBuffer:smallBlockLineBuffer];
    [self appendLines:@[ @"abcdefghij",       // Block 0
                         @"spam",             // Block 1
                         @"bacon",
                         @"eggs",             // Block 2
                         @"spam",
                         @"0123def456789",    // Block 3
                         @"hello def world"]  // Block 4
             toScreen:screen];
    /*
     abcde  0
     fghij  1
     spam   2
     bacon  3
     eggs   4
     spam   5
     0123d  6
     ef456  7
     789    8
     hello  9
      def   10
     world  11
            12
     */
    [self assertSearchInScreen:screen
                    forPattern:@"def"
              forwardDirection:NO
                  ignoringCase:NO
                         regex:NO
                   startingAtX:0
                   startingAtY:12
                    withOffset:0
                matchesResults:@[ [SearchResult searchResultFromX:1 y:10 toX:3 y:10],
                                  [SearchResult searchResultFromX:4 y:6 toX:1 y:7],
                                  [SearchResult searchResultFromX:3 y:0 toX:0 y:1]]
    callBlockBetweenIterations:NULL];
    // Search multiple blocks with a drop between calls to continueFindAllResults
    screen = [self screenWithWidth:5 height:2];
    smallBlockLineBuffer = [[[LineBuffer alloc] initWithBlockSize:10] autorelease];
    [screen setLineBuffer:smallBlockLineBuffer];
    [screen setMaxScrollbackLines:11];
    [self appendLines:@[ @"abcdefghij",       // Block 0
                         @"spam",             // Block 1
                         @"bacon",
                         @"eggs",             // Block 2
                         @"spam",
                         @"0123def456789",    // Block 3
                         @"hello def world"]  // Block 4
             toScreen:screen];
    [self assertSearchInScreen:screen
                    forPattern:@"spam"
              forwardDirection:NO
                  ignoringCase:NO
                         regex:NO
                   startingAtX:0
                   startingAtY:12
                    withOffset:0
                matchesResults:@[ [SearchResult searchResultFromX:0 y:5 toX:3 y:5] ]
    callBlockBetweenIterations:^(VT100Screen *screen) {
        [self appendLines:@[ @"FOO" ] toScreen:screen];
    }];
}

- (void)testScrollingInAltScreen {
    // When in alt screen and scrolling and !saveToScrollbackInAlternateScreen_, then the whole
    // screen must be marked dirty.
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:3];
    [self appendLines:@[ @"0", @"1", @"2", @"3", @"4"] toScreen:screen];
    [self showAltAndUppercase:screen];
    screen.saveToScrollbackInAlternateScreen = YES;
    [screen resetDirty];
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 1);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"1.\n"
            @"2.\n"
            @"3.\n"
            @"4.\n"
            @"..\n"
            @".."]);
    assert([[[screen currentGrid] compactDirtyDump] isEqualToString:
            @"cc\n"
            @"dc\n"
            @"dd"]);
    [screen resetScrollbackOverflow];
    assert([selection_ firstRange].coordRange.start.x == 1);

    screen.saveToScrollbackInAlternateScreen = NO;
    // scrollback overflow should be 0 and selection shoudn't be insane
    [self setSelectionRange:VT100GridCoordRangeMake(1, 5, 2, 5)];
    [screen terminalLineFeed];
    assert([screen scrollbackOverflow] == 0);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"1.\n"
            @"2.\n"
            @"3.\n"
            @"..\n"
            @"..\n"
            @".."]);
    assert([[[screen currentGrid] compactDirtyDump] isEqualToString:
            @"dd\n"
            @"dd\n"
            @"dd"]);
    VT100GridWindowedRange selectionRange = [selection_ firstRange];
    ITERM_TEST_KNOWN_BUG(selectionRange.coordRange.start.y == 4,
                         selectionRange.coordRange.start.y == -1);
    // See comment in -linefeed about why this happens
    // When this bug is fixed, also test truncation with and without scroll regions, as well
    // as deselection because the whole selection scrolled off the top of the scroll region.
}

- (void)testAllDirty {
    // This is not a great test.
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    assert([screen isAllDirty]);
    [screen resetAllDirty];
    assert(![screen isAllDirty]);
    [screen terminalLineFeed];
    assert(![screen isAllDirty]);
    [screen terminalNeedsRedraw];
    assert([screen isAllDirty]);
}

- (void)testSetCharDirtyAtCursor {
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resetDirty];
    // Test normal case
    [screen setCharDirtyAtCursorX:0 Y:0];
    assert([[[screen currentGrid] compactDirtyDump] isEqualToString:
            @"dd\n"
            @"cc\n"
            @"cc"]);
    
    // Test cursor in right margin
    [screen resetDirty];
    [screen setCharDirtyAtCursorX:2 Y:1];
    assert([[[screen currentGrid] compactDirtyDump] isEqualToString:
            @"cc\n"
            @"cc\n"
            @"dd"]);

    // Test cursor in last column
    [screen resetDirty];
    [screen setCharDirtyAtCursorX:1 Y:1];
    assert([[[screen currentGrid] compactDirtyDump] isEqualToString:
            @"cc\n"
            @"cd\n"
            @"cc"]);
}

- (void)testIsDirtyAt {
    VT100Screen *screen = [self screenWithWidth:2 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen resetDirty];
    assert(![screen isDirtyAtX:0 Y:0]);
    [screen appendStringAtCursor:@"x"];
    assert([screen isDirtyAtX:0 Y:0]);
    [screen clearBuffer];  // Marks everything dirty
    assert([screen isDirtyAtX:1 Y:1]);
}

- (void)testSaveToDvr {
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[ @"Line 1", @"Line 2"] toScreen:screen];
    [screen saveToDvr];
    
    [self appendLines:@[ @"Line 3"] toScreen:screen];
    [screen saveToDvr];

    DVRDecoder *decoder = [screen.dvr getDecoder];
    [decoder seek:0];
    screen_char_t *frame = (screen_char_t *)[decoder decodedFrame];
    NSString *s;
    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);

    [decoder next];
    frame = (screen_char_t *)[decoder decodedFrame];
    
    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    assert([s isEqualToString:@"Line 2"]);
}

- (void)testContentsChangedNotification {
    shouldSendContentsChangedNotification_ = NO;
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    assert(![screen shouldSendContentsChangedNotification]);
    shouldSendContentsChangedNotification_ = YES;
    assert([screen shouldSendContentsChangedNotification]);
}

#pragma mark - Test for VT100TerminalDelegate methods

- (void)testPrinting {
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    printingAllowed_ = YES;
    [screen terminalBeginRedirectingToPrintBuffer];
    [screen terminalAppendString:@"test"];
    [screen terminalLineFeed];
    [screen terminalPrintBuffer];
    assert([printed_ isEqualToString:@"test\n"]);
    printed_ = nil;
    
    printingAllowed_ = NO;
    [screen terminalBeginRedirectingToPrintBuffer];
    [screen terminalAppendString:@"test"];
    assert([triggerLine_ isEqualToString:@"test"]);
    [screen terminalLineFeed];
    assert([triggerLine_ isEqualToString:@""]);
    [screen terminalPrintBuffer];
    assert(!printed_);
    assert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         screen.width) isEqualToString:@"test"]);
    
    printed_ = nil;
    printingAllowed_ = YES;
    [screen terminalPrintScreen];
    assert([printed_ isEqualToString:@"(screen dump)"]);
}

- (void)testBackspace {
    // Normal case
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"Hello"];
    [screen terminalMoveCursorToX:5 y:1];
    [screen terminalBackspace];
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);

    // Wrap around soft eol
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"12345678901234567890Hello"];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    assert(screen.cursorX == 20);
    assert(screen.cursorY == 1);

    // No wraparound for hard eol
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 2);

    // With vsplit, no wrap.
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:10];
    [screen terminalMoveCursorToX:3 y:2];
    [screen terminalBackspace];
    assert(screen.cursorX == 3);
    assert(screen.cursorY == 2);
    
    // Over DWC_SKIP
    screen = [self screenWithWidth:20 height:3];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen appendStringAtCursor:@"1234567890123456789Ｗ"];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalBackspace];
    assert(screen.cursorX == 19);
    assert(screen.cursorY == 1);
}

- (NSArray *)tabStopsInScreen:(VT100Screen *)screen {
    NSMutableArray *actual = [NSMutableArray array];
    [screen terminalCarriageReturn];
    int lastX = screen.cursorX;
    while (1) {
        [screen terminalAppendTabAtCursor];
        if (screen.cursorX == lastX) {
            return actual;
        }
        [actual addObject:@(screen.cursorX - 1)];
    }
}

- (void)testTabStops {
    VT100Screen *screen = [self screenWithWidth:20 height:3];
    
    // Test default tab stops
    NSArray *expected = @[ @(8), @(16)];
    assert([expected isEqualToArray:[self tabStopsInScreen:screen]]);
    
    // Add a tab stop
    [screen terminalMoveCursorToX:10 y:1];
    [screen terminalSetTabStopAtCursor];
    expected = @[ @(8), @(9), @(16)];
    assert([expected isEqualToArray:[self tabStopsInScreen:screen]]);
    
    // Remove a tab stop
    [screen terminalMoveCursorToX:9 y:1];
    [screen terminalRemoveTabStopAtCursor];
    expected = @[ @(9), @(16)];
    assert([expected isEqualToArray:[self tabStopsInScreen:screen]]);
    
    // Appending a tab should respect vsplits. (currently not implemented)
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:0 rightMargin:7];
    [screen terminalAppendTabAtCursor];
    ITERM_TEST_KNOWN_BUG(screen.cursorX == 1, screen.cursorX == 9);
    
    // Tabbing over text doesn't change it
    screen = [self screenWithWidth:20 height:3];
    [screen appendStringAtCursor:@"0123456789"];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalAppendTabAtCursor];
    assert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         screen.width) isEqualToString:@"0123456789"]);

    // Tabbing over all nils replaces them with tab fillers and a tab character at the end
    screen = [self screenWithWidth:20 height:3];
    [screen terminalAppendTabAtCursor];
    screen_char_t *line = [screen getLineAtScreenIndex:0];
    for (int i = 0; i < 7; i++) {
        assert(line[i].code == TAB_FILLER);
    }
    assert(line[7].code == '\t');
    
    // If there is a single non-nil, then the cursor just moves.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:3 y:1];
    [screen appendStringAtCursor:@"x"];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalAppendTabAtCursor];
    assert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         screen.width) isEqualToString:@"x"]);
    assert(screen.cursorX == 9);
    
    // Wrapping around to the next line converts eol_hard to eol_soft.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalAppendTabAtCursor];  // 9
    [screen terminalAppendTabAtCursor];  // 15
    [screen terminalAppendTabAtCursor];  // (newline) 1
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 2);
    line = [screen getLineAtScreenIndex:0];
    assert(line[screen.width].code == EOL_SOFT);
    
    // Test backtab (it's simple, no wraparound)
    screen = [self screenWithWidth:20 height:3];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalAppendTabAtCursor];
    [screen terminalAppendTabAtCursor];
    assert(screen.cursorX == 17);
    [screen terminalBackTab:1];
    assert(screen.cursorX == 9);
    [screen terminalBackTab:1];
    assert(screen.cursorX == 1);
    [screen terminalBackTab:1];
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 2);
    
    // backtab should (but doesn't yet) respect vsplits.
    screen = [self screenWithWidth:20 height:3];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:10 rightMargin:19];
    [screen terminalMoveCursorToX:11 y:1];
    [screen terminalBackTab:1];
    ITERM_TEST_KNOWN_BUG(screen.cursorX == 11, screen.cursorX == 9);
}

- (void)testMoveCursor {
    // When not in origin mode, scroll regions are ignored
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:5 rightMargin:15];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    [screen terminalMoveCursorToX:1 y:1];
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    [screen terminalMoveCursorToX:100 y:100];
    assert(screen.cursorX == 21);
    assert(screen.cursorY == 20);
    
    // In origin mode, coord is relative to origin and cursor is forced inside scroll region
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalMoveCursorToX:1 y:1];
    assert(screen.cursorX == 6);
    assert(screen.cursorY == 6);
    
    [screen terminalMoveCursorToX:100 y:100];
    assert(screen.cursorX == 16);
    assert(screen.cursorY == 16);
}

- (void)testSaveAndRestoreCursorAndCharset {
    // Save then restore
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalMoveCursorToX:4 y:5];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [screen terminalSaveCursor];
    [screen terminalSaveCharsetFlags];
    [screen terminalMoveCursorToX:1 y:1];
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    [screen terminalSetCharset:3 toLineDrawingMode:NO];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];

    assert(screen.cursorX == 4);
    assert(screen.cursorY == 5);
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:3 toLineDrawingMode:NO];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    
    // Restore without saving. Should use default charsets and move cursor to origin.
    // Terminal doesn't do anything in this case, but xterm does what we do.
    screen = [self screenWithWidth:20 height:20];
    for (int i = 0; i < 4; i++) {
        [screen terminalSetCharset:i toLineDrawingMode:NO];
    }
    [screen terminalMoveCursorToX:5 y:5];
    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];

    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

}

- (void)testSetTopBottomScrollRegion {
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    [screen terminalMoveCursorToX:5 y:16];
    [screen terminalAppendString:@"Hello"];
    assert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:15],
                                         screen.width) isEqualToString:@"Hello"]);
    [screen terminalLineFeed];
    assert([ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:14],
                                         screen.width) isEqualToString:@"Hello"]);
    
    // When origin mode is on, cursor should move to top left of scroll region.
    screen = [self screenWithWidth:20 height:20];
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalSetScrollRegionTop:5 bottom:15];
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 6);
    [screen terminalMoveCursorToX:2 y:2];
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 7);

    // Now try with a vsplit, too.
    screen = [self screenWithWidth:20 height:20];
    [self sendEscapeCodes:@"^[[?6h"];  // enter origin mode
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:5 rightMargin:15];
    [screen terminalSetScrollRegionTop:5 bottom:15];
    assert(screen.cursorX == 6);
    assert(screen.cursorY == 6);
    [screen terminalMoveCursorToX:2 y:2];
    assert(screen.cursorX == 7);
    assert(screen.cursorY == 7);
}

- (VT100Screen *)screenForEraseInDisplay {
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789\n"
            @".........."]);
    [screen terminalMoveCursorToX:5 y:2];  // over the 'o'
    return screen;
}

- (void)testEraseInDisplay {
    // NOTE: The char the cursor is on always gets erased
    
    // Before and after should clear screen and move all nonempty lines into history
    VT100Screen *screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:YES];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789\n"
            @"..........\n"
            @"..........\n"
            @"..........\n"
            @".........."]);
    
    // Before only should erase from origin to cursor, inclusive.
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"..........\n"
            @".....pqrst\n"
            @"0123456789\n"
            @".........."]);
    
    // Same but with curosr in the right margin
    screen = [self screenForEraseInDisplay];
    [screen terminalMoveCursorToX:11 y:2];
    [screen terminalEraseInDisplayBeforeCursor:YES afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"..........\n"
            @"..........\n"
            @"0123456789\n"
            @".........."]);
    
    // After only erases from cursor position inclusive to end of display
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:NO afterCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmn......\n"
            @"..........\n"
            @".........."]);

    // Neither before nor after does nothing
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseInDisplayBeforeCursor:NO afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789\n"
            @".........."]);
}

- (void)testEraseLine {
    // NOTE: The char the cursor is on always gets erased
    
    // Before and after should clear the whole line
    VT100Screen *screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"..........\n"
            @"0123456789\n"
            @".........."]);
    
    // Before only should erase from start of line to cursor, inclusive.
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @".....pqrst\n"
            @"0123456789\n"
            @".........."]);
    
    // Same but with curosr in the right margin
    screen = [self screenForEraseInDisplay];
    [screen terminalMoveCursorToX:11 y:2];
    [screen terminalEraseLineBeforeCursor:YES afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"..........\n"
            @"0123456789\n"
            @".........."]);
    
    // After only erases from cursor position inclusive to end of line
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:NO afterCursor:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmn......\n"
            @"0123456789\n"
            @".........."]);
    
    // Neither before nor after does nothing
    screen = [self screenForEraseInDisplay];
    [screen terminalEraseLineBeforeCursor:NO afterCursor:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789\n"
            @".........."]);
}

- (void)testIndex {
    // We don't implement index separately from linefeed. As far as I can tell they are the same.
    // Both respect vsplits.
    
    // Test simple indexing
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalMoveCursorToX:1 y:3];
    [screen terminalLineFeed];
    [screen terminalLineFeed];
    assert([[screen compactLineDump] isEqualToString:
            @"klmnopqrst\n"
            @"0123456789\n"
            @"..........\n"
            @".........."]);


    // With vsplit and hsplit
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:5];
    [screen terminalMoveCursorToX:2 y:2];
    assert(screen.cursorY == 2);
    // top-left is c, bottom-right is p
    [screen terminalLineFeed];
    assert(screen.cursorY == 3);
    [screen terminalLineFeed];
    assert(screen.cursorY == 3);
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"kl2345qrst\n"
            @"01....6789\n"
            @".........."]);

    // Test simple reverse indexing
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalMoveCursorToX:1 y:2];
    [screen terminalReverseIndex];
    assert(screen.cursorY == 1);
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789\n"
            @".........."]);
    
    [screen terminalReverseIndex];
    assert([[screen compactLineDump] isEqualToString:
            @"..........\n"
            @"abcdefghij\n"
            @"klmnopqrst\n"
            @"0123456789"]);
    
    
    // Reverse index with vsplit and hsplit
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghij",
                         @"klmnopqrst",
                         @"0123456789" ] toScreen:screen];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:5];
    [screen terminalMoveCursorToX:2 y:3];
    // top-left is c, bottom-right is p
    assert(screen.cursorY == 3);
    [screen terminalReverseIndex];
    assert(screen.cursorY == 2);
    [screen terminalReverseIndex];
    assert(screen.cursorY == 2);
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefghij\n"
            @"kl....qrst\n"
            @"01mnop6789\n"
            @".........."]);
}

- (void)testResetPreservingPrompt {
    // Preserve prompt
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen terminalResetPreservingPrompt:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"klm.......\n"
            @"..........\n"
            @"..........\n"
            @".........."]);
    
    // Don't preserve prompt
    screen = [self screenWithWidth:10 height:4];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen terminalResetPreservingPrompt:NO];
    assert([[screen compactLineDump] isEqualToString:
            @"..........\n"
            @"..........\n"
            @"..........\n"
            @".........."]);
    
    // Tab stops get reset
    screen = [self screenWithWidth:20 height:4];
    NSArray *defaultTabstops = @[ @(8), @(16) ];
    NSArray *augmentedTabstops = @[ @(3), @(8), @(16) ];
    assert([[self tabStopsInScreen:screen] isEqualToArray:defaultTabstops]);

    [screen terminalMoveCursorToX:4 y:1];
    [screen terminalSetTabStopAtCursor];

    assert([[self tabStopsInScreen:screen] isEqualToArray:augmentedTabstops]);
    [screen terminalResetPreservingPrompt:YES];
    assert([[self tabStopsInScreen:screen] isEqualToArray:defaultTabstops]);

    // Saved cursor gets reset to origin
    screen = [self screenWithWidth:10 height:4];
    [screen terminalMoveCursorToX:2 y:2];
    [screen terminalSaveCursor];
    [screen terminalSaveCharsetFlags];

    [screen terminalResetPreservingPrompt:YES];
    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];

    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);

    // Charset flags get reset
    screen = [self screenWithWidth:10 height:4];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:2 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [screen terminalResetPreservingPrompt:YES];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    
    // Saved charset flags get reset
    screen = [self screenWithWidth:10 height:4];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSetCharset:2 toLineDrawingMode:YES];
    [screen terminalSetCharset:3 toLineDrawingMode:YES];
    [screen terminalSaveCursor];
    [screen terminalSaveCharsetFlags];

    [screen terminalResetPreservingPrompt:YES];
    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];

    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Cursor is made visible
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetCursorVisible:NO];
    assert(!cursorVisible_);
    [screen terminalResetPreservingPrompt:YES];
    assert(cursorVisible_);
}

- (void)testTerminalSoftReset {
    // I really don't think this is the same as what xterm does.
    // TODO Go through xterm's code and figure out what's supposed to happen.
    // Save cursor and charset flags
    // Reset scroll region
    // restore cursor and charset flags
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:5];
    [screen terminalMoveCursorToX:2 y:3];
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    [screen terminalSoftReset];
    
    assert([screen currentGrid].topMargin == 0);
    assert([screen currentGrid].bottomMargin == 3);
    assert([screen currentGrid].leftMargin == 0);
    assert([screen currentGrid].rightMargin == 9);
    assert(screen.cursorX == 2);
    assert(screen.cursorY == 3);
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    
    [screen terminalRestoreCursor];
    [screen terminalRestoreCharsetFlags];

    assert(screen.cursorX == 2);
    assert(screen.cursorY == 3);
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:NO];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testSetWidth {
    canResize_ = YES;
    isFullscreen_ = NO;
    VT100Screen *screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    assert(newSize_.width == 6);
    assert(newSize_.height == 4);
    
    newSize_ = VT100GridSizeMake(0, 0);
    canResize_ = NO;
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    assert(newSize_.width == 0);
    assert(newSize_.height == 0);
    
    newSize_ = VT100GridSizeMake(0, 0);
    canResize_ = YES;
    isFullscreen_ = YES;
    screen = [self screenWithWidth:10 height:4];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetWidth:6];
    assert(newSize_.width == 0);
    assert(newSize_.height == 0);
}

- (void)testEraseCharactersAfterCursor {
  // Delete 0 chars, should do nothing
  VT100Screen *screen = [self screenWithWidth:10 height:3];
  [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
  [screen terminalMoveCursorToX:5 y:1];  // 'e'
  [screen terminalEraseCharactersAfterCursor:0];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcdefghij+\n"
          @"klm.......!\n"
          @"..........!"]);

  // Delete 2 chars
  [screen terminalEraseCharactersAfterCursor:2];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcd..ghij+\n"
          @"klm.......!\n"
          @"..........!"]);

  // Delete just to end of line, change eol hard to eol soft.
  [screen terminalEraseCharactersAfterCursor:6];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcd......!\n"
          @"klm.......!\n"
          @"..........!"]);

  // Delete way more than fits on line
  screen = [self screenWithWidth:10 height:3];
  [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
  [screen terminalMoveCursorToX:5 y:1];  // 'e'
  [screen terminalEraseCharactersAfterCursor:100];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcd......!\n"
          @"klm.......!\n"
          @"..........!"]);

  // Break dwc before cursor
  screen = [self screenFromCompactLinesWithContinuationMarks:
            @"abcD-fghij+\n"
            @"klm.......!"];
  [screen terminalMoveCursorToX:5 y:1];  // '-'
  [screen terminalEraseCharactersAfterCursor:2];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abc...ghij+\n"
          @"klm.......!"]);

  // Break dwc after cursor
  screen = [self screenFromCompactLinesWithContinuationMarks:
            @"abcdeF-hij+\n"
            @"klm.......!"];
  [screen terminalMoveCursorToX:5 y:1];  // 'e'
  [screen terminalEraseCharactersAfterCursor:2];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcd...hij+\n"
          @"klm.......!"]);

  // Break split dwc
  screen = [self screenFromCompactLinesWithContinuationMarks:
            @"abcdefghi>>\n"
            @"J-klm.....!"];
  [screen terminalMoveCursorToX:5 y:1];  // 'e'
  [screen terminalEraseCharactersAfterCursor:6];
  assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
          @"abcd......!\n"
          @"J-klm.....!"]);
}

- (void)testSetTitle {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:20];

    // Should come back as joblessName test
    syncTitle_ = YES;
    [screen terminalSetWindowTitle:@"test"];
    assert([windowTitle_ isEqualToString:@"joblessName: test"]);

    // Should come back as just test2
    syncTitle_ = NO;
    [screen terminalSetWindowTitle:@"test2"];
    assert([windowTitle_ isEqualToString:@"test2"]);

    // Absolute cursor line number should be updated with nil directory.
    [dirlog_ removeAllObjects];
    [screen destructivelySetScreenWidth:10 height:10];
    [screen terminalMoveCursorToX:1 y:5];
    [screen terminalSetWindowTitle:@"test"];
    assert(dirlog_.count == 1);
    NSArray *entry = dirlog_[0];
    assert([entry[0] intValue] == 4);
    assert([entry[1] isKindOfClass:[NSNull class]]);

    // Add some scrollback
    for (int i = 0; i < 10; i++) {
        [screen terminalLineFeed];
    }
    [dirlog_ removeAllObjects];
    [screen terminalSetWindowTitle:@"test"];
    assert(dirlog_.count == 1);
    entry = dirlog_[0];
    assert([entry[0] intValue] == 14);
    assert([entry[1] isKindOfClass:[NSNull class]]);

    // Make sure scrollback overflow is included.
    for (int i = 0; i < 100; i++) {
        [screen terminalLineFeed];
    }
    [dirlog_ removeAllObjects];
    [screen terminalSetWindowTitle:@"test"];
    assert(dirlog_.count == 1);
    entry = dirlog_[0];
    assert([entry[0] intValue] == 29);  // 20 lines of scrollback + 10th line of display
    assert([entry[1] isKindOfClass:[NSNull class]]);

    // Test icon title, which is the same, but does not log the pwd.
    syncTitle_ = YES;
    [screen terminalSetIconTitle:@"test3"];
    assert([name_ isEqualToString:@"joblessName: test3"]);

    syncTitle_ = NO;
    [screen terminalSetIconTitle:@"test4"];
    assert([name_ isEqualToString:@"test4"]);
}

- (void)testInsertEmptyCharsAtCursor {
    // Insert 0 should do nothing
    VT100Screen *screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:0];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcdefghij+\n"
            @"klm.......!\n"
            @"..........!"]);

    // Base case: insert 1
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd.efghi+\n"
            @"klm.......!\n"
            @"..........!"]);

    // Insert 2
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:2];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd..efgh+\n"
            @"klm.......!\n"
            @"..........!"]);

    // Insert to end of line, breaking EOL_SOFT
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:6];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd......!\n"
            @"klm.......!\n"
            @"..........!"]);

    // Insert more than fits
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:100];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd......!\n"
            @"klm.......!\n"
            @"..........!"]);

    // Insert 1, breaking DWC_SKIP
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdefghi>>\n"
              @"J-k.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd.efghi+\n"
            @"J-k.......!\n"
            @"..........!"]);

    // Insert breaking DWC that would end at end of line
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdefghI-+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd.efgh.!\n"
            @"jkl.......!\n"
            @"..........!"]);

    // Insert breaking DWC at cursor, which is on left half of dwc
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcdE-fghi+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:6 y:1];  // 'E'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd...fgh+\n"
            @"jkl.......!\n"
            @"..........!"]);

    // Insert breaking DWC at cursor, which is on right half of dwc
    screen = [self screenFromCompactLinesWithContinuationMarks:
              @"abcD-efghi+\n"
              @"jkl.......!\n"
              @"..........!"];
    [screen terminalMoveCursorToX:5 y:1];  // '-'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abc...efgh+\n"
            @"jkl.......!\n"
            @"..........!"]);

    // With vsplit
    screen = [self screenWithWidth:10 height:3];
    [self appendLines:@[ @"abcdefghijklm" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:8];
    [screen terminalMoveCursorToX:5 y:1];  // 'e'
    [screen terminalInsertEmptyCharsAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd.efghj+\n"
            @"klm.......!\n"
            @"..........!"]);

    // There are a few more tests of insertChar in VT100GridTest, no sense duplicating them all here.
}

- (void)testInsertBlankLinesAfterCursor {
    // 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalInsertBlankLinesAfterCursor:0];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);

    // insert 1 blank line, breaking eol_soft
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalInsertBlankLinesAfterCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"....!\n"
            @"efg.!\n"
            @"hij.!"]);

    // Insert outside scroll region does nothing
    screen = [self screenWithWidth:4 height:4];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalInsertBlankLinesAfterCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);

    // Same but with vsplit
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:3];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalInsertBlankLinesAfterCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
}

- (void)testDeleteLinesAtCursor {
    // Deleting 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:0];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);

    // Deleting 1
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:5 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"hij.!\n"
            @"....!\n"
            @"....!"]);
    
    // Outside region does nothing
    screen = [self screenWithWidth:4 height:4];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalDeleteLinesAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);

    // Same but with vsplit
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:2 rightMargin:3];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalMoveCursorToX:1 y:1];  // outside region
    [screen terminalDeleteLinesAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    
    // Delete one inside scroll region
    screen = [self screenWithWidth:4 height:5];
    [self appendLines:@[ @"abcdefg", @"hij", @"klm" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"klm.!\n"
            @"....!"]);
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalMoveCursorToX:2 y:2];  // 'f'
    [screen terminalDeleteLinesAtCursor:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd!\n"
            @"hij.!\n"
            @"....!\n"
            @"klm.!\n"
            @"....!"]);
}

- (void)testTerminalSetPixelSize {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalSetPixelWidth:-1 height:-1];
    assert(newPixelSize_.width == 100);
    assert(newPixelSize_.height == 200);
    
    [screen terminalSetPixelWidth:0 height:0];
    assert(newPixelSize_.width == 1000);
    assert(newPixelSize_.height == 2000);

    [screen terminalSetPixelWidth:50 height:60];
    assert(newPixelSize_.width == 50);
    assert(newPixelSize_.height == 60);
}

- (void)testScrollUp {
    // Scroll by 0 does nothing
    VT100Screen *screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalScrollUp:0];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    
    // Scroll by 1
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalScrollUp:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!\n"
            @"....!"]);

    // Scroll by 2
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalScrollUp:2];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd\n"
            @"efg.\n"
            @"hij.!\n"
            @"....!\n"
            @"....!\n"
            @"....!"]);

    // Scroll with region
    screen = [self screenWithWidth:4 height:4];
    [self appendLines:@[ @"abcdefg", @"hij" ] toScreen:screen];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"efg.!\n"
            @"hij.!\n"
            @"....!"]);
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalScrollUp:1];
    assert([[screen compactLineDumpWithHistoryAndContinuationMarks] isEqualToString:
            @"abcd+\n"
            @"eij.!\n"
            @"h...!\n"
            @"....!"]);
}

#pragma mark - Regression tests

- (void)testPasting {
    VT100Screen *screen = [self screen];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self sendEscapeCodes:@"^[]50;CopyToClipboard=general^GHello world^[]50;EndCopy^G"];
    assert([pasteboard_ isEqualToString:@"general"]);
    assert(!memcmp(pbData_.mutableBytes, "Hello world", strlen("Hello world")));
    assert(pasted_);
}

- (void)testCursorReporting {
    VT100Screen *screen = [self screenWithWidth:20 height:20];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalMoveCursorToX:2 y:3];
    [self sendEscapeCodes:@"^[[6n"];

    NSString *s = [[[NSString alloc] initWithData:write_ encoding:NSUTF8StringEncoding] autorelease];
    assert([s isEqualToString:@"\033[3;2R"]);
}

- (void)testReportWindowSize {
    VT100Screen *screen = [self screenWithWidth:30 height:20];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self sendEscapeCodes:@"^[[18t"];

    NSString *s = [[[NSString alloc] initWithData:write_ encoding:NSUTF8StringEncoding] autorelease];
    assert([s isEqualToString:@"\033[8;20;30t"]);
}

- (void)testResizeNotes {
  // Put a note on the primary grid, switch to alt, resize width, swap back to primary. Note should
  // still be there.
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  assert([[screen compactLineDump] isEqualToString:
          @"abcde\n"
          @"fgh..\n"
          @"ijkl.\n"
          @"....."]);
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 2, 1)];  // fg
  [screen terminalShowAltBuffer];
  [screen resizeWidth:4 height:4];
  [screen terminalShowPrimaryBufferRestoringCursor:YES];
  assert([[screen compactLineDump] isEqualToString:
          @"abcd\n"
          @"efgh\n"
          @"ijkl\n"
          @"...."]);
  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 1);
  assert(range.start.y == 1);
  assert(range.end.x == 3);
  assert(range.end.y == 1);
}

- (void)testResizeWithNoteOnLineOfNulls {
    VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [screen addNote:note inRange:VT100GridCoordRangeMake(0, 3, 2, 3)];  // First two chars on last line
    [screen resizeWidth:4 height:4];
    NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
    assert(notes.count == 0);
}

- (void)testResizeWithSelectionOfJustNullsInAltScreen {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = self;
    [screen terminalShowAltBuffer];
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    assert([selection_ hasSelection]);
    [screen resizeWidth:4 height:4];
    assert(![selection_ hasSelection]);
}

- (void)testResizeWithSelectionOfJustNullsInMainScreen {
    VT100Screen *screen = [self screenWithWidth:5 height:4];
    screen.delegate = self;
    [self setSelectionRange:VT100GridCoordRangeMake(1, 1, 2, 2)];
    assert([selection_ hasSelection]);
    [screen resizeWidth:4 height:4];
    assert(![selection_ hasSelection]);
}

- (void)testResizeNoteInPrimaryWhileInAltAndSomeHistory {
  // Put a note on the primary grid, switch to alt, resize width, swap back to primary. Note should
  // still be there.
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcde\n"   // history
          @"fgh..\n"   // history
          @"ijkl.\n"
          @"hello\n"
          @" worl\n"
          @"d...."]);
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 2, 2)];  // ij
  [screen terminalShowAltBuffer];
  [screen resizeWidth:4 height:4];
  [screen terminalShowPrimaryBufferRestoringCursor:YES];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcd\n"  // history
          @"efgh\n"  // history
          @"ijkl\n"
          @"hell\n"
          @"o wo\n"
          @"rld."]);
  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 5, 3)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 0);
  assert(range.start.y == 2);
  assert(range.end.x == 2);
  assert(range.end.y == 2);
}

- (void)testResizeNoteInPrimaryWhileInAltAndPushingSomePrimaryIncludingWholeNoteIntoHistory {
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcde\n"   // history
          @"fgh..\n"   // history
          @"ijkl.\n"
          @"hello\n"
          @" worl\n"
          @"d...."]);
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 2, 2)];  // ij
  [screen terminalShowAltBuffer];
  [screen resizeWidth:3 height:4];
  [screen terminalShowPrimaryBufferRestoringCursor:YES];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abc\n"
          @"def\n"
          @"gh.\n"
          @"ijk\n"
          @"l..\n"
          @"hel\n"
          @"lo \n"
          @"wor\n"
          @"ld."]);
  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 0);
  assert(range.start.y == 3);
  assert(range.end.x == 2);
  assert(range.end.y == 3);
}

- (void)testResizeNoteInPrimaryWhileInAltAndPushingSomePrimaryIncludingPartOfNoteIntoHistory {
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcde\n"   // history
          @"fgh..\n"   // history
          @"ijkl.\n"
          @"hello\n"
          @" worl\n"
          @"d...."]);
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 2, 5, 3)];  // ijkl\nhello
  [screen terminalShowAltBuffer];
  [screen resizeWidth:3 height:4];
  [screen terminalShowPrimaryBufferRestoringCursor:YES];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abc\n"
          @"def\n"
          @"gh.\n"
          @"ijk\n"
          @"l..\n"
          @"hel\n"
          @"lo \n"
          @"wor\n"
          @"ld."]);
  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 0);
  assert(range.start.y == 3);
  assert(range.end.x == 2);
  assert(range.end.y == 6);
}

- (void)testNoteTruncatedOnSwitchingToAlt {
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcde\n"   // history
          @"fgh..\n"   // history
          @"ijkl.\n"
          @"hello\n"
          @" worl\n"
          @"d...."]);
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 5, 3)];  // fgh\nijkl\nhello
  [screen terminalShowAltBuffer];
  [screen terminalShowPrimaryBufferRestoringCursor:YES];

  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 8, 3)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 0);
  assert(range.start.y == 1);
  assert(range.end.x == 0);
  assert(range.end.y == 2);
}

- (void)testResizeNoteInAlternateThatGetsTruncatedByShrinkage {
  VT100Screen *screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
  [self appendLinesNoNewline:@[ @"hello world" ] toScreen:screen];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abcde\n"   // history
          @"fgh..\n"   // history
          @"ijkl.\n"
          @"hello\n"
          @" worl\n"
          @"d...."]);
  [self showAltAndUppercase:screen];
  PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
  [screen addNote:note inRange:VT100GridCoordRangeMake(0, 1, 5, 3)];  // fgh\nIJKL\nHELLO
  [screen resizeWidth:3 height:4];
  assert([[screen compactLineDumpWithHistory] isEqualToString:
          @"abc\n"
          @"def\n"
          @"gh.\n"
          @"ijk\n"
          @"l..\n"  // last line of history (all pulled from primary)
          @"HEL\n"
          @"LO \n"
          @"WOR\n"
          @"LD."]);
  NSArray *notes = [screen notesInRange:VT100GridCoordRangeMake(0, 0, 3, 6)];
  assert(notes.count == 1);
  assert(notes[0] == note);
  VT100GridCoordRange range = [screen coordRangeOfNote:note];
  assert(range.start.x == 2);  // fgh\nijkl\nHELLO
  assert(range.start.y == 1);
  assert(range.end.x == 2);
  assert(range.end.y == 6);
}

- (void)testEmptyLineRestoresBackgroundColor {
    LineBuffer *lineBuffer = [[[LineBuffer alloc] init] autorelease];
    screen_char_t line[1];
    screen_char_t continuation;
    continuation.backgroundColor = 5;
    [lineBuffer appendLine:line length:0 partial:NO width:80 timestamp:0 continuation:continuation];
    
    screen_char_t buffer[3];
    [lineBuffer copyLineToBuffer:buffer width:3 lineNum:0 continuation:&continuation];
    
    assert(buffer[0].backgroundColor == 5);
    assert(buffer[1].backgroundColor == 5);
    assert(buffer[2].backgroundColor == 5);
}

#pragma mark - CSI Tests

- (void)testCSI_CUD {
    // Cursor Down Ps Times (default = 1) (CUD)
    // This control function moves the cursor down a specified number of lines in the same column. The
    // cursor stops at the bottom margin. If the cursor is already below the bottom margin, then the
    // cursor stops at the bottom line.

    // Test basic usage, default parameter.
    VT100Screen *screen = [self screenWithWidth:3 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[B"];
    assert(screen.currentGrid.cursorX == 1);
    assert(screen.currentGrid.cursorY == 2);

    // Basic usage, explicit parameter.
    screen = [self screenWithWidth:3 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[2B"];
    assert(screen.currentGrid.cursorX == 1);
    assert(screen.currentGrid.cursorY == 3);

    // Start inside scroll region - should stop at bottom margin
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:2 bottom:4];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:2];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    assert(screen.currentGrid.cursorX == 1);
    assert(screen.currentGrid.cursorY == 4);

    // Start above scroll region - should stop at bottom margin
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:2 bottom:3];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:0];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    assert(screen.currentGrid.cursorX == 1);
    assert(screen.currentGrid.cursorY == 3);

    // Start below bottom margin - should stop at bottom of screen.
    screen = [self screenWithWidth:3 height:5];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:3];
    [self sendStringToTerminalWithFormat:@"\033[99B"];
    assert(screen.currentGrid.cursorX == 1);
    assert(screen.currentGrid.cursorY == 4);
}

- (void)testCSI_CUF {
    // Cursor Forward Ps Times (default = 1) (CUF)
    // This control function moves the cursor to the right by a specified number of columns. The
    // cursor stops at the right border of the page.

    // Test basic usage, default parameter.
    VT100Screen *screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[C"];
    assert(screen.currentGrid.cursorX == 2);
    assert(screen.currentGrid.cursorY == 1);

    // Test basic usage, explicit parameter.
    screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[2C"];
    assert(screen.currentGrid.cursorX == 3);
    assert(screen.currentGrid.cursorY == 1);

    // Test stops on right border.
    screen = [self screenWithWidth:5 height:5];
    [screen.currentGrid setCursorX:1];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    assert(screen.currentGrid.cursorX == 4);
    assert(screen.currentGrid.cursorY == 1);

    // Test respects region when starting inside it
    screen = [self screenWithWidth:5 height:5];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:3];
    [screen.currentGrid setCursorX:2];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    assert(screen.currentGrid.cursorX == 3);
    assert(screen.currentGrid.cursorY == 1);

    // Test does not respect region when starting outside it
    screen = [self screenWithWidth:5 height:5];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen.currentGrid setCursorX:3];
    [screen.currentGrid setCursorY:1];
    [self sendStringToTerminalWithFormat:@"\033[99C"];
    assert(screen.currentGrid.cursorX == 4);
    assert(screen.currentGrid.cursorY == 1);
}

/*

{ 0, 0, 'C', VT100CSI_CUF, 1, -1 },
{ 0, 0, 'D', VT100CSI_CUB, 1, -1 },
{ 0, 0, 'E', VT100CSI_CNL, 1, -1 },
{ 0, 0, 'F', VT100CSI_CPL, 1, -1 },
{ 0, 0, 'G', ANSICSI_CHA, 1, -1 },
{ 0, 0, 'H', VT100CSI_CUP, 1, 1 },
// I not supported (Cursor Forward Tabulation P s tab stops (default = 1) (CHT))
{ 0, 0, 'J', VT100CSI_ED, 0, -1 },
// ?J not supported (Erase in Display (DECSED))
{ 0, 0, 'K', VT100CSI_EL, 0, -1 },
// ?K not supported ((Erase in Line (DECSEL))
{ 0, 0, 'L', XTERMCC_INSLN, 1, -1 },
{ 0, 0, 'M', XTERMCC_DELLN, 1, -1 },
{ 0, 0, 'P', XTERMCC_DELCH, 1, -1 },
{ 0, 0, 'S', XTERMCC_SU, 1, -1 },
// ?Pi;Pa;PvS not supported (Sixel/ReGIS)
{ 0, 0, 'T', XTERMCC_SD, 1, -1 },
// Ps;Ps;Ps;Ps;PsT not supported (Initiate highlight mouse tracking)
{ 0, 0, 'X', ANSICSI_ECH, 1, -1 },
{ 0, 0, 'Z', ANSICSI_CBT, 1, -1 },
// ` not supported (Character Position Absolute [column] (default = [row,1]) (HPA))
// a not supported (Character Position Relative [columns] (default = [row,col+1]) (HPR))
// b not supported (Repeat the preceding graphic character P s times (REP))
{ 0, 0, 'c', VT100CSI_DA, 0, -1 },
{ '>', 0, 'c', VT100CSI_DA2, 0, -1 },
{ 0, 0, 'd', ANSICSI_VPA, 1, -1 },
{ 0, 0, 'e', ANSICSI_VPR, 1, -1 },
{ 0, 0, 'f', VT100CSI_HVP, 1, 1 },
{ 0, 0, 'g', VT100CSI_TBC, 0, -1 },
{ 0, 0, 'h', VT100CSI_SM, -1, -1 },
{ '?', 0, 'h', VT100CSI_DECSET, -1, -1 },
{ 0, 0, 'i', ANSICSI_PRINT, 0, -1 },
// ?i not supported (Media Copy (MC, DEC-specific))
{ 0, 0, 'l', VT100CSI_RM, -1, -1 },
{ '?', 0, 'l', VT100CSI_DECRST, -1, -1 },
{ 0, 0, 'm', VT100CSI_SGR, 0, -1 },
{ '>', 0, 'm', VT100CSI_SET_MODIFIERS, -1, -1 },
{ 0, 0, 'n', VT100CSI_DSR, 0, -1 },
{ '>', 0, 'n', VT100CSI_RESET_MODIFIERS, -1, -1 },
{ '?', 0, 'n', VT100CSI_DECDSR, 0, -1 },
// >p not supported (Set resource value pointerMode. This is used by xterm to decide whether
// to hide the pointer cursor as the user types.)
{ '!', 0, 'p', VT100CSI_DECSTR, -1, -1 },
// $p not supported (Request ANSI mode (DECRQM))
// ?$p not supported (Request DEC private mode (DECRQM))
// "p not supported (Set conformance level (DECSCL))
// q not supported (Load LEDs (DECLL))
{ 0, ' ', 'q', VT100CSI_DECSCUSR, 0, -1 },
// "q not supported (Select character protection attribute (DECSCA))
{ 0, 0, 'r', VT100CSI_DECSTBM, -1, -1 },
// $r not supported (Change Attributes in Rectangular Area (DECCARA))
{ 0, 0, 's', VT100CSI_DECSLRM_OR_ANSICSI_SCP, -1, -1 },
// ?s not supported (Save DEC Private Mode Values)
// t tested in -testWindowManipulationCodes
// $t not supported (Reverse Attributes in Rectangular Area (DECRARA))
// >t not supported (Set one or more features of the title modes)
// SP t not supported (Set warning-bell volume (DECSWBV, VT520))
{ 0, 0, 'u', ANSICSI_RCP, -1, -1 },

{ 1, XTERMCC_DEICONIFY },
{ 2, XTERMCC_ICONIFY },
{ 3, XTERMCC_WINDOWPOS },
{ 4, XTERMCC_WINDOWSIZE_PIXEL },
{ 5, XTERMCC_RAISE },
{ 6, XTERMCC_LOWER },
// 7 is not supported (Refresh the window)
{ 8, XTERMCC_WINDOWSIZE },
// 9 is not supported (Various maximize window actions)
// 10 is not supported (Various full-screen actions)
{ 11, XTERMCC_REPORT_WIN_STATE },
// 12 is not defined
{ 13, XTERMCC_REPORT_WIN_POS },
{ 14, XTERMCC_REPORT_WIN_PIX_SIZE },
// 15, 16, and 17 are not defined
{ 18, XTERMCC_REPORT_WIN_SIZE },
{ 19, XTERMCC_REPORT_SCREEN_SIZE },
{ 20, XTERMCC_REPORT_ICON_TITLE },
{ 21, XTERMCC_REPORT_WIN_TITLE },
{ 22, XTERMCC_PUSH_TITLE },
{ 23, XTERMCC_POP_TITLE },
*/

@end
