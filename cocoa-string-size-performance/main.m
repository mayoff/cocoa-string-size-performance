//
//  main.m
//  cocoa-string-size-performance
//
//  Created by Abhi on 5/29/15.
//  Copyright (c) 2015 ___Abhishek Moothedath___. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

#define ITEMS_COUNT 1000000
#define ITEMS_ARRAY_CHUNK_THRESHOLD 10000

typedef CGFloat (^TestBlock)(void);

static void runTest(const char *name, TestBlock block) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    CGFloat answer = block();
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    printf("%07.0f (%.6f) %s\n", 1000000000.0 * (endTime - startTime) / ITEMS_COUNT, answer, name);
}

static NSArray *testStrings;
static CTFontRef font;

static void test_sizeWithAttributes() {
    @autoreleasepool {
        runTest(__func__, ^{
            double width = 0;
            for(NSString *string in testStrings) {
                width = MAX(width, [string sizeWithAttributes:nil].width);
            }
            return width;
        });
    }
}

static void test_NSAttributedString() {
    runTest(__func__, ^{
        double width = 0;
        for(NSString *item in testStrings) {
            NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:item];
            width = MAX(width, attributedString.size.width);
        }
        return width;
    });
}

static void test_NSLayoutManager() {
    runTest(__func__, ^{
        NSLayoutManager *layoutManager = [NSLayoutManager new];
        NSTextContainer *textContainer = [NSTextContainer new];
        [textContainer setLineFragmentPadding:0];
        [layoutManager addTextContainer:textContainer];

        NSMutableArray *textStorageObjects = [NSMutableArray new];
        for(NSString *item in testStrings) {
            @autoreleasepool {
                NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:item];
                [textStorage addLayoutManager:layoutManager];
                [textStorageObjects addObject:textStorage];
            }
        }
        [layoutManager glyphRangeForTextContainer:textContainer];
        double width = [layoutManager usedRectForTextContainer:textContainer].size.width;
        return width;
    });
}

static void test_NSLayoutManager_singleStorage() {
    runTest(__func__, ^{
        NSLayoutManager *layoutManager = [NSLayoutManager new];
        NSTextContainer *textContainer = [NSTextContainer new];
        [textContainer setLineFragmentPadding:0];
        [layoutManager addTextContainer:textContainer];

        NSMutableString *bigString = [NSMutableString string];
        for(NSString *string in testStrings) {
            [bigString appendString:string];
            [bigString appendString:@"\n"];
        }

        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:bigString];
        [storage addLayoutManager:layoutManager];
        [layoutManager glyphRangeForTextContainer:textContainer];
        double width = [layoutManager usedRectForTextContainer:textContainer].size.width;
        return width;
    });
}

static void test_NSLayoutManager_oneStringAtATime() {
    runTest(__func__, ^{
        NSLayoutManager *layoutManager = [NSLayoutManager new];
        NSTextContainer *textContainer = [NSTextContainer new];
        [textContainer setLineFragmentPadding:0];
        [layoutManager addTextContainer:textContainer];
        NSTextStorage *storage = [[NSTextStorage alloc] init];
        [storage addLayoutManager:layoutManager];

        double width = 0;
        for (NSString *string in testStrings) {
            [storage.mutableString setString:string];
            [layoutManager glyphRangeForTextContainer:textContainer];
            width = MAX(width, [layoutManager usedRectForTextContainer:textContainer].size.width);
        }

        return width;
    });
}

static void test_NSLayoutManager_chunked() {
    runTest(__func__, ^{
        NSMutableArray *chunks = [NSMutableArray new];

        for(NSUInteger i = 0; i < testStrings.count; i++) {
            NSUInteger chunkIndex = i / ITEMS_ARRAY_CHUNK_THRESHOLD;
            if(chunks.count <= chunkIndex)
            {
                NSMutableArray *chunk = [NSMutableArray new];
                [chunks addObject:chunk];
            }
            NSMutableArray *chunk = [chunks objectAtIndex:chunkIndex];
            [chunk addObject:[testStrings objectAtIndex:i]];
        }

        double width = 0;

        NSLayoutManager *layoutManager = [NSLayoutManager new];
        NSTextContainer *textContainer = [NSTextContainer new];
        NSTextStorage *textStorage = [NSTextStorage new];
        [textStorage addLayoutManager:layoutManager];

        [textContainer setLineFragmentPadding:0];
        [layoutManager addTextContainer:textContainer];

        for(NSArray *chunk in chunks)
        {
            for(NSString *item in chunk)
            {
                [textStorage replaceCharactersInRange:NSMakeRange(0, textStorage.length) withString:item];
                [layoutManager glyphRangeForTextContainer:textContainer];
                width = MAX(width,[layoutManager usedRectForTextContainer:textContainer].size.width);
            }
        }
        return width;
    });
}

