//
//  main.m
//  cocoa-string-size-performance
//
//  Created by Abhi on 5/29/15.
//  Copyright (c) 2015 ___Abhishek Moothedath___. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define ITEMS_COUNT 1000
#define ITEMS_ARRAY_CHUNK_THRESHOLD 10000

typedef CGFloat (^TestBlock)(void);

static void runTest(NSString *description, TestBlock block) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    CGFloat answer = block();
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    printf("%30s: %3.0f usec per string; answer = %.6f\n", description.UTF8String, 1000000.0 * (endTime - startTime) / ITEMS_COUNT, answer);
}

static void test_sizeWithAttributes(NSArray *testStrings) {
    runTest(@"sizeWithAttributes", ^{
        double width = 0;
        for(NSString *string in testStrings) {
            width = MAX(width, [string sizeWithAttributes:nil].width);
        }
        return width;
    });
}

static void test_NSAttributedString(NSArray* testStrings) {
    runTest(@"NSAttributedString", ^{
        double width = 0;
        for(NSString *item in testStrings) {
            NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:item];
            width = MAX(width, attributedString.size.width);
        }
        return width;
    });
}

static void test_NSLayoutManager(NSArray* testStrings) {
    runTest(@"NSLayoutManager", ^{
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

static void test_NSLayoutManager_chunked(NSArray* testStrings) {
    runTest(@"NSLayoutManager_chunked", ^{
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

static NSArray *newTestStrings(void) {
    NSMutableArray *strings = [NSMutableArray new];
    for(NSUInteger i = 0; i < ITEMS_COUNT; i++)
    {
        double random = (double)arc4random_uniform(1000) / 1000;
        NSString *randomNumber = [NSString stringWithFormat:@"%f", random];
        [strings addObject:randomNumber];
    }
    return strings;
}

int main(int argc, const char * argv[])
{
    NSArray *testStrings = newTestStrings();
    test_sizeWithAttributes(testStrings);
    test_NSAttributedString(testStrings);
    test_NSLayoutManager(testStrings);
    test_NSLayoutManager_chunked(testStrings);
    
    return 0;
}
