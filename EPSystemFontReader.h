//
//  EPSystemFontReader.h
//  
//
//  Created by EXphinx on 13-11-5.
//
//

#import <Foundation/Foundation.h>

@interface EPSystemFontReader : NSObject

+ (BOOL)writeFontDataWithName:(NSString *)fontName toFolder:(NSString *)folder fileName:(NSString *)fileName;

@end
