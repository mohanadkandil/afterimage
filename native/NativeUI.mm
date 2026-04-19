#import "NativeUI.hpp"
#import <QuartzCore/QuartzCore.h>
#include <fstream>
static NSString *S(const std::string &s) {
  return [NSString stringWithUTF8String:s.c_str()] ?: @"";
}
static std::string T(NSString *s) { return std::string(s.UTF8String ?: ""); }
static NSColor *mint() {
  return [NSColor colorWithRed:.64 green:.85 blue:.76 alpha:1];
}
static NSTextField *label(NSString *s, CGFloat size) {
  NSTextField *v = [NSTextField labelWithString:s];
  v.font = [NSFont systemFontOfSize:size];
  v.textColor = NSColor.secondaryLabelColor;
  v.lineBreakMode = NSLineBreakByTruncatingTail;
  return v;
}
static NSButton *button(NSString *title, id target, SEL action,
                        NSString *symbol) {
  NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
  b.bezelStyle = NSBezelStyleRounded;
  b.controlSize = NSControlSizeSmall;
  if (symbol) {
    b.image = [NSImage imageWithSystemSymbolName:symbol
                        accessibilityDescription:title];
    b.imagePosition = NSImageOnly;
    b.bordered = NO;
    [b.widthAnchor constraintEqualToConstant:28].active = YES;
    [b.heightAnchor constraintEqualToConstant:28].active = YES;
    b.toolTip = title;
    [b setAccessibilityLabel:title];
  }
  return b;
}
static NSStackView *row(NSArray<NSView *> *views) {
  NSStackView *s = [NSStackView stackViewWithViews:views];
  s.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  s.spacing = 12;
  s.alignment = NSLayoutAttributeCenterY;
  return s;
}
static NSString *timeText(double t) {
  NSDateFormatter *f = [NSDateFormatter new];
  f.dateFormat = @"d MMM · HH:mm:ss";
  return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

@interface NativeSurface : NSView
@end
@implementation NativeSurface
- (void)drawRect:(NSRect)rect {
  [NSColor.windowBackgroundColor setFill];
  NSRectFill(rect);
}
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  self.needsDisplay = YES;
}
@end
@interface ScreenCanvas : NSView
@property NSImage *image;
@property NSArray *boxes;
@property NSString *query;
@property CGFloat zoom;
@property(readonly) NSUInteger highlights;
@end
@implementation ScreenCanvas
- (BOOL)isFlipped {
  return YES;
}
- (NSUInteger)highlights {
  NSUInteger count = 0;
  for (NSDictionary *b in self.boxes)
    for (NSString *term in [self.query
             componentsSeparatedByCharactersInSet:NSCharacterSet
                                                      .whitespaceCharacterSet])
      if (term.length &&
          [b[@"text"] localizedCaseInsensitiveContainsString:term]) {
        count++;
        break;
      }
  return count;
}
- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  [NSColor.controlBackgroundColor setFill];
  NSRectFill(self.bounds);
  if (!self.image) {
    NSDictionary *a = @{
      NSFontAttributeName : [NSFont systemFontOfSize:24
                                              weight:NSFontWeightMedium],
      NSForegroundColorAttributeName : NSColor.labelColor
    };
    NSString *title =
        self.query.length ? @"No matching moments" : @"A place to return to.";
    NSSize z = [title sizeWithAttributes:a];
    [title drawAtPoint:NSMakePoint((self.bounds.size.width - z.width) / 2,
                                   self.bounds.size.height / 2 - 28)
        withAttributes:a];
    NSString *sub = self.query.length
                        ? @"Try another phrase, date, or app."
                        : @"Start recording, or import a screenshot.";
    a = @{
      NSFontAttributeName : [NSFont systemFontOfSize:13],
      NSForegroundColorAttributeName : NSColor.secondaryLabelColor
    };
    z = [sub sizeWithAttributes:a];
    [sub drawAtPoint:NSMakePoint((self.bounds.size.width - z.width) / 2,
                                 self.bounds.size.height / 2 + 10)
        withAttributes:a];
    return;
  }
  CGFloat r = MIN(self.bounds.size.width / self.image.size.width,
                  self.bounds.size.height / self.image.size.height);
  NSRect fit =
      NSMakeRect((self.bounds.size.width - self.image.size.width * r) / 2,
                 (self.bounds.size.height - self.image.size.height * r) / 2,
                 self.image.size.width * r, self.image.size.height * r);
  [self.image
          drawInRect:fit
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1
      respectFlipped:YES
               hints:@{NSImageHintInterpolation : @(NSImageInterpolationHigh)}];
  for (NSDictionary *b in self.boxes) {
    BOOL match = NO;
    for (NSString *term in [self.query
             componentsSeparatedByCharactersInSet:NSCharacterSet
                                                      .whitespaceCharacterSet])
      if (term.length &&
          [b[@"text"] localizedCaseInsensitiveContainsString:term])
        match = YES;
    if (!match)
      continue;
    NSRect rect =
        NSMakeRect(fit.origin.x + [b[@"x"] doubleValue] * fit.size.width,
                   fit.origin.y + [b[@"y"] doubleValue] * fit.size.height,
                   [b[@"w"] doubleValue] * fit.size.width,
                   [b[@"h"] doubleValue] * fit.size.height);
    [[mint() colorWithAlphaComponent:.22] setFill];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    [mint() setStroke];
    [NSBezierPath strokeRect:rect];
  }
}
@end
@interface MomentTimeline : NSControl
@property NSArray *frames;
@property NSInteger index;
@end
@implementation MomentTimeline
- (BOOL)isFlipped {
  return YES;
}
- (BOOL)acceptsFirstResponder {
  return YES;
}
- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  CGFloat w = self.bounds.size.width;
  CGFloat y = 24;
  [[NSColor.separatorColor colorWithAlphaComponent:.4] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, y, w, 8)
                                   xRadius:4
                                   yRadius:4] fill];
  if (!self.frames.count)
    return;
  double start = [self.frames.firstObject[@"time"] doubleValue],
         end = [self.frames.lastObject[@"time"] doubleValue],
         duration = MAX(1, end - start);
  for (NSUInteger i = 0; i < self.frames.count; i++) {
    NSDictionary *f = self.frames[i];
    double t = [f[@"time"] doubleValue];
    CGFloat x = (t - start) / duration * (w - 4);
    CGFloat next =
        i + 1 < self.frames.count
            ? (MIN([self.frames[i + 1][@"time"] doubleValue], t + 30) - start) /
                  duration * (w - 4)
            : w;
    [mint() setFill];
    [[NSBezierPath
        bezierPathWithRoundedRect:NSMakeRect(x, y, MAX(3, next - x - 1), 8)
                          xRadius:3
                          yRadius:3] fill];
    if (i == 0 || ![f[@"bundle"] isEqual:self.frames[i - 1][@"bundle"]]) {
      NSString *app = f[@"app"];
      [app drawAtPoint:NSMakePoint(MIN(x, MAX(0, w - 100)), 3)
          withAttributes:@{
            NSFontAttributeName : [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName : NSColor.secondaryLabelColor
          }];
    }
  }
  NSInteger idx = MAX(0, MIN(self.index, (NSInteger)self.frames.count - 1));
  CGFloat x =
      ([self.frames[idx][@"time"] doubleValue] - start) / duration * (w - 4);
  [NSColor.labelColor setFill];
  [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, 19, 3, 18)
                                   xRadius:1.5
                                   yRadius:1.5] fill];
}
- (void)seek:(NSEvent *)event {
  if (!self.frames.count)
    return;
  CGFloat fraction =
      MAX(0, MIN(1, [self convertPoint:event.locationInWindow fromView:nil].x /
                        MAX(1, self.bounds.size.width)));
  double a = [self.frames.firstObject[@"time"] doubleValue],
         b = [self.frames.lastObject[@"time"] doubleValue],
         target = a + (b - a) * fraction, best = 1e99;
  NSInteger selected = 0;
  for (NSUInteger i = 0; i < self.frames.count; i++) {
    double d = fabs([self.frames[i][@"time"] doubleValue] - target);
    if (d < best) {
      best = d;
      selected = i;
    }
  }
  self.index = selected;
  [self sendAction:self.action to:self.target];
  self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)e {
  [self seek:e];
}
- (void)mouseDragged:(NSEvent *)e {
  [self seek:e];
}
- (void)keyDown:(NSEvent *)e {
  if (e.keyCode == 123 || e.keyCode == 124) {
    self.index = MAX(0, MIN((NSInteger)self.frames.count - 1,
                            self.index + (e.keyCode == 123 ? -1 : 1)));
    [self sendAction:self.action to:self.target];
    self.needsDisplay = YES;
  } else
    [super keyDown:e];
}
@end
@interface NativeUI () {
  UIRequest request;
  NSString *root;
  NSSearchField *search;
  NSDatePicker *date;
  NSPopUpButton *apps, *speed;
  NSButton *record, *details, *exportButton, *previous, *next, *play, *earlier,
      *newer;
  NSTextField *status, *caption, *timestamp, *countLabel;
  ScreenCanvas *canvas;
  NSScrollView *imageScroll, *filmScroll;
  NSStackView *film;
  MomentTimeline *timeline;
  NSPopover *evidence;
  NSTextView *evidenceText;
  NSWindow *settingsWindow;
  NSPopUpButton *interval, *retention;
  NSTextField *excluded;
  NSTimer *refreshTimer, *playTimer, *searchTimer;
  id keyMonitor;
  json state, frames;
  NSInteger selected, offset;
  long long lastCount;
  double lastTime;
  BOOL loading;
  CGFloat zoom;
}
@end
@implementation NativeUI
- (instancetype)initWithRequest:(UIRequest)r imageRoot:(NSString *)p {
  if ((self = [super init])) {
    request = [r copy];
    root = p;
    frames = json::array();
    selected = -1;
    zoom = 1;
    lastCount = -1;
  }
  return self;
}
- (void)loadView {
  NSView *base = [NativeSurface new];
  self.view = base;

  search = [NSSearchField new];
  search.placeholderString = @"Search screen text";
  search.delegate = self;
  search.sendsSearchStringImmediately = YES;
  [search.widthAnchor constraintEqualToConstant:280].active = YES;
  date = [NSDatePicker new];
  date.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
  date.datePickerElements = NSDatePickerElementFlagYearMonthDay;
  date.dateValue = NSDate.date;
  date.target = self;
  date.action = @selector(filterChanged:);
  date.controlSize = NSControlSizeSmall;
  apps = [NSPopUpButton new];
  [apps addItemWithTitle:@"All apps"];
  apps.target = self;
  apps.action = @selector(filterChanged:);
  [apps.widthAnchor constraintLessThanOrEqualToConstant:160].active = YES;
  record = button(@"Start recording", self, @selector(toggle:), nil);
  status = label(@"Paused", 11);
  [status.widthAnchor constraintLessThanOrEqualToConstant:180].active = YES;
  NSView *spacer = [NSView new];
  [spacer setContentHuggingPriority:1
                     forOrientation:NSLayoutConstraintOrientationHorizontal];
  NSStackView *top = row(@[
    search, spacer, status, record,
    button(@"Settings", self, @selector(showSettings:), @"gearshape")
  ]);
  details =
      button(@"Details", self, @selector(showEvidence:), @"text.alignleft");
  exportButton = button(@"Export screenshot", self, @selector(exportImage:),
                        @"square.and.arrow.up");
  NSView *spacer2 = [NSView new];
  [spacer2 setContentHuggingPriority:1
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
  NSStackView *filters = row(@[
    date, button(@"Today", self, @selector(today:), nil), spacer2, apps,
    button(@"Import", self, @selector(importImage:), @"square.and.arrow.down"),
    details, exportButton
  ]);
  canvas = [ScreenCanvas new];
  canvas.query = @"";
  canvas.zoom = 1;
  [canvas setAccessibilityElement:YES];
  [canvas setAccessibilityRole:NSAccessibilityImageRole];
  [canvas setAccessibilityLabel:@"Selected screen capture"];
  imageScroll = [NSScrollView new];
  imageScroll.documentView = canvas;
  imageScroll.hasHorizontalScroller = YES;
  imageScroll.hasVerticalScroller = YES;
  imageScroll.autohidesScrollers = YES;
  imageScroll.drawsBackground = NO;
  imageScroll.wantsLayer = YES;
  imageScroll.layer.cornerRadius = 10;
  imageScroll.layer.masksToBounds = YES;
  caption = label(@"", 11);
  caption.selectable = YES;
  [caption
      setContentCompressionResistancePriority:1
                               forOrientation:
                                   NSLayoutConstraintOrientationHorizontal];
  film = [NSStackView new];
  film.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  film.spacing = 8;
  film.edgeInsets = NSEdgeInsetsMake(4, 0, 4, 0);
  filmScroll = [NSScrollView new];
  filmScroll.documentView = film;
  filmScroll.hasHorizontalScroller = YES;
  filmScroll.autohidesScrollers = YES;
  filmScroll.drawsBackground = NO;
  previous =
      button(@"Previous moment", self, @selector(previous:), @"chevron.left");
  next = button(@"Next moment", self, @selector(next:), @"chevron.right");
  play = button(@"Play moments", self, @selector(play:), @"play.fill");
  timestamp = label(@"No moments yet", 12);
  timestamp.font = [NSFont monospacedDigitSystemFontOfSize:12
                                                    weight:NSFontWeightRegular];
  countLabel = label(@"", 11);
  newer = button(@"Newer", self, @selector(newer:), nil);
  earlier = button(@"Earlier", self, @selector(earlier:), nil);
  speed = [NSPopUpButton new];
  [speed addItemsWithTitles:@[ @"1×", @"2×", @"4×" ]];
  speed.target = self;
  speed.action = @selector(speedChanged:);
  NSView *spacer3 = [NSView new];
  [spacer3 setContentHuggingPriority:1
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
  NSStackView *bottom = row(@[
    play, previous, next, timestamp, spacer3, newer, earlier, countLabel, speed,
    button(@"Zoom out", self, @selector(zoomOut:), @"minus.magnifyingglass"),
    button(@"Fit screenshot", self, @selector(fit:),
           @"arrow.up.left.and.arrow.down.right"),
    button(@"Zoom in", self, @selector(zoomIn:), @"plus.magnifyingglass")
  ]);
  timeline = [MomentTimeline new];
  timeline.target = self;
  timeline.action = @selector(scrub:);
  [timeline setAccessibilityLabel:@"Recorded moments timeline"];
  NSArray *views =
      @[ top, filters, imageScroll, caption, filmScroll, bottom, timeline ];
  for (NSView *v in views) {
    [base addSubview:v];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [v.leadingAnchor constraintEqualToAnchor:base.leadingAnchor constant:20]
        .active = YES;
    [v.trailingAnchor constraintEqualToAnchor:base.trailingAnchor constant:-20]
        .active = YES;
  }
  [NSLayoutConstraint activateConstraints:@[
    [top.topAnchor constraintEqualToAnchor:base.topAnchor constant:12],
    [top.heightAnchor constraintEqualToConstant:32],
    [filters.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:10],
    [filters.heightAnchor constraintEqualToConstant:28],
    [imageScroll.topAnchor constraintEqualToAnchor:filters.bottomAnchor
                                          constant:12],
    [caption.topAnchor constraintEqualToAnchor:imageScroll.bottomAnchor
                                      constant:8],
    [caption.heightAnchor constraintEqualToConstant:16],
    [filmScroll.topAnchor constraintEqualToAnchor:caption.bottomAnchor
                                         constant:6],
    [filmScroll.heightAnchor constraintEqualToConstant:82],
    [bottom.topAnchor constraintEqualToAnchor:filmScroll.bottomAnchor
                                     constant:10],
    [bottom.heightAnchor constraintEqualToConstant:28],
    [timeline.topAnchor constraintEqualToAnchor:bottom.bottomAnchor constant:4],
    [timeline.heightAnchor constraintEqualToConstant:40],
    [timeline.bottomAnchor constraintEqualToAnchor:base.bottomAnchor
                                          constant:-12]
  ]];
  __weak NativeUI *weak = self;
  refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2
                                                 repeats:YES
                                                   block:^(NSTimer *t) {
                                                     (void)t;
                                                     [weak refresh];
                                                   }];
  keyMonitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                   handler:^NSEvent *(NSEvent *e) {
                                     NativeUI *ui = weak;
                                     if (!ui || e.window != ui.view.window ||
                                         ui->settingsWindow.visible)
                                       return e;
                                     if ((e.modifierFlags &
                                          NSEventModifierFlagCommand) &&
                                         [e.charactersIgnoringModifiers
                                             isEqualToString:@"f"]) {
                                       [ui.view.window
                                           makeFirstResponder:ui->search];
                                       return nil;
                                     }
                                     if ([ui.view.window.firstResponder
                                             isKindOfClass:NSTextView.class])
                                       return e;
                                     if ([e.characters isEqualToString:@"/"]) {
                                       [ui.view.window
                                           makeFirstResponder:ui->search];
                                       return nil;
                                     }
                                     if (e.keyCode == 123) {
                                       [ui previous:nil];
                                       return nil;
                                     }
                                     if (e.keyCode == 124) {
                                       [ui next:nil];
                                       return nil;
                                     }
                                     if (e.keyCode == 49) {
                                       [ui play:nil];
                                       return nil;
                                     }
                                     if (e.keyCode == 53) {
                                       [ui->evidence close];
                                       return nil;
                                     }
                                     return e;
                                   }];
  [self refresh];
}
- (void)dealloc {
  [refreshTimer invalidate];
  [playTimer invalidate];
  [searchTimer invalidate];
  if (keyMonitor)
    [NSEvent removeMonitor:keyMonitor];
}
- (void)viewDidLayout {
  [super viewDidLayout];
  [self resizeCanvas];
}
- (void)resizeCanvas {
  NSSize size = imageScroll.contentSize;
  canvas.frame =
      NSMakeRect(0, 0, MAX(1, size.width * zoom), MAX(1, size.height * zoom));
  canvas.needsDisplay = YES;
}
- (void)error:(std::string)message {
  if (message.empty())
    return;
  status.stringValue = S(message);
  status.toolTip = S(message);
}
- (void)refresh {
  request(@"state", json::object(), ^(json s, std::string error) {
    if (!error.empty()) {
      [self error:error];
      return;
    }
    self->state = s;
    self->record.title =
        s.value("recording", false) ? @"Pause" : @"Start recording";
    self->status.stringValue = S(s.value("captureState", "Paused"));
    self->status.toolTip = S(s.value("error", ""));
    long long count = s.value("count", 0LL);
    double last = s.value("last", 0.0);
    if (self->lastCount < 0 && last > 0)
      self->date.dateValue = [NSDate dateWithTimeIntervalSince1970:last];
    if (self->lastCount != count || self->lastTime != last) {
      self->lastCount = count;
      self->lastTime = last;
      [self updateApps];
      [self loadFrames];
    }
  });
}
- (void)updateApps {
  NSString *value = apps.selectedItem.representedObject ?: @"";
  [apps removeAllItems];
  [apps addItemWithTitle:@"All apps"];
  apps.lastItem.representedObject = @"";
  if (state.contains("apps"))
    for (auto &a : state["apps"]) {
      [apps addItemWithTitle:S(a.value("name", "Unknown"))];
      apps.lastItem.representedObject = S(a.value("bundle", ""));
    }
  for (NSMenuItem *item in apps.itemArray)
    if ([item.representedObject isEqual:value])
      [apps selectItem:item];
}
- (void)loadFrames {
  if (loading)
    return;
  loading = YES;
  NSDate *start = [NSCalendar.currentCalendar startOfDayForDate:date.dateValue];
  NSDate *end = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay
                                                       value:1
                                                      toDate:start
                                                     options:0];
  json args = {{"query", T(search.stringValue)},
               {"app", T(apps.selectedItem.representedObject ?: @"")},
               {"from", start.timeIntervalSince1970},
               {"to", end.timeIntervalSince1970},
               {"limit", 200},
               {"offset", (int)offset}};
  long long keep = selected >= 0 && selected < (NSInteger)frames.size()
                       ? frames[selected]["id"].get<long long>()
                       : -1;
  request(@"frames", args, ^(json data, std::string error) {
    self->loading = NO;
    if (!error.empty()) {
      [self error:error];
      return;
    }
    self->frames = data;
    std::reverse(self->frames.begin(), self->frames.end());
    self->selected =
        self->frames.empty() ? -1 : (NSInteger)self->frames.size() - 1;
    for (NSUInteger i = 0; i < self->frames.size(); i++)
      if (self->frames[i]["id"].get<long long>() == keep)
        self->selected = i;
    self->timeline.frames = [NSJSONSerialization
        JSONObjectWithData:[S(self->frames.dump())
                               dataUsingEncoding:NSUTF8StringEncoding]
                   options:0
                     error:nil];
    [self rebuildFilm];
    [self selectMoment];
  });
}
- (NSString *)imagePath:(long long)identity {
  return [root
      stringByAppendingPathComponent:[NSString
                                         stringWithFormat:@"frames/%lld.jpg",
                                                          identity]];
}
- (void)rebuildFilm {
  for (NSView *v in film.arrangedSubviews.copy) {
    [film removeArrangedSubview:v];
    [v removeFromSuperview];
  }
  for (NSUInteger i = 0; i < frames.size(); i++) {
    auto f = frames[i];
    NSButton *b = button(@"", self, @selector(pick:), nil);
    b.tag = i;
    b.bordered = NO;
    b.image = [[NSImage alloc] initWithContentsOfFile:[self imagePath:f["id"]]];
    b.imageScaling = NSImageScaleProportionallyUpOrDown;
    b.imagePosition = NSImageOnly;
    b.toolTip =
        [NSString stringWithFormat:@"%@ · %@\n%@", S(f.value("app", "")),
                                   timeText(f.value("time", 0.0)),
                                   S(f.value("title", ""))];
    [b setAccessibilityLabel:b.toolTip];
    [b.widthAnchor constraintEqualToConstant:108].active = YES;
    [b.heightAnchor constraintEqualToConstant:66].active = YES;
    [film addArrangedSubview:b];
  }
  film.frame = NSMakeRect(
      0, 0, MAX(filmScroll.contentSize.width, frames.size() * 116), 78);
  [film layoutSubtreeIfNeeded];
}
- (void)selectMoment {
  BOOL has = selected >= 0 && selected < (NSInteger)frames.size();
  canvas.query = search.stringValue;
  details.enabled = exportButton.enabled = play.enabled = has;
  previous.enabled = has && selected > 0;
  next.enabled = has && selected + 1 < (NSInteger)frames.size();
  newer.hidden = offset == 0;
  earlier.hidden = frames.size() < 200;
  countLabel.stringValue =
      has ? [NSString stringWithFormat:@"%lu moments", frames.size()] : @"";
  if (!has) {
    canvas.image = nil;
    canvas.boxes = @[];
    caption.stringValue = @"";
    timestamp.stringValue = @"No moments yet";
    [playTimer invalidate];
    playTimer = nil;
    [evidence close];
  } else {
    auto f = frames[selected];
    canvas.image =
        [[NSImage alloc] initWithContentsOfFile:[self imagePath:f["id"]]];
    canvas.boxes = [NSJSONSerialization
        JSONObjectWithData:[S(f["boxes"].dump())
                               dataUsingEncoding:NSUTF8StringEncoding]
                   options:0
                     error:nil];
    caption.stringValue =
        [NSString stringWithFormat:@"%@  ·  %@", S(f.value("app", "")),
                                   S(f.value("title", ""))];
    timestamp.stringValue = timeText(f.value("time", 0.0));
    if (evidence.shown)
      [self updateEvidence];
  }
  timeline.index = selected;
  timeline.needsDisplay = YES;
  canvas.needsDisplay = YES;
  [canvas
      setAccessibilityValue:has ? caption.stringValue : @"No matching moments"];
  for (NSButton *b in film.arrangedSubviews) {
    b.wantsLayer = YES;
    b.layer.cornerRadius = 6;
    b.layer.borderWidth = b.tag == selected ? 2 : 0;
    b.layer.borderColor = mint().CGColor;
    if (b.tag == selected)
      [film scrollRectToVisible:b.frame];
  }
}
- (void)controlTextDidChange:(NSNotification *)n {
  (void)n;
  [searchTimer invalidate];
  __weak NativeUI *weak = self;
  searchTimer = [NSTimer scheduledTimerWithTimeInterval:.2
                                                repeats:NO
                                                  block:^(NSTimer *t) {
                                                    (void)t;
                                                    [weak filterChanged:nil];
                                                  }];
}
- (void)filterChanged:(id)s {
  (void)s;
  offset = 0;
  [playTimer invalidate];
  playTimer = nil;
  [self loadFrames];
}
- (void)today:(id)s {
  (void)s;
  date.dateValue = NSDate.date;
  [self filterChanged:nil];
}
- (void)pick:(NSButton *)b {
  selected = b.tag;
  [self selectMoment];
}
- (void)previous:(id)s {
  (void)s;
  if (selected > 0) {
    selected--;
    [self selectMoment];
  }
}
- (void)next:(id)s {
  (void)s;
  if (selected + 1 < (NSInteger)frames.size()) {
    selected++;
    [self selectMoment];
  }
}
- (void)newer:(id)s {
  (void)s;
  offset = MAX(0, offset - 200);
  [self loadFrames];
}
- (void)earlier:(id)s {
  (void)s;
  offset += 200;
  [self loadFrames];
}
- (void)scrub:(id)s {
  (void)s;
  selected = timeline.index;
  [self selectMoment];
}
- (void)play:(id)s {
  (void)s;
  if (playTimer) {
    [playTimer invalidate];
    playTimer = nil;
    play.image = [NSImage imageWithSystemSymbolName:@"play.fill"
                           accessibilityDescription:@"Play moments"];
    return;
  }
  if (frames.empty())
    return;
  if (selected + 1 >= (NSInteger)frames.size())
    selected = 0;
  play.image = [NSImage imageWithSystemSymbolName:@"pause.fill"
                         accessibilityDescription:@"Pause playback"];
  __weak NativeUI *weak = self;
  playTimer = [NSTimer
      scheduledTimerWithTimeInterval:1.0 / (1 << speed.indexOfSelectedItem)
                             repeats:YES
                               block:^(NSTimer *t) {
                                 NativeUI *ui = weak;
                                 if (!ui) {
                                   [t invalidate];
                                   return;
                                 }
                                 if (ui->selected + 1 >=
                                     (NSInteger)ui->frames.size()) {
                                   [ui play:nil];
                                   return;
                                 }
                                 [ui next:nil];
                               }];
  [self selectMoment];
}
- (void)speedChanged:(id)s {
  (void)s;
  if (playTimer) {
    [self play:nil];
    [self play:nil];
  }
}
- (void)zoomIn:(id)s {
  (void)s;
  zoom = MIN(4, zoom + .25);
  [self resizeCanvas];
}
- (void)zoomOut:(id)s {
  (void)s;
  zoom = MAX(1, zoom - .25);
  [self resizeCanvas];
}
- (void)fit:(id)s {
  (void)s;
  zoom = 1;
  [self resizeCanvas];
}
- (void)toggle:(id)s {
  (void)s;
  request(@"toggle", json::object(), ^(json result, std::string error) {
    [self error:error];
    [self refresh];
    if (!result.value("error", "").empty()) {
      NSAlert *a = [NSAlert new];
      a.messageText = @"Allow screen recording";
      a.informativeText = S(result.value("error", ""));
      [a addButtonWithTitle:@"Open Settings"];
      [a addButtonWithTitle:@"Later"];
      [a beginSheetModalForWindow:self.view.window
                completionHandler:^(NSModalResponse r) {
                  if (r == NSAlertFirstButtonReturn)
                    self->request(@"permission", json::object(),
                                  ^(json j, std::string e) {
                                    (void)j;
                                    [self error:e];
                                  });
                }];
    }
  });
}
- (void)importImage:(id)s {
  (void)s;
  status.stringValue = @"Importing…";
  request(@"import", json::object(), ^(json j, std::string e) {
    if (!j.value("cancelled", false)) {
      self->search.stringValue = @"";
      self->date.dateValue = NSDate.date;
      self->offset = 0;
      [self->apps selectItemAtIndex:0];
      self->lastCount = -1;
      [self refresh];
    }
    [self error:e];
  });
}
- (void)exportImage:(id)s {
  (void)s;
  if (selected < 0)
    return;
  request(@"export", {{"id", frames[selected]["id"]}},
          ^(json j, std::string e) {
            (void)j;
            [self error:e];
          });
}
- (void)updateEvidence {
  if (selected < 0)
    return;
  auto f = frames[selected];
  evidenceText.string = [NSString
      stringWithFormat:@"%@\n%@\n%@ · %d × %d\n\n%@\n\nText recognized on this "
                       @"Mac. Check the screenshot for accuracy.",
                       S(f.value("app", "")), timeText(f.value("time", 0.0)),
                       f.value("source", "") == "import" ? @"Imported image"
                                                         : @"Screen capture",
                       f.value("width", 0), f.value("height", 0),
                       S(f.value("text", ""))];
}
- (void)showEvidence:(id)s {
  (void)s;
  if (selected < 0)
    return;
  if (evidence.shown) {
    [evidence close];
    return;
  }
  NSViewController *vc = [NSViewController new];
  vc.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 440)];
  NSScrollView *scroll =
      [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 52, 328, 370)];
  scroll.hasVerticalScroller = YES;
  evidenceText = [[NSTextView alloc] initWithFrame:scroll.bounds];
  evidenceText.editable = NO;
  evidenceText.font = [NSFont systemFontOfSize:13];
  evidenceText.textColor = NSColor.labelColor;
  evidenceText.backgroundColor = NSColor.windowBackgroundColor;
  scroll.documentView = evidenceText;
  [vc.view addSubview:scroll];
  NSButton *del =
      button(@"Delete moment…", self, @selector(deleteMoment:), nil);
  del.frame = NSMakeRect(16, 12, 145, 28);
  [vc.view addSubview:del];
  NSButton *copy = button(@"Copy text", self, @selector(copyText:), nil);
  copy.frame = NSMakeRect(244, 12, 100, 28);
  [vc.view addSubview:copy];
  evidence = [NSPopover new];
  evidence.behavior = NSPopoverBehaviorTransient;
  evidence.contentViewController = vc;
  [self updateEvidence];
  [evidence showRelativeToRect:details.bounds
                        ofView:details
                 preferredEdge:NSRectEdgeMinY];
}
- (void)copyText:(id)s {
  (void)s;
  if (selected < 0)
    return;
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard
      setString:S(frames[selected].value("text", ""))
        forType:NSPasteboardTypeString];
}
- (void)deleteMoment:(id)s {
  (void)s;
  if (selected < 0)
    return;
  long long identity = frames[selected]["id"];
  [evidence close];
  NSAlert *a = [NSAlert new];
  a.messageText = @"Delete this moment?";
  a.informativeText = @"Its screenshot and searchable text will be removed.";
  [a addButtonWithTitle:@"Delete"];
  [a addButtonWithTitle:@"Cancel"];
  [a beginSheetModalForWindow:self.view.window
            completionHandler:^(NSModalResponse r) {
              if (r == NSAlertFirstButtonReturn)
                self->request(@"delete", {{"id", identity}},
                              ^(json j, std::string e) {
                                (void)j;
                                [self error:e];
                                [self refresh];
                              });
            }];
}
- (void)showSettings:(id)s {
  (void)s;
  if (settingsWindow.visible)
    return;
  settingsWindow =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  settingsWindow.title = @"Settings";
  settingsWindow.contentView =
      [[NativeSurface alloc] initWithFrame:NSMakeRect(0, 0, 520, 360)];
  interval = [NSPopUpButton new];
  retention = [NSPopUpButton new];
  for (int n : {1, 2, 5, 10, 30}) {
    [interval
        addItemWithTitle:[NSString stringWithFormat:@"Every %d seconds", n]];
    interval.lastItem.tag = n;
    if (n == state["settings"].value("interval", 2))
      [interval selectItem:interval.lastItem];
  }
  for (int n : {1, 7, 14, 30, 90, 365}) {
    [retention addItemWithTitle:[NSString stringWithFormat:@"%d days", n]];
    retention.lastItem.tag = n;
    if (n == state["settings"].value("retentionDays", 14))
      [retention selectItem:retention.lastItem];
  }
  excluded = [NSTextField new];
  excluded.placeholderString = @"com.example.private, com.example.other";
  NSMutableArray *names = [NSMutableArray new];
  for (auto &x : state["settings"]["excluded"])
    [names addObject:S(x.get<std::string>())];
  excluded.stringValue = [names componentsJoinedByString:@", "];
  NSStackView *stack = [NSStackView stackViewWithViews:@[
    row(@[ label(@"Capture interval", 13), interval ]),
    row(@[ label(@"Keep history", 13), retention ]),
    label(@"Excluded applications · bundle IDs", 12), excluded,
    label(@"Recording waits while an excluded app is focused.", 11), row(@[
      button(@"Screen Recording permission…", self, @selector(permission:),
             nil),
      button(@"Show archive", self, @selector(reveal:), nil)
    ]),
    row(@[ button(@"Delete all history…", self, @selector(clear:), nil) ]),
    row(@[
      button(@"Cancel", self, @selector(cancelSettings:), nil),
      button(@"Save", self, @selector(saveSettings:), nil)
    ])
  ]];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 16;
  stack.frame = NSMakeRect(24, 20, 472, 316);
  [excluded.widthAnchor constraintEqualToConstant:472].active = YES;
  [settingsWindow.contentView addSubview:stack];
  [self.view.window beginSheet:settingsWindow completionHandler:nil];
}
- (void)cancelSettings:(id)s {
  (void)s;
  [self.view.window endSheet:settingsWindow];
  [settingsWindow orderOut:nil];
}
- (void)saveSettings:(id)s {
  (void)s;
  json prefs = state["settings"];
  prefs["interval"] = (int)interval.selectedItem.tag;
  prefs["retentionDays"] = (int)retention.selectedItem.tag;
  prefs["excluded"] = json::array();
  for (NSString *x in [excluded.stringValue componentsSeparatedByString:@","]) {
    NSString *v = [x
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
    if (v.length)
      prefs["excluded"].push_back(T(v));
  }
  request(@"settings", prefs, ^(json j, std::string e) {
    (void)j;
    if (e.empty()) {
      [self cancelSettings:nil];
      [self refresh];
    } else
      [self error:e];
  });
}
- (void)permission:(id)s {
  (void)s;
  request(@"permission", json::object(), ^(json j, std::string e) {
    (void)j;
    [self error:e];
  });
}
- (void)reveal:(id)s {
  (void)s;
  request(@"reveal", json::object(), ^(json j, std::string e) {
    (void)j;
    [self error:e];
  });
}
- (void)clear:(id)s {
  (void)s;
  [self cancelSettings:nil];
  NSAlert *a = [NSAlert new];
  a.messageText = @"Delete all history?";
  a.informativeText =
      @"All saved screenshots and searchable text will be permanently removed.";
  [a addButtonWithTitle:@"Delete all"];
  [a addButtonWithTitle:@"Cancel"];
  [a beginSheetModalForWindow:self.view.window
            completionHandler:^(NSModalResponse r) {
              if (r == NSAlertFirstButtonReturn)
                self->request(@"clear", json::object(),
                              ^(json j, std::string e) {
                                (void)j;
                                [self error:e];
                                [self refresh];
                              });
            }];
}
- (void)smoke:(NSString *)output {
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(),
      ^{
        json checks = {{"nativeAppKit", true},
                       {"canvasFits", self->imageScroll.frame.size.width >
                                          self.view.bounds.size.width * .9},
                       {"controlsVisible", self->timeline.frame.origin.y >= 0}};
        if (!self->frames.empty()) {
          checks["imageLoaded"] = self->canvas.image != nil;
          auto original = self->frames.size();
          self->search.stringValue = @"seahorse742";
          [self filterChanged:nil];
          checks["search"] =
              !self->frames.empty() && self->frames.size() == original;
          checks["ocrHighlights"] = self->canvas.highlights > 0;
          self->search.stringValue = @"not-a-real-fixture-token-92733";
          [self filterChanged:nil];
          checks["searchMiss"] = self->frames.empty();
          self->search.stringValue = @"seahorse742";
          [self filterChanged:nil];
          checks["appNames"] =
              self->apps.numberOfItems > 1 &&
              ![self->apps.itemArray[1].title isEqualToString:@"Unknown"];
          [self->apps selectItemAtIndex:1];
          [self filterChanged:nil];
          checks["appFilter"] = !self->frames.empty();
          [self->apps selectItemAtIndex:0];
          NSDate *saved = self->date.dateValue;
          self->date.dateValue = [saved dateByAddingTimeInterval:-86400 * 3];
          [self filterChanged:nil];
          checks["dateFilter"] = self->frames.empty();
          self->date.dateValue = saved;
          [self filterChanged:nil];
          [self zoomIn:nil];
          checks["zoom"] = self->canvas.frame.size.width >
                           self->imageScroll.contentSize.width;
          [self fit:nil];
          self->timeline.index = 0;
          [self scrub:nil];
          checks["scrub"] = self->selected == 0;
          if (self->frames.size() > 1) {
            self->selected = 0;
            [self next:nil];
            checks["navigation"] = self->selected == 1;
          }
          [self showEvidence:nil];
          checks["evidence"] = self->evidenceText.string.length > 0;
          [self->evidence close];
        } else
          checks["empty"] = self->canvas.image == nil;
        [self showSettings:nil];
        checks["settings"] = self->settingsWindow.sheetParent != nil;
        [self->settingsWindow.contentView layoutSubtreeIfNeeded];
        NSView *settingsView = self->settingsWindow.contentView;
        NSBitmapImageRep *settingsRep = [settingsView
            bitmapImageRepForCachingDisplayInRect:settingsView.bounds];
        [settingsView cacheDisplayInRect:settingsView.bounds
                        toBitmapImageRep:settingsRep];
        [[settingsRep representationUsingType:NSBitmapImageFileTypePNG
                                   properties:@{}]
            writeToFile:[output stringByAppendingString:@"-settings.png"]
             atomically:YES];
        [self cancelSettings:nil];
        [self.view layoutSubtreeIfNeeded];
        BOOL passed = YES;
        for (auto &v : checks.items())
          passed &= v.value().get<bool>();
        json result = {{"passed", (bool)passed}, {"checks", checks}};
        std::ofstream(T(output) + ".json") << result.dump();
        NSBitmapImageRep *rep =
            [self.view bitmapImageRepForCachingDisplayInRect:self.view.bounds];
        [self.view cacheDisplayInRect:self.view.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[output stringByAppendingString:@".png"]
             atomically:YES];
        exit(passed ? 0 : 3);
      });
}
@end
