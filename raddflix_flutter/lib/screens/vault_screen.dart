import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../services/vault_service.dart';
import 'vault_settings_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/thumb_service.dart';

class VaultScreen extends StatefulWidget {
  final String? folderPath;
  final String? folderName;
  const VaultScreen({super.key, this.folderPath, this.folderName});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  RaddTheme get t => RaddTheme.of(context);

  List<VaultFile> _files = [];
  bool _loading = true;
  bool _gridView = false;
  Set<String> _selected = {};
  bool _selectMode = false;
  int _totalSize = 0;
  bool _isFake = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFake = VaultService.isFakeVault;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // FIX-VAULT-AUTOLOCK: Only lock immediately when auto-lock = 0 (instant).
      // For any other setting, just record pause time — isUnlocked already
      // checks elapsed time and locks if the threshold has passed.
      // Previously we called VaultService.lock() unconditionally which caused
      // the vault to ask for PIN every time notifications were swiped or a
      // call arrived (any pause > 0ms triggered a full re-lock).
      VaultService.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      if (!VaultService.isUnlocked) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.vaultLock);
      } else {
        VaultService.refreshUnlockTime();
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await VaultService.listFiles(
        folder: widget.folderPath != null
            ? widget.folderPath!.split('/').last
            : null);
    final size = widget.folderPath == null ? await VaultService.totalVaultSize() : 0;
    if (mounted) setState(() { _files = files; _totalSize = size; _loading = false; });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(path);
        _selectMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Delete $count item${count > 1 ? 's' : ''}?',
            style: TextStyle(color: t.textPrimary)),
        content: Text('This permanently removes the file${count > 1 ? 's' : ''} from the vault.',
            style: TextStyle(color: t.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    for (final path in _selected) {
      await VaultService.deleteVaultFile(path);
    }
    HapticFeedback.mediumImpact();
    setState(() { _selected.clear(); _selectMode = false; });
    await _load();
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('New Folder', style: TextStyle(color: t.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: t.textPrimary),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: t.textSecondary),
            filled: true, fillColor: t.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text('Create', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await VaultService.createFolder(name);
    await _load();
  }

  void _openFile(VaultFile f) {
    if (f.isFolder) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VaultScreen(folderPath: f.path, folderName: f.name),
      ));
      return;
    }
    if (f.isVideo) {
      Navigator.of(context).pushNamed(AppRoutes.player, arguments: {
        'file_id': '',
        'title': f.name,
        'local_path': f.path,
      });
    }
  }

  Future<void> _renameFile(VaultFile f) async {
    final ctrl = TextEditingController(text: f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Rename', style: TextStyle(color: t.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: t.textPrimary),
          decoration: InputDecoration(
            filled: true, fillColor: t.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text('Rename', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == f.name) return;
    await VaultService.renameFile(f.path, name);
    await _load();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final isRoot = widget.folderPath == null;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: _selectMode
            ? IconButton(
                icon: const Icon(AppIcons.close),
                onPressed: () => setState(() { _selected.clear(); _selectMode = false; }),
              )
            : (isRoot
                ? IconButton(
                    icon: const Icon(AppIcons.lock),
                    tooltip: 'Lock vault',
                    onPressed: () {
                      VaultService.lock();
                      Navigator.of(context).pushReplacementNamed(AppRoutes.vaultLock);
                    },
                  )
                : null),
        title: _selectMode
            ? Text('${_selected.length} selected',
                style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w700))
            : Row(children: [
                if (!isRoot) ...[
                  Icon(AppIcons.localMediaFill, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                ],
                if (isRoot)
                  RichText(text: TextSpan(
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    children: [
                      TextSpan(text: _isFake ? '📁 ' : '🔒 ', style: TextStyle(fontSize: 16)),
                      const TextSpan(text: 'Private ', style: TextStyle(color: Colors.white)),
                      const TextSpan(text: 'Vault', style: TextStyle(color: AppColors.primary)),
                    ],
                  ))
                else
                  Text(
                    widget.folderName ?? 'Folder',
                    style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
              ]),
        actions: _selectMode
            ? [
                IconButton(
                    icon: const Icon(AppIcons.trash, color: Colors.red),
                    onPressed: _deleteSelected),
                if (_selected.length == 1)
                  IconButton(
                      icon: Icon(AppIcons.edit),
                      onPressed: () {
                        final f = _files.firstWhere((f) => f.path == _selected.first);
                        _renameFile(f);
                      }),
                IconButton(
                    icon: Icon(_selected.length == _files.length
                        ? AppIcons.deselect : AppIcons.selectAll),
                    onPressed: () => setState(() {
                      if (_selected.length == _files.length) {
                        _selected.clear(); _selectMode = false;
                      } else {
                        _selected = _files.map((f) => f.path).toSet();
                      }
                    })),
              ]
            : [
                IconButton(
                    icon: Icon(_gridView ? AppIcons.listView : AppIcons.gridView),
                    color: t.textSecondary,
                    onPressed: () => setState(() => _gridView = !_gridView)),
                if (isRoot)
                  IconButton(
                      icon: Icon(AppIcons.settings),
                      color: t.textSecondary,
                      onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const VaultSettingsScreen()),
                          ).then((_) => _load())),
              ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (isRoot && _totalSize > 0)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(children: [
                      Icon(AppIcons.storage, color: AppColors.primary, size: 18),
                      SizedBox(width: 10),
                      Text('Vault size: ', style: TextStyle(color: t.textSecondary, fontSize: 13)),
                      Text(_formatSize(_totalSize),
                          style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${_files.length} items',
                          style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    ]),
                  ).animate().fadeIn(),

                Expanded(
                  child: _files.isEmpty
                      ? Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(AppIcons.unlock, size: 64, color: t.border),
                            SizedBox(height: 16),
                            Text('Vault is empty', style: TextStyle(
                                color: t.textSecondary, fontSize: 16)),
                            SizedBox(height: 8),
                            Text('Add files using the + button below',
                                style: TextStyle(color: t.textSecondary, fontSize: 13)),
                          ]).animate().fadeIn(),
                        )
                      : _gridView
                          ? _buildGrid()
                          : _buildList(),
                ),
              ],
            ),
      floatingActionButton: !_selectMode
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(AppIcons.add),
              label: const Text('Add'),
              onPressed: _showAddMenu,
            )
          : null,
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _files.length,
      itemBuilder: (_, i) {
        final f = _files[i];
        final selected = _selected.contains(f.path);
        return _FileListTile(
          file: f,
          selected: selected,
          selectMode: _selectMode,
          onTap: () => _selectMode ? _toggleSelect(f.path) : _openFile(f),
          onLongPress: () { HapticFeedback.mediumImpact(); _toggleSelect(f.path); },
          onMenuTap: () => _showFileMenu(f),
        ).animate(delay: Duration(milliseconds: i * 30)).fadeIn();
      },
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.8,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: _files.length,
      itemBuilder: (_, i) {
        final f = _files[i];
        final selected = _selected.contains(f.path);
        return GestureDetector(
          onTap: () => _selectMode ? _toggleSelect(f.path) : _openFile(f),
          onLongPress: () { HapticFeedback.mediumImpact(); _toggleSelect(f.path); },
          child: AnimatedContainer(
            duration: AppDurations.fast,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withOpacity(0.15) : t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : t.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected)
                Icon(AppIcons.successIcon, color: Color(0xFF7C5CFF), size: 40)
              else
                Icon(f.icon, color: f.isFolder ? AppColors.primary : t.textSecondary, size: 40),
              SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
              ),
              SizedBox(height: 4),
              Text(f.displaySize, style: TextStyle(color: t.textSecondary, fontSize: 10)),
            ]),
          ),
        ).animate(delay: Duration(milliseconds: i * 25)).fadeIn().scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  void _showFileMenu(VaultFile f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
          ListTile(leading: Icon(f.icon, color: AppColors.primary),
              title: Text(f.name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600))),
          const Divider(height: 1),
          if (f.isVideo)
            _SheetTile(icon: AppIcons.play, label: 'Play', onTap: () {
              Navigator.pop(context); _openFile(f);
            }),
          _SheetTile(icon: AppIcons.edit, label: 'Rename', onTap: () {
            Navigator.pop(context); _renameFile(f);
          }),
          if (!f.isFolder)
            _SheetTile(icon: AppIcons.refresh, label: 'Restore to Gallery', onTap: () async {
              Navigator.pop(context);
              await _restoreToGallery(f);
            }),
          _SheetTile(icon: AppIcons.trash, label: 'Delete', color: Colors.red,
              onTap: () async {
                Navigator.pop(context);
                await VaultService.deleteVaultFile(f.path);
                await _load();
              }),
          SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _restoreToGallery(VaultFile f) async {
    try {
      final destDir = '/storage/emulated/0/Download';
      await VaultService.restoreFile(f.path, destDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restored to Downloads folder'),
          backgroundColor: t.surface,
        ));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  // _importFiles removed — replaced by _importVideoFiles / _importVideoFolder (videos only)

  Future<void> _importVideoFiles() async {
    Navigator.pop(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video, allowMultiple: true, withData: false, withReadStream: false);
      if (result == null || result.files.isEmpty) return;
      await _processPickedFiles(result.files);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not import: $e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _importVideoFolder() async {
    Navigator.pop(context);
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;
      const videoExts = ['mp4','mkv','avi','mov','ts','m2ts','wmv','flv','webm','3gp','m4v'];
      final videoFiles = Directory(dir).listSync(recursive: false)
          .whereType<File>()
          .where((f) => videoExts.contains(f.path.split('.').last.toLowerCase()))
          .toList();
      if (videoFiles.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No video files found in that folder'), backgroundColor: t.surface));
        return;
      }
      final folder = widget.folderPath != null ? widget.folderPath!.split('/').last : null;
      for (final f in videoFiles) await VaultService.moveFileToVault(f.path, folder: folder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${videoFiles.length} video${videoFiles.length > 1 ? "s" : ""} imported'),
          backgroundColor: t.surface));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not import folder: $e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _processPickedFiles(List<PlatformFile> files) async {
    int imported = 0; bool hadBytesOnly = false;
    final contentUris = <String>[];
    final folder = widget.folderPath != null ? widget.folderPath!.split('/').last : null;
    for (final file in files) {
      final src = file.path;
      if (src != null) {
        await VaultService.moveFileToVault(src, folder: folder);
        final uri = file.identifier;
        if (uri != null && uri.isNotEmpty) contentUris.add(uri);
        imported++;
      } else { hadBytesOnly = true; }
    }
    if (contentUris.isNotEmpty) await VaultService.deleteFromMediaStore(contentUris);
    if (mounted && imported > 0) {
      final msg = hadBytesOnly
          ? '$imported file${imported > 1 ? "s" : ""} added. Some originals may still appear in gallery.'
          : '$imported video${imported > 1 ? "s" : ""} added to vault';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: t.surface,
        duration: Duration(seconds: hadBytesOnly ? 5 : 3)));
      await _load();
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add to Vault', style: TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          _SheetTile(icon: AppIcons.createFolder, label: 'New Folder',
              onTap: () { Navigator.pop(context); _createFolder(); }),
          _SheetTile(icon: AppIcons.videoLibrary, label: 'Add Video Files',
              subtitle: 'Pick individual video files',
              onTap: () => _importVideoFiles()),
          _SheetTile(icon: AppIcons.folder2, label: 'Add Folder',
              subtitle: 'Import all videos from a folder',
              onTap: () => _importVideoFolder()),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _FileListTile extends StatefulWidget {
  final VaultFile file;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuTap;
  const _FileListTile({required this.file, required this.selected,
    required this.selectMode, required this.onTap,
    required this.onLongPress, required this.onMenuTap});
  @override
  State<_FileListTile> createState() => _FileListTileState();
}

class _FileListTileState extends State<_FileListTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    if (widget.file.isVideo && !widget.file.isFolder) {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final t = await ThumbService.getThumbnail(widget.file.path, timeMs: 3000, maxWidth: 120);
    if (mounted) setState(() => _thumb = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final iconWidget = (widget.file.isVideo && _thumb != null)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_thumb!, width: 44, height: 44, fit: BoxFit.cover),
          )
        : Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: widget.file.isFolder
                  ? AppColors.primary.withOpacity(0.15)
                  : t.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.file.icon,
                color: widget.file.isFolder ? AppColors.primary : t.textSecondary,
                size: 24),
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          color: widget.selected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            AnimatedSwitcher(
              duration: AppDurations.fast,
              child: widget.selected
                  ? Icon(AppIcons.successIcon, color: Color(0xFF7C5CFF), size: 40, key: ValueKey('check'))
                  : SizedBox(key: const ValueKey('icon'), width: 44, height: 44, child: iconWidget),
            ),
            SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              SizedBox(height: 3),
              Text(widget.file.displaySize,
                  style: TextStyle(color: t.textSecondary, fontSize: 12)),
            ])),
            if (!widget.selectMode)
              IconButton(
                icon: Icon(AppIcons.more, color: t.textSecondary, size: 20),
                onPressed: widget.onMenuTap,
              ),
          ]),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  const _SheetTile({required this.icon, required this.label, required this.onTap, this.subtitle, this.color});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return ListTile(
      leading: Icon(icon, color: color ?? t.textPrimary),
      title: Text(label, style: TextStyle(color: color ?? t.textPrimary)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: t.textMuted, fontSize: 12))
          : null,
      onTap: onTap,
    );
  }
}
