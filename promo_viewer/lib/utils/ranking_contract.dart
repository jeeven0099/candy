class RankingContract {
  static const version = 'v2_personal_email_top_10';

  static const forYouLimit = 10;
  static const nearMeLimit = 10;

  static const minConfidence = 0.70;
  static const forYouQualityFloor = 65.0;
  static const nearMeQualityFloor = 55.0;
  static const strongUnknownDiscountFloor = 82.0;
  static const exceptionalPointsFloor = 78.0;
  static const emailQualityFloor = 45.0;
  static const emailPersonalRankFloor = 70.0;

  static const nearMeDefaultRadiusMi = 5;
  static const nearMeMaxDistanceKm = 8.05; // 5 miles

  static const maxPrimaryDealsPerBrand = 1;
  static const maxFallbackDealsPerBrand = 2;

  static const favoriteBrandBoost = 24.0;
  static const favoriteCategoryBoost = 14.0;
  static const priorityBoost = 8.0;
  static const birthdayBoost = 12.0;

  static const savedDealBoost = 18.0;
  static const clickedDealBoost = 6.0;
  static const recentBrandSearchBoost = 12.0;
  static const emailSourceBoost = 4.0;
  static const personalModelMultiplier = 0.8;
  static const personalModelBoostCap = 30.0;
  static const personalModelPenaltyCap = 18.0;

  static const memberBoost = 12.0;
  static const noMembershipBoost = 3.0;
  static const freeMembershipPenalty = 2.0;
  static const paidMembershipPenalty = 18.0;
  static const unknownMembershipPenalty = 6.0;

  static const validTodayBonus = 4.0;
  static const urgencyMultiplier = 1.2;

  static const veryNearBonus = 25.0;
  static const nearBonus = 18.0;
  static const localBonus = 10.0;
  static const nearbyBonus = 5.0;
}
