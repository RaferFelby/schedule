final class PdfTextSpan {
  const PdfTextSpan({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
}

final class PdfTimetablePage {
  const PdfTimetablePage({
    required this.index,
    required this.rotation,
    required this.source,
    required this.spans,
  });

  final int index;
  final int rotation;
  final String source;
  final List<PdfTextSpan> spans;
}

final class PdfTimetableDocument {
  const PdfTimetableDocument({required this.pages});

  final List<PdfTimetablePage> pages;
}
