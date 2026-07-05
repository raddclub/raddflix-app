// lib/core/design/app_icons.dart
//
// Central icon wrapper — use AppIcons instead of raw Material Icons or
// PhosphorIcons calls scattered around the codebase. Swapping icon families
// in the future means changing this file only.
//
// Usage:
//   Icon(AppIcons.home)           // outline / regular
//   Icon(AppIcons.homeFill)       // filled / active state
//   Icon(AppIcons.search, size: 20, color: t.textMuted)

import 'package:phosphor_flutter/phosphor_flutter.dart';

// ignore_for_file: non_constant_identifier_names

class AppIcons {
  AppIcons._();

  // ── Navigation ────────────────────────────────────────────────────────────
  static PhosphorIconData get home           => PhosphorIcons.house();
  static PhosphorIconData get homeFill       => PhosphorIcons.house(PhosphorIconsStyle.fill);
  static PhosphorIconData get localMedia     => PhosphorIcons.folder();
  static PhosphorIconData get localMediaFill => PhosphorIcons.folder(PhosphorIconsStyle.fill);
  static PhosphorIconData get downloads      => PhosphorIcons.arrowCircleDown();
  static PhosphorIconData get downloadsFill  => PhosphorIcons.arrowCircleDown(PhosphorIconsStyle.fill);
  static PhosphorIconData get profile        => PhosphorIcons.user();
  static PhosphorIconData get profileFill    => PhosphorIcons.user(PhosphorIconsStyle.fill);

