//
//  NSImage+iTerm.m
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import "NSImage+iTerm.h"

@implementation NSImage (iTerm)

- (NSImage *)blurredImageWithRadius:(int)radius {
    // Initially, this used a CIFilter but this doesn't work on some machines for mysterious reasons.
    // Instead, this algorithm implements a really simple box blur. It's quite fast--about 5ms on
    // a macbook pro with radius 5 for a 48x48 image.

    NSImage *image = self;
    NSSize size = self.size;
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    for (int i = 0; i < radius; i++) {
        [image lockFocus];
        [self drawInRect:frame
                fromRect:frame
               operation:NSCompositeSourceOver
                fraction:1];
        [image unlockFocus];
        image = [self onePixelBoxBlurOfImage:image alpha:1.0/9.0];
    }
    return image;
}

- (NSImage *)onePixelBoxBlurOfImage:(NSImage *)image alpha:(CGFloat)alpha {
    NSSize size = image.size;
    NSImage *destination = [[NSImage alloc] initWithSize:image.size];
    [destination lockFocus];
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            [image drawInRect:NSMakeRect(dx,
                                         dy,
                                         size.width,
                                         size.height)
                     fromRect:NSMakeRect(0, 0, size.width, size.height)
                    operation:NSCompositeSourceOver
                     fraction:alpha];
        }
    }
    [destination unlockFocus];
    return destination;
}

- (CGContextRef)bitmapContextWithStorage:(NSMutableData *)data {
  NSSize size = self.size;
  NSInteger bytesPerRow = size.width * 4;
  NSUInteger storageNeeded = bytesPerRow * size.height;
  [data setLength:storageNeeded];

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate((void *)data.bytes,
                                               size.width,
                                               size.height,
                                               8,
                                               bytesPerRow,
                                               colorSpace,
                                               (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  if (!context) {
    return NULL;
  }

  CGColorSpaceRelease(colorSpace);

  return context;
}

- (NSImage *)imageWithColor:(NSColor *)color {
  NSSize size = self.size;
  NSRect rect = NSZeroRect;
  rect.size = size;

  // Create a bitmap context.
  NSMutableData *data = [NSMutableData data];
  CGContextRef context = [self bitmapContextWithStorage:data];

  // Draw myself into that context.
  CGContextDrawImage(context, rect, [self CGImageForProposedRect:NULL context:nil hints:nil]);

  // Now draw over it with |color|.
  CGContextSetFillColorWithColor(context, [color CGColor]);
  CGContextSetBlendMode(context, kCGBlendModeSourceAtop);
  CGContextFillRect(context, rect);

  // Extract the resulting image into the graphics context.
  CGImageRef image = CGBitmapContextCreateImage(context);

  // Convert to NSImage
  NSImage *coloredImage = [[[NSImage alloc] initWithCGImage:image size:size] autorelease];

  // Release memory.
  CGContextRelease(context);
  CGImageRelease(image);

  return coloredImage;
}

@end
