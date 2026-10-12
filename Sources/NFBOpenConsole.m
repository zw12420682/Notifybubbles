#import "NFBOpenConsole.h"
#import "NFBOpenConsolePolicy.h"
#import "NFBDebugLog.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
BOOL NFBOpenNativeConsole(void) {
    if (!NSThread.isMainThread || !NSClassFromString(@"TOJBConsolePanelView")) return NO;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const struct mach_header *image = _dyld_get_image_header(index);
        if (!image || image->magic != MH_MAGIC_64 || image->cputype != CPU_TYPE_ARM64) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)image;
        if (header->sizeofcmds > 1024 * 1024 || header->ncmds > 1024) continue;
        const uint8_t *cursor = (const uint8_t *)(header + 1), *end = cursor + header->sizeofcmds;
        const uint8_t *uuid = NULL;
        const struct segment_command_64 *text = NULL;
        for (uint32_t command = 0; command < header->ncmds; command++) {
            if ((size_t)(end-cursor) < sizeof(struct load_command)) break;
            const struct load_command *load = (const struct load_command *)cursor;
            if (load->cmdsize < sizeof(*load) || load->cmdsize > (size_t)(end-cursor)) break;
            if (load->cmd == LC_UUID && load->cmdsize >= sizeof(struct uuid_command)) uuid = ((const struct uuid_command *)load)->uuid;
            if (load->cmd == LC_SEGMENT_64 && load->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)load;
                if (!strncmp(segment->segname,"__TEXT",16) && (segment->initprot & VM_PROT_EXECUTE)) text = segment;
            }
            cursor += load->cmdsize;
        }
        const NFBConsoleTarget *target = NFBConsoleTargetForImage(header->cputype,header->cpusubtype,uuid);
        if (!target || !text || target->address < text->vmaddr || target->address-text->vmaddr > text->vmsize || text->vmsize-(target->address-text->vmaddr) < sizeof(target->code)) continue;
        void *entry = (void *)((uintptr_t)header + target->address - text->vmaddr);
        if (!NFBConsoleCodeMatches(target,entry)) continue;
#if __has_feature(ptrauth_calls)
        entry = ptrauth_sign_unauthenticated(entry,ptrauth_key_function_pointer,0);
#endif
        @try {
            // The verified void(void) dispatcher queues Open's original console
            // presentation block on the main queue; it owns all panel actions.
            ((void (*)(void))entry)();
            return YES;
        } @catch (NSException *error) { NFBErrorLog(@"Open console failed: %@",error); return NO; }
    }
    return NO;
}
