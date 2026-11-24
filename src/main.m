#import <Cocoa/Cocoa.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#include "patch_data.h"

static NSString *getDefaultGamePath(void) {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@"Library/Application Support/Steam/steamapps/common/Lovers in a Dangerous Spacetime/LoversInADangerousSpacetime.app"];
}

static BOOL runCodesign(NSString *appPath, NSString **errorOut) {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/codesign"];
    [task setArguments:@[@"--force", @"--deep", @"-s", @"-", appPath]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *e) {
        if (errorOut) *errorOut = [e reason];
        return NO;
    }

    if ([task terminationStatus] != 0) {
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *outStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (errorOut) *errorOut = outStr;
        return NO;
    }
    return YES;
}

static BOOL patchMachoFile(NSString *machoPath, BOOL restore, NSString **errorOut) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:machoPath]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"File not found: %@", machoPath];
        return NO;
    }

    // Create backup if not present
    NSString *bakPath = [machoPath stringByAppendingString:@".bak"];
    if (![fm fileExistsAtPath:bakPath]) {
        [fm copyItemAtPath:machoPath toPath:bakPath error:nil];
    }

    NSMutableData *data = [NSMutableData dataWithContentsOfFile:machoPath];
    if (!data) {
        if (errorOut) *errorOut = @"Unable to read Mach-O binary";
        return NO;
    }

    uint8_t *bytes = (uint8_t *)[data mutableBytes];
    NSUInteger len = [data length];

    size_t sigB_len = sizeof(kMachoSigBefore);
    size_t sigA_len = sizeof(kMachoSigAfter);
    size_t pattern_len = sigB_len + 2 + sigA_len;

    uint8_t target_sig[pattern_len];
    memcpy(target_sig, kMachoSigBefore, sigB_len);
    if (restore) {
        target_sig[sigB_len] = 0x90;
        target_sig[sigB_len + 1] = 0x90;
    } else {
        target_sig[sigB_len] = 0xeb;
        target_sig[sigB_len + 1] = 0x07;
    }
    memcpy(target_sig + sigB_len + 2, kMachoSigAfter, sigA_len);

    uint8_t *found = memmem(bytes, len, target_sig, pattern_len);
    if (!found) {
        // Check if already in requested state
        uint8_t check_sig[pattern_len];
        memcpy(check_sig, kMachoSigBefore, sigB_len);
        if (restore) {
            check_sig[sigB_len] = 0xeb;
            check_sig[sigB_len + 1] = 0x07;
        } else {
            check_sig[sigB_len] = 0x90;
            check_sig[sigB_len + 1] = 0x90;
        }
        memcpy(check_sig + sigB_len + 2, kMachoSigAfter, sigA_len);
        if (memmem(bytes, len, check_sig, pattern_len)) {
            return YES; // Already done
        }
        if (errorOut) *errorOut = @"Mach-O signature pattern not found";
        return NO;
    }

    uint8_t *patch_ptr = found + sigB_len;
    if (restore) {
        patch_ptr[0] = 0xeb;
        patch_ptr[1] = 0x07;
    } else {
        patch_ptr[0] = 0x90;
        patch_ptr[1] = 0x90;
    }

    return [data writeToFile:machoPath atomically:YES];
}

static BOOL patchDllFile(NSString *dllPath, BOOL restore, NSString **errorOut) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dllPath]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"File not found: %@", dllPath];
        return NO;
    }

    // Create backup if not present
    NSString *bakPath = [dllPath stringByAppendingString:@".bak"];
    if (![fm fileExistsAtPath:bakPath]) {
        [fm copyItemAtPath:dllPath toPath:bakPath error:nil];
    }

    NSMutableData *data = [NSMutableData dataWithContentsOfFile:dllPath];
    if (!data) {
        if (errorOut) *errorOut = @"Unable to read Assembly-CSharp.dll";
        return NO;
    }

    uint8_t *bytes = (uint8_t *)[data mutableBytes];
    NSUInteger len = [data length];

    for (size_t i = 0; i < NUM_DLL_PATCHES; i++) {
        const DllPatchBlock *pb = &kDllPatches[i];
        if (pb->offset + pb->len > len) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"DLL patch offset 0x%zx out of bounds", pb->offset];
            return NO;
        }

        const uint8_t *expected = restore ? pb->patch : pb->orig;
        const uint8_t *replacement = restore ? pb->orig : pb->patch;

        if (memcmp(bytes + pb->offset, expected, pb->len) == 0) {
            memcpy(bytes + pb->offset, replacement, pb->len);
        } else if (memcmp(bytes + pb->offset, replacement, pb->len) == 0) {
            // Already in desired state
            continue;
        } else {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"DLL verification mismatch at offset 0x%zx", pb->offset];
            return NO;
        }
    }

    return [data writeToFile:dllPath atomically:YES];
}

