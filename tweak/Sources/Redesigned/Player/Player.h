// The player redesign (screen key "player"): Spotify's full screen player kept, with its controller,
// units, controls and card list, and restyled from the Kit. Every control stays Spotify's own, so its
// action, state and accessibility do too; the redesign adds the artwork field behind it, glass behind
// the header buttons, bare glyphs for previous, play and next, a lyrics glyph in the footer, and one
// screen with nothing under it: every card is collapsed and the player does not scroll. The lyrics
// come to the player itself, the way the Music app shows them, when the lyrics glyph is tapped.
//
//     PlayerField.x      the switch's flags and rows, the field in the background plane, the cover it reads
//     PlayerArtwork.x    the cover's corners, shadow and paused shrink, the lyric preview under it hidden
//     PlayerHeader.x     glass behind the close and more buttons
//     PlayerControls.x   previous, play and next as bare glyphs, monospaced times
//     PlayerFooter.x     share gone, lyrics, Connect and queue as one row of three glyphs
//     PlayerCards.x      every card under the player collapsed, so the list closes up
//     PlayerScroll.x     the list pinned to the top, so the player is one screen and cannot be scrolled
//     PlayerLyrics.x     the lyrics in the player: the cover as a thumbnail, the title up beside it
//     PlayerGestures.x   the gestures' hookup
//     PlayerMorph.x      the open and close grown out of the now playing bar's card, the cover flown
//     PlayerMenu.x       Speed and pitch, an expandable row with two sliders in the more button's menu
//     PlayerSpeedPitch.x speed and pitch done to Spotify's audio, between its mixer and its speaker unit
//     SGRTimePitch.m     Apple's time and pitch unit, pulling the mixer or working in place
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGRArtworkField, SGModRow;

// Spotify's looping Canvas video behind the artwork. Read at launch like every other switch; unset is
// on. While one plays the field steps aside, because the field is what would cover it (PlayerField.x).
#define SGRKeyCanvas @"spotifyglass.redesign.player.canvas"

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);
// The Canvas switch's row, for the Player page (PlayerField.x).
SGModRow *SGRCanvasRow(void);

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
// The cover on screen as it is drawn, its paused shrink included, in `host`'s coordinates; CGRectNull
// when no cover has laid out.
CGRect SGRPlayerCoverFrameIn(UIView *host);
// The band that cover sits in -- the room the player gives its artwork, between the header row and the
// title -- in `host`'s coordinates; CGRectNull when no cover has laid out.
CGRect SGRPlayerArtworkAreaIn(UIView *host);
// Hides the cover on screen and its shadow, or shows them again, for a stand-in to fly in its place
// (PlayerMorph.x).
void SGRPlayerSetCoverHidden(BOOL hidden);

#pragma mark - the lyrics in the player (PlayerLyrics.x)

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the player is showing them.
BOOL SGRPlayerLyricsOpen(void);
// Shows them, or puts the cover back; does nothing when there are none to show.
void SGRPlayerToggleLyrics(void);
// Called by PlayerLyrics.x whenever either of those two changed, so the footer's lyrics glyph follows
// (PlayerFooter.x). It returns at once when nothing changed.
void SGRPlayerLyricsChanged(void);

#pragma mark - the more menu's speed and pitch (PlayerMenu.x, PlayerSpeedPitch.x)

// Marks a menu opened soon after a tap on `button`, the player's more button, as the player's, so it gets
// Speed and pitch (PlayerHeader.x hands it over; watching it twice does nothing).
void SGRPlayerMenuWatchMoreButton(UIView *button);
// The speed Spotify's sound plays at, 1 when normal; lasts until Spotify quits.
double SGRPlayerSpeed(void);
// Whether speed can apply: Spotify's output was taken over when it wired it.
BOOL SGRPlayerSpeedAllowed(void);
void SGRSetPlayerSpeed(double speed);
// Semitones Spotify's output is moved by, 0 when it is not; lasts until Spotify quits.
float SGRPlayerPitch(void);
void SGRSetPlayerPitch(float semitones);
// Whether the output could be reached to change its pitch.
BOOL SGRPlayerPitchAvailable(void);

// Alpha 0, no touches, hidden from accessibility, set again on every call: for Spotify's Swift views,
// which SGRSuppress cannot keep (PlayerControls.x).
void SGRPlayerVanish(UIView *view);
