import 'package:flutter/material.dart';

/// All available icon packs for the player UI.
enum IconPack { mx, ios, fluent, material3, cute, minimal }

IconPack iconPackFromString(String s) =>
    IconPack.values.firstWhere((e) => e.name == s,
        orElse: () => IconPack.mx);

/// Per-pack icon mappings for every player action.
class PlayerIcons {
  final IconData play;
  final IconData pause;
  final IconData forward;
  final IconData back;
  final IconData lock;
  final IconData unlock;
  final IconData settings;
  final IconData more;
  final IconData subtitles;
  final IconData audio;
  final IconData rotate;
  final IconData pip;
  final IconData skipNext;
  final IconData skipPrev;
  final IconData eq;
  final IconData bookmark;
  final IconData speed;
  final IconData sleep;
  final IconData screenshot;
  final IconData info;
  final IconData share;

  const PlayerIcons({
    required this.play, required this.pause, required this.forward,
    required this.back, required this.lock, required this.unlock,
    required this.settings, required this.more, required this.subtitles,
    required this.audio, required this.rotate, required this.pip,
    required this.skipNext, required this.skipPrev, required this.eq,
    required this.bookmark, required this.speed, required this.sleep,
    required this.screenshot, required this.info, required this.share,
  });
}

const _mx = PlayerIcons(
  play:       Icons.play_arrow_rounded,
  pause:      Icons.pause_rounded,
  forward:    Icons.forward_10_rounded,
  back:       Icons.replay_10_rounded,
  lock:       Icons.lock_rounded,
  unlock:     Icons.lock_open_rounded,
  settings:   Icons.settings_rounded,
  more:       Icons.more_vert_rounded,
  subtitles:  Icons.subtitles_rounded,
  audio:      Icons.audiotrack_rounded,
  rotate:     Icons.screen_rotation_rounded,
  pip:        Icons.picture_in_picture_rounded,
  skipNext:   Icons.skip_next_rounded,
  skipPrev:   Icons.skip_previous_rounded,
  eq:         Icons.equalizer_rounded,
  bookmark:   Icons.bookmark_rounded,
  speed:      Icons.speed_rounded,
  sleep:      Icons.bedtime_rounded,
  screenshot: Icons.screenshot_monitor_rounded,
  info:       Icons.info_outline_rounded,
  share:      Icons.share_rounded,
);

const _ios = PlayerIcons(
  play:       Icons.play_circle_outline,
  pause:      Icons.pause_circle_outline,
  forward:    Icons.arrow_forward_ios_rounded,
  back:       Icons.arrow_back_ios_rounded,
  lock:       Icons.lock_outline,
  unlock:     Icons.lock_open_outlined,
  settings:   Icons.settings_outlined,
  more:       Icons.more_horiz,
  subtitles:  Icons.closed_caption_outlined,
  audio:      Icons.music_note_outlined,
  rotate:     Icons.rotate_right_outlined,
  pip:        Icons.picture_in_picture_alt_rounded,
  skipNext:   Icons.skip_next,
  skipPrev:   Icons.skip_previous,
  eq:         Icons.graphic_eq_outlined,
  bookmark:   Icons.bookmark_outline_rounded,
  speed:      Icons.timelapse,
  sleep:      Icons.nights_stay_outlined,
  screenshot: Icons.crop_rounded,
  info:       Icons.info_outline,
  share:      Icons.ios_share,
);

const _fluent = PlayerIcons(
  play:       Icons.play_arrow,
  pause:      Icons.pause,
  forward:    Icons.fast_forward,
  back:       Icons.fast_rewind,
  lock:       Icons.lock,
  unlock:     Icons.lock_open,
  settings:   Icons.tune,
  more:       Icons.more_horiz,
  subtitles:  Icons.subtitles,
  audio:      Icons.spatial_audio_rounded,
  rotate:     Icons.crop_rotate,
  pip:        Icons.picture_in_picture,
  skipNext:   Icons.skip_next,
  skipPrev:   Icons.skip_previous,
  eq:         Icons.equalizer,
  bookmark:   Icons.bookmark,
  speed:      Icons.av_timer,
  sleep:      Icons.bedtime,
  screenshot: Icons.photo_camera_rounded,
  info:       Icons.info,
  share:      Icons.share,
);

