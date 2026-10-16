abstract final class ReportsSuggestionsEndpoints {
  const ReportsSuggestionsEndpoints._();

  /// POST: Report a content problem
  static const String report = '/api/report';

  /// GET: List available reasons for reporting content
  static const String reportReasons = '/api/report-reasons';

  /// POST: Suggest new content to add (JSON or multipart/form-data with photo)
  static const String suggestContent = '/api/suggest-content';
}

