//
//  EPSystemFontReader.m
//  
//
//  Created by EXphinx on 13-11-5.
//
//

#import "EPSystemFontReader.h"
#import <QuartzCore/QuartzCore.h>

@implementation EPSystemFontReader

+ (BOOL)writeFontDataWithName:(NSString *)fontName toFolder:(NSString *)folder fileName:(NSString *)fileName {
    
    CGFontRef cgFont = CGFontCreateWithFontName((__bridge CFStringRef)fontName);
    
    if (!cgFont) {
        return NO;
    }
    
    BOOL hasCFFTable;
    NSData *fontData = [self fontDataForCGFont:cgFont hasCFFTable:&hasCFFTable];
    NSString *destinationFileName = fileName ? [fileName stringByDeletingPathExtension] : fontName;
    destinationFileName = [destinationFileName stringByAppendingPathExtension:hasCFFTable ? @"otf" : @"ttf"];
    NSString *filePath = [folder stringByAppendingPathComponent:destinationFileName];
    CGFontRelease(cgFont);
    
    return [fontData writeToFile:filePath atomically:YES];
}

#pragma mark -
#pragma mark Internal

typedef struct EPCGFont_Convert_FontHeader {
    int32_t fVersion;
    uint16_t fNumTables;
    uint16_t fSearchRange;
    uint16_t fEntrySelector;
    uint16_t fRangeShift;
}EPCGFont_Convert_FontHeader;

typedef struct EPCGFont_Convert_TableEntry {
    uint32_t fTag;
    uint32_t fCheckSum;
    uint32_t fOffset;
    uint32_t fLength;
}EPCGFont_Convert_TableEntry;

static uint32_t CalcTableCheckSum(const uint32_t *table, uint32_t numberOfBytesInTable) {
    uint32_t sum = 0;
    uint32_t nLongs = (numberOfBytesInTable + 3) / 4;
    while (nLongs-- > 0) {
        sum += CFSwapInt32HostToBig(*table++);
    }
    return sum;
}

static uint32_t CalcTableDataRefCheckSum(CFDataRef dataRef) {
    const uint32_t *dataBuff = (const uint32_t *)CFDataGetBytePtr(dataRef);
    uint32_t dataLength = (uint32_t)CFDataGetLength(dataRef);
    return CalcTableCheckSum(dataBuff, dataLength);
}

// TrueType Tables Need "Big Endian"
//http://skia.googlecode.com/svn-history/r1473/trunk/src/ports/SkFontHost_mac_coretext.cpp
//SkStream* SkFontHost::OpenStream(SkFontID uniqueID)

+ (NSData *)fontDataForCGFont:(CGFontRef)cgFont hasCFFTable:(BOOL *)hasCFFTable {
    
    if (!cgFont) {
        return nil;
    }
    // get table tags
    CFRetain(cgFont);
    
    CFArrayRef tags = CGFontCopyTableTags(cgFont);
    int tableCount = CFArrayGetCount(tags);
    
    size_t *tableSizes = malloc(sizeof(size_t) * tableCount);
    memset(tableSizes, 0, sizeof(size_t) * tableCount);
    
    BOOL cffTable = NO;
    
    // calc total size for font, save sizes
    size_t totalSize = sizeof(EPCGFont_Convert_FontHeader) + sizeof(EPCGFont_Convert_TableEntry) * tableCount;
    
    for (int index = 0; index < tableCount; ++index) {
        
        //get size
        size_t tableSize = 0;
        uint32_t aTag = (uint32_t)CFArrayGetValueAtIndex(tags, index);
        
        if (aTag == 'CFF ' && !cffTable) {
            cffTable = YES;
        }
        
        CFDataRef tableDataRef = CGFontCopyTableForTag(cgFont, aTag);
        if (tableDataRef != NULL) {
            tableSize = CFDataGetLength(tableDataRef);
            CFRelease(tableDataRef);
        }
        totalSize += (tableSize + 3) & ~3;
        
        tableSizes[index] = tableSize;
    }
    
    unsigned char *stream = malloc(totalSize);
    
    memset(stream, 0, totalSize);
    char* dataStart = (char*)stream;
    char* dataPtr = dataStart;
    
    // compute font header entries
    uint16_t entrySelector = 0;
    uint16_t searchRange = 1;
    
    while (searchRange < tableCount >> 1) {
        entrySelector++;
        searchRange <<= 1;
    }
    searchRange <<= 4;
    
    uint16_t rangeShift = (tableCount << 4) - searchRange;
    
    EPCGFont_Convert_FontHeader* offsetTable = (EPCGFont_Convert_FontHeader*)dataPtr;

    offsetTable->fVersion = cffTable ? 'OTTO' : CFSwapInt16HostToBig(1);
    offsetTable->fNumTables = CFSwapInt16HostToBig((uint16_t)tableCount);
    offsetTable->fSearchRange = CFSwapInt16HostToBig((uint16_t)searchRange);
    offsetTable->fEntrySelector = CFSwapInt16HostToBig((uint16_t)entrySelector);
    offsetTable->fRangeShift = CFSwapInt16HostToBig((uint16_t)rangeShift);

    dataPtr += sizeof(EPCGFont_Convert_FontHeader);
    
    EPCGFont_Convert_TableEntry* entry = (EPCGFont_Convert_TableEntry*)dataPtr;
    dataPtr += sizeof(EPCGFont_Convert_TableEntry) * tableCount;
    
    for (int index = 0; index < tableCount; ++index) {
        
        uint32_t aTag = (uint32_t)CFArrayGetValueAtIndex(tags, index);
        CFDataRef tableDataRef = CGFontCopyTableForTag(cgFont, aTag);
        size_t tableSize = CFDataGetLength(tableDataRef);
        
        memcpy(dataPtr, CFDataGetBytePtr(tableDataRef), tableSize);
        
        entry->fTag = CFSwapInt32HostToBig((uint32_t)aTag);
        entry->fCheckSum = CFSwapInt32HostToBig(CalcTableCheckSum((uint32_t *)dataPtr, tableSize));
        
        uint32_t offset = dataPtr - dataStart;
        entry->fOffset = CFSwapInt32HostToBig((uint32_t)offset);
        entry->fLength = CFSwapInt32HostToBig((uint32_t)tableSize);
        dataPtr += (tableSize + 3) & ~3;
        ++entry;
        CFRelease(tableDataRef);
    }
    
    CFRelease(cgFont);
    free(tableSizes);
    NSData *fontData = [NSData dataWithBytesNoCopy:stream
                                            length:totalSize
                                      freeWhenDone:YES];
    
    *hasCFFTable = cffTable;
    
    return fontData;
}

@end