static CGFloat maxWidthOfStringsUsingCTLine(NSArray *strings, NSRange range) {
    CFMutableAttributedStringRef richText = CFAttributedStringCreateMutable(NULL, 0);
    CFIndex priorStringLength = 0;
    CGFloat width = 0.0;
    for (NSString *string in [testStrings subarrayWithRange:range]) {
        CFAttributedStringReplaceString(richText, CFRangeMake(0, priorStringLength), (__bridge CFStringRef)string);
        priorStringLength = string.length;
        CFAttributedStringSetAttribute(richText, CFRangeMake(0, priorStringLength), kCTFontAttributeName, font);
        CTLineRef line = CTLineCreateWithAttributedString(richText);
        width = MAX(width, CTLineGetTypographicBounds(line, NULL, NULL, NULL));
        CFRelease(line);
    }
    CFRelease(richText);
    return (CGFloat)width;
}

static void test_CTLine() {
    runTest(__func__, ^{
        return maxWidthOfStringsUsingCTLine(testStrings, NSMakeRange(0, testStrings.count));
    });
}

static void test_CTLine_dispatched() {
    runTest(__func__, ^{
        dispatch_queue_t gatherQueue = dispatch_queue_create("test_CTLine_dispatched result-gathering queue", nil);
        dispatch_queue_t runQueue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
        dispatch_group_t group = dispatch_group_create();

        __block CGFloat gatheredWidth = 0.0;

        const size_t Parallelism = 4;
        const size_t totalCount = testStrings.count;
        // Force unsigned long to get 64-bit math to avoid overflow for large totalCounts.
        for (unsigned long i = 0; i < Parallelism; ++i) {
            NSUInteger start = (totalCount * i) / Parallelism;
            NSUInteger end = (totalCount * (i + 1)) / Parallelism;
            NSRange range = NSMakeRange(start, end - start);
            dispatch_group_async(group, runQueue, ^{
                double width = maxWidthOfStringsUsingCTLine(testStrings, range);
                dispatch_sync(gatherQueue, ^{
                    gatheredWidth = MAX(gatheredWidth, width);
                });
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        return gatheredWidth;
    });
}

static CGFloat maxWidthOfStringsUsingCTFramesetter(NSArray *strings, NSRange range) {
    NSString *bigString = [[strings subarrayWithRange:range] componentsJoinedByString:@"\n"];
    NSAttributedString *richText = [[NSAttributedString alloc] initWithString:bigString attributes:@{ NSFontAttributeName: (__bridge NSFont *)font }];
    CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, CGFLOAT_MAX, CGFLOAT_MAX), NULL);
    CGFloat width = 0.0;
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)richText);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, bigString.length), path, NULL);
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(frame);
    for (id item in lines) {
        CTLineRef line = (__bridge CTLineRef)item;
        width = MAX(width, CTLineGetTypographicBounds(line, NULL, NULL, NULL));
    }
    CFRelease(frame);
    CFRelease(setter);
    CFRelease(path);
    return (CGFloat)width;
}

static void test_CTFramesetter() {
    runTest(__func__, ^{
        return maxWidthOfStringsUsingCTFramesetter(testStrings, NSMakeRange(0, testStrings.count));
    });
}

static void test_CTFramesetter_dispatched() {
    runTest(__func__, ^{
        dispatch_queue_t gatherQueue = dispatch_queue_create("test_CTFramesetter_dispatched result-gathering queue", nil);
        dispatch_queue_t runQueue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
        dispatch_group_t group = dispatch_group_create();

        __block CGFloat gatheredWidth = 0.0;

        const size_t Parallelism = 16;
        const size_t totalCount = testStrings.count;
        // Force unsigned long to get 64-bit math to avoid overflow for large totalCounts.
        for (unsigned long i = 0; i < Parallelism; ++i) {
            NSUInteger start = (totalCount * i) / Parallelism;
            NSUInteger end = (totalCount * (i + 1)) / Parallelism;
            NSRange range = NSMakeRange(start, end - start);
            dispatch_group_async(group, runQueue, ^{
                double width = maxWidthOfStringsUsingCTFramesetter(testStrings, range);
                dispatch_sync(gatherQueue, ^{
                    gatheredWidth = MAX(gatheredWidth, width);
                });
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        return gatheredWidth;
    });
}

static void initTestStrings(void) {
    NSMutableArray *strings = [NSMutableArray new];
    for(NSUInteger i = 0; i < ITEMS_COUNT; i++)
    {
        double random = (double)arc4random_uniform(1000) / 1000;
        NSString *randomNumber = [NSString stringWithFormat:@"%f", random];
        [strings addObject:randomNumber];
    }
    testStrings = [strings copy];
}

int main(int argc, const char * argv[])
{
    initTestStrings();
    font = (__bridge CTFontRef)[NSFont fontWithName:@"Helvetica" size:12];

    test_CTFramesetter();
    test_CTFramesetter_dispatched();
    test_CTLine();
//    test_CTLine_dispatched();
//    test_NSLayoutManager();
#if 0
    test_sizeWithAttributes();
    test_NSAttributedString();
    test_NSLayoutManager_chunked();
    test_NSLayoutManager_singleStorage();
    test_NSLayoutManager_oneStringAtATime();
#endif

    return 0;
}
