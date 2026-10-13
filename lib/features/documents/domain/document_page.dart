import 'page_crop.dart';
export 'page_crop.dart';

enum PageSource { gallery, nativeScanner }

/// Capture produces only previewTemporary files. Retained editing pages need a
/// separate storage handoff; changing this metadata alone does not retain files.
enum PageFileLifetime { previewTemporary, retainedForEditing }

/// EXIF (including mirroring) is applied by Flutter's image decoder, not edits.
enum PageOrientation { decoderManagedExif }

class PageFileOwnership {
  const PageFileOwnership({
    required this.sessionId,
    this.lifetime = PageFileLifetime.previewTemporary,
  });

  final String sessionId;
  final PageFileLifetime lifetime;
}

class DocumentPage {
  const DocumentPage({
    required this.id,
    required String path,
    String? sourcePath,
    required this.width,
    required this.height,
    this.byteLength = 0,
    this.sortOrder = 0,
    this.rotationQuarterTurns = 0,
    this.crop = PageCrop.full,
    this.source = PageSource.gallery,
    this.ownership,
  }) : workingPath = path,
       sourcePath = sourcePath ?? path,
       assert(sortOrder >= 0),
       assert(rotationQuarterTurns >= 0 && rotationQuarterTurns < 4);

  final String id;

  /// App-owned, unchanged input copy; never a picker/scanner URI.
  final String sourcePath;

  /// Initially shares the source copy. No second copy is needed before editing.
  final String workingPath;
  String get path => workingPath;

  /// Dimensions after decoder-managed EXIF orientation, before extra rotation.
  final int width;
  final int height;
  final int byteLength;
  final int sortOrder;

  /// Additional clockwise quarter-turns, separate from source EXIF orientation.
  final int rotationQuarterTurns;
  final PageCrop crop;
  final PageSource source;
  final PageFileOwnership? ownership;
  PageOrientation get orientation => PageOrientation.decoderManagedExif;

  DocumentPage copyWith({
    int? sortOrder,
    int? rotationQuarterTurns,
    PageCrop? crop,
  }) => DocumentPage(
    id: id,
    path: workingPath,
    sourcePath: sourcePath,
    width: width,
    height: height,
    byteLength: byteLength,
    sortOrder: sortOrder ?? this.sortOrder,
    rotationQuarterTurns:
        ((rotationQuarterTurns ?? this.rotationQuarterTurns) % 4 + 4) % 4,
    crop: crop ?? this.crop,
    source: source,
    ownership: ownership,
  );
}
