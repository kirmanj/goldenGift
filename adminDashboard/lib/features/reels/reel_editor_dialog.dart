import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/reel_model.dart';

import '../../core/session/admin_session.dart';
import '../../core/web/video_probe.dart';
import '../../core/widgets/form_widgets.dart';
import 'data/reel_media.dart';
import 'data/reels_admin_repository.dart';
import 'reel_product_picker.dart';
import 'reel_widgets.dart';

/// Create ([reel] == null) or edit dialog (SRS §9 Reels). Resolves to true when saved.
Future<bool> showReelEditor(BuildContext context, {ReelModel? reel}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReelEditorDialog(reel: reel),
  );
  return saved ?? false;
}

/// Product picker, MP4 upload (progress) to `reels/{id}.mp4`, the poster
/// captured in the browser (or **Replace poster**) to `reels/{id}.jpg`,
/// duration / aspect ratio read from the file, optional trilingual caption
/// (≤ 150) and the Active switch. Save = uploads, then ONE batch (reel +
/// derived fields + audit entry, [ReelsAdminRepository.save]). Editing
/// without a new video keeps the stored video and poster.
class ReelEditorDialog extends ConsumerStatefulWidget {
  const ReelEditorDialog({super.key, this.reel});
  final ReelModel? reel;

  @override
  ConsumerState<ReelEditorDialog> createState() => _ReelEditorDialogState();
}