const _material3 = PlayerIcons(
  play:       Icons.play_arrow_rounded,
  pause:      Icons.pause_rounded,
  forward:    Icons.forward_30_rounded,
  back:       Icons.replay_30_rounded,
  lock:       Icons.lock_rounded,
  unlock:     Icons.lock_open_rounded,
  settings:   Icons.settings_rounded,
  more:       Icons.more_vert_rounded,
  subtitles:  Icons.subtitles_rounded,
  audio:      Icons.hearing_rounded,
  rotate:     Icons.screen_rotation_alt_rounded,
  pip:        Icons.picture_in_picture_rounded,
  skipNext:   Icons.skip_next_rounded,
  skipPrev:   Icons.skip_previous_rounded,
  eq:         Icons.graphic_eq_rounded,
  bookmark:   Icons.bookmark_added_rounded,
  speed:      Icons.speed_rounded,
  sleep:      Icons.dark_mode_rounded,
  screenshot: Icons.screenshot_rounded,
  info:       Icons.info_rounded,
  share:      Icons.adaptive_share_rounded,
);

const _cute = PlayerIcons(
  play:       Icons.play_circle_filled_rounded,
  pause:      Icons.pause_circle_filled_rounded,
  forward:    Icons.arrow_circle_right_rounded,
  back:       Icons.arrow_circle_left_rounded,
  lock:       Icons.security_rounded,
  unlock:     Icons.no_encryption_rounded,
  settings:   Icons.manage_accounts_rounded,
  more:       Icons.apps_rounded,
  subtitles:  Icons.chat_bubble_rounded,
  audio:      Icons.music_note_rounded,
  rotate:     Icons.autorenew_rounded,
  pip:        Icons.open_in_new_rounded,
  skipNext:   Icons.navigate_next_rounded,
  skipPrev:   Icons.navigate_before_rounded,
  eq:         Icons.bar_chart_rounded,
  bookmark:   Icons.favorite_rounded,
  speed:      Icons.bolt_rounded,
  sleep:      Icons.mode_night_rounded,
  screenshot: Icons.add_a_photo_rounded,
  info:       Icons.help_rounded,
  share:      Icons.send_rounded,
);

const _minimal = PlayerIcons(
  play:       Icons.play_arrow,
  pause:      Icons.pause,
  forward:    Icons.arrow_right_alt,
  back:       Icons.arrow_left_alt_rounded,
  lock:       Icons.lock_outline,
  unlock:     Icons.lock_open_outlined,
  settings:   Icons.tune,
  more:       Icons.more_horiz,
  subtitles:  Icons.closed_caption_disabled,
  audio:      Icons.volume_up_outlined,
  rotate:     Icons.rotate_right,
  pip:        Icons.crop_square,
  skipNext:   Icons.chevron_right,
  skipPrev:   Icons.chevron_left,
  eq:         Icons.bar_chart,
  bookmark:   Icons.flag_outlined,
  speed:      Icons.timer_outlined,
  sleep:      Icons.hourglass_empty,
  screenshot: Icons.crop,
  info:       Icons.help_outline,
  share:      Icons.upload,
);

/// Get icons for a given pack.
PlayerIcons iconsFor(IconPack pack) {
  switch (pack) {
    case IconPack.mx:        return _mx;
    case IconPack.ios:       return _ios;
    case IconPack.fluent:    return _fluent;
    case IconPack.material3: return _material3;
    case IconPack.cute:      return _cute;
    case IconPack.minimal:   return _minimal;
  }
}
