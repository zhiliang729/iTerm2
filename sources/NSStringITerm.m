// $Id: NSStringITerm.m,v 1.11 2008-09-24 22:35:38 yfabian Exp $
/*
 **  NSStringIterm.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements NSString extensions.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import <apr-1/apr_base64.h>
#import <Carbon/Carbon.h>
#import <wctype.h>

#define AMB_CHAR_NUMBER (sizeof(ambiguous_chars) / sizeof(int))

static const int ambiguous_chars[] = {
    0xa1, 0xa4, 0xa7, 0xa8, 0xaa, 0xad, 0xae, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb6, 0xb7,
    0xb8, 0xb9, 0xba, 0xbc, 0xbd, 0xbe, 0xbf, 0xc6, 0xd0, 0xd7, 0xd8, 0xde, 0xdf, 0xe0,
    0xe1, 0xe6, 0xe8, 0xe9, 0xea, 0xec, 0xed, 0xf0, 0xf2, 0xf3, 0xf7, 0xf8, 0xf9, 0xfa,
    0xfc, 0xfe, 0x101, 0x111, 0x113, 0x11b, 0x126, 0x127, 0x12b, 0x131, 0x132, 0x133,
    0x138, 0x13f, 0x140, 0x141, 0x142, 0x144, 0x148, 0x149, 0x14a, 0x14b, 0x14d, 0x152,
    0x153, 0x166, 0x167, 0x16b, 0x1ce, 0x1d0, 0x1d2, 0x1d4, 0x1d6, 0x1d8, 0x1da, 0x1dc,
    0x251, 0x261, 0x2c4, 0x2c7, 0x2c9, 0x2ca, 0x2cb, 0x2cd, 0x2d0, 0x2d8, 0x2d9, 0x2da,
    0x2db, 0x2dd, 0x2df, 0x3a3, 0x3a4, 0x3a5, 0x3a6, 0x3a7, 0x3a8, 0x3a9, 0x3c3, 0x3c4,
    0x3c5, 0x3c6, 0x3c7, 0x3c8, 0x3c9, 0x401, 0x451, 0x2010, 0x2013, 0x2014, 0x2015,
    0x2016, 0x2018, 0x2019, 0x201c, 0x201d, 0x2020, 0x2021, 0x2022, 0x2024, 0x2025,
    0x2026, 0x2027, 0x2030, 0x2032, 0x2033, 0x2035, 0x203b, 0x203e, 0x2074, 0x207f,
    0x2081, 0x2082, 0x2083, 0x2084, 0x20ac, 0x2103, 0x2105, 0x2109, 0x2113, 0x2116,
    0x2121, 0x2122, 0x2126, 0x212b, 0x2153, 0x2154, 0x215b, 0x215c, 0x215d, 0x215e,
    0x2189, 0x21b8, 0x21b9, 0x21d2, 0x21d4, 0x21e7, 0x2200, 0x2202, 0x2203, 0x2207,
    0x2208, 0x220b, 0x220f, 0x2211, 0x2215, 0x221a, 0x221d, 0x221e, 0x221f, 0x2220,
    0x2223, 0x2225, 0x2227, 0x2228, 0x2229, 0x222a, 0x222b, 0x222c, 0x222e, 0x2234,
    0x2235, 0x2236, 0x2237, 0x223c, 0x223d, 0x2248, 0x224c, 0x2252, 0x2260, 0x2261,
    0x2264, 0x2265, 0x2266, 0x2267, 0x226a, 0x226b, 0x226e, 0x226f, 0x2282, 0x2283,
    0x2286, 0x2287, 0x2295, 0x2299, 0x22a5, 0x22bf, 0x2312, 0x2592, 0x2593, 0x2594,
    0x2595, 0x25a0, 0x25a1, 0x25a3, 0x25a4, 0x25a5, 0x25a6, 0x25a7, 0x25a8, 0x25a9,
    0x25b2, 0x25b3, 0x25b6, 0x25b7, 0x25bc, 0x25bd, 0x25c0, 0x25c1, 0x25c6, 0x25c7,
    0x25c8, 0x25cb, 0x25ce, 0x25cf, 0x25d0, 0x25d1, 0x25e2, 0x25e3, 0x25e4, 0x25e5,
    0x25ef, 0x2605, 0x2606, 0x2609, 0x260e, 0x260f, 0x2614, 0x2615, 0x261c, 0x261e,
    0x2640, 0x2642, 0x2660, 0x2661, 0x2663, 0x2664, 0x2665, 0x2667, 0x2668, 0x2669,
    0x266a, 0x266c, 0x266d, 0x266f, 0x269e, 0x269f, 0x26be, 0x26bf, 0x26e3, 0x273d,
    0x2757, 0x2b55, 0x2b56, 0x2b57, 0x2b58, 0x2b59, 0xfffd
    // This is not a complete list - there are also several large ranges that
    // are found in the code.
};


@implementation NSString (iTerm)

+ (NSString *)stringWithInt:(int)num
{
    return [NSString stringWithFormat:@"%d", num];
}

+ (BOOL)isDoubleWidthCharacter:(int)unicode
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    if (unicode <= 0xa0 ||
        (unicode > 0x452 && unicode < 0x1100)) {
        // Quickly cover the common cases.
        return NO;
    }

    // This list of fullwidth and wide characters comes from Unicode 6.0:
    // http://www.unicode.org/Public/6.0.0/ucd/EastAsianWidth.txt
    if ((unicode >= 0x1100 && unicode <= 0x115f) ||
        (unicode >= 0x11a3 && unicode <= 0x11a7) ||
        (unicode >= 0x11fa && unicode <= 0x11ff) ||
        (unicode >= 0x2329 && unicode <= 0x232a) ||
        (unicode >= 0x2e80 && unicode <= 0x2e99) ||
        (unicode >= 0x2e9b && unicode <= 0x2ef3) ||
        (unicode >= 0x2f00 && unicode <= 0x2fd5) ||
        (unicode >= 0x2ff0 && unicode <= 0x2ffb) ||
        (unicode >= 0x3000 && unicode <= 0x303e) ||
        (unicode >= 0x3041 && unicode <= 0x3096) ||
        (unicode >= 0x3099 && unicode <= 0x30ff) ||
        (unicode >= 0x3105 && unicode <= 0x312d) ||
        (unicode >= 0x3131 && unicode <= 0x318e) ||
        (unicode >= 0x3190 && unicode <= 0x31ba) ||
        (unicode >= 0x31c0 && unicode <= 0x31e3) ||
        (unicode >= 0x31f0 && unicode <= 0x321e) ||
        (unicode >= 0x3220 && unicode <= 0x3247) ||
        (unicode >= 0x3250 && unicode <= 0x32fe) ||
        (unicode >= 0x3300 && unicode <= 0x4dbf) ||
        (unicode >= 0x4e00 && unicode <= 0xa48c) ||
        (unicode >= 0xa490 && unicode <= 0xa4c6) ||
        (unicode >= 0xa960 && unicode <= 0xa97c) ||
        (unicode >= 0xac00 && unicode <= 0xd7a3) ||
        (unicode >= 0xd7b0 && unicode <= 0xd7c6) ||
        (unicode >= 0xd7cb && unicode <= 0xd7fb) ||
        (unicode >= 0xf900 && unicode <= 0xfaff) ||
        (unicode >= 0xfe10 && unicode <= 0xfe19) ||
        (unicode >= 0xfe30 && unicode <= 0xfe52) ||
        (unicode >= 0xfe54 && unicode <= 0xfe66) ||
        (unicode >= 0xfe68 && unicode <= 0xfe6b) ||
        (unicode >= 0xff01 && unicode <= 0xff60) ||
        (unicode >= 0xffe0 && unicode <= 0xffe6) ||
        (unicode >= 0x1b000 && unicode <= 0x1b001) ||
        (unicode >= 0x1f200 && unicode <= 0x1f202) ||
        (unicode >= 0x1f210 && unicode <= 0x1f23a) ||
        (unicode >= 0x1f240 && unicode <= 0x1f248) ||
        (unicode >= 0x1f250 && unicode <= 0x1f251) ||
        (unicode >= 0x20000 && unicode <= 0x2fffd) ||
        (unicode >= 0x30000 && unicode <= 0x3fffd)) {
        return YES;
    }

    // These are the ambiguous-width characters (ibid.)
    if (ambiguousIsDoubleWidth) {
        // First check if the character falls in any range of consecutive
        // ambiguous-width characters before performing the binary search.
        // This keeps the list from being absurdly large.
        if ((unicode >= 0x300 && unicode <= 0x36f) ||
            (unicode >= 0x391 && unicode <= 0x3a1) ||
            (unicode >= 0x3b1 && unicode <= 0x3c1) ||
            (unicode >= 0x410 && unicode <= 0x44f) ||
            (unicode >= 0x2160 && unicode <= 0x216b) ||
            (unicode >= 0x2170 && unicode <= 0x2179) ||
            (unicode >= 0x2190 && unicode <= 0x2199) ||
            (unicode >= 0x2460 && unicode <= 0x24e9) ||
            (unicode >= 0x24eb && unicode <= 0x254b) ||
            (unicode >= 0x2550 && unicode <= 0x2573) ||
            (unicode >= 0x2580 && unicode <= 0x258f) ||
            (unicode >= 0x26c4 && unicode <= 0x26cd) ||
            (unicode >= 0x26cf && unicode <= 0x26e1) ||
            (unicode >= 0x26e8 && unicode <= 0x26ff) ||
            (unicode >= 0x2776 && unicode <= 0x277f) ||
            (unicode >= 0x3248 && unicode <= 0x324f) ||
            (unicode >= 0xe000 && unicode <= 0xf8ff) ||
            (unicode >= 0xfe00 && unicode <= 0xfe0f) ||
            (unicode >= 0x1f100 && unicode <= 0x1f10a) ||
            (unicode >= 0x1f110 && unicode <= 0x1f12d) ||
            (unicode >= 0x1f130 && unicode <= 0x1f169) ||
            (unicode >= 0x1f170 && unicode <= 0x1f19a) ||
            (unicode >= 0xe0100 && unicode <= 0xe01ef) ||
            (unicode >= 0xf0000 && unicode <= 0xffffd) ||
            (unicode >= 0x100000 && unicode <= 0x10fffd)) {
            return YES;
        }

        // Now do a binary search of the individual ambiguous width code points
        // in the array above.
        int ind = AMB_CHAR_NUMBER / 2;
        int start = 0;
        int end = AMB_CHAR_NUMBER;
        while (start < end) {
            if (ambiguous_chars[ind] == unicode) {
                return YES;
            } else if (ambiguous_chars[ind] < unicode) {
                start = ind + 1;
                ind = (start + end) / 2;
            } else {
                end = ind;
                ind = (start + end) / 2;
            }
        }
        // Fall through if not in ambiguous character list.
    }

    return NO;
}

+ (NSString *)stringFromPasteboard {
    NSPasteboard *board;

    board = [NSPasteboard generalPasteboard];
    assert(board != nil);

    NSArray *supportedTypes = @[ NSFilenamesPboardType, NSStringPboardType ];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    DLog(@"Getting pasteboard string...");
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        NSMutableArray *escapedFilenames = [NSMutableArray array];
        DLog(@"Pasteboard has filenames: %@.", filenames);
        for (NSString *filename in filenames) {
            [escapedFilenames addObject:[filename stringWithEscapedShellCharacters]];
        }
        if (escapedFilenames.count > 0) {
            info = [escapedFilenames componentsJoinedByString:@" "];
        }
        if ([info length] == 0) {
            info = nil;
        }
    } else {
        DLog(@"Pasteboard has a string.");
        info = [board stringForType:NSStringPboardType];
    }
    return info;
}

+ (NSString *)shellEscapableCharacters {
    return @"\\ ()\"&'!$<>;|*?[]#`";
}

- (NSString *)stringWithEscapedShellCharacters {
    NSMutableString *aMutableString = [[[NSMutableString alloc] initWithString:self] autorelease];
    [aMutableString escapeShellCharacters];
    return [NSString stringWithString:aMutableString];
}

- (NSString *)stringWithShellEscapedTabs
{
    const int kLNEXT = 22;
    NSString *replacement = [NSString stringWithFormat:@"%c\t", kLNEXT];

    return [self stringByReplacingOccurrencesOfString:@"\t" withString:replacement];
}

- (NSString*)stringWithPercentEscape
{
    // From
    // http://stackoverflow.com/questions/705448/iphone-sdk-problem-with-ampersand-in-the-url-string
    return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                (CFStringRef)[[self mutableCopy] autorelease],
                                                                NULL,
                                                                CFSTR("￼=,!$&'()*+;@?\n\"<>#\t :/"),
                                                                kCFStringEncodingUTF8) autorelease];
}

- (NSString*)stringWithLinefeedNewlines
{
    return [[self stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"]
               stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
}

- (NSArray *)componentsInShellCommand {
    NSMutableArray *result = [NSMutableArray array];

    int inQuotes = 0; // Are we inside double quotes?
    BOOL escape = NO;  // Should this char be escaped?
    NSMutableString *currentValue = [NSMutableString string];
    BOOL valueStarted = NO;
    BOOL firstCharacterNotQuotedOrEscaped = NO;

    for (NSInteger i = 0; i <= self.length; i++) {
        unichar c;
        if (i < self.length) {
            c = [self characterAtIndex:i];
            if (c == 0) {
                // Pretty sure this can't happen, but better to be safe.
                c = ' ';
            }
        } else {
            // Signifies end-of-string.
            c = 0;
        }

        if (c == '\\' && !escape) {
            escape = YES;
            continue;
        }

        if (escape) {
            valueStarted = YES;
            escape = NO;
            if (c == 'n') {
                [currentValue appendString:@"\n"];
            } else if (c == 'a') {
                [currentValue appendFormat:@"%c", 7];
            } else if (c == 't') {
                [currentValue appendString:@"\t"];
            } else if (c == 'r') {
                [currentValue appendString:@"\r"];
            } else {
                [currentValue appendFormat:@"%C", c];
            }
            continue;
        }

        if (c == '"') {
            inQuotes = !inQuotes;
            valueStarted = YES;
            continue;
        }

        if (c == 0) {
            inQuotes = NO;
        }

        // Treat end-of-string like whitespace.
        BOOL isWhitespace = (c == 0 || iswspace(c));

        if (!inQuotes && isWhitespace) {
            if (valueStarted) {
                if (firstCharacterNotQuotedOrEscaped) {
                    [result addObject:[currentValue stringByExpandingTildeInPath]];
                } else {
                    [result addObject:currentValue];
                }
                currentValue = [NSMutableString string];
                firstCharacterNotQuotedOrEscaped = NO;
                valueStarted = NO;
            }
            // If !valueStarted, this char is meaningless whitespace.
            continue;
        }

        if (!valueStarted) {
            firstCharacterNotQuotedOrEscaped = !inQuotes;
        }
        valueStarted = YES;
        [currentValue appendFormat:@"%C", c];
    }

    return result;
}

- (NSString *)stringByReplacingBackreference:(int)n withString:(NSString *)s
{
    return [self stringByReplacingEscapedChar:'0' + n withString:s];
}

static BOOL ishex(unichar c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static int fromhex(unichar c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return c - 'A' + 10;
}

- (NSData *)dataFromHexValues
{
    NSMutableData *data = [NSMutableData data];
    int length = self.length;  // Convert to signed so length-1 is safe below.
    for (int i = 0; i < length - 1; i+=2) {
        const char high = fromhex([self characterAtIndex:i]) << 4;
        const char low = fromhex([self characterAtIndex:i + 1]);
        const char b = high | low;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (NSString *)stringByReplacingEscapedHexValuesWithChars
{
    NSMutableArray *ranges = [NSMutableArray array];
    NSRange range = [self rangeOfString:@"\\x"];
    while (range.location != NSNotFound) {
        int numSlashes = 0;
        for (int i = range.location - 1; i >= 0 && [self characterAtIndex:i] == '\\'; i--) {
            ++numSlashes;
        }
        if (range.location + 3 < self.length) {
            if (numSlashes % 2 == 0) {
                unichar c1 = [self characterAtIndex:range.location + 2];
                unichar c2 = [self characterAtIndex:range.location + 3];
                if (ishex(c1) && ishex(c2)) {
                    range.length += 2;
                    [ranges insertObject:[NSValue valueWithRange:range] atIndex:0];
                }
            }
        }
        range = [self rangeOfString:@"\\x"
                            options:0
                              range:NSMakeRange(range.location + 1, self.length - range.location - 1)];
    }

    NSString *newString = self;
    for (NSValue *value in ranges) {
        NSRange r = [value rangeValue];

        unichar c1 = [self characterAtIndex:r.location + 2];
        unichar c2 = [self characterAtIndex:r.location + 3];
        unichar c = (fromhex(c1) << 4) + fromhex(c2);
        NSString *s = [NSString stringWithCharacters:&c length:1];
        newString = [newString stringByReplacingCharactersInRange:r withString:s];
    }

    return newString;
}

- (NSString *)stringByReplacingEscapedChar:(unichar)echar withString:(NSString *)s
{
    NSString *br = [NSString stringWithFormat:@"\\%C", echar];
    NSMutableArray *ranges = [NSMutableArray array];
    NSRange range = [self rangeOfString:br];
    while (range.location != NSNotFound) {
        int numSlashes = 0;
        for (int i = range.location - 1; i >= 0 && [self characterAtIndex:i] == '\\'; i--) {
            ++numSlashes;
        }
        if (numSlashes % 2 == 0) {
            [ranges insertObject:[NSValue valueWithRange:range] atIndex:0];
        }
        range = [self rangeOfString:br
                            options:0
                              range:NSMakeRange(range.location + 1, self.length - range.location - 1)];
    }

    NSString *newString = self;
    for (NSValue *value in ranges) {
        NSRange r = [value rangeValue];
        newString = [newString stringByReplacingCharactersInRange:r withString:s];
    }

    return newString;
}

// foo"bar -> foo\"bar
// foo\bar -> foo\\bar
// foo\"bar -> foo\\\"bar
- (NSString *)stringByEscapingQuotes {
    return [[self stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
               stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// Returns the number of valid bytes in a sequence from a row in table 3-7 of the Unicode 6.2 spec.
// Returns 0 if no bytes are valid (a true maximal subpart is never less than 1).
static int maximal_subpart_of_row(const unsigned char *datap,
                                  int datalen,
                                  int bytesInRow,
                                  int *min,  // array of min values, with |bytesInRow| elements.
                                  int *max)  // array of max values, with |bytesInRow| elements.
{
    for (int i = 0; i < bytesInRow && i < datalen; i++) {
        const int v = datap[i];
        if (v < min[i] || v > max[i]) {
            return i;
        }
    }
    return bytesInRow;
}

// This function finds the longest intial sequence of bytes that look like a valid UTF-8 sequence.
// It's used to gobble them up and replace them with a <?> replacement mark in an invalid sequence.
static int minimal_subpart(const unsigned char *datap, int datalen)
{
    // This comes from table 3-7 in http://www.unicode.org/versions/Unicode6.2.0/ch03.pdf
    struct {
        int numBytes;  // Num values in min, max arrays
        int min[4];    // Minimum values for each byte in a utf-8 sequence.
        int max[4];    // Max values.
    } wellFormedSequencesTable[] = {
        {
            1,
            { 0x00, -1, -1, -1, },
            { 0x7f, -1, -1, -1, },
        },
        {
            2,
            { 0xc2, 0x80, -1, -1, },
            { 0xdf, 0xbf, -1, -1 },
        },
        {
            3,
            { 0xe0, 0xa0, 0x80, -1, },
            { 0xe0, 0xbf, 0xbf, -1 },
        },
        {
            3,
            { 0xe1, 0x80, 0x80, -1, },
            { 0xec, 0xbf, 0xbf, -1, },
        },
        {
            3,
            { 0xed, 0x80, 0x80, -1, },
            { 0xed, 0x9f, 0xbf, -1 },
        },
        {
            3,
            { 0xee, 0x80, 0x80, -1, },
            { 0xef, 0xbf, 0xbf, -1, },
        },
        {
            4,
            { 0xf0, 0x90, 0x80, -1, },
            { 0xf0, 0xbf, 0xbf, -1, },
        },
        {
            4,
            { 0xf1, 0x80, 0x80, 0x80, },
            { 0xf3, 0xbf, 0xbf, 0xbf, },
        },
        {
            4,
            { 0xf4, 0x80, 0x80, 0x80, },
            { 0xf4, 0x8f, 0xbf, 0xbf },
        },
        { -1, { -1 }, { -1 } }
    };

    int longest = 0;
    for (int row = 0; wellFormedSequencesTable[row].numBytes > 0; row++) {
        longest = MAX(longest,
                      maximal_subpart_of_row(datap,
                                             datalen,
                                             wellFormedSequencesTable[row].numBytes,
                                             wellFormedSequencesTable[row].min,
                                             wellFormedSequencesTable[row].max));
    }
    return MIN(datalen, MAX(1, longest));
}

int decode_utf8_char(const unsigned char *datap,
                     int datalen,
                     int * restrict result)
{
    unsigned int theChar;
    int utf8Length;
    unsigned char c;
    // This maps a utf-8 sequence length to the smallest code point it should
    // encode (e.g., using 5 bytes to encode an ascii character would be
    // considered an error).
    unsigned int smallest[7] = { 0, 0, 0x80UL, 0x800UL, 0x10000UL, 0x200000UL, 0x4000000UL };

    if (datalen == 0) {
        return 0;
    }

    c = *datap;
    if ((c & 0x80) == 0x00) {
        *result = c;
        return 1;
    } else if ((c & 0xE0) == 0xC0) {
        theChar = c & 0x1F;
        utf8Length = 2;
    } else if ((c & 0xF0) == 0xE0) {
        theChar = c & 0x0F;
        utf8Length = 3;
    } else if ((c & 0xF8) == 0xF0) {
        theChar = c & 0x07;
        utf8Length = 4;
    } else if ((c & 0xFC) == 0xF8) {
        theChar = c & 0x03;
        utf8Length = 5;
    } else if ((c & 0xFE) == 0xFC) {
        theChar = c & 0x01;
        utf8Length = 6;
    } else {
        return -1;
    }
    for (int i = 1; i < utf8Length; i++) {
        if (datalen <= i) {
            return 0;
        }
        c = datap[i];
        if ((c & 0xc0) != 0x80) {
            // Expected a continuation character but did not get one.
            return -i;
        }
        theChar = (theChar << 6) | (c & 0x3F);
    }

    if (theChar < smallest[utf8Length]) {
        // A too-long sequence was used to encode a value. For example, a 4-byte sequence must encode
        // a value of at least 0x10000 (it is F0 90 80 80). A sequence like F0 8F BF BF is invalid
        // because there is a 3-byte sequence to encode U+FFFF (the sequence is EF BF BF).
        return -minimal_subpart(datap, datalen);
    }

    // Reject UTF-16 surrogates. They are invalid UTF-8 sequences.
    // Reject characters above U+10FFFF, as they are also invalid UTF-8 sequences.
    if ((theChar >= 0xD800 && theChar <= 0xDFFF) || theChar > 0x10FFFF) {
        return -minimal_subpart(datap, datalen);
    }

    *result = (int)theChar;
    return utf8Length;
}

- (NSString *)initWithUTF8DataIgnoringErrors:(NSData *)data {
    const unsigned char *p = data.bytes;
    int len = data.length;
    int utf8DecodeResult;
    int theChar = 0;
    NSMutableData *utf16Data = [NSMutableData data];

    while (len > 0) {
        utf8DecodeResult = decode_utf8_char(p, len, &theChar);
        if (utf8DecodeResult == 0) {
            // Stop on end of stream.
            break;
        } else if (utf8DecodeResult < 0) {
            theChar = UNICODE_REPLACEMENT_CHAR;
            utf8DecodeResult = -utf8DecodeResult;
        } else if (theChar > 0xFFFF) {
            // Convert to surrogate pair.
           UniChar high, low;
           high = ((theChar - 0x10000) >> 10) + 0xd800;
           low = (theChar & 0x3ff) + 0xdc00;

           [utf16Data appendBytes:&high length:sizeof(high)];
           theChar = low;
        }

        UniChar c = theChar;
        [utf16Data appendBytes:&c length:sizeof(c)];

        p += utf8DecodeResult;
        len -= utf8DecodeResult;
    }

    return [self initWithData:utf16Data encoding:NSUTF16LittleEndianStringEncoding];
}

- (NSString *)stringWithOnlyDigits {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < self.length; i++) {
    unichar c = [self characterAtIndex:i];
    if (iswdigit(c)) {
      [s appendFormat:@"%c", (char)c];
    }
  }
  return s;
}

- (NSString*)stringByTrimmingLeadingWhitespace {
    int i = 0;

    while ((i < self.length) &&
           [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[self characterAtIndex:i]]) {
        i++;
    }
    return [self substringFromIndex:i];
}

- (NSString *)stringByBase64DecodingStringWithEncoding:(NSStringEncoding)encoding {
    const char *buffer = [self UTF8String];
    int destLength = apr_base64_decode_len(buffer);
    if (destLength <= 0) {
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    return [[[NSString alloc] initWithBytes:decodedBuffer
                                     length:resultLength
                                   encoding:NSISOLatin1StringEncoding] autorelease];
}

- (NSString *)stringByTrimmingTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:nonWhitespaceSet
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        return self;
    } else if (rangeOfLastWantedCharacter.location + rangeOfLastWantedCharacter.length < self.length) {
        NSUInteger i = rangeOfLastWantedCharacter.location + rangeOfLastWantedCharacter.length;
        return [self substringToIndex:i];
    }
    return self;
}

// Returns a substring of contiguous characters only from a given character set
// including some character in the middle of the "haystack" (source) string.
- (NSString *)substringIncludingOffset:(int)offset
            fromCharacterSet:(NSCharacterSet *)charSet
        charsTakenFromPrefix:(int*)charsTakenFromPrefixPtr
{
    if (![self length]) {
        if (charsTakenFromPrefixPtr) {
            *charsTakenFromPrefixPtr = 0;
        }
        return @"";
    }
    NSRange firstBadCharRange = [self rangeOfCharacterFromSet:[charSet invertedSet]
                                                      options:NSBackwardsSearch
                                                        range:NSMakeRange(0, offset)];
    NSRange lastBadCharRange = [self rangeOfCharacterFromSet:[charSet invertedSet]
                                                     options:0
                                                       range:NSMakeRange(offset, [self length] - offset)];
    int start = 0;
    int end = [self length];
    if (firstBadCharRange.location != NSNotFound) {
        start = firstBadCharRange.location + 1;
        if (charsTakenFromPrefixPtr) {
            *charsTakenFromPrefixPtr = offset - start;
        }
    } else if (charsTakenFromPrefixPtr) {
        *charsTakenFromPrefixPtr = offset;
    }
    
    if (lastBadCharRange.location != NSNotFound) {
        end = lastBadCharRange.location;
    }
    
    return [self substringWithRange:NSMakeRange(start, end - start)];
}

// This handles a few kinds of URLs, after trimming whitespace from the beginning and end:
// 1. Well formed strings like:
//    "http://example.com/foo?query#fragment"
// 2. URLs in parens:
//    "(http://example.com/foo?query#fragment)" -> http://example.com/foo?query#fragment
// 3. URLs at the end of a sentence:
//    "http://example.com/foo?query#fragment." -> http://example.com/foo?query#fragment
// 4. Case 2 & 3 combined:
//    "(http://example.com/foo?query#fragment)." -> http://example.com/foo?query#fragment
// 5. Strings without a scheme (http is assumed, previous cases do not apply)
//    "example.com/foo?query#fragment" -> http://example.com/foo?query#fragment
// *offset will be set to the number of characters at the start of self that were skipped past.
// offset may be nil. If |length| is not nil, then *length will be set to the number of chars matched
// in self.
- (NSString *)URLInStringWithOffset:(int *)offset length:(int *)length
{
    NSString* trimmedURLString;
    
    trimmedURLString = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (![trimmedURLString length]) {
        return nil;
    }
    if (offset) {
        *offset = 0;
    }
    
    NSRange range = [trimmedURLString rangeOfString:@":"];
    if (range.location == NSNotFound) {
        if (length) {
            *length = trimmedURLString.length;
        }
        trimmedURLString = [NSString stringWithFormat:@"http://%@", trimmedURLString];
    } else {
        if (length) {
            *length = trimmedURLString.length;
        }
        // Search backwards for the start of the scheme.
        for (int i = range.location - 1; 0 <= i; i--) {
            unichar c = [trimmedURLString characterAtIndex:i];
            if (!isalnum(c)) {
                // Remove garbage before the scheme part
                trimmedURLString = [trimmedURLString substringFromIndex:i + 1];
                if (offset) {
                    *offset = i + 1;
                }
                if (length) {
                    *length = trimmedURLString.length;
                }
                if (c == '(') {
                    // If an open parenthesis is right before the
                    // scheme part, remove the closing parenthesis
                    NSRange closer = [trimmedURLString rangeOfString:@")"];
                    if (closer.location != NSNotFound) {
                        trimmedURLString = [trimmedURLString substringToIndex:closer.location];
                        if (length) {
                            *length = trimmedURLString.length;
                        }
                    }
                }
                break;
            }
        }
    }
    
    // Remove trailing punctuation.
    NSArray *punctuation = @[ @".", @",", @";", @":", @"!" ];
    BOOL found;
    do {
        found = NO;
        for (NSString *pchar in punctuation) {
            if ([trimmedURLString hasSuffix:pchar]) {
                trimmedURLString = [trimmedURLString substringToIndex:trimmedURLString.length - 1];
                found = YES;
                if (length) {
                    (*length)--;
                }
            }
        }
    } while (found);
    
    return trimmedURLString;
}

- (NSString *)stringByEscapingForURL {
    NSString *theString =
        (NSString *) CFURLCreateStringByAddingPercentEscapes(NULL,
                                                             (CFStringRef)self,
                                                             (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                             NULL,
                                                             kCFStringEncodingUTF8);
    return [theString autorelease];
}

- (NSString *)stringByCapitalizingFirstLetter {
    if ([self length] == 0) {
        return self;
    }
    NSString *prefix = [self substringToIndex:1];
    NSString *suffix = [self substringFromIndex:1];
    return [[prefix uppercaseString] stringByAppendingString:suffix];
}

- (NSString *)hexOrDecimalConversionHelp {
    unsigned long long value;
    BOOL decToHex;
    if ([self hasPrefix:@"0x"] && [self length] <= 18) {
        decToHex = NO;
        NSScanner *scanner = [NSScanner scannerWithString:self];
        
        [scanner setScanLocation:2]; // bypass 0x
        if (![scanner scanHexLongLong:&value]) {
            return nil;
        }
    } else {
        decToHex = YES;
        value = [self longLongValue];
    }
    if (!value) {
        return nil;
    }
    
    BOOL is32bit;
    if (decToHex) {
        is32bit = ((long long)value >= -2147483648LL && (long long)value <= 2147483647LL);
    } else {
        is32bit = [self length] <= 10;
    }
    
    if (is32bit) {
        // Value fits in a signed 32-bit value, so treat it as such
        int intValue = (int)value;
        if (decToHex) {
            return [NSString stringWithFormat:@"%d = 0x%x", intValue, intValue];
        } else if (intValue >= 0) {
            return [NSString stringWithFormat:@"0x%x = %d", intValue, intValue];
        } else {
            return [NSString stringWithFormat:@"0x%x = %d or %u", intValue, intValue, intValue];
        }
    } else {
        // 64-bit value
        if (decToHex) {
            return [NSString stringWithFormat:@"%lld = 0x%llx", value, value];
        } else if ((long long)value >= 0) {
            return [NSString stringWithFormat:@"0x%llx = %lld", value, value];
        } else {
            return [NSString stringWithFormat:@"0x%llx = %lld or %llu", value, value, value];
        }
    }
}

- (BOOL)stringIsUrlLike {
    return [self hasPrefix:@"http://"] || [self hasPrefix:@"https://"];
}

- (NSFont *)fontValue {
    float fontSize;
    char utf8FontName[128];
    NSFont *aFont;
    
    if ([self length] == 0) {
        return ([NSFont userFixedPitchFontOfSize:0.0]);
    }
    
    sscanf([self UTF8String], "%127s %g", utf8FontName, &fontSize);
    // The sscanf man page is unclear whether it will always null terminate when the length hits the
    // maximum field width, so ensure it is null terminated.
    utf8FontName[127] = '\0';
    
    aFont = [NSFont fontWithName:[NSString stringWithFormat:@"%s", utf8FontName] size:fontSize];
    if (aFont == nil) {
        return ([NSFont userFixedPitchFontOfSize:0.0]);
    }
    
    return aFont;
}

- (NSString *)hexEncodedString {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < self.length; i++) {
        [result appendFormat:@"%02X", [self characterAtIndex:i]];
    }
    return [[result copy] autorelease];
}

+ (NSString *)stringWithHexEncodedString:(NSString *)hexEncodedString {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i + 1 < hexEncodedString.length; i += 2) {
        char buffer[3] = { [hexEncodedString characterAtIndex:i],
                           [hexEncodedString characterAtIndex:i + 1],
                           0 };
        int value;
        sscanf(buffer, "%02x", &value);
        [result appendFormat:@"%C", (unichar)value];
    }
    return [[result copy] autorelease];
}

// Return TEC converter between UTF16 variants, or NULL on failure.
// You should call TECDisposeConverter on the returned obj.
static TECObjectRef CreateTECConverterForUTF8Variants(TextEncodingVariant variant) {
    TextEncoding utf16Encoding = CreateTextEncoding(kTextEncodingUnicodeDefault,
                                                    kTextEncodingDefaultVariant,
                                                    kUnicodeUTF16Format);
    TextEncoding hfsPlusEncoding = CreateTextEncoding(kTextEncodingUnicodeDefault,
                                                      variant,
                                                      kUnicodeUTF16Format);

    TECObjectRef conv;
    if (TECCreateConverter(&conv, utf16Encoding, hfsPlusEncoding) != noErr) {
        NSLog(@"Failed to create HFS Plus converter.\n");
        return NULL;
    }

    return conv;
}

- (NSString *)_convertBetweenUTF8AndHFSPlusAsPrecomposition:(BOOL)precompose {
    static TECObjectRef gHFSPlusComposed;
    static TECObjectRef gHFSPlusDecomposed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gHFSPlusComposed = CreateTECConverterForUTF8Variants(kUnicodeHFSPlusCompVariant);
        gHFSPlusDecomposed = CreateTECConverterForUTF8Variants(kUnicodeHFSPlusDecompVariant);
    });
    
    size_t in_len = sizeof(unichar) * [self length];
    size_t out_len;
    unichar *in = malloc(in_len);
    if (!in) {
        return self;
    }
    unichar *out;
    NSString *ret;

    [self getCharacters:in range:NSMakeRange(0, [self length])];
    out_len = in_len;
    if (!precompose) {
        out_len *= 2;
    }
    out = malloc(sizeof(unichar) * out_len);
    if (!out) {
        free(in);
        return self;
    }
    
    if (TECConvertText(precompose ? gHFSPlusComposed : gHFSPlusDecomposed,
                       (TextPtr)in,
                       in_len,
                       &in_len,
                       (TextPtr)out,
                       out_len,
                       &out_len) != noErr) {
        ret = self;
    } else {
        int numCharsOut = out_len / sizeof(unichar);
        ret = [NSString stringWithCharacters:out length:numCharsOut];
    }
    
    free(in);
    free(out);

    return ret;
}

- (NSString *)precomposedStringWithHFSPlusMapping {
    return [self _convertBetweenUTF8AndHFSPlusAsPrecomposition:YES];
}

- (NSString *)decomposedStringWithHFSPlusMapping {
    return [self _convertBetweenUTF8AndHFSPlusAsPrecomposition:NO];
}

- (NSUInteger)indexOfSubstring:(NSString *)substring fromIndex:(NSUInteger)index {
    return [self rangeOfString:substring options:0 range:NSMakeRange(index, self.length - index)].location;
}

- (NSString *)octalCharacter {
    unichar value = 0;
    for (int i = 0; i < self.length; i++) {
        value *= 8;
        unichar c = [self characterAtIndex:i];
        if (c < '0' || c >= '8') {
            return @"";
        }
        value += c - '0';
    }
    return [NSString stringWithCharacters:&value length:1];
}

- (NSString *)hexCharacter {
    if (self.length == 0 || self.length == 3 || self.length > 4) {
        return @"";
    }
    
    unsigned int value;
    NSScanner *scanner = [NSScanner scannerWithString:self];
    if (![scanner scanHexInt:&value]) {
        return @"";
    }
    
    unichar c = value;
    return [NSString stringWithCharacters:&c length:1];
}

- (NSString *)controlCharacter {
    unichar c = [[self lowercaseString] characterAtIndex:0];
    if (c < 'a' || c >= 'z') {
        return @"";
    }
    c -= 'a' - 1;
    return [NSString stringWithFormat:@"%c", c];
}

- (NSString *)metaCharacter {
    return [NSString stringWithFormat:@"%c%@", 27, self];
}

- (NSString *)stringByExpandingVimSpecialCharacters {
    typedef enum {
        kSpecialCharacterThreeDigitOctal,  // \...    three-digit octal number (e.g., "\316")
        kSpecialCharacterTwoDigitOctal,    // \..     two-digit octal number (must be followed by non-digit)
        kSpecialCharacterOneDigitOctal,    // \.      one-digit octal number (must be followed by non-digit)
        kSpecialCharacterTwoDigitHex,      // \x..    byte specified with two hex numbers (e.g., "\x1f")
        kSpecialCharacterOneDigitHex,      // \x.     byte specified with one hex number (must be followed by non-hex char)
        kSpecialCharacterFourDigitUnicode, // \u....  character specified with up to 4 hex numbers
        kSpecialCharacterBackspace,        // \b      backspace <BS>
        kSpecialCharacterEscape,           // \e      escape <Esc>
        kSpecialCharacterFormFeed,         // \f      formfeed <FF>
        kSpecialCharacterNewline,          // \n      newline <NL>
        kSpecialCharacterReturn,           // \r      return <CR>
        kSpecialCharacterTab,              // \t      tab <Tab>
        kSpecialCharacterBackslash,        // \\      backslash
        kSpecialCharacterDoubleQuote,      // \"      double quote
        kSpecialCharacterControlKey,       // \<C-W>  Control key
        kSpecialCharacterMetaKey,          // \<M-W>  Meta key
    } SpecialCharacter;
    
    NSDictionary *regexes =
        @{ @"^(([0-7]{3}))": @(kSpecialCharacterThreeDigitOctal),
           @"^(([0-7]{2}))(?:[^0-8]|$)": @(kSpecialCharacterTwoDigitOctal),
           @"^(([0-7]))(?:[^0-8]|$)": @(kSpecialCharacterOneDigitOctal),
           @"^(x([0-9a-fA-F]{2}))": @(kSpecialCharacterTwoDigitHex),
           @"^(x([0-9a-fA-F]))(?:[^0-9a-fA-F]|$)": @(kSpecialCharacterOneDigitHex),
           @"^(u([0-9a-fA-F]{4}))": @(kSpecialCharacterFourDigitUnicode),
           @"^(b)": @(kSpecialCharacterBackspace),
           @"^(e)": @(kSpecialCharacterEscape),
           @"^(f)": @(kSpecialCharacterFormFeed),
           @"^(n)": @(kSpecialCharacterNewline),
           @"^(r)": @(kSpecialCharacterReturn),
           @"^(t)": @(kSpecialCharacterTab),
           @"^(\\\\)": @(kSpecialCharacterBackslash),
           @"^(\")": @(kSpecialCharacterDoubleQuote),
           @"^(<C-([A-Za-z])>)": @(kSpecialCharacterControlKey),
           @"^(<M-([A-Za-z])>)": @(kSpecialCharacterMetaKey) };
           

    NSMutableString *result = [NSMutableString string];
    __block int haveAppendedUpToIndex = 0;
    NSUInteger index = [self indexOfSubstring:@"\\" fromIndex:0];
    while (index != NSNotFound && index < self.length) {
        [result appendString:[self substringWithRange:NSMakeRange(haveAppendedUpToIndex,
                                                                  index - haveAppendedUpToIndex)]];
        haveAppendedUpToIndex = index + 1;
        NSString *fragment = [self substringFromIndex:haveAppendedUpToIndex];
        BOOL foundMatch = NO;
        for (NSString *regex in regexes) {
            NSRange regexRange = [fragment rangeOfRegex:regex];
            if (regexRange.location != NSNotFound) {
                foundMatch = YES;
                NSArray *capture = [fragment captureComponentsMatchedByRegex:regex];
                index += [capture[1] length] + 1;
                // capture[0]: The whole match
                // capture[1]: Characters to consume
                // capture[2]: Optional. Characters of interest.
                switch ([regexes[regex] intValue]) {
                    case kSpecialCharacterThreeDigitOctal:
                    case kSpecialCharacterTwoDigitOctal:
                    case kSpecialCharacterOneDigitOctal:
                        [result appendString:[capture[2] octalCharacter]];
                        break;
                        
                    case kSpecialCharacterFourDigitUnicode:
                    case kSpecialCharacterTwoDigitHex:
                    case kSpecialCharacterOneDigitHex:
                        [result appendString:[capture[2] hexCharacter]];
                        break;
                        
                    case kSpecialCharacterBackspace:
                        [result appendFormat:@"%c", 0x7f];
                        break;
                        
                    case kSpecialCharacterEscape:
                        [result appendFormat:@"%c", 27];
                        break;
                        
                    case kSpecialCharacterFormFeed:
                        [result appendFormat:@"%c", 12];
                        break;
                        
                    case kSpecialCharacterNewline:
                        [result appendString:@"\n"];
                        break;
                        
                    case kSpecialCharacterReturn:
                        [result appendString:@"\r"];
                        break;
                        
                    case kSpecialCharacterTab:
                        [result appendString:@"\t"];
                        break;
                        
                    case kSpecialCharacterBackslash:
                        [result appendString:@"\\"];
                        break;
                        
                    case kSpecialCharacterDoubleQuote:
                        [result appendString:@"\""];
                        break;
                        
                    case kSpecialCharacterControlKey:
                        [result appendString:[capture[2] controlCharacter]];
                        break;
                        
                    case kSpecialCharacterMetaKey:
                        [result appendString:[capture[2] metaCharacter]];
                        break;
                }
                haveAppendedUpToIndex = index;
                break;
            }  // If a regex matched
        }  // for loop over regexes
        if (!foundMatch) {
            ++index;
        }
        index = [self indexOfSubstring:@"\\" fromIndex:index];
    }  // while searching for backslashes
    
    index = self.length;
    [result appendString:[self substringWithRange:NSMakeRange(haveAppendedUpToIndex,
                                                              index - haveAppendedUpToIndex)]];

    return result;
}

- (CGFloat)heightWithAttributes:(NSDictionary *)attributes constrainedToWidth:(CGFloat)maxWidth {
    NSAttributedString *attributedString =
        [[[NSAttributedString alloc] initWithString:self attributes:attributes] autorelease];
    if (![self length]) {
        return 0;
    }

    NSSize size = NSMakeSize(maxWidth, FLT_MAX);
    NSTextContainer *textContainer =
        [[[NSTextContainer alloc] initWithContainerSize:size] autorelease];
    NSTextStorage *textStorage =
        [[[NSTextStorage alloc] initWithAttributedString:attributedString] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];

    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    [layoutManager setHyphenationFactor:0.0];
    
    // Force layout.
    [layoutManager glyphRangeForTextContainer:textContainer];
    
    // Don't count space added for insertion point.
    CGFloat height =
        [layoutManager usedRectForTextContainer:textContainer].size.height;
    const CGFloat extraLineFragmentHeight =
        [layoutManager extraLineFragmentRect].size.height;
    height -= MAX(0, extraLineFragmentHeight);

    return height;
}

- (NSArray *)keyValuePair {
    NSRange range = [self rangeOfString:@"="];
    if (range.location == NSNotFound) {
        return @[ self, @"" ];
    } else {
        return @[ [self substringToIndex:range.location],
                  [self substringFromIndex:range.location + 1] ];
    }
}

// Replace substrings like \(foo) or \1...\9 with the value of vars[@"foo"] or vars[@"1"].
- (NSString *)stringByReplacingVariableReferencesWithVariables:(NSDictionary *)vars {
    unichar *chars = (unichar *)malloc(self.length * sizeof(unichar));
    [self getCharacters:chars];
    enum {
        kLiteral,
        kEscaped,
        kInParens
    } state = kLiteral;
    NSMutableString *result = [NSMutableString string];
    NSMutableString *varName = nil;
    for (int i = 0; i < self.length; i++) {
        unichar c = chars[i];
        switch (state) {
            case kLiteral:
                if (c == '\\') {
                    state = kEscaped;
                } else {
                    [result appendFormat:@"%C", c];
                }
                break;

            case kEscaped:
                if (c == '(') {
                    state = kInParens;
                    varName = [NSMutableString string];
                } else {
                    // \1...\9 also work as subs.
                    NSString *singleCharVar = [NSString stringWithFormat:@"%C", c];
                    if (singleCharVar.integerValue > 0 && vars[singleCharVar]) {
                        [result appendString:vars[singleCharVar]];
                    } else {
                        [result appendFormat:@"\\%C", c];
                    }
                    state = kLiteral;
                }
                break;

            case kInParens:
                if (c == ')') {
                    state = kLiteral;
                    NSString *value = vars[varName];
                    if (value) {
                        [result appendString:value];
                    }
                } else {
                    [varName appendFormat:@"%C", c];
                }
                break;
        }
    }
    free(chars);
    return result;
}

- (BOOL)containsString:(NSString *)substring {
    return [self rangeOfString:substring].location != NSNotFound;
}

- (NSString *)stringRepeatedTimes:(int)n {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        [result appendString:self];
    }
    return result;
}

- (NSUInteger)numberOfLines {
    NSUInteger stringLength = [self length];
    NSUInteger numberOfLines = 0;
    for (NSUInteger index = 0; index < stringLength; numberOfLines++) {
        index = NSMaxRange([self lineRangeForRange:NSMakeRange(index, 0)]);
    }
    return numberOfLines;
}

- (NSString *)ellipsizedDescriptionNoLongerThan:(int)maxLength {
    NSString *noNewlineSelf = [self stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (noNewlineSelf.length <= maxLength) {
        return noNewlineSelf;
    }
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange firstNonWhitespaceRange = [noNewlineSelf rangeOfCharacterFromSet:[whitespace invertedSet]];
    if (firstNonWhitespaceRange.location == NSNotFound) {
        return @"";
    }
    int length = noNewlineSelf.length - firstNonWhitespaceRange.location;
    if (length < maxLength) {
        return [noNewlineSelf substringFromIndex:firstNonWhitespaceRange.location];
    } else {
        NSString *prefix = [noNewlineSelf substringWithRange:NSMakeRange(firstNonWhitespaceRange.location, maxLength - 1)];
        return [prefix stringByAppendingString:@"…"];
    }
}

- (NSString *)stringWithFirstLetterCapitalized {
    if (self.length == 0) {
        return self;
    }
    if (self.length == 1) {
        return [self uppercaseString];
    }
    return [[[self substringToIndex:1] uppercaseString] stringByAppendingString:[self substringFromIndex:1]];
}

+ (NSString *)stringForModifiersWithMask:(NSUInteger)keyMods {
    NSMutableString *theKeyString = [NSMutableString string];
    if (keyMods & NSControlKeyMask) {
        [theKeyString appendString: @"^"];
    }
    if (keyMods & NSAlternateKeyMask) {
        [theKeyString appendString: @"⌥"];
    }
    if (keyMods & NSShiftKeyMask) {
        [theKeyString appendString: @"⇧"];
    }
    if (keyMods & NSCommandKeyMask) {
        [theKeyString appendString: @"⌘"];
    }
    return theKeyString;
}

+ (NSString *)uuid {
    CFUUIDRef uuidObj = CFUUIDCreate(nil);
    NSString *uuidString = (NSString *)CFUUIDCreateString(nil, uuidObj);
    CFRelease(uuidObj);
    return [uuidString autorelease];
}

- (NSString *)stringByReplacingControlCharsWithQuestionMark {
    return [self stringByReplacingOccurrencesOfRegex:@"[\x00-\x1f\x7f]" withString:@"?"];
}

@end

@implementation NSMutableString (iTerm)

- (void)trimTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:nonWhitespaceSet
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        [self deleteCharactersInRange:NSMakeRange(0, self.length)];
    } else if (rangeOfLastWantedCharacter.location < self.length - 1) {
        NSUInteger i = rangeOfLastWantedCharacter.location + 1;
        [self deleteCharactersInRange:NSMakeRange(i, self.length - i)];
    }
}

- (void)escapeShellCharacters {
    NSString* charsToEscape = [NSString shellEscapableCharacters];
    for (int i = 0; i < [charsToEscape length]; i++) {
        NSString* before = [charsToEscape substringWithRange:NSMakeRange(i, 1)];
        NSString* after = [@"\\" stringByAppendingString:before];
        [self replaceOccurrencesOfString:before
                              withString:after
                                 options:0
                                   range:NSMakeRange(0, [self length])];
    }
}

@end
