#import <Foundation/Foundation.h>
#import <notify.h>
#import "../Sources/NFBKeyboardSettingsWire.h"
#include <assert.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
int main(int argc,const char *argv[]) {
 @autoreleasepool {
  if (argc==4) {
   int token=-1; uint64_t value=0;
   assert(notify_register_check(argv[1],&token)==NOTIFY_STATUS_OK);
   assert(notify_get_state(token,&value)==NOTIFY_STATUS_OK);
   NFBKeyboardSettings received={0,0,0,0};
   assert(NFBKeyboardSettingsDecode(value,&received));
   BOOL enabled=strcmp(argv[2],"1")==0;
   double height=strtod(argv[3],NULL);
   assert(received.enabled==enabled && received.height==height);
   assert(received.globe==enabled && received.voice==enabled);
   notify_cancel(token); return 0;
  }
  NSString *channel=[NSString stringWithFormat:@"local.notifybubbles.test.keyboard.%d",getpid()];
  int writer=-1;
  assert(notify_register_check(channel.UTF8String,&writer)==NOTIFY_STATUS_OK);
  for (int enabled=1;enabled>=0;enabled--) {
   NFBKeyboardSettings settings={enabled,enabled,enabled,enabled ? 10.25 : 34};
   assert(notify_set_state(writer,NFBKeyboardSettingsEncode(settings))==NOTIFY_STATUS_OK);
   assert(notify_post(channel.UTF8String)==NOTIFY_STATUS_OK);
   NSTask *child=[NSTask new];
   child.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
   child.arguments=@[channel,enabled ? @"1" : @"0",enabled ? @"10.25" : @"34"];
   NSError *error=nil;
   assert([child launchAndReturnError:&error]);
   [child waitUntilExit]; assert(child.terminationStatus==0);
  }
  notify_cancel(writer);
  puts("PASS: a newly launched process receives current enabled and disabled keyboard snapshots");
 }
 return 0;
}
