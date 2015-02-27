//
//  VT100XtermParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "iTermParser.h"
#import "CVector.h"
#import "VT100Token.h"

NS_INLINE BOOL isXTERM(unsigned char *code, int len) {
    return (len >= 2 && code[0] == VT100CC_ESC && (code[1] == ']'));
}

@interface VT100XtermParser : NSObject

+ (void)decodeFromContext:(iTermParserContext *)context
              incidentals:(CVector *)incidentals
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState;

@end
