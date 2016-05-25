//
//  KBPlayerTests.m
//  KBPlayerTests
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <pthread.h>
#import <sys/time.h>


@interface KBPlayerTests : XCTestCase

@end

@implementation KBPlayerTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    
    pthread_cond_t cond;
    pthread_mutex_t mutex;
    
    pthread_cond_init(&cond, NULL);
    pthread_mutex_init(&mutex, NULL);
    
    struct timeval now;
    struct timespec outtime;
    gettimeofday(&now, NULL);
    
    outtime.tv_sec = now.tv_sec + 5;
    outtime.tv_nsec = now.tv_usec * 1000;
    
    NSLog(@"=========test1=============");
    
    pthread_cond_timedwait(&cond, &mutex, &outtime);
    
    NSLog(@"=========test2=============");

    
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