class _ReelEditorDialogState extends ConsumerState<ReelEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final ReelModel? _original = widget.reel;

  /// Known before any upload, so a new reel's files go to `reels/{id}.*`.
  late final String _id = _original?.id ?? ref.read(reelsAdminRepositoryProvider).newId();

  ProductModel? _product;
  bool _loadingProduct = false;
  String? _missingProductId;

  PickedReelFile? _video;
  VideoProbe? _probe;
  bool _probing = false;
  int _probeGeneration = 0;

  /// A picked replacement poster (overrides the captured frame).
  PickedReelFile? _poster;

  late LocalizedText _caption = _original?.caption ?? LocalizedText.empty;
  late bool _isActive = _original?.isActive ?? true;

  // What an earlier attempt already uploaded, so retrying a failed save
  // doesn't upload the same file again.
  Object? _uploadedVideoFor;
  String? _uploadedVideoUrl;
  Object? _uploadedPosterFor;
  String? _uploadedPosterUrl;

  bool _saving = false;
  String? _phase;
  double? _progress;
  Map<String, String> _errors = const {};
  String? _error;

  bool get _isNew => _original == null;

  @override
  void initState() {
    super.initState();
    final productId = _original?.productId ?? '';
    if (productId.isNotEmpty) _loadProduct(productId);
  }

  Future<void> _loadProduct(String id) async {
    setState(() => _loadingProduct = true);
    try {
      final p = await ref.read(reelsAdminRepositoryProvider).loadProduct(id);
      if (!mounted) return;
      setState(() {
        _product = p;
        _missingProductId = p == null ? id : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the product: $e');
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  Future<void> _pickVideo() async {
    final file = await ref.read(reelFilePickerProvider)(ReelFileKind.video);
    if (file == null || !mounted) return;
    final error = reelVideoFileError(file.name, file.size);
    if (error != null) {
      setState(() => _errors = {..._errors, 'video': error});
      return;
    }
    final generation = ++_probeGeneration;
    setState(() {
      _video = file;
      _probe = null;
      _probing = true;
      _errors = {..._errors}..remove('video');
    });
    VideoProbe? probe;
    try {
      probe = await ref.read(reelVideoProberProvider)(file.bytes);
    } catch (_) {
      probe = null;
    }
    if (!mounted || generation != _probeGeneration) return;
    setState(() {
      _probe = probe;
      _probing = false;
    });
  }

  Future<void> _pickPoster() async {
    final file = await ref.read(reelFilePickerProvider)(ReelFileKind.poster);
    if (file == null || !mounted) return;
    final error = reelPosterFileError(file.name, file.size);
    setState(() {
      if (error != null) {
        _errors = {..._errors, 'poster': error};
      } else {
        _poster = file;
        _errors = {..._errors}..remove('poster');
      }
    });
  }

  /// Duration / aspect ratio / size the reel will be saved with.
  int? get _durationMs => _video != null ? _probe?.durationMs : _original?.durationMs;
  double? get _aspectRatio => _video != null ? _probe?.aspectRatio : _original?.aspectRatio;

  Future<void> _save() async {
    final errors = <String, String>{
      if (_product == null) 'product': 'Choose the product this reel shows.',
      if (_isNew && _video == null) 'video': 'Choose the video (MP4).',
    };
    final formOk = _form.currentState?.validate() ?? true;
    setState(() {
      _errors = {...errors, if (_errors['poster'] != null) 'poster': _errors['poster']!};
      _error = errors.isNotEmpty ? errors.values.join('\n') : (formOk ? null : 'Fix the highlighted fields.');
    });
    if (errors.isNotEmpty || !formOk) return;
    final uid = ref.read(adminSessionProvider)?.uid;
    if (uid == null) {
      setState(() => _error = 'Your session has ended — sign in again.');
      return;
    }
    setState(() => _saving = true);
    final media = ref.read(reelMediaStoreProvider);
    try {
      var videoUrl = _original?.videoUrl ?? '';
      var posterUrl = _original?.posterUrl;
      final video = _video;
      if (video != null) {
        if (!identical(_uploadedVideoFor, video)) {
          setState(() {
            _phase = 'Uploading video';
            _progress = 0;
          });
          _uploadedVideoUrl = await media.putVideo(_id, video.bytes, onProgress: (f) {
            if (mounted) setState(() => _progress = f.clamp(0.0, 1.0));
          });
          _uploadedVideoFor = video;
        }
        videoUrl = _uploadedVideoUrl!;
        posterUrl = null; // the old poster shows another video
      }
      final Object? posterSource = _poster ?? (video != null && _probe?.poster != null ? _probe : null);
      if (posterSource != null) {
        if (!identical(_uploadedPosterFor, posterSource)) {
          setState(() {
            _phase = 'Uploading poster';
            _progress = null;
          });
          final (Uint8List bytes, String type) = _poster != null
              ? (_poster!.bytes, posterContentType(_poster!.name))
              : (_probe!.poster!, 'image/jpeg');
          _uploadedPosterUrl = await media.putPoster(_id, bytes, contentType: type);
          _uploadedPosterFor = posterSource;
        }
        posterUrl = _uploadedPosterUrl;
      }
      setState(() {
        _phase = 'Saving';
        _progress = null;
      });
      await ref.read(reelsAdminRepositoryProvider).save(
            ReelModel(
              id: _id,
              productId: _product!.id,
              videoUrl: videoUrl,
              posterUrl: posterUrl,
              durationMs: _durationMs,
              aspectRatio: _aspectRatio,
              caption: _caption,
              isActive: _isActive,
            ),
            isNew: _isNew,
            adminUid: uid,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ReelValidationException ? e.errors.join('\n') : 'Could not save: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _phase = null;
          _progress = null;
        });
      }
    }
  }

  String? _sizeLabel() {
    final w = _video != null ? _probe?.width : null, h = _video != null ? _probe?.height : null;
    final ratio = _aspectRatio;
    if (w != null && h != null) return '$w × $h${isVertical916(ratio) ? ' (9:16)' : ''}';
    if (ratio == null) return null;
    return isVertical916(ratio) ? '9:16' : 'ratio ${ratio.toStringAsFixed(2)}';
  }

  List<String> _warnings() {
    final warnings = <String>[];
    if (_video != null && !_probing) {
      if (_probe == null) {
        warnings.add('This browser could not read the video, so there is no poster, duration or size. '
            'Check that it is an H.264 MP4 — it can still be uploaded; add a poster with Replace poster.');
      } else if (_probe!.poster == null && _poster == null) {
        warnings.add('No frame could be captured for the poster — use Replace poster.');
      }
    }
    final ratio = _aspectRatio;
    if (ratio != null && !isVertical916(ratio)) {
      warnings.add('Not vertical 9:16 — the app crops it to fill the screen.');
    }
    final ms = _durationMs;
    if (ms != null && ms > ReelFileRules.recommendedMaxSeconds * 1000) {
      warnings.add('Longer than the recommended ${ReelFileRules.recommendedMaxSeconds} s.');
    }
    return warnings;
  }

  Widget _videoSection(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted(context));
    final error = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error);
    final video = _video;
    final posterBytes = _poster?.bytes ?? (video != null ? _probe?.poster : null);
    final posterUrl = video == null ? _original?.posterUrl : null;
    final duration = formatReelDuration(_durationMs);
    final size = _sizeLabel();
    final info = [if (duration != null) 'Duration $duration', if (size != null) size].join(' · ');
    final hasVideo = video != null || (_original?.videoUrl.isNotEmpty ?? false);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 108,
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ReelPosterImage(
              key: const ValueKey('reelPosterPreview'),
              bytes: posterBytes,
              url: posterUrl,
              cacheWidth: 216,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            OutlinedButton.icon(
              key: const ValueKey('pickReelVideo'),
              onPressed: _saving ? null : _pickVideo,
              icon: const Icon(Icons.video_file_outlined),
              label: Text(hasVideo ? 'Replace video' : 'Choose video'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('pickReelPoster'),
              onPressed: _saving ? null : _pickPoster,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Replace poster'),
            ),
            if (_poster != null)
              TextButton(
                onPressed: _saving ? null : () => setState(() => _poster = null),
                child: Text(video != null ? 'Use the video frame' : 'Keep the current poster'),
              ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(ReelFileRules.videoHint, style: muted),
          if (video != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${video.name} · ${fileSizeLabel(video.size)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ],
          if (_poster != null)
            Text('Poster: ${_poster!.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          if (_probing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text('Reading the video…', style: muted)),
              ]),
            )
          else if (info.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(info, key: const ValueKey('reelVideoInfo'), style: theme.textTheme.bodySmall),
          ],
          for (final w in _warnings())
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(w, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
            ),
          for (final key in const ['video', 'poster'])
            if (_errors[key] != null)
              Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(_errors[key]!, style: error)),
          if (_saving && _phase != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(key: const ValueKey('reelUploadProgress'), value: _progress),
            const SizedBox(height: AppSpacing.xs),
            Text('$_phase…${_progress == null ? '' : ' ${(_progress! * 100).round()} %'}', style: muted),
          ],
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(_isNew ? 'New reel' : 'Edit reel',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Flexible(
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_loadingProduct)
                        const LinearProgressIndicator()
                      else
                        ReelProductPicker(
                          selected: _product,
                          missingId: _missingProductId,
                          errorText: _errors['product'],
                          enabled: !_saving,
                          onSelected: (p) => setState(() {
                            _product = p;
                            _missingProductId = null;
                            _errors = {..._errors}..remove('product');
                          }),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(_isNew ? 'Video *' : 'Video', style: section),
                      const SizedBox(height: AppSpacing.sm),
                      _videoSection(context),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Caption (optional)', style: section),
                      const SizedBox(height: AppSpacing.sm),
                      TrilingualField(
                        label: 'Caption',
                        value: _caption,
                        required: false,
                        maxLines: 3,
                        maxLength: ReelModel.maxCaptionLength,
                        onChanged: (t) => _caption = t,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        subtitle: const Text('Shown in the app’s Reels tab while its product is active.'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ]),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
                  Expanded(
                    child: _error == null
                        ? const SizedBox.shrink()
                        : Text(_error!, key: const ValueKey('reelEditorError'), style: TextStyle(color: theme.colorScheme.error)),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    key: const ValueKey('saveReel'),
                    onPressed: _saving || _probing || _loadingProduct ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isNew ? 'Create' : 'Save'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
