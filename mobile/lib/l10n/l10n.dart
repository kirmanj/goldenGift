import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'l10n_ar.dart';
import 'l10n_ckb.dart';
import 'l10n_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('ckb'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Golden Gift'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Personalized gifts, made for them'**
  String get appTagline;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @cart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cart;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Your Account'**
  String get createYourAccount;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Register now and start creating personalized gifts in minutes!'**
  String get registerSubtitle;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get yourName;

  /// No description provided for @enterYourName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourName;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @enterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterYourEmail;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileNumber;

  /// No description provided for @enterYourNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your number'**
  String get enterYourNumber;

  /// No description provided for @haveReferralCode.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get haveReferralCode;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as a guest'**
  String get continueAsGuest;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @aiGiftSearch.
  ///
  /// In en, this message translates to:
  /// **'AI Gift Search'**
  String get aiGiftSearch;

  /// No description provided for @aiGiftSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Describe who it\'s for or the occasion'**
  String get aiGiftSearchHint;

  /// No description provided for @popular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get popular;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get featured;

  /// No description provided for @forYou.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get forYou;

  /// No description provided for @giftCards.
  ///
  /// In en, this message translates to:
  /// **'Gift Cards'**
  String get giftCards;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @myCart.
  ///
  /// In en, this message translates to:
  /// **'My Cart'**
  String get myCart;

  /// No description provided for @emptyCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Golden Gift cart is feeling lonely!'**
  String get emptyCartTitle;

  /// No description provided for @emptyCartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s fill it with personalized magic. Start designing your perfect gifts now!'**
  String get emptyCartSubtitle;

  /// No description provided for @startShopping.
  ///
  /// In en, this message translates to:
  /// **'Start Shopping'**
  String get startShopping;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @searchForProduct.
  ///
  /// In en, this message translates to:
  /// **'Search for a product'**
  String get searchForProduct;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All Categories'**
  String get allCategories;

  /// No description provided for @searchForCategory.
  ///
  /// In en, this message translates to:
  /// **'Search for a category'**
  String get searchForCategory;

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetails;

  /// No description provided for @aboutTheProduct.
  ///
  /// In en, this message translates to:
  /// **'About the Product'**
  String get aboutTheProduct;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @preparationDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{This product requires 1 day for preparation} other{This product requires {days} days for preparation}}'**
  String preparationDays(int days);

  /// No description provided for @sameDayShipping.
  ///
  /// In en, this message translates to:
  /// **'This product can be shipped same day'**
  String get sameDayShipping;

  /// No description provided for @availableOnlyIn.
  ///
  /// In en, this message translates to:
  /// **'Available only in: {cities}'**
  String availableOnlyIn(String cities);

  /// No description provided for @uploadYourPhotos.
  ///
  /// In en, this message translates to:
  /// **'Upload your photos'**
  String get uploadYourPhotos;

  /// No description provided for @customizeTextHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the text you want to customize on your product'**
  String get customizeTextHint;

  /// No description provided for @selectADate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get selectADate;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @myWishlists.
  ///
  /// In en, this message translates to:
  /// **'My Wishlists'**
  String get myWishlists;

  /// No description provided for @wishlistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gifts you\'ve saved'**
  String get wishlistSubtitle;

  /// No description provided for @secretSanta.
  ///
  /// In en, this message translates to:
  /// **'Secret Santa'**
  String get secretSanta;

  /// No description provided for @secretSantaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Family, friends and work exchanges'**
  String get secretSantaSubtitle;

  /// No description provided for @savedCards.
  ///
  /// In en, this message translates to:
  /// **'Saved Cards'**
  String get savedCards;

  /// No description provided for @myWallet.
  ///
  /// In en, this message translates to:
  /// **'My Wallet'**
  String get myWallet;

  /// No description provided for @inviteAndEarn.
  ///
  /// In en, this message translates to:
  /// **'Invite & Earn'**
  String get inviteAndEarn;

  /// No description provided for @specialRequests.
  ///
  /// In en, this message translates to:
  /// **'Special Requests'**
  String get specialRequests;

  /// No description provided for @savedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Saved Addresses'**
  String get savedAddresses;

  /// No description provided for @myGiftCards.
  ///
  /// In en, this message translates to:
  /// **'My Gift Cards'**
  String get myGiftCards;

  /// No description provided for @promoCodes.
  ///
  /// In en, this message translates to:
  /// **'Promo Codes'**
  String get promoCodes;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactUs;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available Balance'**
  String get availableBalance;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No Transactions Yet'**
  String get noTransactionsYet;

  /// No description provided for @transactionHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Your Transaction History will appear here'**
  String get transactionHistoryHint;

  /// No description provided for @creditsBalance.
  ///
  /// In en, this message translates to:
  /// **'Golden Gift Credits Balance'**
  String get creditsBalance;

  /// No description provided for @successfulReferrals.
  ///
  /// In en, this message translates to:
  /// **'Successful Referrals'**
  String get successfulReferrals;

  /// No description provided for @pendingReferrals.
  ///
  /// In en, this message translates to:
  /// **'Pending Referrals'**
  String get pendingReferrals;

  /// No description provided for @yourReferralCode.
  ///
  /// In en, this message translates to:
  /// **'Your referral code'**
  String get yourReferralCode;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get inviteFriends;

  /// No description provided for @walletTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get walletTransactions;

  /// No description provided for @walletBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get walletBalance;

  /// No description provided for @walletCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get walletCredits;

  /// No description provided for @walletSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your balance, credits and transactions.'**
  String get walletSignInBody;

  /// No description provided for @txnTopUp.
  ///
  /// In en, this message translates to:
  /// **'Top-up'**
  String get txnTopUp;

  /// No description provided for @txnOrderPayment.
  ///
  /// In en, this message translates to:
  /// **'Order payment'**
  String get txnOrderPayment;

  /// No description provided for @txnRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get txnRefund;

  /// No description provided for @txnReferralCredit.
  ///
  /// In en, this message translates to:
  /// **'Referral reward'**
  String get txnReferralCredit;

  /// No description provided for @txnGiftCardRedeem.
  ///
  /// In en, this message translates to:
  /// **'Gift card redeemed'**
  String get txnGiftCardRedeem;

  /// No description provided for @txnAdminAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Balance adjustment'**
  String get txnAdminAdjustment;

  /// No description provided for @txnCreditExpiry.
  ///
  /// In en, this message translates to:
  /// **'Credits expired'**
  String get txnCreditExpiry;

  /// No description provided for @creditsExpiryNote.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Credits expire 1 day after you receive them.} other{Credits expire {days} days after you receive them.}}'**
  String creditsExpiryNote(int days);

  /// No description provided for @promoHeaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Love a Good Deal? We Do Too! 🎉'**
  String get promoHeaderTitle;

  /// No description provided for @promoPercentOff.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Off'**
  String promoPercentOff(int percent);

  /// No description provided for @promoAmountOff.
  ///
  /// In en, this message translates to:
  /// **'{amount} Off'**
  String promoAmountOff(String amount);

  /// No description provided for @promoCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get promoCopyCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get codeCopied;

  /// No description provided for @promoMinOrder.
  ///
  /// In en, this message translates to:
  /// **'Min. order {amount}'**
  String promoMinOrder(String amount);

  /// No description provided for @promoMaxDiscount.
  ///
  /// In en, this message translates to:
  /// **'Max. discount {amount}'**
  String promoMaxDiscount(String amount);

  /// No description provided for @promoFirstOrderOnly.
  ///
  /// In en, this message translates to:
  /// **'First order only'**
  String get promoFirstOrderOnly;

  /// No description provided for @promoUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get promoUse;

  /// No description provided for @promoAppliedLabel.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get promoAppliedLabel;

  /// No description provided for @promoAppliedSnack.
  ///
  /// In en, this message translates to:
  /// **'{code} applied to your cart'**
  String promoAppliedSnack(String code);

  /// No description provided for @noPromoCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'No promo codes right now'**
  String get noPromoCodesTitle;

  /// No description provided for @noPromoCodesBody.
  ///
  /// In en, this message translates to:
  /// **'New deals show up here — check back soon.'**
  String get noPromoCodesBody;

  /// No description provided for @promoCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get promoCodeHint;

  /// No description provided for @promoNotFound.
  ///
  /// In en, this message translates to:
  /// **'This code doesn\'t exist'**
  String get promoNotFound;

  /// No description provided for @promoInactive.
  ///
  /// In en, this message translates to:
  /// **'This code is no longer active'**
  String get promoInactive;

  /// No description provided for @promoExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired'**
  String get promoExpired;

  /// No description provided for @promoMinOrderNotMet.
  ///
  /// In en, this message translates to:
  /// **'Minimum order for this code is {amount}'**
  String promoMinOrderNotMet(String amount);

  /// No description provided for @promoUsageLimit.
  ///
  /// In en, this message translates to:
  /// **'This code has reached its usage limit'**
  String get promoUsageLimit;

  /// No description provided for @promoPerUserLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already used this code'**
  String get promoPerUserLimit;

  /// No description provided for @promoFirstOrderOnlyError.
  ///
  /// In en, this message translates to:
  /// **'This code is only for your first order'**
  String get promoFirstOrderOnlyError;

  /// No description provided for @promoNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not valid for the items in your cart'**
  String get promoNotApplicable;

  /// No description provided for @promoDiscountRow.
  ///
  /// In en, this message translates to:
  /// **'Promo ({code})'**
  String promoDiscountRow(String code);

  /// No description provided for @promoSaved.
  ///
  /// In en, this message translates to:
  /// **'You save {amount}'**
  String promoSaved(String amount);

  /// No description provided for @useMyCredits.
  ///
  /// In en, this message translates to:
  /// **'Use my credits ({amount} available)'**
  String useMyCredits(String amount);

  /// No description provided for @inviteFriendsBody.
  ///
  /// In en, this message translates to:
  /// **'Invite your friends and let them create unique gifts & products their way. 🎁✨'**
  String get inviteFriendsBody;

  /// No description provided for @successfulReferralsHint.
  ///
  /// In en, this message translates to:
  /// **'Friends who signed up and placed a paid order'**
  String get successfulReferralsHint;

  /// No description provided for @pendingReferralsHint.
  ///
  /// In en, this message translates to:
  /// **'Friends who signed up — reward when they order'**
  String get pendingReferralsHint;

  /// No description provided for @referralBothGet.
  ///
  /// In en, this message translates to:
  /// **'Share it with friends — you\'ll both get {amount}'**
  String referralBothGet(String amount);

  /// No description provided for @referralEachGets.
  ///
  /// In en, this message translates to:
  /// **'Share it with friends — they get {friend}, you get {you}'**
  String referralEachGets(String friend, String you);

  /// No description provided for @referralYouGet.
  ///
  /// In en, this message translates to:
  /// **'Share it with friends — you get {you} after their first paid order'**
  String referralYouGet(String you);

  /// No description provided for @referralFriendGets.
  ///
  /// In en, this message translates to:
  /// **'Share it with friends — they get {friend} when they join'**
  String referralFriendGets(String friend);

  /// No description provided for @learnMoreReferrals.
  ///
  /// In en, this message translates to:
  /// **'Learn more about referrals'**
  String get learnMoreReferrals;

  /// No description provided for @copyReferralCode.
  ///
  /// In en, this message translates to:
  /// **'Copy referral code'**
  String get copyReferralCode;

  /// No description provided for @referralShareText.
  ///
  /// In en, this message translates to:
  /// **'Join me on Golden Gift for personalized gifts! Sign up with my code {code} and get {amount} in credits: {link}'**
  String referralShareText(String amount, String code, String link);

  /// No description provided for @referralShareTextNoBonus.
  ///
  /// In en, this message translates to:
  /// **'Join me on Golden Gift for personalized gifts! Sign up with my code {code}: {link}'**
  String referralShareTextNoBonus(String code, String link);

  /// No description provided for @referralShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Join me on Golden Gift'**
  String get referralShareSubject;

  /// No description provided for @referralRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'How referrals work'**
  String get referralRulesTitle;

  /// No description provided for @referralRuleJoin.
  ///
  /// In en, this message translates to:
  /// **'Your friend signs up with your code and gets {amount} in credits.'**
  String referralRuleJoin(String amount);

  /// No description provided for @referralRuleOrder.
  ///
  /// In en, this message translates to:
  /// **'You get {amount} in credits when their first order is delivered and paid.'**
  String referralRuleOrder(String amount);

  /// No description provided for @referralRuleMonthlyCap.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You can be rewarded for 1 friend per month.} other{You can be rewarded for up to {count} friends per month.}}'**
  String referralRuleMonthlyCap(int count);

  /// No description provided for @referralRuleSpend.
  ///
  /// In en, this message translates to:
  /// **'Credits can be spent on any order in the app; they can\'t be withdrawn as cash.'**
  String get referralRuleSpend;

  /// No description provided for @referralRuleFairUse.
  ///
  /// In en, this message translates to:
  /// **'Referring yourself, or another account on the same device, doesn\'t earn rewards.'**
  String get referralRuleFairUse;

  /// No description provided for @referralInvitesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your invites'**
  String get referralInvitesTitle;

  /// No description provided for @referralStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get referralStatusPending;

  /// No description provided for @referralStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Rewarded'**
  String get referralStatusCompleted;

  /// No description provided for @referralStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get referralStatusCancelled;

  /// No description provided for @referralAFriend.
  ///
  /// In en, this message translates to:
  /// **'A friend'**
  String get referralAFriend;

  /// No description provided for @inviteSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to get your referral code and invite friends.'**
  String get inviteSignInBody;

  /// No description provided for @referralRewardsChip.
  ///
  /// In en, this message translates to:
  /// **'Referral rewards'**
  String get referralRewardsChip;

  /// No description provided for @referralSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite friends, earn credits'**
  String get referralSheetTitle;

  /// No description provided for @referralSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Share your personal link once and get rewarded when friends discover Golden Gift.'**
  String get referralSheetBody;

  /// No description provided for @referralFriendJoins.
  ///
  /// In en, this message translates to:
  /// **'Friend joins'**
  String get referralFriendJoins;

  /// No description provided for @referralFirstPaidOrder.
  ///
  /// In en, this message translates to:
  /// **'First paid order'**
  String get referralFirstPaidOrder;

  /// No description provided for @referralShareLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Share your invite link'**
  String get referralShareLinkTitle;

  /// No description provided for @referralShareLinkBody.
  ///
  /// In en, this message translates to:
  /// **'Open My Rewards anytime to copy or share it.'**
  String get referralShareLinkBody;

  /// No description provided for @referralWatchCreditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch credits build up'**
  String get referralWatchCreditsTitle;

  /// No description provided for @referralWatchBoth.
  ///
  /// In en, this message translates to:
  /// **'They get {friend} when they join, and you earn {you} after their first paid order.'**
  String referralWatchBoth(String friend, String you);

  /// No description provided for @referralWatchYou.
  ///
  /// In en, this message translates to:
  /// **'You earn {you} after their first paid order.'**
  String referralWatchYou(String you);

  /// No description provided for @referralWatchFriend.
  ///
  /// In en, this message translates to:
  /// **'They get {friend} when they join.'**
  String referralWatchFriend(String friend);

  /// No description provided for @referralMyRewards.
  ///
  /// In en, this message translates to:
  /// **'My Rewards'**
  String get referralMyRewards;

  /// No description provided for @referralInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get referralInvite;

  /// No description provided for @referralMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get referralMaybeLater;

  /// No description provided for @referralLinkSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Referral codes are for new accounts. Invite your own friends from Invite & Earn.'**
  String get referralLinkSignedIn;

  /// No description provided for @submitYourRequest.
  ///
  /// In en, this message translates to:
  /// **'Submit your request'**
  String get submitYourRequest;

  /// No description provided for @writeYourIdeaHere.
  ///
  /// In en, this message translates to:
  /// **'Write your idea here'**
  String get writeYourIdeaHere;

  /// No description provided for @expiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires on: {date}'**
  String expiresOn(String date);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @addToWishlist.
  ///
  /// In en, this message translates to:
  /// **'Add to wishlist'**
  String get addToWishlist;

  /// No description provided for @removeFromWishlist.
  ///
  /// In en, this message translates to:
  /// **'Remove from wishlist'**
  String get removeFromWishlist;

  /// No description provided for @originalPrice.
  ///
  /// In en, this message translates to:
  /// **'Original price {price}'**
  String originalPrice(String price);

  /// No description provided for @percentOff.
  ///
  /// In en, this message translates to:
  /// **'{percent}% off'**
  String percentOff(int percent);

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Personalize every gift'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Add names, photos, colours and messages to make it truly theirs.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Delivered with care'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Delivery across Iraq and the Kurdistan Region — wrapped and ready to give.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Earn credits'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Invite friends and collect Golden Gift credits when they order.'**
  String get onboardingBody3;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get signInTitle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your mobile number to continue.'**
  String get signInSubtitle;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get dontHaveAccount;

  /// No description provided for @referralCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Referral code'**
  String get referralCodeLabel;

  /// No description provided for @referralCodeHint.
  ///
  /// In en, this message translates to:
  /// **'6-character code'**
  String get referralCodeHint;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @selectCountry.
  ///
  /// In en, this message translates to:
  /// **'Select country'**
  String get selectCountry;

  /// No description provided for @termsAgreement.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to our Terms of Service and Privacy Policy.'**
  String get termsAgreement;

  /// No description provided for @completeProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your account'**
  String get completeProfileTitle;

  /// No description provided for @completeProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us a little about you to finish signing up.'**
  String get completeProfileSubtitle;

  /// No description provided for @phoneLaterNote.
  ///
  /// In en, this message translates to:
  /// **'You can add your mobile number later — it\'s needed before checkout.'**
  String get phoneLaterNote;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your number'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we sent to {phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @otpResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String otpResendIn(int seconds);

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get otpResend;

  /// No description provided for @otpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// No description provided for @otpCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent'**
  String get otpCodeSent;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @errorRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get errorRequired;

  /// No description provided for @errorNameLength.
  ///
  /// In en, this message translates to:
  /// **'Name must be 2–50 characters'**
  String get errorNameLength;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get errorInvalidEmail;

  /// No description provided for @errorInvalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number'**
  String get errorInvalidPhone;

  /// No description provided for @errorInvalidReferralCode.
  ///
  /// In en, this message translates to:
  /// **'Referral codes have 6 letters or digits'**
  String get errorInvalidReferralCode;

  /// No description provided for @authErrorInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t right. Check it and try again.'**
  String get authErrorInvalidCode;

  /// No description provided for @authErrorCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired. Request a new one.'**
  String get authErrorCodeExpired;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your connection and try again.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorPhoneInUse.
  ///
  /// In en, this message translates to:
  /// **'This number is already linked to another account.'**
  String get authErrorPhoneInUse;

  /// No description provided for @authErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This sign-in option isn\'t available yet.'**
  String get authErrorUnavailable;

  /// No description provided for @authErrorAccountDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Contact us for help.'**
  String get authErrorAccountDisabled;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @signInToContinueBody.
  ///
  /// In en, this message translates to:
  /// **'Create an account or sign in to save gifts, check out and track your orders.'**
  String get signInToContinueBody;

  /// No description provided for @maintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll be right back'**
  String get maintenanceTitle;

  /// No description provided for @maintenanceBody.
  ///
  /// In en, this message translates to:
  /// **'Golden Gift is getting a small upgrade. Please check back soon.'**
  String get maintenanceBody;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'A new version of Golden Gift is available. Please update to continue.'**
  String get updateRequiredBody;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @guestProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing as a guest'**
  String get guestProfileTitle;

  /// No description provided for @guestProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your orders, wallet and saved gifts.'**
  String get guestProfileBody;

  /// No description provided for @inviteAndEarnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Earn {amount} per friend'**
  String inviteAndEarnSubtitle(String amount);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out of Golden Gift?'**
  String get logoutConfirm;

  /// No description provided for @addPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Add mobile number'**
  String get addPhoneNumber;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// No description provided for @selectBirthday.
  ///
  /// In en, this message translates to:
  /// **'Select your birthday'**
  String get selectBirthday;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @genderPreferNot.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get genderPreferNot;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @selectCity.
  ///
  /// In en, this message translates to:
  /// **'Select your city'**
  String get selectCity;

  /// No description provided for @changePhone.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changePhone;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @phoneUpdated.
  ///
  /// In en, this message translates to:
  /// **'Mobile number updated'**
  String get phoneUpdated;

  /// No description provided for @changePhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Change mobile number'**
  String get changePhoneTitle;

  /// No description provided for @changePhoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a verification code to your new number.'**
  String get changePhoneSubtitle;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @phoneChangeMobileOnly.
  ///
  /// In en, this message translates to:
  /// **'Changing your number is available in the mobile app.'**
  String get phoneChangeMobileOnly;

  /// No description provided for @photoUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the photo. Please try again.'**
  String get photoUploadFailed;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get unsavedChanges;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @notificationsSetting.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsSetting;

  /// No description provided for @notificationsSettingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Order updates and offers'**
  String get notificationsSettingSubtitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Your profile, addresses, cart and wishlist will be removed. Past orders are kept for our records. This can\'t be undone.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountConfirm;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get accountDeleted;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageKurdish.
  ///
  /// In en, this message translates to:
  /// **'کوردی'**
  String get languageKurdish;

  /// Profile photo source option (Edit Profile)
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// Profile photo source option (Edit Profile)
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @authErrorDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send the code. Check the number and your connection, then try again.'**
  String get authErrorDeliveryFailed;

  /// No description provided for @profileCompletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile to unlock better recommendations'**
  String get profileCompletionTitle;

  /// No description provided for @goToProfile.
  ///
  /// In en, this message translates to:
  /// **'Go to profile'**
  String get goToProfile;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortRelevance.
  ///
  /// In en, this message translates to:
  /// **'Best match'**
  String get sortRelevance;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// No description provided for @sortPopular.
  ///
  /// In en, this message translates to:
  /// **'Most popular'**
  String get sortPopular;

  /// No description provided for @sortPriceLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: low to high'**
  String get sortPriceLowHigh;

  /// No description provided for @sortPriceHighLow.
  ///
  /// In en, this message translates to:
  /// **'Price: high to low'**
  String get sortPriceHighLow;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @priceUnder.
  ///
  /// In en, this message translates to:
  /// **'Under {amount}'**
  String priceUnder(String amount);

  /// No description provided for @priceBetween.
  ///
  /// In en, this message translates to:
  /// **'{min} – {max}'**
  String priceBetween(String min, String max);

  /// No description provided for @priceAndAbove.
  ///
  /// In en, this message translates to:
  /// **'{amount} and above'**
  String priceAndAbove(String amount);

  /// No description provided for @availability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get availability;

  /// No description provided for @sameDayOnly.
  ///
  /// In en, this message translates to:
  /// **'Ships same day'**
  String get sameDayOnly;

  /// No description provided for @onSaleOnly.
  ///
  /// In en, this message translates to:
  /// **'On sale'**
  String get onSaleOnly;

  /// No description provided for @deliverTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get deliverTo;

  /// No description provided for @anyCity.
  ///
  /// In en, this message translates to:
  /// **'Any city'**
  String get anyCity;

  /// No description provided for @resetFilters.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetFilters;

  /// No description provided for @showResults.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get showResults;

  /// No description provided for @offlineChip.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved items'**
  String get offlineChip;

  /// No description provided for @noProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'No gifts found'**
  String get noProductsTitle;

  /// No description provided for @noProductsBody.
  ///
  /// In en, this message translates to:
  /// **'Try another search or remove some filters.'**
  String get noProductsBody;

  /// No description provided for @searchFallbackNote.
  ///
  /// In en, this message translates to:
  /// **'Search is limited right now — showing matches from all categories and cities.'**
  String get searchFallbackNote;

  /// No description provided for @noCategoriesMatch.
  ///
  /// In en, this message translates to:
  /// **'No categories match your search'**
  String get noCategoriesMatch;

  /// No description provided for @loadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more gifts.'**
  String get loadMoreFailed;

  /// No description provided for @readMore.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get readMore;

  /// No description provided for @readLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get readLess;

  /// No description provided for @optionalLabel.
  ///
  /// In en, this message translates to:
  /// **'(Optional)'**
  String get optionalLabel;

  /// No description provided for @optionRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Please choose an option'**
  String get optionRequiredError;

  /// No description provided for @textRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Please enter the text'**
  String get textRequiredError;

  /// No description provided for @dateRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Please choose a date'**
  String get dateRequiredError;

  /// No description provided for @textTooLongError.
  ///
  /// In en, this message translates to:
  /// **'Keep it to {max} characters'**
  String textTooLongError(int max);

  /// No description provided for @photosRequiredError.
  ///
  /// In en, this message translates to:
  /// **'{min, plural, =1{Add a photo} other{Add at least {min} photos}}'**
  String photosRequiredError(int min);

  /// No description provided for @optionUnavailableError.
  ///
  /// In en, this message translates to:
  /// **'This option is sold out — choose another'**
  String get optionUnavailableError;

  /// No description provided for @addedToCart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get addedToCart;

  /// No description provided for @viewCart.
  ///
  /// In en, this message translates to:
  /// **'View cart'**
  String get viewCart;

  /// No description provided for @uploadingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Uploading photos… {percent}%'**
  String uploadingPhotos(int percent);

  /// No description provided for @photoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This photo is larger than 10 MB'**
  String get photoTooLarge;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @photoSlot.
  ///
  /// In en, this message translates to:
  /// **'Photo {n}'**
  String photoSlot(int n);

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @productNotFound.
  ///
  /// In en, this message translates to:
  /// **'This gift is no longer available'**
  String get productNotFound;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @deliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get deliveryFee;

  /// No description provided for @deliveryCalculatedAtCheckout.
  ///
  /// In en, this message translates to:
  /// **'Calculated at checkout'**
  String get deliveryCalculatedAtCheckout;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @itemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No longer available — not included in the total'**
  String get itemUnavailable;

  /// No description provided for @priceChangedNote.
  ///
  /// In en, this message translates to:
  /// **'Price updated to {price}'**
  String priceChangedNote(String price);

  /// No description provided for @soldBy.
  ///
  /// In en, this message translates to:
  /// **'Sold by {store}'**
  String soldBy(String store);

  /// No description provided for @photosCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String photosCount(int count);

  /// No description provided for @wishlistEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved gifts yet'**
  String get wishlistEmptyTitle;

  /// No description provided for @wishlistEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on any gift to save it here.'**
  String get wishlistEmptyBody;

  /// No description provided for @increaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get increaseQuantity;

  /// No description provided for @decreaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get decreaseQuantity;

  /// No description provided for @addAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addAddress;

  /// No description provided for @editAddress.
  ///
  /// In en, this message translates to:
  /// **'Edit address'**
  String get editAddress;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Label (e.g. Home, Work)'**
  String get addressLabel;

  /// No description provided for @recipientName.
  ///
  /// In en, this message translates to:
  /// **'Recipient name'**
  String get recipientName;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area / district'**
  String get area;

  /// No description provided for @street.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get street;

  /// No description provided for @building.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get building;

  /// No description provided for @floor.
  ///
  /// In en, this message translates to:
  /// **'Floor / apartment'**
  String get floor;

  /// No description provided for @addressNotes.
  ///
  /// In en, this message translates to:
  /// **'Directions for the courier'**
  String get addressNotes;

  /// No description provided for @defaultAddress.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultAddress;

  /// No description provided for @setAsDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get setAsDefault;

  /// No description provided for @deleteAddressConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this address?'**
  String get deleteAddressConfirm;

  /// No description provided for @noAddressesTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved addresses'**
  String get noAddressesTitle;

  /// No description provided for @noAddressesBody.
  ///
  /// In en, this message translates to:
  /// **'Add an address to get your gifts delivered.'**
  String get noAddressesBody;

  /// No description provided for @deliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get deliveryAddress;

  /// No description provided for @changeAddress.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAddress;

  /// No description provided for @deliveryDateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Delivery date & time'**
  String get deliveryDateAndTime;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @noSlotsToday.
  ///
  /// In en, this message translates to:
  /// **'No delivery times left today — choose another day'**
  String get noSlotsToday;

  /// No description provided for @giftOptions.
  ///
  /// In en, this message translates to:
  /// **'Gift options'**
  String get giftOptions;

  /// No description provided for @thisIsAGift.
  ///
  /// In en, this message translates to:
  /// **'This is a gift'**
  String get thisIsAGift;

  /// No description provided for @hidePricesOnInvoice.
  ///
  /// In en, this message translates to:
  /// **'Hide prices on the invoice'**
  String get hidePricesOnInvoice;

  /// No description provided for @giftMessage.
  ///
  /// In en, this message translates to:
  /// **'Gift message'**
  String get giftMessage;

  /// No description provided for @giftMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Write a message for the card'**
  String get giftMessageHint;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get paymentMethod;

  /// No description provided for @cashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get cashOnDelivery;

  /// No description provided for @walletPayment.
  ///
  /// In en, this message translates to:
  /// **'Wallet & credits'**
  String get walletPayment;

  /// No description provided for @cardPayment.
  ///
  /// In en, this message translates to:
  /// **'Card / e-wallet'**
  String get cardPayment;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order summary'**
  String get orderSummary;

  /// No description provided for @placeOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get placeOrder;

  /// No description provided for @placingOrder.
  ///
  /// In en, this message translates to:
  /// **'Placing your order…'**
  String get placingOrder;

  /// No description provided for @itemNotDeliverableToCity.
  ///
  /// In en, this message translates to:
  /// **'{item} can\'t be delivered to this city'**
  String itemNotDeliverableToCity(String item);

  /// No description provided for @minimumOrderNotMet.
  ///
  /// In en, this message translates to:
  /// **'The minimum order is {amount}'**
  String minimumOrderNotMet(String amount);

  /// No description provided for @orderFailedCartChanged.
  ///
  /// In en, this message translates to:
  /// **'Some items changed. Please review your cart.'**
  String get orderFailedCartChanged;

  /// No description provided for @orderFailedOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Some items just sold out. Please review your cart.'**
  String get orderFailedOutOfStock;

  /// No description provided for @orderFailedCity.
  ///
  /// In en, this message translates to:
  /// **'Some items can\'t be delivered to the selected city.'**
  String get orderFailedCity;

  /// No description provided for @orderFailedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Ordering isn\'t available right now. Please try again later.'**
  String get orderFailedUnavailable;

  /// No description provided for @orderPlacedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order placed!'**
  String get orderPlacedTitle;

  /// No description provided for @orderPlacedBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you! We\'ve received order {number}.'**
  String orderPlacedBody(String number);

  /// No description provided for @estimatedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Estimated delivery'**
  String get estimatedDelivery;

  /// No description provided for @trackOrder.
  ///
  /// In en, this message translates to:
  /// **'Track order'**
  String get trackOrder;

  /// No description provided for @continueShopping.
  ///
  /// In en, this message translates to:
  /// **'Continue shopping'**
  String get continueShopping;

  /// No description provided for @activeOrders.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeOrders;

  /// No description provided for @completedOrders.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedOrders;

  /// No description provided for @cancelledOrders.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelledOrders;

  /// No description provided for @noOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get noOrdersTitle;

  /// No description provided for @noOrdersBody.
  ///
  /// In en, this message translates to:
  /// **'Your orders will appear here.'**
  String get noOrdersBody;

  /// No description provided for @orderNumber.
  ///
  /// In en, this message translates to:
  /// **'Order {number}'**
  String orderNumber(String number);

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get orderDetails;

  /// No description provided for @orderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order status'**
  String get orderStatus;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @paymentInfo.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentInfo;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @cancelOrderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get cancelOrderConfirm;

  /// No description provided for @cancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get cancelReasonHint;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get orderCancelled;

  /// No description provided for @orderNotCancellable.
  ///
  /// In en, this message translates to:
  /// **'This order can no longer be cancelled.'**
  String get orderNotCancellable;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @reorderAdded.
  ///
  /// In en, this message translates to:
  /// **'Items added to your cart'**
  String get reorderAdded;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get contactSupport;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get statusPreparing;

  /// No description provided for @statusReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Ready for delivery'**
  String get statusReadyForDelivery;

  /// No description provided for @statusOutForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Out for delivery'**
  String get statusOutForDelivery;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get statusDelivered;

  /// No description provided for @statusCancelledByBuyer.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelledByBuyer;

  /// No description provided for @statusCancelledBySeller.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the store'**
  String get statusCancelledBySeller;

  /// No description provided for @statusReturned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get statusReturned;

  /// No description provided for @statusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get statusRefunded;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// No description provided for @noNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsTitle;

  /// No description provided for @noNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Order updates and offers will show up here.'**
  String get noNotificationsBody;

  /// No description provided for @contactUsBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re here to help — reach us any way you like.'**
  String get contactUsBody;

  /// No description provided for @contactWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get contactWhatsapp;

  /// No description provided for @contactCall.
  ///
  /// In en, this message translates to:
  /// **'Call us'**
  String get contactCall;

  /// No description provided for @contactEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get contactEmail;

  /// No description provided for @contactInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram'**
  String get contactInstagram;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @paymentStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Not paid yet'**
  String get paymentStatusPending;

  /// No description provided for @paymentStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paymentStatusPaid;

  /// No description provided for @paymentStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentStatusFailed;

  /// No description provided for @paymentStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get paymentStatusRefunded;

  /// No description provided for @paymentZainCash.
  ///
  /// In en, this message translates to:
  /// **'ZainCash'**
  String get paymentZainCash;

  /// No description provided for @paymentZainCashHint.
  ///
  /// In en, this message translates to:
  /// **'Pay on ZainCash\'s secure page'**
  String get paymentZainCashHint;

  /// No description provided for @zainCashMinimum.
  ///
  /// In en, this message translates to:
  /// **'ZainCash needs at least {amount} to pay. Choose another payment method.'**
  String zainCashMinimum(String amount);

  /// No description provided for @paymentConnecting.
  ///
  /// In en, this message translates to:
  /// **'Opening ZainCash…'**
  String get paymentConnecting;

  /// No description provided for @paymentOrderSaved.
  ///
  /// In en, this message translates to:
  /// **'Your order is saved — you can pay it from Order details.'**
  String get paymentOrderSaved;

  /// No description provided for @paymentErrorDisabled.
  ///
  /// In en, this message translates to:
  /// **'Online payment is switched off right now. Please choose another payment method.'**
  String get paymentErrorDisabled;

  /// No description provided for @paymentErrorNotPayable.
  ///
  /// In en, this message translates to:
  /// **'This order can\'t be paid online.'**
  String get paymentErrorNotPayable;

  /// No description provided for @paymentErrorAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'This order is already paid.'**
  String get paymentErrorAlreadyPaid;

  /// No description provided for @paymentErrorExpired.
  ///
  /// In en, this message translates to:
  /// **'The time to pay this order has run out.'**
  String get paymentErrorExpired;

  /// No description provided for @paymentErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'ZainCash isn\'t available right now. Nothing was charged — please try again in a moment.'**
  String get paymentErrorUnavailable;

  /// No description provided for @paymentOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open ZainCash. Tap “Open ZainCash again”.'**
  String get paymentOpenFailed;

  /// No description provided for @paymentWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your payment on ZainCash'**
  String get paymentWaitingTitle;

  /// No description provided for @paymentWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'We opened ZainCash\'s secure page. After you pay, come back here — this page updates by itself.'**
  String get paymentWaitingBody;

  /// No description provided for @paymentAmountToPay.
  ///
  /// In en, this message translates to:
  /// **'Amount to pay'**
  String get paymentAmountToPay;

  /// No description provided for @paymentForTopUp.
  ///
  /// In en, this message translates to:
  /// **'Wallet top-up'**
  String get paymentForTopUp;

  /// No description provided for @paymentTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'Time left to pay: {time}'**
  String paymentTimeLeft(String time);

  /// No description provided for @paymentOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Open ZainCash again'**
  String get paymentOpenAgain;

  /// No description provided for @paymentCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'I\'ve paid — check status'**
  String get paymentCheckStatus;

  /// No description provided for @paymentStillPending.
  ///
  /// In en, this message translates to:
  /// **'ZainCash hasn\'t confirmed the payment yet. This page updates as soon as it does.'**
  String get paymentStillPending;

  /// No description provided for @paymentTimeUp.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up. We\'re confirming the result with ZainCash — this can take a few minutes.'**
  String get paymentTimeUp;

  /// No description provided for @paymentChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your payment…'**
  String get paymentChecking;

  /// No description provided for @paymentNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this payment.'**
  String get paymentNotFound;

  /// No description provided for @paymentFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment didn\'t go through'**
  String get paymentFailedTitle;

  /// No description provided for @paymentExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to pay ran out'**
  String get paymentExpiredTitle;

  /// No description provided for @paymentOrderCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'Order {number} was cancelled. Nothing was charged, and any credits you used are back in your wallet.'**
  String paymentOrderCancelledBody(String number);

  /// No description provided for @paymentNothingCharged.
  ///
  /// In en, this message translates to:
  /// **'Nothing was charged. You can try again.'**
  String get paymentNothingCharged;

  /// No description provided for @paymentTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get paymentTryAgain;

  /// No description provided for @paymentLateCreditedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get paymentLateCreditedTitle;

  /// No description provided for @paymentLateCreditedBody.
  ///
  /// In en, this message translates to:
  /// **'The order had already been cancelled, so we added {amount} to your wallet balance.'**
  String paymentLateCreditedBody(String amount);

  /// No description provided for @topUpSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Top-up complete'**
  String get topUpSuccessTitle;

  /// No description provided for @topUpSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Added {amount} to your balance.'**
  String topUpSuccessBody(String amount);

  /// No description provided for @backToWallet.
  ///
  /// In en, this message translates to:
  /// **'Back to wallet'**
  String get backToWallet;

  /// No description provided for @payNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get payNow;

  /// No description provided for @payWithinNote.
  ///
  /// In en, this message translates to:
  /// **'Pay within {time}, or the order will be cancelled automatically.'**
  String payWithinNote(String time);

  /// No description provided for @orderCancelReasonPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'The payment didn\'t go through'**
  String get orderCancelReasonPaymentFailed;

  /// No description provided for @orderCancelReasonPaymentExpired.
  ///
  /// In en, this message translates to:
  /// **'Not paid in time'**
  String get orderCancelReasonPaymentExpired;

  /// No description provided for @walletTopUp.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get walletTopUp;

  /// No description provided for @topUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Top up your balance'**
  String get topUpTitle;

  /// No description provided for @topUpBody.
  ///
  /// In en, this message translates to:
  /// **'Pay with ZainCash — the amount is added to your wallet balance.'**
  String get topUpBody;

  /// No description provided for @topUpOtherAmount.
  ///
  /// In en, this message translates to:
  /// **'Other amount'**
  String get topUpOtherAmount;

  /// No description provided for @topUpAmountHint.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}'**
  String topUpAmountHint(String min, String max);

  /// No description provided for @topUpAmountRange.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount between {min} and {max}.'**
  String topUpAmountRange(String min, String max);

  /// No description provided for @topUpContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue to ZainCash'**
  String get topUpContinue;

  /// Checkout: promo rejected by placeOrder
  ///
  /// In en, this message translates to:
  /// **'Your promo code can no longer be used, so we removed it. Please check the new total.'**
  String get orderFailedPromo;

  /// Checkout: wallet payment does not cover the total
  ///
  /// In en, this message translates to:
  /// **'Your wallet doesn\'t cover this order. Choose cash on delivery or turn on your credits.'**
  String get walletInsufficient;

  /// No description provided for @orderFailedInvalidChoice.
  ///
  /// In en, this message translates to:
  /// **'That delivery time or payment method is no longer available. Please choose again.'**
  String get orderFailedInvalidChoice;

  /// No description provided for @checkoutRemoveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some items in your cart are no longer available. Remove them from the cart to continue.'**
  String get checkoutRemoveUnavailable;

  /// No description provided for @giftCardLabel.
  ///
  /// In en, this message translates to:
  /// **'GIFT CARD'**
  String get giftCardLabel;

  /// No description provided for @giftCardFrom.
  ///
  /// In en, this message translates to:
  /// **'From {amount}'**
  String giftCardFrom(String amount);

  /// No description provided for @giftCardTo.
  ///
  /// In en, this message translates to:
  /// **'To: {name}'**
  String giftCardTo(String name);

  /// No description provided for @giftCardShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift Card Shop'**
  String get giftCardShopTitle;

  /// No description provided for @giftCardShopEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No gift cards available yet'**
  String get giftCardShopEmptyTitle;

  /// No description provided for @giftCardShopEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'New designs are coming soon.'**
  String get giftCardShopEmptyBody;

  /// No description provided for @giftCardDesignTagline.
  ///
  /// In en, this message translates to:
  /// **'Design your gift card — make it personal.'**
  String get giftCardDesignTagline;

  /// No description provided for @giftCardDesignerTitle.
  ///
  /// In en, this message translates to:
  /// **'Design Your Gift Card'**
  String get giftCardDesignerTitle;

  /// No description provided for @giftCardDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'Card design'**
  String get giftCardDesignTitle;

  /// No description provided for @giftCardAmountTitle.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get giftCardAmountTitle;

  /// No description provided for @giftCardCustomAmount.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get giftCardCustomAmount;

  /// No description provided for @giftCardAmountHint.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}'**
  String giftCardAmountHint(String min, String max);

  /// No description provided for @giftCardAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get giftCardAmountRequired;

  /// No description provided for @giftCardAmountRange.
  ///
  /// In en, this message translates to:
  /// **'Choose an amount between {min} and {max}'**
  String giftCardAmountRange(String min, String max);

  /// No description provided for @giftCardPhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get giftCardPhotoTitle;

  /// No description provided for @giftCardMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get giftCardMessageTitle;

  /// No description provided for @giftCardRecipientTitle.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get giftCardRecipientTitle;

  /// No description provided for @giftCardRecipientPhone.
  ///
  /// In en, this message translates to:
  /// **'Recipient\'s mobile number'**
  String get giftCardRecipientPhone;

  /// No description provided for @giftCardContactHint.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send the card to this phone number or email.'**
  String get giftCardContactHint;

  /// No description provided for @giftCardContactRequired.
  ///
  /// In en, this message translates to:
  /// **'Add the recipient\'s phone number or email'**
  String get giftCardContactRequired;

  /// No description provided for @giftCardWhenTitle.
  ///
  /// In en, this message translates to:
  /// **'When to send'**
  String get giftCardWhenTitle;

  /// No description provided for @giftCardSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get giftCardSendNow;

  /// No description provided for @giftCardSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get giftCardSchedule;

  /// No description provided for @giftCardSendNowNote.
  ///
  /// In en, this message translates to:
  /// **'We send it as soon as it\'s paid.'**
  String get giftCardSendNowNote;

  /// No description provided for @giftCardSendOn.
  ///
  /// In en, this message translates to:
  /// **'Send on'**
  String get giftCardSendOn;

  /// No description provided for @giftCardScheduleRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the day to send the card'**
  String get giftCardScheduleRequired;

  /// No description provided for @giftCardScheduleRange.
  ///
  /// In en, this message translates to:
  /// **'Choose a day from tomorrow up to one year ahead'**
  String get giftCardScheduleRange;

  /// No description provided for @giftCardWalletBalance.
  ///
  /// In en, this message translates to:
  /// **'Wallet balance'**
  String get giftCardWalletBalance;

  /// No description provided for @giftCardWalletNote.
  ///
  /// In en, this message translates to:
  /// **'Paid from your wallet balance ({balance}). Credits can\'t be used for gift cards.'**
  String giftCardWalletNote(String balance);

  /// No description provided for @giftCardWalletShort.
  ///
  /// In en, this message translates to:
  /// **'Your wallet balance ({balance}) doesn\'t cover this card. Credits can\'t be used for gift cards.'**
  String giftCardWalletShort(String balance);

  /// No description provided for @giftCardCodNote.
  ///
  /// In en, this message translates to:
  /// **'Our courier collects payment at your address; the card is sent once paid.'**
  String get giftCardCodNote;

  /// No description provided for @giftCardAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Add the address where we collect the payment'**
  String get giftCardAddressRequired;

  /// No description provided for @giftCardBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy gift card'**
  String get giftCardBuy;

  /// No description provided for @giftCardFixErrors.
  ///
  /// In en, this message translates to:
  /// **'Please check the highlighted fields'**
  String get giftCardFixErrors;

  /// No description provided for @giftCardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This gift card is no longer available'**
  String get giftCardUnavailable;

  /// No description provided for @giftCardHaveCode.
  ///
  /// In en, this message translates to:
  /// **'Have a gift card code?'**
  String get giftCardHaveCode;

  /// No description provided for @giftCardRedeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get giftCardRedeem;

  /// No description provided for @giftCardRedeemToCredits.
  ///
  /// In en, this message translates to:
  /// **'Redeem to my credits'**
  String get giftCardRedeemToCredits;

  /// No description provided for @giftCardCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the 12-character code'**
  String get giftCardCodeInvalid;

  /// No description provided for @giftCardsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get giftCardsReceived;

  /// No description provided for @giftCardsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get giftCardsSent;

  /// No description provided for @giftCardsReceivedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No gift cards yet'**
  String get giftCardsReceivedEmptyTitle;

  /// No description provided for @giftCardsReceivedEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Gift cards sent to you appear here. Got a code? Enter it above.'**
  String get giftCardsReceivedEmptyBody;

  /// No description provided for @giftCardsSentEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t sent a gift card yet'**
  String get giftCardsSentEmptyTitle;

  /// No description provided for @giftCardsSentEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Surprise someone with a personal gift card.'**
  String get giftCardsSentEmptyBody;

  /// No description provided for @giftCardDesignCta.
  ///
  /// In en, this message translates to:
  /// **'Design a gift card'**
  String get giftCardDesignCta;

  /// No description provided for @giftCardStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get giftCardStatusPending;

  /// No description provided for @giftCardStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get giftCardStatusScheduled;

  /// No description provided for @giftCardStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get giftCardStatusActive;

  /// No description provided for @giftCardStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get giftCardStatusSent;

  /// No description provided for @giftCardStatusRedeemed.
  ///
  /// In en, this message translates to:
  /// **'Redeemed'**
  String get giftCardStatusRedeemed;

  /// No description provided for @giftCardStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get giftCardStatusExpired;

  /// No description provided for @giftCardStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get giftCardStatusDisabled;

  /// No description provided for @giftCardBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {amount}'**
  String giftCardBalance(String amount);

  /// No description provided for @giftCardSentOn.
  ///
  /// In en, this message translates to:
  /// **'Sent on {date}'**
  String giftCardSentOn(String date);

  /// No description provided for @giftCardScheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Will be sent on {date}'**
  String giftCardScheduledFor(String date);

  /// No description provided for @giftCardRedeemedTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift card redeemed!'**
  String get giftCardRedeemedTitle;

  /// No description provided for @giftCardRedeemedBody.
  ///
  /// In en, this message translates to:
  /// **'{amount} added to your credits'**
  String giftCardRedeemedBody(String amount);

  /// No description provided for @giftCardViewWallet.
  ///
  /// In en, this message translates to:
  /// **'View my wallet'**
  String get giftCardViewWallet;

  /// No description provided for @redeemNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a gift card with this code. Check it and try again.'**
  String get redeemNotFound;

  /// No description provided for @redeemExpired.
  ///
  /// In en, this message translates to:
  /// **'This gift card has expired.'**
  String get redeemExpired;

  /// No description provided for @redeemAlreadyRedeemed.
  ///
  /// In en, this message translates to:
  /// **'This gift card has already been redeemed.'**
  String get redeemAlreadyRedeemed;

  /// No description provided for @redeemDisabled.
  ///
  /// In en, this message translates to:
  /// **'This gift card can\'t be used. Please contact support.'**
  String get redeemDisabled;

  /// No description provided for @redeemNotYetSent.
  ///
  /// In en, this message translates to:
  /// **'This gift card isn\'t active yet — it\'s activated once it\'s paid and sent.'**
  String get redeemNotYetSent;

  /// No description provided for @redeemTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get redeemTooManyAttempts;

  /// No description provided for @redeemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Redeeming isn\'t available right now. Please try again later.'**
  String get redeemUnavailable;

  /// No description provided for @srAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get srAddPhoto;

  /// No description provided for @srSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Got a special idea? Tell us about it and we\'ll reach out soon to bring it to life!'**
  String get srSubtitle;

  /// No description provided for @srPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Add up to {max} photos (optional)'**
  String srPhotosHint(int max);

  /// No description provided for @srTextRequired.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your idea'**
  String get srTextRequired;

  /// No description provided for @srSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Thanks! We received your request and will reach out soon.'**
  String get srSubmitted;

  /// No description provided for @srMyRequests.
  ///
  /// In en, this message translates to:
  /// **'My requests'**
  String get srMyRequests;

  /// No description provided for @srStatusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get srStatusSubmitted;

  /// No description provided for @srStatusInReview.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get srStatusInReview;

  /// No description provided for @srStatusQuoted.
  ///
  /// In en, this message translates to:
  /// **'Quoted'**
  String get srStatusQuoted;

  /// No description provided for @srStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get srStatusAccepted;

  /// No description provided for @srStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get srStatusRejected;

  /// No description provided for @srStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get srStatusCompleted;

  /// No description provided for @srTypeSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get srTypeSupport;

  /// No description provided for @srNewReply.
  ///
  /// In en, this message translates to:
  /// **'New reply'**
  String get srNewReply;

  /// No description provided for @srDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your request'**
  String get srDetailsTitle;

  /// No description provided for @srNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this request'**
  String get srNotFound;

  /// No description provided for @srMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get srMessages;

  /// No description provided for @srNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet — we\'ll reply here.'**
  String get srNoMessages;

  /// No description provided for @srYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get srYou;

  /// No description provided for @srReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Write a message'**
  String get srReplyHint;

  /// No description provided for @srSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get srSend;

  /// No description provided for @srClosedNote.
  ///
  /// In en, this message translates to:
  /// **'This request is closed. For anything else, send us a new request.'**
  String get srClosedNote;

  /// No description provided for @srRejectedNote.
  ///
  /// In en, this message translates to:
  /// **'Sorry, we can\'t make this one. Feel free to send us another idea.'**
  String get srRejectedNote;

  /// No description provided for @srQuoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Our quote'**
  String get srQuoteTitle;

  /// No description provided for @srQuoteDeliveryNote.
  ///
  /// In en, this message translates to:
  /// **'The delivery fee is added at the next step.'**
  String get srQuoteDeliveryNote;

  /// No description provided for @srAcceptQuote.
  ///
  /// In en, this message translates to:
  /// **'Accept quote'**
  String get srAcceptQuote;

  /// No description provided for @srViewOrder.
  ///
  /// In en, this message translates to:
  /// **'View order'**
  String get srViewOrder;

  /// No description provided for @srQuoteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This quote can no longer be accepted'**
  String get srQuoteUnavailable;

  /// No description provided for @srBackToRequest.
  ///
  /// In en, this message translates to:
  /// **'Back to request'**
  String get srBackToRequest;

  /// No description provided for @srCityNotServed.
  ///
  /// In en, this message translates to:
  /// **'We don\'t deliver to this city yet. Choose another address.'**
  String get srCityNotServed;

  /// No description provided for @srWalletShort.
  ///
  /// In en, this message translates to:
  /// **'Your wallet balance ({balance}) doesn\'t cover this order.'**
  String srWalletShort(String balance);

  /// No description provided for @srQuoteRow.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get srQuoteRow;

  /// No description provided for @srConfirmOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm order'**
  String get srConfirmOrder;

  /// No description provided for @supportSendUsMessage.
  ///
  /// In en, this message translates to:
  /// **'Send us a message'**
  String get supportSendUsMessage;

  /// No description provided for @supportMessageHint.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportMessageHint;

  /// No description provided for @supportSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get supportSend;

  /// No description provided for @supportMessageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent! We\'ll reply in your messages soon.'**
  String get supportMessageSent;

  /// No description provided for @supportViewMessages.
  ///
  /// In en, this message translates to:
  /// **'View your messages'**
  String get supportViewMessages;

  /// No description provided for @supportSendAnother.
  ///
  /// In en, this message translates to:
  /// **'Send another'**
  String get supportSendAnother;

  /// No description provided for @partnerScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Become a Partner'**
  String get partnerScreenTitle;

  /// No description provided for @partnerHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell on Golden Gift'**
  String get partnerHeroTitle;

  /// No description provided for @partnerHeroBody.
  ///
  /// In en, this message translates to:
  /// **'Bring your gifts to more people across Iraq and Kurdistan.'**
  String get partnerHeroBody;

  /// No description provided for @partnerWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why partner with us'**
  String get partnerWhyTitle;

  /// No description provided for @partnerBenefitReachTitle.
  ///
  /// In en, this message translates to:
  /// **'Reach more customers'**
  String get partnerBenefitReachTitle;

  /// No description provided for @partnerBenefitReachBody.
  ///
  /// In en, this message translates to:
  /// **'Show your products to gift shoppers in every city we serve.'**
  String get partnerBenefitReachBody;

  /// No description provided for @partnerBenefitDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Your own store dashboard'**
  String get partnerBenefitDashboardTitle;

  /// No description provided for @partnerBenefitDashboardBody.
  ///
  /// In en, this message translates to:
  /// **'Manage your products and orders in one place.'**
  String get partnerBenefitDashboardBody;

  /// No description provided for @partnerBenefitPersonalTitle.
  ///
  /// In en, this message translates to:
  /// **'Made-to-order gifts'**
  String get partnerBenefitPersonalTitle;

  /// No description provided for @partnerBenefitPersonalBody.
  ///
  /// In en, this message translates to:
  /// **'Receive customers\' names, photos and messages with every order.'**
  String get partnerBenefitPersonalBody;

  /// No description provided for @partnerFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply to sell'**
  String get partnerFormTitle;

  /// No description provided for @partnerStoreName.
  ///
  /// In en, this message translates to:
  /// **'Store name'**
  String get partnerStoreName;

  /// No description provided for @partnerStoreNameLength.
  ///
  /// In en, this message translates to:
  /// **'Store name must be 2–60 characters'**
  String get partnerStoreNameLength;

  /// No description provided for @partnerOwnerName.
  ///
  /// In en, this message translates to:
  /// **'Owner name'**
  String get partnerOwnerName;

  /// No description provided for @partnerCategory.
  ///
  /// In en, this message translates to:
  /// **'What do you sell?'**
  String get partnerCategory;

  /// No description provided for @partnerCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Engraved wood, flowers, cakes'**
  String get partnerCategoryHint;

  /// No description provided for @partnerInstagramInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Instagram username'**
  String get partnerInstagramInvalid;

  /// No description provided for @partnerSamplePhotos.
  ///
  /// In en, this message translates to:
  /// **'Sample product photos'**
  String get partnerSamplePhotos;

  /// No description provided for @partnerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit application'**
  String get partnerSubmit;

  /// No description provided for @partnerThanksTitle.
  ///
  /// In en, this message translates to:
  /// **'Thank you for applying!'**
  String get partnerThanksTitle;

  /// No description provided for @partnerThanksBody.
  ///
  /// In en, this message translates to:
  /// **'We received your application and will contact you soon.'**
  String get partnerThanksBody;

  /// No description provided for @partnerPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re reviewing your application'**
  String get partnerPendingTitle;

  /// No description provided for @partnerPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Thanks for applying to sell {store} on Golden Gift. We\'ll contact you soon.'**
  String partnerPendingBody(String store);

  /// No description provided for @partnerYourStore.
  ///
  /// In en, this message translates to:
  /// **'your store'**
  String get partnerYourStore;

  /// No description provided for @partnerActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Your store is live'**
  String get partnerActiveTitle;

  /// No description provided for @partnerActiveBody.
  ///
  /// In en, this message translates to:
  /// **'Manage it in the Golden Gift dashboard:'**
  String get partnerActiveBody;

  /// No description provided for @partnerOpenDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open dashboard'**
  String get partnerOpenDashboard;

  /// No description provided for @partnerCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get partnerCopyLink;

  /// No description provided for @partnerSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your store is suspended'**
  String get partnerSuspendedTitle;

  /// No description provided for @partnerSuspendedBody.
  ///
  /// In en, this message translates to:
  /// **'Please contact our support team to resolve this.'**
  String get partnerSuspendedBody;

  /// No description provided for @partnerAlreadyApplied.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already applied with this account.'**
  String get partnerAlreadyApplied;

  /// No description provided for @partnerInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please check your details and try again.'**
  String get partnerInvalid;

  /// No description provided for @partnerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Applications aren\'t available right now. Please try again later.'**
  String get partnerUnavailable;

  /// No description provided for @aiSearchFieldHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My sister\'s graduation, she loves plants'**
  String get aiSearchFieldHint;

  /// No description provided for @aiSearchExamplesTitle.
  ///
  /// In en, this message translates to:
  /// **'Try an example'**
  String get aiSearchExamplesTitle;

  /// No description provided for @aiSearchOccasion.
  ///
  /// In en, this message translates to:
  /// **'Occasion'**
  String get aiSearchOccasion;

  /// No description provided for @aiSearchRecipient.
  ///
  /// In en, this message translates to:
  /// **'Who it\'s for'**
  String get aiSearchRecipient;

  /// No description provided for @aiSearchBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get aiSearchBudget;

  /// No description provided for @aiSearchAnyBudget.
  ///
  /// In en, this message translates to:
  /// **'Any budget'**
  String get aiSearchAnyBudget;

  /// No description provided for @aiSearchUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount}'**
  String aiSearchUpTo(String amount);

  /// No description provided for @aiOccasionBirthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get aiOccasionBirthday;

  /// No description provided for @aiOccasionAnniversary.
  ///
  /// In en, this message translates to:
  /// **'Anniversary'**
  String get aiOccasionAnniversary;

  /// No description provided for @aiOccasionGraduation.
  ///
  /// In en, this message translates to:
  /// **'Graduation'**
  String get aiOccasionGraduation;

  /// No description provided for @aiOccasionWedding.
  ///
  /// In en, this message translates to:
  /// **'Wedding'**
  String get aiOccasionWedding;

  /// No description provided for @aiOccasionNewBaby.
  ///
  /// In en, this message translates to:
  /// **'New baby'**
  String get aiOccasionNewBaby;

  /// No description provided for @aiOccasionEid.
  ///
  /// In en, this message translates to:
  /// **'Eid'**
  String get aiOccasionEid;

  /// No description provided for @aiOccasionThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you'**
  String get aiOccasionThankYou;

  /// No description provided for @aiRecipientMum.
  ///
  /// In en, this message translates to:
  /// **'Mum'**
  String get aiRecipientMum;

  /// No description provided for @aiRecipientDad.
  ///
  /// In en, this message translates to:
  /// **'Dad'**
  String get aiRecipientDad;

  /// No description provided for @aiRecipientWife.
  ///
  /// In en, this message translates to:
  /// **'Wife'**
  String get aiRecipientWife;

  /// No description provided for @aiRecipientHusband.
  ///
  /// In en, this message translates to:
  /// **'Husband'**
  String get aiRecipientHusband;

  /// No description provided for @aiRecipientSister.
  ///
  /// In en, this message translates to:
  /// **'Sister'**
  String get aiRecipientSister;

  /// No description provided for @aiRecipientBrother.
  ///
  /// In en, this message translates to:
  /// **'Brother'**
  String get aiRecipientBrother;

  /// No description provided for @aiRecipientFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get aiRecipientFriend;

  /// No description provided for @aiRecipientColleague.
  ///
  /// In en, this message translates to:
  /// **'Colleague'**
  String get aiRecipientColleague;

  /// No description provided for @aiRecipientChild.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get aiRecipientChild;

  /// No description provided for @aiSearchFindGifts.
  ///
  /// In en, this message translates to:
  /// **'Find gifts'**
  String get aiSearchFindGifts;

  /// No description provided for @aiSearchQueryRequired.
  ///
  /// In en, this message translates to:
  /// **'Tell us who the gift is for or the occasion.'**
  String get aiSearchQueryRequired;

  /// No description provided for @aiSearchQueryTooShort.
  ///
  /// In en, this message translates to:
  /// **'Add a few more words so we can find the right gifts.'**
  String get aiSearchQueryTooShort;

  /// No description provided for @aiSearchResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift ideas for you'**
  String get aiSearchResultsTitle;

  /// No description provided for @aiSearchFallbackNote.
  ///
  /// In en, this message translates to:
  /// **'Showing keyword matches — AI suggestions aren\'t available right now.'**
  String get aiSearchFallbackNote;

  /// No description provided for @aiSearchRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s AI searches. Showing keyword matches instead.'**
  String get aiSearchRateLimited;

  /// No description provided for @aiSearchNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No gift ideas found'**
  String get aiSearchNoResultsTitle;

  /// No description provided for @aiSearchNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try describing them in other words, or choose a bigger budget.'**
  String get aiSearchNoResultsBody;

  /// No description provided for @secretSantaIntro.
  ///
  /// In en, this message translates to:
  /// **'Draw names with family, friends or colleagues — everyone only sees who they\'re buying for.'**
  String get secretSantaIntro;

  /// No description provided for @secretSantaCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get secretSantaCreateGroup;

  /// No description provided for @secretSantaJoinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get secretSantaJoinWithCode;

  /// No description provided for @secretSantaCodeHint.
  ///
  /// In en, this message translates to:
  /// **'8-character invite code'**
  String get secretSantaCodeHint;

  /// No description provided for @secretSantaJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get secretSantaJoin;

  /// No description provided for @secretSantaInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 8-character code from your invite.'**
  String get secretSantaInvalidCode;

  /// No description provided for @secretSantaNoGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get secretSantaNoGroupsTitle;

  /// No description provided for @secretSantaNoGroupsBody.
  ///
  /// In en, this message translates to:
  /// **'Create a group, or join one with the invite code you received.'**
  String get secretSantaNoGroupsBody;

  /// No description provided for @secretSantaTypeFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get secretSantaTypeFamily;

  /// No description provided for @secretSantaTypeFriends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get secretSantaTypeFriends;

  /// No description provided for @secretSantaTypeWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get secretSantaTypeWork;

  /// No description provided for @secretSantaStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get secretSantaStatusOpen;

  /// No description provided for @secretSantaStatusDrawn.
  ///
  /// In en, this message translates to:
  /// **'Drawn'**
  String get secretSantaStatusDrawn;

  /// No description provided for @secretSantaStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get secretSantaStatusClosed;

  /// No description provided for @secretSantaOrganiserBadge.
  ///
  /// In en, this message translates to:
  /// **'You\'re the organiser'**
  String get secretSantaOrganiserBadge;

  /// No description provided for @secretSantaOrganiser.
  ///
  /// In en, this message translates to:
  /// **'Organiser'**
  String get secretSantaOrganiser;

  /// No description provided for @secretSantaMembersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String secretSantaMembersCount(int count);

  /// No description provided for @secretSantaMembersOf.
  ///
  /// In en, this message translates to:
  /// **'Members ({count}/{max})'**
  String secretSantaMembersOf(int count, int max);

  /// No description provided for @secretSantaBudgetValue.
  ///
  /// In en, this message translates to:
  /// **'{amount} per gift'**
  String secretSantaBudgetValue(String amount);

  /// No description provided for @secretSantaNoBudget.
  ///
  /// In en, this message translates to:
  /// **'No budget'**
  String get secretSantaNoBudget;

  /// No description provided for @secretSantaExchangeOn.
  ///
  /// In en, this message translates to:
  /// **'Exchange on {date}'**
  String secretSantaExchangeOn(String date);

  /// No description provided for @secretSantaGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get secretSantaGroupName;

  /// No description provided for @secretSantaGroupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Office 2026'**
  String get secretSantaGroupNameHint;

  /// No description provided for @secretSantaType.
  ///
  /// In en, this message translates to:
  /// **'Group type'**
  String get secretSantaType;

  /// No description provided for @secretSantaBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget per gift'**
  String get secretSantaBudget;

  /// No description provided for @secretSantaCustomBudget.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get secretSantaCustomBudget;

  /// No description provided for @secretSantaCustomBudgetHint.
  ///
  /// In en, this message translates to:
  /// **'Amount in IQD'**
  String get secretSantaCustomBudgetHint;

  /// No description provided for @secretSantaBudgetError.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get secretSantaBudgetError;

  /// No description provided for @secretSantaExchangeDate.
  ///
  /// In en, this message translates to:
  /// **'Exchange date'**
  String get secretSantaExchangeDate;

  /// No description provided for @secretSantaDateError.
  ///
  /// In en, this message translates to:
  /// **'Choose a date from tomorrow on.'**
  String get secretSantaDateError;

  /// No description provided for @secretSantaInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite your group'**
  String get secretSantaInviteTitle;

  /// No description provided for @secretSantaInviteBody.
  ///
  /// In en, this message translates to:
  /// **'Share the link or the code — members join in the Golden Gift app.'**
  String get secretSantaInviteBody;

  /// No description provided for @secretSantaCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get secretSantaCopyCode;

  /// No description provided for @secretSantaShareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get secretSantaShareLink;

  /// No description provided for @secretSantaShareText.
  ///
  /// In en, this message translates to:
  /// **'Join my Secret Santa group “{name}” on Golden Gift! Open {link} or enter the code {code}.'**
  String secretSantaShareText(String name, String link, String code);

  /// No description provided for @secretSantaShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Secret Santa on Golden Gift'**
  String get secretSantaShareSubject;

  /// No description provided for @secretSantaMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get secretSantaMembers;

  /// No description provided for @secretSantaYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get secretSantaYou;

  /// No description provided for @secretSantaMyWishNote.
  ///
  /// In en, this message translates to:
  /// **'My wish note'**
  String get secretSantaMyWishNote;

  /// No description provided for @secretSantaWishNoteHint.
  ///
  /// In en, this message translates to:
  /// **'What would you love to get? Your Secret Santa will see this.'**
  String get secretSantaWishNoteHint;

  /// No description provided for @secretSantaWishNoteEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add a note so your Secret Santa knows what you\'d love.'**
  String get secretSantaWishNoteEmpty;

  /// No description provided for @secretSantaAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get secretSantaAddNote;

  /// No description provided for @secretSantaWishNoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Wish note saved'**
  String get secretSantaWishNoteSaved;

  /// No description provided for @secretSantaDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw names'**
  String get secretSantaDraw;

  /// No description provided for @secretSantaDrawHint.
  ///
  /// In en, this message translates to:
  /// **'At least {min} members are needed to draw names.'**
  String secretSantaDrawHint(int min);

  /// No description provided for @secretSantaDrawConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Draw names now?'**
  String get secretSantaDrawConfirmTitle;

  /// No description provided for @secretSantaDrawConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone will see who they\'re buying for, and no one can join after the draw.'**
  String get secretSantaDrawConfirmBody;

  /// No description provided for @secretSantaDrawDone.
  ///
  /// In en, this message translates to:
  /// **'Names drawn! Everyone can now see who they\'re buying for.'**
  String get secretSantaDrawDone;

  /// No description provided for @secretSantaBuyingFor.
  ///
  /// In en, this message translates to:
  /// **'You\'re buying for {name}'**
  String secretSantaBuyingFor(String name);

  /// No description provided for @secretSantaOnlyYou.
  ///
  /// In en, this message translates to:
  /// **'Shh — only you can see this.'**
  String get secretSantaOnlyYou;

  /// No description provided for @secretSantaTheirWish.
  ///
  /// In en, this message translates to:
  /// **'Their wish note'**
  String get secretSantaTheirWish;

  /// No description provided for @secretSantaNoWishNote.
  ///
  /// In en, this message translates to:
  /// **'They haven\'t added a wish note yet.'**
  String get secretSantaNoWishNote;

  /// No description provided for @secretSantaShopForThem.
  ///
  /// In en, this message translates to:
  /// **'Shop for them'**
  String get secretSantaShopForThem;

  /// No description provided for @secretSantaDrawPending.
  ///
  /// In en, this message translates to:
  /// **'Names have been drawn — your match will appear in a moment.'**
  String get secretSantaDrawPending;

  /// No description provided for @secretSantaWaitingForDraw.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the organiser to draw names.'**
  String get secretSantaWaitingForDraw;

  /// No description provided for @secretSantaNotMember.
  ///
  /// In en, this message translates to:
  /// **'This group isn\'t available to you.'**
  String get secretSantaNotMember;

  /// No description provided for @secretSantaJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Secret Santa'**
  String get secretSantaJoinTitle;

  /// No description provided for @secretSantaJoinBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited with the code {code}. Add your name so the group knows who you are.'**
  String secretSantaJoinBody(String code);

  /// No description provided for @secretSantaJoinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get secretSantaJoinGroup;

  /// No description provided for @secretSantaJoined.
  ///
  /// In en, this message translates to:
  /// **'You\'re in! Welcome to the group.'**
  String get secretSantaJoined;

  /// No description provided for @secretSantaErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a group with that code.'**
  String get secretSantaErrorNotFound;

  /// No description provided for @secretSantaErrorAlreadyDrawn.
  ///
  /// In en, this message translates to:
  /// **'Names have already been drawn in this group.'**
  String get secretSantaErrorAlreadyDrawn;

  /// No description provided for @secretSantaErrorFull.
  ///
  /// In en, this message translates to:
  /// **'This group is full.'**
  String get secretSantaErrorFull;

  /// No description provided for @secretSantaErrorImpossible.
  ///
  /// In en, this message translates to:
  /// **'No valid draw is possible with the current exclusions.'**
  String get secretSantaErrorImpossible;

  /// No description provided for @secretSantaErrorNotOrganiser.
  ///
  /// In en, this message translates to:
  /// **'Only the organiser can draw names.'**
  String get secretSantaErrorNotOrganiser;

  /// No description provided for @secretSantaErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secret Santa isn\'t available right now. Please try again later.'**
  String get secretSantaErrorUnavailable;

  /// No description provided for @reviewsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviewsTitle;

  /// No description provided for @reviewsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No reviews yet} =1{1 review} other{{count} reviews}}'**
  String reviewsCount(int count);

  /// No description provided for @reviewsSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get reviewsSeeAll;

  /// No description provided for @reviewStarsLabel.
  ///
  /// In en, this message translates to:
  /// **'Rated {rating} out of 5'**
  String reviewStarsLabel(String rating);

  /// No description provided for @reviewStarButton.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String reviewStarButton(int count);

  /// No description provided for @reviewRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get reviewRate;

  /// No description provided for @reviewFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate this gift'**
  String get reviewFormTitle;

  /// No description provided for @reviewYourRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get reviewYourRating;

  /// No description provided for @reviewRatingRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a star rating.'**
  String get reviewRatingRequired;

  /// No description provided for @reviewTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Your review'**
  String get reviewTextLabel;

  /// No description provided for @reviewTextHint.
  ///
  /// In en, this message translates to:
  /// **'What did you love about it?'**
  String get reviewTextHint;

  /// No description provided for @reviewAddPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos (up to {max})'**
  String reviewAddPhotos(int max);

  /// No description provided for @reviewAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get reviewAddPhoto;

  /// No description provided for @reviewSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get reviewSubmit;

  /// No description provided for @reviewThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your review will appear after approval.'**
  String get reviewThanks;

  /// No description provided for @reviewPending.
  ///
  /// In en, this message translates to:
  /// **'Your review is pending approval'**
  String get reviewPending;

  /// No description provided for @reviewReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get reviewReviewed;

  /// No description provided for @reviewEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit review'**
  String get reviewEdit;

  /// No description provided for @reviewEditWarning.
  ///
  /// In en, this message translates to:
  /// **'Editing your review sends it back for approval before it\'s shown again.'**
  String get reviewEditWarning;

  /// No description provided for @reviewAnonymous.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get reviewAnonymous;

  /// No description provided for @addressPinOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pin on map'**
  String get addressPinOnMap;

  /// No description provided for @addressPinOnMapHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — helps the driver find the door'**
  String get addressPinOnMapHint;

  /// No description provided for @addressLocationPinned.
  ///
  /// In en, this message translates to:
  /// **'Location pinned'**
  String get addressLocationPinned;

  /// No description provided for @addressChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get addressChangePin;

  /// No description provided for @addressUseThisLocation.
  ///
  /// In en, this message translates to:
  /// **'Use this location'**
  String get addressUseThisLocation;

  /// No description provided for @addressMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Pin your location'**
  String get addressMapTitle;

  /// No description provided for @addressMapHelp.
  ///
  /// In en, this message translates to:
  /// **'Move the map until the pin sits on your door.'**
  String get addressMapHelp;

  /// No description provided for @wishlistDefaultList.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get wishlistDefaultList;

  /// No description provided for @wishlistNewList.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get wishlistNewList;

  /// No description provided for @wishlistListName.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get wishlistListName;

  /// No description provided for @wishlistListNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Mum\'s birthday'**
  String get wishlistListNameHint;

  /// No description provided for @wishlistCreateList.
  ///
  /// In en, this message translates to:
  /// **'Create list'**
  String get wishlistCreateList;

  /// No description provided for @wishlistRenameList.
  ///
  /// In en, this message translates to:
  /// **'Rename list'**
  String get wishlistRenameList;

  /// No description provided for @wishlistDeleteList.
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get wishlistDeleteList;

  /// No description provided for @wishlistDeleteListConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? Its gifts move to {defaultName}.'**
  String wishlistDeleteListConfirm(String name, String defaultName);

  /// No description provided for @wishlistListOptions.
  ///
  /// In en, this message translates to:
  /// **'List options'**
  String get wishlistListOptions;

  /// No description provided for @wishlistMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get wishlistMoveTo;

  /// No description provided for @wishlistSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Save to…'**
  String get wishlistSaveTo;

  /// No description provided for @wishlistSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {name}'**
  String wishlistSavedTo(String name);

  /// No description provided for @wishlistMovedTo.
  ///
  /// In en, this message translates to:
  /// **'Moved to {name}'**
  String wishlistMovedTo(String name);

  /// No description provided for @wishlistListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'This list is empty'**
  String get wishlistListEmptyTitle;

  /// No description provided for @wishlistListEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Long-press the heart on any gift to save it to a list.'**
  String get wishlistListEmptyBody;

  /// No description provided for @wishlistChooseList.
  ///
  /// In en, this message translates to:
  /// **'Choose a list'**
  String get wishlistChooseList;

  /// No description provided for @orderRefundedToWallet.
  ///
  /// In en, this message translates to:
  /// **'Refunded to your wallet: {amount}'**
  String orderRefundedToWallet(String amount);

  /// No description provided for @orderChangedByStore.
  ///
  /// In en, this message translates to:
  /// **'By the store'**
  String get orderChangedByStore;

  /// No description provided for @orderChangedByYou.
  ///
  /// In en, this message translates to:
  /// **'By you'**
  String get orderChangedByYou;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// Screen-reader label of a Home banner without a title.
  ///
  /// In en, this message translates to:
  /// **'Offer {index} of {count}'**
  String bannerSemanticLabel(int index, int count);

  /// Tiny pill on a coming-soon category tile / chip (SRS §5.7a). Keep it one short word.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get categorySoonBadge;

  /// Screen-reader label of a coming-soon category tile.
  ///
  /// In en, this message translates to:
  /// **'{category}, coming soon'**
  String categoryComingSoonLabel(String category);

  /// Line under the category name in the gold hero of the coming-soon page.
  ///
  /// In en, this message translates to:
  /// **'Curated with care. Arriving soon.'**
  String get comingSoonTagline;

  /// Main message of the coming-soon page (SRS §5.7a).
  ///
  /// In en, this message translates to:
  /// **'We\'re crafting something special for {category}. Our team is working on it — in the meantime, discover beautiful gifts in our other categories.'**
  String comingSoonMessage(String category);

  /// No description provided for @comingSoonExploreOthers.
  ///
  /// In en, this message translates to:
  /// **'Explore other categories'**
  String get comingSoonExploreOthers;

  /// No description provided for @comingSoonGiftsYouMightLove.
  ///
  /// In en, this message translates to:
  /// **'Gifts you might love'**
  String get comingSoonGiftsYouMightLove;

  /// No description provided for @comingSoonExploreAll.
  ///
  /// In en, this message translates to:
  /// **'Explore all categories'**
  String get comingSoonExploreAll;

  /// No description provided for @comingSoonBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get comingSoonBackHome;

  /// Discover's inline coming-soon card: selects the All chip again.
  ///
  /// In en, this message translates to:
  /// **'Show all gifts'**
  String get comingSoonShowAllGifts;

  /// Title of the gift-type filter section and the Product Details line (SRS §5.8a).
  ///
  /// In en, this message translates to:
  /// **'Gift for'**
  String get giftForTitle;

  /// Gift-type filter: no gift type chosen.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get giftForEveryone;

  /// Gift type `men` (SRS §5.8a).
  ///
  /// In en, this message translates to:
  /// **'For him'**
  String get giftForMen;

  /// Gift type `women`.
  ///
  /// In en, this message translates to:
  /// **'For her'**
  String get giftForWomen;

  /// Gift type `companies` — companies and organizations.
  ///
  /// In en, this message translates to:
  /// **'For companies'**
  String get giftForCompanies;

  /// Home Shop-for tile, under For him.
  ///
  /// In en, this message translates to:
  /// **'Gifts he\'ll love'**
  String get giftForMenTagline;

  /// Home Shop-for tile, under For her.
  ///
  /// In en, this message translates to:
  /// **'Gifts she\'ll love'**
  String get giftForWomenTagline;

  /// Home Shop-for tile, under For companies.
  ///
  /// In en, this message translates to:
  /// **'Corporate & team gifts'**
  String get giftForCompaniesTagline;

  /// Home section title above the For him / For her / For companies tiles.
  ///
  /// In en, this message translates to:
  /// **'Shop for'**
  String get shopForTitle;

  /// Bottom navigation tab and page title of the product videos (SRS §5.27).
  ///
  /// In en, this message translates to:
  /// **'Reels'**
  String get reels;

  /// Title of the Reels filter sheet.
  ///
  /// In en, this message translates to:
  /// **'Filter reels'**
  String get reelsFilterTitle;

  /// Reels filter sheet section.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get reelsCategory;

  /// Apply button of the Reels filter sheet.
  ///
  /// In en, this message translates to:
  /// **'Show reels'**
  String get reelsShowResults;

  /// Gold button on a reel's product card.
  ///
  /// In en, this message translates to:
  /// **'Shop now'**
  String get reelsShopNow;

  /// Reels tab with no reels at all.
  ///
  /// In en, this message translates to:
  /// **'No reels yet'**
  String get reelsEmptyTitle;

  /// No description provided for @reelsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Fresh gift videos are on their way.'**
  String get reelsEmptyBody;

  /// No description provided for @reelsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No reels match these filters'**
  String get reelsNoMatchTitle;

  /// No description provided for @reelsNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Try another category, price or gift type.'**
  String get reelsNoMatchBody;

  /// No description provided for @reelsClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get reelsClearFilters;

  /// Tooltip of the muted sound button.
  ///
  /// In en, this message translates to:
  /// **'Turn sound on'**
  String get reelsSoundOn;

  /// Tooltip of the sound button while sound is on.
  ///
  /// In en, this message translates to:
  /// **'Turn sound off'**
  String get reelsSoundOff;

  /// No description provided for @reelsPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get reelsPlay;

  /// No description provided for @reelsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get reelsPause;

  /// No description provided for @reelsVideoError.
  ///
  /// In en, this message translates to:
  /// **'This video can\'t be played'**
  String get reelsVideoError;

  /// Tooltip of the ✕ on an active-filter chip.
  ///
  /// In en, this message translates to:
  /// **'Remove filter'**
  String get reelsRemoveFilter;

  /// Shown after a truncated caption; tapping expands it.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get reelsMore;

  /// Screen-reader label of a reel's product card.
  ///
  /// In en, this message translates to:
  /// **'View {product}'**
  String reelsViewProduct(String product);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'ckb', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'ckb':
      return AppLocalizationsCkb();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
