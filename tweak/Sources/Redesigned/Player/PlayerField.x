// Player redesign: the artwork field behind the full screen player, and what the switch forces.
//
// Tree (trees/clean/player/01.txt:449): NPVBackgroundViewController's view is a plane inside the NPV's
// own list (scrolling_npv_collection_view), painted the album colour with Spotify's gradients
// (NPVGradientView) stacked on it. Its top stays at the top of the content and it grows as the list
// scrolls (874 at rest, 1495 and 2144 further down, 02.txt:757, 03.txt:861), so a field inside it
// scrolls with the cards and is laid out again on every scroll frame: the hook only compares a frame.
// The field goes on top of the plane's own subviews, so Spotify's gradients are covered rather than
// fought over, and nothing depends on a repaint hook.
//
// The picture comes from the Kit's now playing artwork: the now playing bar's 40pt cover, published by
// the Kit, and the player's own 354pt cover, published here from the cell in the middle of the
// sideways list of covers (AccessibleCollectionView, 01.txt:28, one CoverArtCellImpl per queued track,
// the ones out of view hidden). Until the first picture has been read the field takes the colour
// Spotify already has for the player, from -[NPVBackgroundViewController
// backgroundViewModel:didChangeColor:playerState:] (objc-methods.txt:57949).
//
// Canvas is the one thing that wants the same room: Spotify's looping video for the track. The switch
// (SGRKeyCanvas, on until switched off) decides whether the redesign forces it off as it does the rest
// of the player's flags, and while one plays the field fades out under it and comes back when it goes,
// so a track with a Canvas shows the video and a track without still gets the field.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

// Past the plane's edges: above for the pull that dismisses the player, below for the bounce at the end
// of the cards.
static const UIEdgeInsets kBleed = {200, 0, 600, 0};
// A cover this narrow is a placeholder glyph or the bar's, not the player's.
static const CGFloat kCoverMinWidth = 200;

static char kFieldKey, kCoverImageKey;
static __weak SGRArtworkField *sg_field;
static __weak UIScrollView *sg_coverList;
// The Canvas cell on screen while one plays, nil when none is (the Canvas group below).
static __weak UIView *sg_canvasCell;
static __weak UIImage *sg_lastCover;
static NSString *sg_lastCoverURI;
// Spotify's colour for the player, which can arrive before the plane has laid out once.
static UIColor *sg_spotifyColor;

SGRArtworkField *SGRPlayerField(void) {
    return sg_field;
}

#pragma mark - the field

static void showArtwork(SGRArtworkField *field, BOOL animated) {
    NSString *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(NULL, &identity);
    if (field && image) [field setArtwork:image identity:identity animated:animated];
}

// Canvas plays where the field is, so the two cannot both be on: the field fades out under a Canvas and
// comes back when it goes. The cell is held weakly, so one that is let go without a last window callback
// leaves the field on again at the next layout of the plane rather than a blank background.
static void syncCanvas(void) {
    SGRArtworkField *field = sg_field;
    if (!field) return;
    UIView *cell = sg_canvasCell;
    CGFloat wanted = (cell && cell.window && !cell.hidden && cell.alpha > 0.01) ? 0 : 1;
    if (fabs(field.alpha - wanted) < 0.01) return;
    [UIView animateWithDuration:0.3 animations:^{ field.alpha = wanted; }];
}

static SGRArtworkField *fieldIn(UIView *plane) {
    SGRArtworkField *field = objc_getAssociatedObject(plane, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:plane.bounds];
    field.showsBackdrop = YES;
    field.bleed = kBleed;
    objc_setAssociatedObject(plane, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_field = field;
    [field setProvisionalColor:sg_spotifyColor];
    // Made while the player is about to open: whatever is read lands in the first frames of the
    // animation, where a crossfade would only add work.
    showArtwork(field, NO);
    SGLog(@"redesign player: field in the background plane %.0fx%.0f, artwork %@", plane.bounds.size.width, plane.bounds.size.height, SGRNowPlayingArtwork(NULL, NULL) ? @"ready" : @"not read yet");
    return field;
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    if (!plane || plane.bounds.size.height < 200) return;
    SGRArtworkField *field = fieldIn(plane);
    sg_field = field;
    if (field.superview != plane) [plane addSubview:field];
    else if (plane.subviews.lastObject != field) [plane bringSubviewToFront:field];
    if (!CGRectEqualToRect(field.frame, plane.bounds)) field.frame = plane.bounds;
    syncCanvas();
}

- (void)backgroundViewModel:(id)model didChangeColor:(id)color playerState:(id)state {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: Spotify's colour %@ (%@), state %@", color, [color class], [state class]); });
    if (![color isKindOfClass:UIColor.class]) return;
    sg_spotifyColor = color;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    SGRArtworkField *field = plane ? objc_getAssociatedObject(plane, &kFieldKey) : nil;
    [field setProvisionalColor:color];
}
%end

#pragma mark - the player's own cover

// The picture of the cell under the middle of the list once it has settled: mid swipe the middle is
// between two tracks.
static UIImage *settledCover(UIScrollView *list) {
    if (!list.window || list.isDragging || list.isDecelerating) return nil;
    CGFloat middle = CGRectGetMidX(list.bounds);
    for (UIView *cell in list.subviews) {
        if (cell.hidden || ![cell isKindOfClass:UICollectionViewCell.class] || fabs(CGRectGetMidX(cell.frame) - middle) > 1) continue;
        UIView *holder = SGRFindByIdentifier(cell, @"Encore.ImageView", &kCoverImageKey);
        if (holder.bounds.size.width < kCoverMinWidth) return nil;
        for (UIView *sub in holder.subviews) {
            UIImageView *image = (UIImageView *)sub;
            if ([sub isKindOfClass:UIImageView.class] && image.image && image.alpha > 0) return image.image;
        }
        return nil;
    }
    return nil;
}

static void publishCover(void) {
    UIImage *cover = settledCover(sg_coverList);
    if (!cover) return;
    NSString *uri = SGRURIString(SGRPlayerState().track.URI);
    if (!uri || (cover == sg_lastCover && [uri isEqualToString:sg_lastCoverURI])) return;
    sg_lastCover = cover;
    sg_lastCoverURI = uri;
    SGRSetNowPlayingArtwork(cover, uri, SGRArtworkQualityHigh);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: cover %.0fx%.0f published for %@", cover.size.width, cover.size.height, uri);
}

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    sg_coverList = (UIScrollView *)self;
    publishCover();
}
%end

