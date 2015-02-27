//
//  VT100DCSParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

typedef enum {
    kDcsTermcapTerminfoRequestUnrecognizedName,
    kDcsTermcapTerminfoRequestTerminalName,
    kDcsTermcapTerminfoRequestiTerm2ProfileName,
    kDcsTermcapTerminfoRequestTerminfoName
} DcsTermcapTerminfoRequestName;

NS_INLINE BOOL isDCS(unsigned char *code, int len) {
    return (len >= 2 && code[0] == VT100CC_ESC && code[1] == 'P');
}


@interface VT100DCSParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result
           encoding:(NSStringEncoding)encoding;

+ (NSDictionary *)termcapTerminfoNameDictionary;  // string name -> DcsTermcapTerminfoRequestName
+ (NSDictionary *)termcapTerminfoInverseNameDictionary;  // DcsTermcapTerminfoRequestName -> string name

@end

