#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

// Every key of the mod's is under one prefix, so a reset is a sweep of the defaults with the stock
// marker of SGPrefs.h left behind; the hooks read them at launch, so it ends in a restart.
static void resetAll(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSUInteger removed = 0;
    for (NSString *key in [store persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].allKeys) {
        if (![key hasPrefix:@"spotifyglass."]) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    [store setBool:YES forKey:SGKeyStock];
    SGLog(@"reset: removed %lu keys", (unsigned long)removed);
    SGRestartSpotify();
}

static void confirmReset(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset all settings?"
                                                                  message:@"Every switch goes off, flag overrides and the tab bar layout are cleared, and Spotify restarts as it came, with the mod doing nothing until asked. Spotify's own settings are untouched."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset and restart" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { resetAll(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *withSymbol(SGModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

// Which build this is, whether GitHub has a newer release, and where to reach the mod: without these
// rows a build that is already installed has no way of telling its user that anything moved on.
UIViewController *SGAboutPage(void) {
    SGModRow *reset = withSymbol(SGActionRow(@"Reset all settings", @"Every switch off, Spotify as it came, then a restart", ^{ confirmReset(); }), @"trash");
    reset.color = SGRed();
    NSString *spotify = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    return [[SGModPage alloc] initWithTitle:@"Mod" intro:nil sections:@[
        SGSection(nil, @[
            SGStatActionRow(@"Updates", @"Asks GitHub for the newest release; tap to check now", ^NSString *{
                return SGUpdateStatus();
            }, ^{ SGCheckForUpdate(YES); }),
            SGStatRow(@"Version", ^NSString *{ return @(SG_VERSION); }),
            SGStatRow(@"Spotify", ^NSString *{ return spotify; }),
            SGStatRow(@"Fork", ^NSString *{ return @"marwannsaz"; }),
        ]),
        SGSection(nil, @[
            withSymbol(SGLinkRow(@"Website", @"Features, and how to build it yourself", SGSiteURL), @"safari"),
            withSymbol(SGLinkRow(@"GitHub", @"Source, releases and issues", SGRepoURL), @"chevron.left.forwardslash.chevron.right"),
            withSymbol(SGActionRow(@"Welcome tour", @"The pages from the first launch, again", ^{ SGShowOnboarding(); }), @"map"),
        ]),
        SGSection(nil, @[
            withSymbol(SGActionRow(@"Export settings", @"Every switch and choice to a file to keep or share", ^{ SGExportSettings(); }), @"square.and.arrow.up"),
            withSymbol(SGActionRow(@"Import settings", @"Replace yours with a file's, then a restart", ^{ SGImportSettings(); }), @"square.and.arrow.down"),
        ]),
        SGSection(nil, @[reset]),
    ] footer:nil];
}