// A cover that loads after the track changed sets an image and lays nothing out, so the list is looked
// at again a few times while it comes in, as the Kit does for the bar.
@interface SGRPlayerCoverWatcher : NSObject <SGRPlayerStateObserver>
@end

@implementation SGRPlayerCoverWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGRURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    for (NSNumber *delay in @[@0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ publishCover(); });
    }
}

@end

static SGRPlayerCoverWatcher *sg_coverWatcher;

#pragma mark - Canvas

// Installed only while the switch is on, so a build with Canvas off carries no hook for it at all. The
// cell is Spotify's own (_TtC17Canvas_CommonImpl20CanvasNowPlayingCell, Canvas_CommonImpl/
// CanvasNowPlayingCell.swift in the binary); both callbacks are UIView's, and each one only records
// the cell and lets syncCanvas() decide.
%group Canvas
%hook _TtC17Canvas_CommonImpl20CanvasNowPlayingCell
- (void)didMoveToWindow {
    %orig;
    sg_canvasCell = (UIView *)self;
    syncCanvas();
}

- (void)layoutSubviews {
    %orig;
    sg_canvasCell = (UIView *)self;
    syncCanvas();
}
%end
%end

SGModRow *SGRCanvasRow(void) {
    return SGWithSymbol(SGSwitchRow(@"Canvas", @"Spotify's looping video behind the artwork. The field steps aside while one plays.", SGRKeyCanvas), @"play.rectangle");
}

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    NSMutableDictionary<NSString *, id> *flags = [@{
        // The header, slider and sheets the trees were recorded with (trees/clean/player/01.txt:122
        // id=Context menu, :216 SPTNowPlayingSliderV2).
        @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled": @YES,
        @"ios-feature-encoreexperiments.new_npv_slider_enabled": @YES,
        @"ios-feature-nowplaying.bottom_sheet_queue_enabled": @YES,
        @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet": @YES,
        @"ios-feature-nowplaying.sheet_style_npv": @YES,
        // Art around the play disc would sit under a bare glyph.
        @"ios-feature-nowplaying-elements.mixing_play_button": @NO,
    } mutableCopy];
    for (NSString *egg in @[@"ariana_petal_play_button_easter_egg", @"attack_on_titan_easter_egg_enabled", @"barbie_easter_egg_enabled",
                            @"black_panther_easter_egg_enabled", @"demogorgon_easter_egg", @"harry_potter_play_button_surround_easter_egg",
                            @"luma_easter_egg", @"pokemon_easter_egg_enabled", @"sanremo_easter_egg_enabled", @"sanrio_easter_egg_enabled",
                            @"spiderman_easter_egg_enabled", @"star_easter_egg", @"wednesday_easter_egg", @"wicked_easter_egg_enabled",
                            @"world_cup_easter_egg"]) {
        flags[[@"ios-feature-nowplaying." stringByAppendingString:egg]] = @NO;
    }
    // Canvas is the one flag here the switch decides. Off, it joins the rest and is forced off, which
    // locks its row on the All flags page too; on, nothing forces it and Spotify's own value stands.
    BOOL canvas = SGEnabled(SGRKeyCanvas);
    if (!canvas) flags[@"ios-feature-canvas.canvas_enabled"] = @NO;
    SGRedesignForceFlags(@"player", flags);
    if (!SGRedesignedUI()) return;
    %init;
    sg_coverWatcher = [SGRPlayerCoverWatcher new];
    SGRAddPlayerStateObserver(sg_coverWatcher);
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        showArtwork(sg_field, YES);
    }];
    NSMutableArray<NSString *> *classes = [@[
        @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController",
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
    ] mutableCopy];
    if (canvas) {
        %init(Canvas);
        [classes addObject:@"_TtC17Canvas_CommonImpl20CanvasNowPlayingCell"];
    }
    SGRequireClasses(classes);
}
