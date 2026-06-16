// cinematic_overlay.dart
//
// Cinematic mode no longer needs a separate overlay widget.
// Controls in player_screen.dart are wrapped in Opacity(_cinematicOpacity)
// which provides the same dimmed-but-functional behaviour without gesture
// conflicts.  This file is kept only so any external references compile.
