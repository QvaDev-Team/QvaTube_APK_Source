abstract final class ReviewsEndpoints {
  const ReviewsEndpoints._();

  /// GET: List site reviews with average rating
  /// POST: Submit a site review (rating and optional comment)
  static const String reviews = '/api/reviews';
}