static BOOL applyFix(NSString *appPath, NSString **errorOut) {
    NSString *macho = [appPath stringByAppendingPathComponent:@"Contents/MacOS/LoversInADangerousSpacetime"];
    NSString *dll = [appPath stringByAppendingPathComponent:@"Contents/Resources/Data/Managed/Assembly-CSharp.dll"];

    if (!patchMachoFile(macho, NO, errorOut)) return NO;
    if (!patchDllFile(dll, NO, errorOut)) return NO;
    if (!runCodesign(appPath, errorOut)) return NO;

    return YES;
}

static BOOL restoreOriginal(NSString *appPath, NSString **errorOut) {
    NSString *macho = [appPath stringByAppendingPathComponent:@"Contents/MacOS/LoversInADangerousSpacetime"];
    NSString *dll = [appPath stringByAppendingPathComponent:@"Contents/Resources/Data/Managed/Assembly-CSharp.dll"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *machoBak = [macho stringByAppendingString:@".bak"];
    NSString *dllBak = [dll stringByAppendingString:@".bak"];

    if ([fm fileExistsAtPath:machoBak]) {
        [fm removeItemAtPath:macho error:nil];
        [fm copyItemAtPath:machoBak toPath:macho error:nil];
    } else {
        if (!patchMachoFile(macho, YES, errorOut)) return NO;
    }

    if ([fm fileExistsAtPath:dllBak]) {
        [fm removeItemAtPath:dll error:nil];
        [fm copyItemAtPath:dllBak toPath:dll error:nil];
    } else {
        if (!patchDllFile(dll, YES, errorOut)) return NO;
    }

    if (!runCodesign(appPath, errorOut)) return NO;
    return YES;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL cliMode = NO;
        BOOL restoreMode = NO;
        NSString *customPath = nil;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--cli") == 0) cliMode = YES;
            else if (strcmp(argv[i], "--restore") == 0) { cliMode = YES; restoreMode = YES; }
            else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                printf("Lovers in a Dangerous Spacetime — macOS Gamepad & Sequoia Fix\n");
                printf("Usage: %s [--cli] [--restore] [path/to/LoversInADangerousSpacetime.app]\n", argv[0]);
                return 0;
            } else if (argv[i][0] != '-') {
                customPath = [NSString stringWithUTF8String:argv[i]];
            }
        }

        NSString *appPath = customPath ?: getDefaultGamePath();
        NSFileManager *fm = [NSFileManager defaultManager];

        if (cliMode) {
            printf("[Lovers Fix] Target: %s\n", [appPath UTF8String]);
            if (![fm fileExistsAtPath:appPath]) {
                fprintf(stderr, "[ERROR] Game not found at %s\n", [appPath UTF8String]);
                return 1;
            }
            NSString *err = nil;
            if (restoreMode) {
                printf("[Lovers Fix] Restoring original files...\n");
                if (restoreOriginal(appPath, &err)) {
                    printf("[SUCCESS] Original files restored and app resigned successfully!\n");
                    return 0;
                } else {
                    fprintf(stderr, "[ERROR] %s\n", [err UTF8String]);
                    return 1;
                }
            } else {
                printf("[Lovers Fix] Applying gamepad and Sequoia fix...\n");
                if (applyFix(appPath, &err)) {
                    printf("[SUCCESS] Fix applied and app resigned successfully!\n");
                    return 0;
                } else {
                    fprintf(stderr, "[ERROR] %s\n", [err UTF8String]);
                    return 1;
                }
            }
        }

        // GUI Mode
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateAllWindows];

        if (![fm fileExistsAtPath:appPath]) {
            NSAlert *notFound = [[NSAlert alloc] init];
            [notFound setMessageText:@"Game Not Found"];
            [notFound setInformativeText:[NSString stringWithFormat:@"Could not automatically find Lovers in a Dangerous Spacetime in your Steam library:\n%@\n\nWould you like to manually locate the .app?", appPath]];
            [notFound addButtonWithTitle:@"Locate .app..."];
            [notFound addButtonWithTitle:@"Cancel"];

            if ([notFound runModal] == NSAlertFirstButtonReturn) {
                NSOpenPanel *panel = [NSOpenPanel openPanel];
                [panel setTitle:@"Select LoversInADangerousSpacetime.app"];
                [panel setCanChooseFiles:YES];
                [panel setCanChooseDirectories:NO];
                [panel setAllowsMultipleSelection:NO];
                [panel setAllowedFileTypes:@[@"app"]];

                if ([panel runModal] == NSModalResponseOK) {
                    appPath = [[[panel URLs] firstObject] path];
                } else {
                    return 0;
                }
            } else {
                return 0;
            }
        }

        NSAlert *mainAlert = [[NSAlert alloc] init];
        [mainAlert setMessageText:@"Lovers in a Dangerous Spacetime Fix"];
        [mainAlert setInformativeText:[NSString stringWithFormat:
            @"Game detected successfully!\n\n"
            "This fix provides:\n"
            "• Fixes game launch crash on macOS 15 Sequoia (IOHIDManagerOpen)\n"
            "• Multi-gamepad local co-op support (up to 4 players)\n"
            "• Native Bluetooth support for Xbox Wireless Controllers & clones\n"
            "• Full support for Valve Steam Controller\n"
            "• Prevents duplicate / uncontrollable phantom player pods\n"
            "• Unlocks pause menu for all 4 player slots\n\n"
            "Would you like to apply the fix now?", nil]];

        [mainAlert addButtonWithTitle:@"Apply Fix"];
        [mainAlert addButtonWithTitle:@"Restore Original"];
        [mainAlert addButtonWithTitle:@"Quit"];

        NSModalResponse response = [mainAlert runModal];
        if (response == NSAlertFirstButtonReturn) {
            NSString *err = nil;
            if (applyFix(appPath, &err)) {
                NSAlert *success = [[NSAlert alloc] init];
                [success setMessageText:@"Fix Applied Successfully! 🎉"];
                [success setInformativeText:
                    @"The game has been patched and resigned with a valid local signature.\n\n"
                    "⚠️ IMPORTANT STEAM SETTING:\n"
                    "Open Steam -> Settings -> Controller and turn OFF:\n"
                    "\"Enable Steam Input for Xbox Controllers\"\n"
                    "(Keep Steam Input turned ON for Steam Controller if you use one).\n\n"
                    "Enjoy the game with your friends!"];
                [success addButtonWithTitle:@"Awesome!"];
                [success runModal];
            } else {
                NSAlert *fail = [[NSAlert alloc] init];
                [fail setMessageText:@"Patch Failed"];
                [fail setInformativeText:[NSString stringWithFormat:@"An error occurred while applying the fix:\n%@", err]];
                [fail addButtonWithTitle:@"OK"];
                [fail runModal];
            }
        } else if (response == NSAlertSecondButtonReturn) {
            NSString *err = nil;
            if (restoreOriginal(appPath, &err)) {
                NSAlert *restored = [[NSAlert alloc] init];
                [restored setMessageText:@"Original Restored"];
                [restored setInformativeText:@"The original game files have been restored and resigned."];
                [restored addButtonWithTitle:@"OK"];
                [restored runModal];
            } else {
                NSAlert *fail = [[NSAlert alloc] init];
                [fail setMessageText:@"Restore Failed"];
                [fail setInformativeText:[NSString stringWithFormat:@"An error occurred during restore:\n%@", err]];
                [fail addButtonWithTitle:@"OK"];
                [fail runModal];
            }
        }
#pragma clang diagnostic pop
    }
    return 0;
}
