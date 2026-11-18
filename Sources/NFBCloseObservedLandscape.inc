BOOL NFBCloseObservedLandscape(UIView *target) {
    if (!NSThread.isMainThread || !target || !visibleView(target) || !movieLandscape(target) ||
        boolStateOf(target,@"miniWindowModeEnabled")!=0 || boolStateOf(target,@"isClosingWithKeepAliveAnimation")==1) return NO;
    @try {
        SEL close=NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
        NSMethodSignature *sig=NFBSignature(target,close);
        if (sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(void))) return NO;
        ((void (*)(id,SEL))objc_msgSend)(target,close);
        NFBInvalidateWindowState(); movieDesktopAttempted=YES; movieReadAt=0;
        NFBDebugLog(@"movie-exit: closed exact upper landscape app=%@ view=%p",appOfWindow(target),target);
        return YES;
    } @catch (NSException *error) { NFBDebugLog(@"movie-exit: landscape close failed %@",error); return NO; }
}
