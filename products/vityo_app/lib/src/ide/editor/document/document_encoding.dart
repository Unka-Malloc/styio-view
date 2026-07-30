/// Per-document encoding tracking for file save/load round-trips.
///
/// The editor text buffer always operates on decoded UTF-16 Dart [String]
/// values.  This encoding is used at the workspace-document-store boundary
/// when reading and writing file content, so that non-UTF-8 encodings,
/// BOM-prefixed files, and newline conventions are preserved across sessions.
///
/// UTF-8 is the default encoding.  Unknown or unsupported persisted wire values
/// are ignored so callers can fall back to the default decode path.
enum DocumentEncoding {
  utf8('UTF-8'),
  utf8WithBom('UTF-8-BOM'),
  utf16le('UTF-16-LE'),
  utf16be('UTF-16-BE'),
  latin1('ISO-8859-1'),
  ascii('ASCII');

  const DocumentEncoding(this.label);

  /// Human-readable label (IANA charset name or common alias).
  final String label;

  /// Wire value for serialisation (lowercase, hyphen-free form).
  String get wireValue => switch (this) {
    DocumentEncoding.utf8 => 'utf-8',
    DocumentEncoding.utf8WithBom => 'utf-8-bom',
    DocumentEncoding.utf16le => 'utf-16-le',
    DocumentEncoding.utf16be => 'utf-16-be',
    DocumentEncoding.latin1 => 'latin-1',
    DocumentEncoding.ascii => 'ascii',
  };

  /// Parse from a [wireValue] string.  Returns `null` for unknown values.
  static DocumentEncoding? fromWireValue(String value) {
    return switch (value) {
      'utf-8' => DocumentEncoding.utf8,
      'utf-8-bom' => DocumentEncoding.utf8WithBom,
      'utf-16-le' => DocumentEncoding.utf16le,
      'utf-16-be' => DocumentEncoding.utf16be,
      'latin-1' => DocumentEncoding.latin1,
      'ascii' => DocumentEncoding.ascii,
      _ => null,
    };
  }
}