  // ── Actions ───────────────────────────────────────────────────────────────
  static PhosphorIconData get search         => PhosphorIcons.magnifyingGlass();
  static PhosphorIconData get searchFill     => PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.fill);
  static PhosphorIconData get play           => PhosphorIcons.play(PhosphorIconsStyle.fill);
  static PhosphorIconData get playCircle     => PhosphorIcons.playCircle();
  static PhosphorIconData get playCircleFill => PhosphorIcons.playCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get pause          => PhosphorIcons.pause(PhosphorIconsStyle.fill);
  static PhosphorIconData get settings       => PhosphorIcons.gear();
  static PhosphorIconData get settingsFill   => PhosphorIcons.gear(PhosphorIconsStyle.fill);
  static PhosphorIconData get back           => PhosphorIcons.arrowLeft();
  static PhosphorIconData get close          => PhosphorIcons.x();
  static PhosphorIconData get check          => PhosphorIcons.check();
  static PhosphorIconData get more           => PhosphorIcons.dotsThreeVertical();
  static PhosphorIconData get moreHoriz      => PhosphorIcons.dotsThree();
  static PhosphorIconData get share          => PhosphorIcons.shareNetwork();
  static PhosphorIconData get add            => PhosphorIcons.plus();
  static PhosphorIconData get trash          => PhosphorIcons.trash();
  static PhosphorIconData get edit           => PhosphorIcons.pencilSimple();
  static PhosphorIconData get copy           => PhosphorIcons.copy();
  static PhosphorIconData get refresh        => PhosphorIcons.arrowClockwise();
  static PhosphorIconData get arrowsSync     => PhosphorIcons.arrowsClockwise();
  static PhosphorIconData get filter         => PhosphorIcons.funnel();
  static PhosphorIconData get filterFill     => PhosphorIcons.funnel(PhosphorIconsStyle.fill);
  static PhosphorIconData get equalizer      => PhosphorIcons.slidersHorizontal();
  static PhosphorIconData get upload         => PhosphorIcons.upload();
  static PhosphorIconData get sort           => PhosphorIcons.sortAscending();
  static PhosphorIconData get listView       => PhosphorIcons.list();
  static PhosphorIconData get gridView       => PhosphorIcons.squaresFour();
  static PhosphorIconData get arrowDown      => PhosphorIcons.arrowDown();
  static PhosphorIconData get arrowUp        => PhosphorIcons.arrowUp();

  // ── Media / Playback ─────────────────────────────────────────────────────
  static PhosphorIconData get movie          => PhosphorIcons.filmStrip();
  static PhosphorIconData get movieFill      => PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
  static PhosphorIconData get filmSlate      => PhosphorIcons.filmSlate();
  static PhosphorIconData get tv             => PhosphorIcons.television();
  static PhosphorIconData get tvFill         => PhosphorIcons.television(PhosphorIconsStyle.fill);
  static PhosphorIconData get liveTv         => PhosphorIcons.broadcast();
  static PhosphorIconData get videoLibrary   => PhosphorIcons.filmStrip();
  static PhosphorIconData get music          => PhosphorIcons.musicNote();
  static PhosphorIconData get musicFill      => PhosphorIcons.musicNote(PhosphorIconsStyle.fill);
  static PhosphorIconData get subtitle       => PhosphorIcons.subtitles();
  static PhosphorIconData get audioTrack     => PhosphorIcons.speakerHigh();
  static PhosphorIconData get muted          => PhosphorIcons.speakerSlash();
  static PhosphorIconData get fullscreen     => PhosphorIcons.arrowsOut();
  static PhosphorIconData get skipForward    => PhosphorIcons.skipForward(PhosphorIconsStyle.fill);
  static PhosphorIconData get skipBack       => PhosphorIcons.skipBack(PhosphorIconsStyle.fill);
  static PhosphorIconData get rewind         => PhosphorIcons.rewind(PhosphorIconsStyle.fill);
  static PhosphorIconData get fastForward    => PhosphorIcons.fastForward(PhosphorIconsStyle.fill);
  static PhosphorIconData get screenshotIcon => PhosphorIcons.camera(PhosphorIconsStyle.fill);
  static PhosphorIconData get loop           => PhosphorIcons.repeat();
  static PhosphorIconData get shuffle        => PhosphorIcons.shuffle();
  static PhosphorIconData get rotate         => PhosphorIcons.arrowsClockwise();
  static PhosphorIconData get pip            => PhosphorIcons.frameCorners();
  static PhosphorIconData get stopIcon       => PhosphorIcons.stop(PhosphorIconsStyle.fill);

  // ── Download / Storage ────────────────────────────────────────────────────
  static PhosphorIconData get downloadAction => PhosphorIcons.downloadSimple();
  static PhosphorIconData get downloadDone   => PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get cloudDownload  => PhosphorIcons.cloudArrowDown();
  static PhosphorIconData get cloudUpload    => PhosphorIcons.cloudArrowUp();
  static PhosphorIconData get storage        => PhosphorIcons.hardDrive();
  static PhosphorIconData get file           => PhosphorIcons.file();
  static PhosphorIconData get folder2        => PhosphorIcons.folderOpen();
  static PhosphorIconData get folderX        => PhosphorIcons.folderMinus();
  static PhosphorIconData get createFolder   => PhosphorIcons.folderPlus();
  static PhosphorIconData get systemUpdate   => PhosphorIcons.arrowCircleUp();
  static PhosphorIconData get videoCamera    => PhosphorIcons.videoCamera();
  static PhosphorIconData get deselect       => PhosphorIcons.minusSquare();
  static PhosphorIconData get selectAll      => PhosphorIcons.checkSquare(PhosphorIconsStyle.fill);
  static PhosphorIconData get backspace      => PhosphorIcons.backspace();

  // ── Content ───────────────────────────────────────────────────────────────
  static PhosphorIconData get heart          => PhosphorIcons.heart();
  static PhosphorIconData get heartFill      => PhosphorIcons.heart(PhosphorIconsStyle.fill);
  static PhosphorIconData get star           => PhosphorIcons.star();
  static PhosphorIconData get starFill       => PhosphorIcons.star(PhosphorIconsStyle.fill);
  static PhosphorIconData get bookmark       => PhosphorIcons.bookmark();
  static PhosphorIconData get bookmarkFill   => PhosphorIcons.bookmark(PhosphorIconsStyle.fill);
  static PhosphorIconData get image          => PhosphorIcons.image();
  static PhosphorIconData get camera         => PhosphorIcons.camera();
  static PhosphorIconData get tag            => PhosphorIcons.tag();
  static PhosphorIconData get tagFill        => PhosphorIcons.tag(PhosphorIconsStyle.fill);
  static PhosphorIconData get newReleases    => PhosphorIcons.sparkle(PhosphorIconsStyle.fill);
  static PhosphorIconData get trending       => PhosphorIcons.fire(PhosphorIconsStyle.fill);
  static PhosphorIconData get gift           => PhosphorIcons.gift();

  // ── Security / Auth ───────────────────────────────────────────────────────
  static PhosphorIconData get lock           => PhosphorIcons.lock(PhosphorIconsStyle.fill);
  static PhosphorIconData get unlock         => PhosphorIcons.lockOpen();
  static PhosphorIconData get eye            => PhosphorIcons.eye();
  static PhosphorIconData get eyeOff         => PhosphorIcons.eyeSlash();
  static PhosphorIconData get fingerprint    => PhosphorIcons.fingerprint();
  static PhosphorIconData get shield         => PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill);
  static PhosphorIconData get pinCode        => PhosphorIcons.password();
  static PhosphorIconData get block          => PhosphorIcons.prohibit(PhosphorIconsStyle.fill);

  // ── Status / Feedback ─────────────────────────────────────────────────────
  static PhosphorIconData get info           => PhosphorIcons.info();
  static PhosphorIconData get infoFill       => PhosphorIcons.info(PhosphorIconsStyle.fill);
  static PhosphorIconData get warning        => PhosphorIcons.warning(PhosphorIconsStyle.fill);
  static PhosphorIconData get errorIcon      => PhosphorIcons.xCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get successIcon    => PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get notification   => PhosphorIcons.bell();
  static PhosphorIconData get notificationFill => PhosphorIcons.bell(PhosphorIconsStyle.fill);
  static PhosphorIconData get hourglass      => PhosphorIcons.hourglass();
  static PhosphorIconData get clock          => PhosphorIcons.clock();
  static PhosphorIconData get timerIcon      => PhosphorIcons.timer();
  static PhosphorIconData get calendar       => PhosphorIcons.calendarBlank();
  static PhosphorIconData get bugReport      => PhosphorIcons.bug();
  static PhosphorIconData get tools          => PhosphorIcons.wrench();

  // ── Network / Connectivity ────────────────────────────────────────────────
  static PhosphorIconData get wifi           => PhosphorIcons.wifiHigh();
  static PhosphorIconData get wifiOff        => PhosphorIcons.wifiSlash();
  static PhosphorIconData get dataSaver      => PhosphorIcons.waveform();

  // ── User / Profile ────────────────────────────────────────────────────────
  static PhosphorIconData get userCircle     => PhosphorIcons.userCircle();
  static PhosphorIconData get userCircleFill => PhosphorIcons.userCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get users          => PhosphorIcons.users();
  static PhosphorIconData get crown          => PhosphorIcons.crown(PhosphorIconsStyle.fill);
  static PhosphorIconData get manageAccount  => PhosphorIcons.userGear();
  static PhosphorIconData get personAdd      => PhosphorIcons.userPlus();
  static PhosphorIconData get logout         => PhosphorIcons.signOut();
  static PhosphorIconData get phone          => PhosphorIcons.phone();
  static PhosphorIconData get mail           => PhosphorIcons.envelope();
  static PhosphorIconData get device         => PhosphorIcons.deviceMobile();
  static PhosphorIconData get devices        => PhosphorIcons.monitor();
  static PhosphorIconData get support        => PhosphorIcons.headset();
  static PhosphorIconData get clearCache     => PhosphorIcons.broom();
  static PhosphorIconData get receipt        => PhosphorIcons.receipt();
  static PhosphorIconData get verified       => PhosphorIcons.sealCheck(PhosphorIconsStyle.fill);
  static PhosphorIconData get wallet         => PhosphorIcons.wallet();
  static PhosphorIconData get sendMessage    => PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.fill);

  // ── Theme / Display ───────────────────────────────────────────────────────
  static PhosphorIconData get moon           => PhosphorIcons.moon(PhosphorIconsStyle.fill);
  static PhosphorIconData get sun            => PhosphorIcons.sun(PhosphorIconsStyle.fill);
  static PhosphorIconData get brightness     => PhosphorIcons.sunHorizon();
  static PhosphorIconData get colorPalette   => PhosphorIcons.palette();
  static PhosphorIconData get lightning      => PhosphorIcons.lightning(PhosphorIconsStyle.fill);

  // ── Navigation chevrons ───────────────────────────────────────────────────
  static PhosphorIconData get caretDown      => PhosphorIcons.caretDown();
  static PhosphorIconData get caretRight     => PhosphorIcons.caretRight();
  static PhosphorIconData get caretUp        => PhosphorIcons.caretUp();
  static PhosphorIconData get caretLeft      => PhosphorIcons.caretLeft();

  // ── Communication ─────────────────────────────────────────────────────────
  static PhosphorIconData get chat           => PhosphorIcons.chatCircle();
  static PhosphorIconData get link           => PhosphorIcons.link();
  static PhosphorIconData get qrCode         => PhosphorIcons.qrCode();
  static PhosphorIconData get whatsapp       => PhosphorIcons.whatsappLogo();

  // ── Misc ──────────────────────────────────────────────────────────────────
  static PhosphorIconData get calendarCheck  => PhosphorIcons.calendarCheck();
  static PhosphorIconData get history        => PhosphorIcons.clockCounterClockwise();
  static PhosphorIconData get sparkle        => PhosphorIcons.sparkle(PhosphorIconsStyle.fill);
  static PhosphorIconData get minusCircle    => PhosphorIcons.minusCircle();
  static PhosphorIconData get category       => PhosphorIcons.squaresFour();
  static PhosphorIconData get cancel         => PhosphorIcons.xCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get pin            => PhosphorIcons.pushPin(PhosphorIconsStyle.fill);
  static PhosphorIconData get timeline       => PhosphorIcons.chartLineUp();
}
