final class ReportsSuggestionsEndpoints {
  const ReportsSuggestionsEndpoints();

  /// POST: Report a content problem
  final String report = '/api/report';

  /// GET: List available reasons for reporting content
  final String reportReasons = '/api/report-reasons';

  /// POST: Suggest new content to add (JSON or multipart/form-data with photo)
  final String suggestContent = '/api/suggest-content';
}

