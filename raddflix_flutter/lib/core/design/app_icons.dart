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
  static PhosphorIconData get play           => PhosphorIcons.play(PhosphorIconsStyle.fill);
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
  static PhosphorIconData get filter         => PhosphorIcons.funnel();
  static PhosphorIconData get filterFill     => PhosphorIcons.funnel(PhosphorIconsStyle.fill);
  static PhosphorIconData get upload         => PhosphorIcons.upload();
  static PhosphorIconData get sort           => PhosphorIcons.sortAscending();

  // ── Content ───────────────────────────────────────────────────────────────
  static PhosphorIconData get heart          => PhosphorIcons.heart();
  static PhosphorIconData get heartFill      => PhosphorIcons.heart(PhosphorIconsStyle.fill);
  static PhosphorIconData get star           => PhosphorIcons.star();
  static PhosphorIconData get starFill       => PhosphorIcons.star(PhosphorIconsStyle.fill);
  static PhosphorIconData get bookmark       => PhosphorIcons.bookmark();
  static PhosphorIconData get bookmarkFill   => PhosphorIcons.bookmark(PhosphorIconsStyle.fill);
  static PhosphorIconData get image          => PhosphorIcons.image();
  static PhosphorIconData get camera         => PhosphorIcons.camera();

  // ── Media / Player ────────────────────────────────────────────────────────
  static PhosphorIconData get subtitle       => PhosphorIcons.subtitles();
  static PhosphorIconData get audioTrack     => PhosphorIcons.speakerHigh();
  static PhosphorIconData get muted          => PhosphorIcons.speakerSlash();
  static PhosphorIconData get fullscreen     => PhosphorIcons.arrowsOut();
  static PhosphorIconData get skipForward    => PhosphorIcons.skipForward(PhosphorIconsStyle.fill);
  static PhosphorIconData get skipBack       => PhosphorIcons.skipBack(PhosphorIconsStyle.fill);
  static PhosphorIconData get rewind         => PhosphorIcons.rewind(PhosphorIconsStyle.fill);
  static PhosphorIconData get fastForward    => PhosphorIcons.fastForward(PhosphorIconsStyle.fill);
  static PhosphorIconData get screenshot     => PhosphorIcons.camera(PhosphorIconsStyle.fill);
  static PhosphorIconData get loop           => PhosphorIcons.repeat();
  static PhosphorIconData get shuffle        => PhosphorIcons.shuffle();

  // ── Security / Auth ───────────────────────────────────────────────────────
  static PhosphorIconData get lock           => PhosphorIcons.lock(PhosphorIconsStyle.fill);
  static PhosphorIconData get unlock         => PhosphorIcons.lockOpen();
  static PhosphorIconData get eye            => PhosphorIcons.eye();
  static PhosphorIconData get eyeOff         => PhosphorIcons.eyeSlash();
  static PhosphorIconData get fingerprint    => PhosphorIcons.fingerprint();
  static PhosphorIconData get shield         => PhosphorIcons.shieldCheck(PhosphorIconsStyle.fill);

  // ── Status / Feedback ─────────────────────────────────────────────────────
  static PhosphorIconData get info           => PhosphorIcons.info();
  static PhosphorIconData get infoFill       => PhosphorIcons.info(PhosphorIconsStyle.fill);
  static PhosphorIconData get warning        => PhosphorIcons.warning(PhosphorIconsStyle.fill);
  static PhosphorIconData get errorIcon      => PhosphorIcons.xCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get successIcon    => PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get notification   => PhosphorIcons.bell();
  static PhosphorIconData get notificationFill => PhosphorIcons.bell(PhosphorIconsStyle.fill);

  // ── Network / Connectivity ────────────────────────────────────────────────
  static PhosphorIconData get wifi           => PhosphorIcons.wifi();
  static PhosphorIconData get wifiOff        => PhosphorIcons.wifiSlash();

  // ── Storage / Files ───────────────────────────────────────────────────────
  static PhosphorIconData get file           => PhosphorIcons.file();
  static PhosphorIconData get folder2        => PhosphorIcons.folderOpen();
  static PhosphorIconData get cloud          => PhosphorIcons.cloud();
  static PhosphorIconData get cloudDownload  => PhosphorIcons.cloudArrowDown();

  // ── User / Profile ────────────────────────────────────────────────────────
  static PhosphorIconData get userCircle     => PhosphorIcons.userCircle();
  static PhosphorIconData get userCircleFill => PhosphorIcons.userCircle(PhosphorIconsStyle.fill);
  static PhosphorIconData get users          => PhosphorIcons.users();
  static PhosphorIconData get crown          => PhosphorIcons.crown(PhosphorIconsStyle.fill);

  // ── Misc ──────────────────────────────────────────────────────────────────
  static PhosphorIconData get caretDown      => PhosphorIcons.caretDown();
  static PhosphorIconData get caretRight     => PhosphorIcons.caretRight();
  static PhosphorIconData get caretUp        => PhosphorIcons.caretUp();
  static PhosphorIconData get link           => PhosphorIcons.link();
  static PhosphorIconData get qrCode         => PhosphorIcons.qrCode();
  static PhosphorIconData get whatsapp       => PhosphorIcons.whatsappLogo();
  static PhosphorIconData get calendarCheck  => PhosphorIcons.calendarCheck();
  static PhosphorIconData get history        => PhosphorIcons.clockCounterClockwise();
  static PhosphorIconData get colorPalette   => PhosphorIcons.palette();
  static PhosphorIconData get sparkle        => PhosphorIcons.sparkle(PhosphorIconsStyle.fill);
}
