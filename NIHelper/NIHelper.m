// Runs inside /usr/bin/perl (loaded via DynaLoader). Since macOS 15.4 MediaRemote only
// answers Apple-signed processes, so the app hosts this bridge in the system perl.
// Protocol: one JSON object per line on stdout; commands on stdin
// (play, pause, toggle, next, prev, seek <seconds>). EOF on stdin exits.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetBoolFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef BOOL (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn getInfo;
static MRGetBoolFn getPlaying;
static MRGetPIDFn getPID;
static MRSendCommandFn sendCommand;
static MRSetElapsedFn setElapsed;
static dispatch_queue_t queue;
static NSUInteger lastArtKey = NSUIntegerMax;
static BOOL pending;

static id orEmpty(id value, id fallback) { return value ?: fallback; }

static void emitNow(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getPlaying(queue, ^(BOOL playing) {
            getPID(queue, ^(int pid) {
                NSMutableDictionary *o = [NSMutableDictionary dictionary];
                o[@"title"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoTitle"], @"");
                o[@"artist"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoArtist"], @"");
                o[@"album"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoAlbum"], @"");
                o[@"duration"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoDuration"], @0);
                o[@"elapsed"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"], @0);
                o[@"rate"] = orEmpty(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"], @0);
                NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                o[@"timestamp"] = @([ts isKindOfClass:NSDate.class] ? ts.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970);
                o[@"playing"] = @(playing);
                o[@"pid"] = @(pid);
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if (![art isKindOfClass:NSData.class]) art = nil;
                NSUInteger key = art ? art.length * 31 + art.hash : 0;
                if (key != lastArtKey) {
                    lastArtKey = key;
                    o[@"art"] = art ? [art base64EncodedStringWithOptions:0] : @"";
                }
                NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    fflush(stdout);
                }
            });
        });
    });
}

static void scheduleEmit(double delay) {
    dispatch_async(queue, ^{
        if (pending) return;
        pending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, ^{
            pending = NO;
            emitNow();
        });
    });
}

static void readCommands(void) {
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!strcmp(line, "play")) sendCommand(0, nil);
        else if (!strcmp(line, "pause")) sendCommand(1, nil);
        else if (!strcmp(line, "toggle")) sendCommand(2, nil);
        else if (!strcmp(line, "next")) sendCommand(4, nil);
        else if (!strcmp(line, "prev")) sendCommand(5, nil);
        else if (!strncmp(line, "seek ", 5)) setElapsed(atof(line + 5));
        scheduleEmit(0.3);
    }
    exit(0); // the app went away
}

void ni_run(void *interp, void *cv) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "MediaRemote missing\n"); exit(1); }
    getInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = (MRGetBoolFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (MRGetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    MRRegisterFn reg = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getPlaying || !getPID || !sendCommand || !setElapsed || !reg) { fprintf(stderr, "MediaRemote symbols missing\n"); exit(1); }

    queue = dispatch_queue_create("ni.mediaremote", DISPATCH_QUEUE_SERIAL);
    reg(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
            scheduleEmit(0.05);
        }];
    }
    // Some players skip notifications on seek; a slow heartbeat keeps the clock honest.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ emitNow(); });
    dispatch_resume(timer);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ readCommands(); });
    CFRunLoopRun();
}
