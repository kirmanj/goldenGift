// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Golden Gift';

  @override
  String get appTagline => 'Personalized gifts, made for them';

  @override
  String get loading => 'Loading...';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get ok => 'OK';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get search => 'Search';

  @override
  String get viewAll => 'View All';

  @override
  String get noResults => 'No results found';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get confirm => 'Confirm';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get apply => 'Apply';

  @override
  String get home => 'Home';

  @override
  String get cart => 'Cart';

  @override
  String get profile => 'Profile';

  @override
  String get createYourAccount => 'Create Your Account';

  @override
  String get registerSubtitle =>
      'Register now and start creating personalized gifts in minutes!';

  @override
  String get signUp => 'Sign Up';

  @override
  String get signIn => 'Sign In';

  @override
  String get yourName => 'Your Name';

  @override
  String get enterYourName => 'Enter your name';

  @override
  String get email => 'Email';

  @override
  String get enterYourEmail => 'Enter your email';

  @override
  String get mobileNumber => 'Mobile Number';

  @override
  String get enterYourNumber => 'Enter your number';

  @override
  String get haveReferralCode => 'Have a referral code?';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get or => 'Or';

  @override
  String get continueAsGuest => 'Continue as a guest';

  @override
  String get goodMorning => 'Good morning';

  @override
  String get goodAfternoon => 'Good afternoon';

  @override
  String get goodEvening => 'Good evening';

  @override
  String get aiGiftSearch => 'AI Gift Search';

  @override
  String get aiGiftSearchHint => 'Describe who it\'s for or the occasion';

  @override
  String get popular => 'Popular';

  @override
  String get featured => 'Featured';

  @override
  String get forYou => 'For you';

  @override
  String get giftCards => 'Gift Cards';

  @override
  String get discover => 'Discover';

  @override
  String get all => 'All';

  @override
  String get more => 'More';

  @override
  String get myCart => 'My Cart';

  @override
  String get emptyCartTitle => 'Your Golden Gift cart is feeling lonely!';

  @override
  String get emptyCartSubtitle =>
      'Let\'s fill it with personalized magic. Start designing your perfect gifts now!';

  @override
  String get startShopping => 'Start Shopping';

  @override
  String get products => 'Products';

  @override
  String get searchForProduct => 'Search for a product';

  @override
  String get allCategories => 'All Categories';

  @override
  String get searchForCategory => 'Search for a category';

  @override
  String get productDetails => 'Product Details';

  @override
  String get aboutTheProduct => 'About the Product';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get share => 'Share';

  @override
  String preparationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'This product requires $days days for preparation',
      one: 'This product requires 1 day for preparation',
    );
    return '$_temp0';
  }

  @override
  String get sameDayShipping => 'This product can be shipped same day';

  @override
  String availableOnlyIn(String cities) {
    return 'Available only in: $cities';
  }

  @override
  String get uploadYourPhotos => 'Upload your photos';

  @override
  String get customizeTextHint =>
      'Enter the text you want to customize on your product';

  @override
  String get selectADate => 'Select a date';

  @override
  String get notes => 'Notes';

  @override
  String get account => 'Account';

  @override
  String get orders => 'Orders';

  @override
  String get myWishlists => 'My Wishlists';

  @override
  String get wishlistSubtitle => 'Gifts you\'ve saved';

  @override
  String get secretSanta => 'Secret Santa';

  @override
  String get secretSantaSubtitle => 'Family, friends and work exchanges';

  @override
  String get savedCards => 'Saved Cards';

  @override
  String get myWallet => 'My Wallet';

  @override
  String get inviteAndEarn => 'Invite & Earn';

  @override
  String get specialRequests => 'Special Requests';

  @override
  String get savedAddresses => 'Saved Addresses';

  @override
  String get myGiftCards => 'My Gift Cards';

  @override
  String get promoCodes => 'Promo Codes';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get availableBalance => 'Available Balance';

  @override
  String get noTransactionsYet => 'No Transactions Yet';

  @override
  String get transactionHistoryHint =>
      'Your Transaction History will appear here';

  @override
  String get creditsBalance => 'Golden Gift Credits Balance';

  @override
  String get successfulReferrals => 'Successful Referrals';

  @override
  String get pendingReferrals => 'Pending Referrals';

  @override
  String get yourReferralCode => 'Your referral code';

  @override
  String get inviteFriends => 'Invite Friends';

  @override
  String get walletTransactions => 'Transactions';

  @override
  String get walletBalance => 'Balance';

  @override
  String get walletCredits => 'Credits';

  @override
  String get walletSignInBody =>
      'Sign in to see your balance, credits and transactions.';

  @override
  String get txnTopUp => 'Top-up';

  @override
  String get txnOrderPayment => 'Order payment';

  @override
  String get txnRefund => 'Refund';

  @override
  String get txnReferralCredit => 'Referral reward';

  @override
  String get txnGiftCardRedeem => 'Gift card redeemed';

  @override
  String get txnAdminAdjustment => 'Balance adjustment';

  @override
  String get txnCreditExpiry => 'Credits expired';

  @override
  String creditsExpiryNote(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Credits expire $days days after you receive them.',
      one: 'Credits expire 1 day after you receive them.',
    );
    return '$_temp0';
  }

  @override
  String get promoHeaderTitle => 'Love a Good Deal? We Do Too! 🎉';

  @override
  String promoPercentOff(int percent) {
    return '$percent% Off';
  }

  @override
  String promoAmountOff(String amount) {
    return '$amount Off';
  }

  @override
  String get promoCopyCode => 'Copy code';

  @override
  String get codeCopied => 'Copied';

  @override
  String promoMinOrder(String amount) {
    return 'Min. order $amount';
  }

  @override
  String promoMaxDiscount(String amount) {
    return 'Max. discount $amount';
  }

  @override
  String get promoFirstOrderOnly => 'First order only';

  @override
  String get promoUse => 'Use';

  @override
  String get promoAppliedLabel => 'Applied';

  @override
  String promoAppliedSnack(String code) {
    return '$code applied to your cart';
  }

  @override
  String get noPromoCodesTitle => 'No promo codes right now';

  @override
  String get noPromoCodesBody => 'New deals show up here — check back soon.';

  @override
  String get promoCodeHint => 'Promo code';

  @override
  String get promoNotFound => 'This code doesn\'t exist';

  @override
  String get promoInactive => 'This code is no longer active';

  @override
  String get promoExpired => 'This code has expired';

  @override
  String promoMinOrderNotMet(String amount) {
    return 'Minimum order for this code is $amount';
  }

  @override
  String get promoUsageLimit => 'This code has reached its usage limit';

  @override
  String get promoPerUserLimit => 'You\'ve already used this code';

  @override
  String get promoFirstOrderOnlyError =>
      'This code is only for your first order';

  @override
  String get promoNotApplicable => 'Not valid for the items in your cart';

  @override
  String promoDiscountRow(String code) {
    return 'Promo ($code)';
  }

  @override
  String promoSaved(String amount) {
    return 'You save $amount';
  }

  @override
  String useMyCredits(String amount) {
    return 'Use my credits ($amount available)';
  }

  @override
  String get inviteFriendsBody =>
      'Invite your friends and let them create unique gifts & products their way. 🎁✨';

  @override
  String get successfulReferralsHint =>
      'Friends who signed up and placed a paid order';

  @override
  String get pendingReferralsHint =>
      'Friends who signed up — reward when they order';

  @override
  String referralBothGet(String amount) {
    return 'Share it with friends — you\'ll both get $amount';
  }

  @override
  String referralEachGets(String friend, String you) {
    return 'Share it with friends — they get $friend, you get $you';
  }

  @override
  String referralYouGet(String you) {
    return 'Share it with friends — you get $you after their first paid order';
  }

  @override
  String referralFriendGets(String friend) {
    return 'Share it with friends — they get $friend when they join';
  }

  @override
  String get learnMoreReferrals => 'Learn more about referrals';

  @override
  String get copyReferralCode => 'Copy referral code';

  @override
  String referralShareText(String amount, String code, String link) {
    return 'Join me on Golden Gift for personalized gifts! Sign up with my code $code and get $amount in credits: $link';
  }

  @override
  String referralShareTextNoBonus(String code, String link) {
    return 'Join me on Golden Gift for personalized gifts! Sign up with my code $code: $link';
  }

  @override
  String get referralShareSubject => 'Join me on Golden Gift';

  @override
  String get referralRulesTitle => 'How referrals work';

  @override
  String referralRuleJoin(String amount) {
    return 'Your friend signs up with your code and gets $amount in credits.';
  }

  @override
  String referralRuleOrder(String amount) {
    return 'You get $amount in credits when their first order is delivered and paid.';
  }

  @override
  String referralRuleMonthlyCap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You can be rewarded for up to $count friends per month.',
      one: 'You can be rewarded for 1 friend per month.',
    );
    return '$_temp0';
  }

  @override
  String get referralRuleSpend =>
      'Credits can be spent on any order in the app; they can\'t be withdrawn as cash.';

  @override
  String get referralRuleFairUse =>
      'Referring yourself, or another account on the same device, doesn\'t earn rewards.';

  @override
  String get referralInvitesTitle => 'Your invites';

  @override
  String get referralStatusPending => 'Pending';

  @override
  String get referralStatusCompleted => 'Rewarded';

  @override
  String get referralStatusCancelled => 'Cancelled';

  @override
  String get referralAFriend => 'A friend';

  @override
  String get inviteSignInBody =>
      'Sign in to get your referral code and invite friends.';

  @override
  String get referralRewardsChip => 'Referral rewards';

  @override
  String get referralSheetTitle => 'Invite friends, earn credits';

  @override
  String get referralSheetBody =>
      'Share your personal link once and get rewarded when friends discover Golden Gift.';

  @override
  String get referralFriendJoins => 'Friend joins';

  @override
  String get referralFirstPaidOrder => 'First paid order';

  @override
  String get referralShareLinkTitle => 'Share your invite link';

  @override
  String get referralShareLinkBody =>
      'Open My Rewards anytime to copy or share it.';

  @override
  String get referralWatchCreditsTitle => 'Watch credits build up';

  @override
  String referralWatchBoth(String friend, String you) {
    return 'They get $friend when they join, and you earn $you after their first paid order.';
  }

  @override
  String referralWatchYou(String you) {
    return 'You earn $you after their first paid order.';
  }

  @override
  String referralWatchFriend(String friend) {
    return 'They get $friend when they join.';
  }

  @override
  String get referralMyRewards => 'My Rewards';

  @override
  String get referralInvite => 'Invite';

  @override
  String get referralMaybeLater => 'Maybe later';

  @override
  String get referralLinkSignedIn =>
      'Referral codes are for new accounts. Invite your own friends from Invite & Earn.';

  @override
  String get submitYourRequest => 'Submit your request';

  @override
  String get writeYourIdeaHere => 'Write your idea here';

  @override
  String expiresOn(String date) {
    return 'Expires on: $date';
  }

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get filter => 'Filter';

  @override
  String get clear => 'Clear';

  @override
  String get addToWishlist => 'Add to wishlist';

  @override
  String get removeFromWishlist => 'Remove from wishlist';

  @override
  String originalPrice(String price) {
    return 'Original price $price';
  }

  @override
  String percentOff(int percent) {
    return '$percent% off';
  }

  @override
  String get onboardingTitle1 => 'Personalize every gift';

  @override
  String get onboardingBody1 =>
      'Add names, photos, colours and messages to make it truly theirs.';

  @override
  String get onboardingTitle2 => 'Delivered with care';

  @override
  String get onboardingBody2 =>
      'Delivery across Iraq and the Kurdistan Region — wrapped and ready to give.';

  @override
  String get onboardingTitle3 => 'Earn credits';

  @override
  String get onboardingBody3 =>
      'Invite friends and collect Golden Gift credits when they order.';

  @override
  String get getStarted => 'Get started';

  @override
  String get signInTitle => 'Welcome back';

  @override
  String get signInSubtitle => 'Sign in with your mobile number to continue.';

  @override
  String get dontHaveAccount => 'Don\'t have an account?';

  @override
  String get referralCodeLabel => 'Referral code';

  @override
  String get referralCodeHint => '6-character code';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get selectCountry => 'Select country';

  @override
  String get termsAgreement =>
      'By continuing you agree to our Terms of Service and Privacy Policy.';

  @override
  String get completeProfileTitle => 'Complete your account';

  @override
  String get completeProfileSubtitle =>
      'Tell us a little about you to finish signing up.';

  @override
  String get phoneLaterNote =>
      'You can add your mobile number later — it\'s needed before checkout.';

  @override
  String get otpTitle => 'Verify your number';

  @override
  String otpSubtitle(String phone) {
    return 'Enter the 6-digit code we sent to $phone';
  }

  @override
  String otpResendIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get otpResend => 'Resend code';

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpCodeSent => 'Code sent';

  @override
  String get changeNumber => 'Change number';

  @override
  String get errorRequired => 'This field is required';

  @override
  String get errorNameLength => 'Name must be 2–50 characters';

  @override
  String get errorInvalidEmail => 'Enter a valid email address';

  @override
  String get errorInvalidPhone => 'Enter a valid mobile number';

  @override
  String get errorInvalidReferralCode =>
      'Referral codes have 6 letters or digits';

  @override
  String get authErrorInvalidCode =>
      'That code isn\'t right. Check it and try again.';

  @override
  String get authErrorCodeExpired => 'The code expired. Request a new one.';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Please try again later.';

  @override
  String get authErrorNetwork =>
      'No internet connection. Check your connection and try again.';

  @override
  String get authErrorPhoneInUse =>
      'This number is already linked to another account.';

  @override
  String get authErrorUnavailable =>
      'This sign-in option isn\'t available yet.';

  @override
  String get authErrorAccountDisabled =>
      'This account has been disabled. Contact us for help.';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String get signInToContinueBody =>
      'Create an account or sign in to save gifts, check out and track your orders.';

  @override
  String get maintenanceTitle => 'We\'ll be right back';

  @override
  String get maintenanceBody =>
      'Golden Gift is getting a small upgrade. Please check back soon.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'A new version of Golden Gift is available. Please update to continue.';

  @override
  String get updateNow => 'Update now';

  @override
  String get guest => 'Guest';

  @override
  String get guestProfileTitle => 'You\'re browsing as a guest';

  @override
  String get guestProfileBody =>
      'Sign in to see your orders, wallet and saved gifts.';

  @override
  String inviteAndEarnSubtitle(String amount) {
    return 'Earn $amount per friend';
  }

  @override
  String get language => 'Language';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get settings => 'Settings';

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirm => 'Log out of Golden Gift?';

  @override
  String get addPhoneNumber => 'Add mobile number';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get birthday => 'Birthday';

  @override
  String get selectBirthday => 'Select your birthday';

  @override
  String get gender => 'Gender';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderPreferNot => 'Prefer not to say';

  @override
  String get city => 'City';

  @override
  String get selectCity => 'Select your city';

  @override
  String get changePhone => 'Change';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get phoneUpdated => 'Mobile number updated';

  @override
  String get changePhoneTitle => 'Change mobile number';

  @override
  String get changePhoneSubtitle =>
      'We\'ll send a verification code to your new number.';

  @override
  String get sendCode => 'Send code';

  @override
  String get phoneChangeMobileOnly =>
      'Changing your number is available in the mobile app.';

  @override
  String get photoUploadFailed =>
      'Couldn\'t upload the photo. Please try again.';

  @override
  String get unsavedChanges => 'Discard your changes?';

  @override
  String get discard => 'Discard';

  @override
  String get notificationsSetting => 'Notifications';

  @override
  String get notificationsSettingSubtitle => 'Order updates and offers';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'Your profile, addresses, cart and wishlist will be removed. Past orders are kept for our records. This can\'t be undone.';

  @override
  String get deleteAccountConfirm => 'Delete my account';

  @override
  String get accountDeleted => 'Your account has been deleted.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageKurdish => 'کوردی';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get authErrorDeliveryFailed =>
      'We couldn\'t send the code. Check the number and your connection, then try again.';

  @override
  String get profileCompletionTitle =>
      'Complete your profile to unlock better recommendations';

  @override
  String get goToProfile => 'Go to profile';

  @override
  String get notifications => 'Notifications';

  @override
  String get filters => 'Filters';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortRelevance => 'Best match';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortPopular => 'Most popular';

  @override
  String get sortPriceLowHigh => 'Price: low to high';

  @override
  String get sortPriceHighLow => 'Price: high to low';

  @override
  String get price => 'Price';

  @override
  String priceUnder(String amount) {
    return 'Under $amount';
  }

  @override
  String priceBetween(String min, String max) {
    return '$min – $max';
  }

  @override
  String priceAndAbove(String amount) {
    return '$amount and above';
  }

  @override
  String get availability => 'Availability';

  @override
  String get sameDayOnly => 'Ships same day';

  @override
  String get onSaleOnly => 'On sale';

  @override
  String get deliverTo => 'Deliver to';

  @override
  String get anyCity => 'Any city';

  @override
  String get resetFilters => 'Reset';

  @override
  String get showResults => 'Show results';

  @override
  String get offlineChip => 'Offline — showing saved items';

  @override
  String get noProductsTitle => 'No gifts found';

  @override
  String get noProductsBody => 'Try another search or remove some filters.';

  @override
  String get searchFallbackNote =>
      'Search is limited right now — showing matches from all categories and cities.';

  @override
  String get noCategoriesMatch => 'No categories match your search';

  @override
  String get loadMoreFailed => 'Couldn\'t load more gifts.';

  @override
  String get readMore => 'Read more';

  @override
  String get readLess => 'Show less';

  @override
  String get optionalLabel => '(Optional)';

  @override
  String get optionRequiredError => 'Please choose an option';

  @override
  String get textRequiredError => 'Please enter the text';

  @override
  String get dateRequiredError => 'Please choose a date';

  @override
  String textTooLongError(int max) {
    return 'Keep it to $max characters';
  }

  @override
  String photosRequiredError(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: 'Add at least $min photos',
      one: 'Add a photo',
    );
    return '$_temp0';
  }

  @override
  String get optionUnavailableError =>
      'This option is sold out — choose another';

  @override
  String get addedToCart => 'Added to cart';

  @override
  String get viewCart => 'View cart';

  @override
  String uploadingPhotos(int percent) {
    return 'Uploading photos… $percent%';
  }

  @override
  String get photoTooLarge => 'This photo is larger than 10 MB';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String photoSlot(int n) {
    return 'Photo $n';
  }

  @override
  String get quantity => 'Quantity';

  @override
  String get productNotFound => 'This gift is no longer available';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get deliveryFee => 'Delivery';

  @override
  String get deliveryCalculatedAtCheckout => 'Calculated at checkout';

  @override
  String get total => 'Total';

  @override
  String get checkout => 'Checkout';

  @override
  String get remove => 'Remove';

  @override
  String get itemUnavailable =>
      'No longer available — not included in the total';

  @override
  String priceChangedNote(String price) {
    return 'Price updated to $price';
  }

  @override
  String soldBy(String store) {
    return 'Sold by $store';
  }

  @override
  String photosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get wishlistEmptyTitle => 'No saved gifts yet';

  @override
  String get wishlistEmptyBody => 'Tap the heart on any gift to save it here.';

  @override
  String get increaseQuantity => 'Increase quantity';

  @override
  String get decreaseQuantity => 'Decrease quantity';

  @override
  String get addAddress => 'Add address';

  @override
  String get editAddress => 'Edit address';

  @override
  String get addressLabel => 'Label (e.g. Home, Work)';

  @override
  String get recipientName => 'Recipient name';

  @override
  String get area => 'Area / district';

  @override
  String get street => 'Street';

  @override
  String get building => 'Building';

  @override
  String get floor => 'Floor / apartment';

  @override
  String get addressNotes => 'Directions for the courier';

  @override
  String get defaultAddress => 'Default';

  @override
  String get setAsDefault => 'Set as default';

  @override
  String get deleteAddressConfirm => 'Delete this address?';

  @override
  String get noAddressesTitle => 'No saved addresses';

  @override
  String get noAddressesBody => 'Add an address to get your gifts delivered.';

  @override
  String get deliveryAddress => 'Delivery address';

  @override
  String get changeAddress => 'Change';

  @override
  String get deliveryDateAndTime => 'Delivery date & time';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get noSlotsToday =>
      'No delivery times left today — choose another day';

  @override
  String get giftOptions => 'Gift options';

  @override
  String get thisIsAGift => 'This is a gift';

  @override
  String get hidePricesOnInvoice => 'Hide prices on the invoice';

  @override
  String get giftMessage => 'Gift message';

  @override
  String get giftMessageHint => 'Write a message for the card';

  @override
  String get paymentMethod => 'Payment method';

  @override
  String get cashOnDelivery => 'Cash on delivery';

  @override
  String get walletPayment => 'Wallet & credits';

  @override
  String get cardPayment => 'Card / e-wallet';

  @override
  String get orderSummary => 'Order summary';

  @override
  String get placeOrder => 'Place order';

  @override
  String get placingOrder => 'Placing your order…';

  @override
  String itemNotDeliverableToCity(String item) {
    return '$item can\'t be delivered to this city';
  }

  @override
  String minimumOrderNotMet(String amount) {
    return 'The minimum order is $amount';
  }

  @override
  String get orderFailedCartChanged =>
      'Some items changed. Please review your cart.';

  @override
  String get orderFailedOutOfStock =>
      'Some items just sold out. Please review your cart.';

  @override
  String get orderFailedCity =>
      'Some items can\'t be delivered to the selected city.';

  @override
  String get orderFailedUnavailable =>
      'Ordering isn\'t available right now. Please try again later.';

  @override
  String get orderPlacedTitle => 'Order placed!';

  @override
  String orderPlacedBody(String number) {
    return 'Thank you! We\'ve received order $number.';
  }

  @override
  String get estimatedDelivery => 'Estimated delivery';

  @override
  String get trackOrder => 'Track order';

  @override
  String get continueShopping => 'Continue shopping';

  @override
  String get activeOrders => 'Active';

  @override
  String get completedOrders => 'Completed';

  @override
  String get cancelledOrders => 'Cancelled';

  @override
  String get noOrdersTitle => 'No orders yet';

  @override
  String get noOrdersBody => 'Your orders will appear here.';

  @override
  String orderNumber(String number) {
    return 'Order $number';
  }

  @override
  String get orderDetails => 'Order details';

  @override
  String get orderStatus => 'Order status';

  @override
  String get items => 'Items';

  @override
  String get paymentInfo => 'Payment';

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get cancelOrderConfirm => 'Cancel this order?';

  @override
  String get cancelReasonHint => 'Reason (optional)';

  @override
  String get orderCancelled => 'Order cancelled';

  @override
  String get orderNotCancellable => 'This order can no longer be cancelled.';

  @override
  String get reorder => 'Reorder';

  @override
  String get reorderAdded => 'Items added to your cart';

  @override
  String get contactSupport => 'Contact support';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusPreparing => 'Preparing';

  @override
  String get statusReadyForDelivery => 'Ready for delivery';

  @override
  String get statusOutForDelivery => 'Out for delivery';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String get statusCancelledByBuyer => 'Cancelled';

  @override
  String get statusCancelledBySeller => 'Cancelled by the store';

  @override
  String get statusReturned => 'Returned';

  @override
  String get statusRefunded => 'Refunded';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get noNotificationsTitle => 'No notifications yet';

  @override
  String get noNotificationsBody =>
      'Order updates and offers will show up here.';

  @override
  String get contactUsBody =>
      'We\'re here to help — reach us any way you like.';

  @override
  String get contactWhatsapp => 'WhatsApp';

  @override
  String get contactCall => 'Call us';

  @override
  String get contactEmail => 'Email';

  @override
  String get contactInstagram => 'Instagram';

  @override
  String get discount => 'Discount';

  @override
  String get paymentStatusPending => 'Not paid yet';

  @override
  String get paymentStatusPaid => 'Paid';

  @override
  String get paymentStatusFailed => 'Payment failed';

  @override
  String get paymentStatusRefunded => 'Refunded';

  @override
  String get paymentZainCash => 'ZainCash';

  @override
  String get paymentZainCashHint => 'Pay on ZainCash\'s secure page';

  @override
  String zainCashMinimum(String amount) {
    return 'ZainCash needs at least $amount to pay. Choose another payment method.';
  }

  @override
  String get paymentConnecting => 'Opening ZainCash…';

  @override
  String get paymentOrderSaved =>
      'Your order is saved — you can pay it from Order details.';

  @override
  String get paymentErrorDisabled =>
      'Online payment is switched off right now. Please choose another payment method.';

  @override
  String get paymentErrorNotPayable => 'This order can\'t be paid online.';

  @override
  String get paymentErrorAlreadyPaid => 'This order is already paid.';

  @override
  String get paymentErrorExpired => 'The time to pay this order has run out.';

  @override
  String get paymentErrorUnavailable =>
      'ZainCash isn\'t available right now. Nothing was charged — please try again in a moment.';

  @override
  String get paymentOpenFailed =>
      'We couldn\'t open ZainCash. Tap “Open ZainCash again”.';

  @override
  String get paymentWaitingTitle => 'Complete your payment on ZainCash';

  @override
  String get paymentWaitingBody =>
      'We opened ZainCash\'s secure page. After you pay, come back here — this page updates by itself.';

  @override
  String get paymentAmountToPay => 'Amount to pay';

  @override
  String get paymentForTopUp => 'Wallet top-up';

  @override
  String paymentTimeLeft(String time) {
    return 'Time left to pay: $time';
  }

  @override
  String get paymentOpenAgain => 'Open ZainCash again';

  @override
  String get paymentCheckStatus => 'I\'ve paid — check status';

  @override
  String get paymentStillPending =>
      'ZainCash hasn\'t confirmed the payment yet. This page updates as soon as it does.';

  @override
  String get paymentTimeUp =>
      'Time\'s up. We\'re confirming the result with ZainCash — this can take a few minutes.';

  @override
  String get paymentChecking => 'Checking your payment…';

  @override
  String get paymentNotFound => 'We couldn\'t find this payment.';

  @override
  String get paymentFailedTitle => 'Payment didn\'t go through';

  @override
  String get paymentExpiredTitle => 'Time to pay ran out';

  @override
  String paymentOrderCancelledBody(String number) {
    return 'Order $number was cancelled. Nothing was charged, and any credits you used are back in your wallet.';
  }

  @override
  String get paymentNothingCharged => 'Nothing was charged. You can try again.';

  @override
  String get paymentTryAgain => 'Try again';

  @override
  String get paymentLateCreditedTitle => 'Payment received';

  @override
  String paymentLateCreditedBody(String amount) {
    return 'The order had already been cancelled, so we added $amount to your wallet balance.';
  }

  @override
  String get topUpSuccessTitle => 'Top-up complete';

  @override
  String topUpSuccessBody(String amount) {
    return 'Added $amount to your balance.';
  }

  @override
  String get backToWallet => 'Back to wallet';

  @override
  String get payNow => 'Pay now';

  @override
  String payWithinNote(String time) {
    return 'Pay within $time, or the order will be cancelled automatically.';
  }

  @override
  String get orderCancelReasonPaymentFailed => 'The payment didn\'t go through';

  @override
  String get orderCancelReasonPaymentExpired => 'Not paid in time';

  @override
  String get walletTopUp => 'Top up';

  @override
  String get topUpTitle => 'Top up your balance';

  @override
  String get topUpBody =>
      'Pay with ZainCash — the amount is added to your wallet balance.';

  @override
  String get topUpOtherAmount => 'Other amount';

  @override
  String topUpAmountHint(String min, String max) {
    return 'Between $min and $max';
  }

  @override
  String topUpAmountRange(String min, String max) {
    return 'Enter an amount between $min and $max.';
  }

  @override
  String get topUpContinue => 'Continue to ZainCash';

  @override
  String get orderFailedPromo =>
      'Your promo code can no longer be used, so we removed it. Please check the new total.';

  @override
  String get walletInsufficient =>
      'Your wallet doesn\'t cover this order. Choose cash on delivery or turn on your credits.';

  @override
  String get orderFailedInvalidChoice =>
      'That delivery time or payment method is no longer available. Please choose again.';

  @override
  String get checkoutRemoveUnavailable =>
      'Some items in your cart are no longer available. Remove them from the cart to continue.';

  @override
  String get giftCardLabel => 'GIFT CARD';

  @override
  String giftCardFrom(String amount) {
    return 'From $amount';
  }

  @override
  String giftCardTo(String name) {
    return 'To: $name';
  }

  @override
  String get giftCardShopTitle => 'Gift Card Shop';

  @override
  String get giftCardShopEmptyTitle => 'No gift cards available yet';

  @override
  String get giftCardShopEmptyBody => 'New designs are coming soon.';

  @override
  String get giftCardDesignTagline =>
      'Design your gift card — make it personal.';

  @override
  String get giftCardDesignerTitle => 'Design Your Gift Card';

  @override
  String get giftCardDesignTitle => 'Card design';

  @override
  String get giftCardAmountTitle => 'Amount';

  @override
  String get giftCardCustomAmount => 'Custom';

  @override
  String giftCardAmountHint(String min, String max) {
    return 'Between $min and $max';
  }

  @override
  String get giftCardAmountRequired => 'Enter an amount';

  @override
  String giftCardAmountRange(String min, String max) {
    return 'Choose an amount between $min and $max';
  }

  @override
  String get giftCardPhotoTitle => 'Photo';

  @override
  String get giftCardMessageTitle => 'Message';

  @override
  String get giftCardRecipientTitle => 'Recipient';

  @override
  String get giftCardRecipientPhone => 'Recipient\'s mobile number';

  @override
  String get giftCardContactHint =>
      'We\'ll send the card to this phone number or email.';

  @override
  String get giftCardContactRequired =>
      'Add the recipient\'s phone number or email';

  @override
  String get giftCardWhenTitle => 'When to send';

  @override
  String get giftCardSendNow => 'Send now';

  @override
  String get giftCardSchedule => 'Schedule';

  @override
  String get giftCardSendNowNote => 'We send it as soon as it\'s paid.';

  @override
  String get giftCardSendOn => 'Send on';

  @override
  String get giftCardScheduleRequired => 'Choose the day to send the card';

  @override
  String get giftCardScheduleRange =>
      'Choose a day from tomorrow up to one year ahead';

  @override
  String get giftCardWalletBalance => 'Wallet balance';

  @override
  String giftCardWalletNote(String balance) {
    return 'Paid from your wallet balance ($balance). Credits can\'t be used for gift cards.';
  }

  @override
  String giftCardWalletShort(String balance) {
    return 'Your wallet balance ($balance) doesn\'t cover this card. Credits can\'t be used for gift cards.';
  }

  @override
  String get giftCardCodNote =>
      'Our courier collects payment at your address; the card is sent once paid.';

  @override
  String get giftCardAddressRequired =>
      'Add the address where we collect the payment';

  @override
  String get giftCardBuy => 'Buy gift card';

  @override
  String get giftCardFixErrors => 'Please check the highlighted fields';

  @override
  String get giftCardUnavailable => 'This gift card is no longer available';

  @override
  String get giftCardHaveCode => 'Have a gift card code?';

  @override
  String get giftCardRedeem => 'Redeem';

  @override
  String get giftCardRedeemToCredits => 'Redeem to my credits';

  @override
  String get giftCardCodeInvalid => 'Enter the 12-character code';

  @override
  String get giftCardsReceived => 'Received';

  @override
  String get giftCardsSent => 'Sent';

  @override
  String get giftCardsReceivedEmptyTitle => 'No gift cards yet';

  @override
  String get giftCardsReceivedEmptyBody =>
      'Gift cards sent to you appear here. Got a code? Enter it above.';

  @override
  String get giftCardsSentEmptyTitle => 'You haven\'t sent a gift card yet';

  @override
  String get giftCardsSentEmptyBody =>
      'Surprise someone with a personal gift card.';

  @override
  String get giftCardDesignCta => 'Design a gift card';

  @override
  String get giftCardStatusPending => 'Awaiting payment';

  @override
  String get giftCardStatusScheduled => 'Scheduled';

  @override
  String get giftCardStatusActive => 'Active';

  @override
  String get giftCardStatusSent => 'Sent';

  @override
  String get giftCardStatusRedeemed => 'Redeemed';

  @override
  String get giftCardStatusExpired => 'Expired';

  @override
  String get giftCardStatusDisabled => 'Disabled';

  @override
  String giftCardBalance(String amount) {
    return 'Balance: $amount';
  }

  @override
  String giftCardSentOn(String date) {
    return 'Sent on $date';
  }

  @override
  String giftCardScheduledFor(String date) {
    return 'Will be sent on $date';
  }

  @override
  String get giftCardRedeemedTitle => 'Gift card redeemed!';

  @override
  String giftCardRedeemedBody(String amount) {
    return '$amount added to your credits';
  }

  @override
  String get giftCardViewWallet => 'View my wallet';

  @override
  String get redeemNotFound =>
      'We couldn\'t find a gift card with this code. Check it and try again.';

  @override
  String get redeemExpired => 'This gift card has expired.';

  @override
  String get redeemAlreadyRedeemed =>
      'This gift card has already been redeemed.';

  @override
  String get redeemDisabled =>
      'This gift card can\'t be used. Please contact support.';

  @override
  String get redeemNotYetSent =>
      'This gift card isn\'t active yet — it\'s activated once it\'s paid and sent.';

  @override
  String get redeemTooManyAttempts =>
      'Too many attempts. Please try again later.';

  @override
  String get redeemUnavailable =>
      'Redeeming isn\'t available right now. Please try again later.';

  @override
  String get srAddPhoto => 'Add a photo';

  @override
  String get srSubtitle =>
      'Got a special idea? Tell us about it and we\'ll reach out soon to bring it to life!';

  @override
  String srPhotosHint(int max) {
    return 'Add up to $max photos (optional)';
  }

  @override
  String get srTextRequired => 'Tell us about your idea';

  @override
  String get srSubmitted =>
      'Thanks! We received your request and will reach out soon.';

  @override
  String get srMyRequests => 'My requests';

  @override
  String get srStatusSubmitted => 'Submitted';

  @override
  String get srStatusInReview => 'In review';

  @override
  String get srStatusQuoted => 'Quoted';

  @override
  String get srStatusAccepted => 'Accepted';

  @override
  String get srStatusRejected => 'Rejected';

  @override
  String get srStatusCompleted => 'Completed';

  @override
  String get srTypeSupport => 'Support';

  @override
  String get srNewReply => 'New reply';

  @override
  String get srDetailsTitle => 'Your request';

  @override
  String get srNotFound => 'We couldn\'t find this request';

  @override
  String get srMessages => 'Messages';

  @override
  String get srNoMessages => 'No messages yet — we\'ll reply here.';

  @override
  String get srYou => 'You';

  @override
  String get srReplyHint => 'Write a message';

  @override
  String get srSend => 'Send';

  @override
  String get srClosedNote =>
      'This request is closed. For anything else, send us a new request.';

  @override
  String get srRejectedNote =>
      'Sorry, we can\'t make this one. Feel free to send us another idea.';

  @override
  String get srQuoteTitle => 'Our quote';

  @override
  String get srQuoteDeliveryNote =>
      'The delivery fee is added at the next step.';

  @override
  String get srAcceptQuote => 'Accept quote';

  @override
  String get srViewOrder => 'View order';

  @override
  String get srQuoteUnavailable => 'This quote can no longer be accepted';

  @override
  String get srBackToRequest => 'Back to request';

  @override
  String get srCityNotServed =>
      'We don\'t deliver to this city yet. Choose another address.';

  @override
  String srWalletShort(String balance) {
    return 'Your wallet balance ($balance) doesn\'t cover this order.';
  }

  @override
  String get srQuoteRow => 'Quote';

  @override
  String get srConfirmOrder => 'Confirm order';

  @override
  String get supportSendUsMessage => 'Send us a message';

  @override
  String get supportMessageHint => 'How can we help?';

  @override
  String get supportSend => 'Send';

  @override
  String get supportMessageSent =>
      'Message sent! We\'ll reply in your messages soon.';

  @override
  String get supportViewMessages => 'View your messages';

  @override
  String get supportSendAnother => 'Send another';

  @override
  String get partnerScreenTitle => 'Become a Partner';

  @override
  String get partnerHeroTitle => 'Sell on Golden Gift';

  @override
  String get partnerHeroBody =>
      'Bring your gifts to more people across Iraq and Kurdistan.';

  @override
  String get partnerWhyTitle => 'Why partner with us';

  @override
  String get partnerBenefitReachTitle => 'Reach more customers';

  @override
  String get partnerBenefitReachBody =>
      'Show your products to gift shoppers in every city we serve.';

  @override
  String get partnerBenefitDashboardTitle => 'Your own store dashboard';

  @override
  String get partnerBenefitDashboardBody =>
      'Manage your products and orders in one place.';

  @override
  String get partnerBenefitPersonalTitle => 'Made-to-order gifts';

  @override
  String get partnerBenefitPersonalBody =>
      'Receive customers\' names, photos and messages with every order.';

  @override
  String get partnerFormTitle => 'Apply to sell';

  @override
  String get partnerStoreName => 'Store name';

  @override
  String get partnerStoreNameLength => 'Store name must be 2–60 characters';

  @override
  String get partnerOwnerName => 'Owner name';

  @override
  String get partnerCategory => 'What do you sell?';

  @override
  String get partnerCategoryHint => 'e.g. Engraved wood, flowers, cakes';

  @override
  String get partnerInstagramInvalid => 'Enter a valid Instagram username';

  @override
  String get partnerSamplePhotos => 'Sample product photos';

  @override
  String get partnerSubmit => 'Submit application';

  @override
  String get partnerThanksTitle => 'Thank you for applying!';

  @override
  String get partnerThanksBody =>
      'We received your application and will contact you soon.';

  @override
  String get partnerPendingTitle => 'We\'re reviewing your application';

  @override
  String partnerPendingBody(String store) {
    return 'Thanks for applying to sell $store on Golden Gift. We\'ll contact you soon.';
  }

  @override
  String get partnerYourStore => 'your store';

  @override
  String get partnerActiveTitle => 'Your store is live';

  @override
  String get partnerActiveBody => 'Manage it in the Golden Gift dashboard:';

  @override
  String get partnerOpenDashboard => 'Open dashboard';

  @override
  String get partnerCopyLink => 'Copy link';

  @override
  String get partnerSuspendedTitle => 'Your store is suspended';

  @override
  String get partnerSuspendedBody =>
      'Please contact our support team to resolve this.';

  @override
  String get partnerAlreadyApplied =>
      'You\'ve already applied with this account.';

  @override
  String get partnerInvalid => 'Please check your details and try again.';

  @override
  String get partnerUnavailable =>
      'Applications aren\'t available right now. Please try again later.';

  @override
  String get aiSearchFieldHint =>
      'e.g. My sister\'s graduation, she loves plants';

  @override
  String get aiSearchExamplesTitle => 'Try an example';

  @override
  String get aiSearchOccasion => 'Occasion';

  @override
  String get aiSearchRecipient => 'Who it\'s for';

  @override
  String get aiSearchBudget => 'Budget';

  @override
  String get aiSearchAnyBudget => 'Any budget';

  @override
  String aiSearchUpTo(String amount) {
    return 'Up to $amount';
  }

  @override
  String get aiOccasionBirthday => 'Birthday';

  @override
  String get aiOccasionAnniversary => 'Anniversary';

  @override
  String get aiOccasionGraduation => 'Graduation';

  @override
  String get aiOccasionWedding => 'Wedding';

  @override
  String get aiOccasionNewBaby => 'New baby';

  @override
  String get aiOccasionEid => 'Eid';

  @override
  String get aiOccasionThankYou => 'Thank you';

  @override
  String get aiRecipientMum => 'Mum';

  @override
  String get aiRecipientDad => 'Dad';

  @override
  String get aiRecipientWife => 'Wife';

  @override
  String get aiRecipientHusband => 'Husband';

  @override
  String get aiRecipientSister => 'Sister';

  @override
  String get aiRecipientBrother => 'Brother';

  @override
  String get aiRecipientFriend => 'Friend';

  @override
  String get aiRecipientColleague => 'Colleague';

  @override
  String get aiRecipientChild => 'Child';

  @override
  String get aiSearchFindGifts => 'Find gifts';

  @override
  String get aiSearchQueryRequired =>
      'Tell us who the gift is for or the occasion.';

  @override
  String get aiSearchQueryTooShort =>
      'Add a few more words so we can find the right gifts.';

  @override
  String get aiSearchResultsTitle => 'Gift ideas for you';

  @override
  String get aiSearchFallbackNote =>
      'Showing keyword matches — AI suggestions aren\'t available right now.';

  @override
  String get aiSearchRateLimited =>
      'You\'ve reached today\'s AI searches. Showing keyword matches instead.';

  @override
  String get aiSearchNoResultsTitle => 'No gift ideas found';

  @override
  String get aiSearchNoResultsBody =>
      'Try describing them in other words, or choose a bigger budget.';

  @override
  String get secretSantaIntro =>
      'Draw names with family, friends or colleagues — everyone only sees who they\'re buying for.';

  @override
  String get secretSantaCreateGroup => 'Create group';

  @override
  String get secretSantaJoinWithCode => 'Join with a code';

  @override
  String get secretSantaCodeHint => '8-character invite code';

  @override
  String get secretSantaJoin => 'Join';

  @override
  String get secretSantaInvalidCode =>
      'Enter the 8-character code from your invite.';

  @override
  String get secretSantaNoGroupsTitle => 'No groups yet';

  @override
  String get secretSantaNoGroupsBody =>
      'Create a group, or join one with the invite code you received.';

  @override
  String get secretSantaTypeFamily => 'Family';

  @override
  String get secretSantaTypeFriends => 'Friends';

  @override
  String get secretSantaTypeWork => 'Work';

  @override
  String get secretSantaStatusOpen => 'Open';

  @override
  String get secretSantaStatusDrawn => 'Drawn';

  @override
  String get secretSantaStatusClosed => 'Closed';

  @override
  String get secretSantaOrganiserBadge => 'You\'re the organiser';

  @override
  String get secretSantaOrganiser => 'Organiser';

  @override
  String secretSantaMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String secretSantaMembersOf(int count, int max) {
    return 'Members ($count/$max)';
  }

  @override
  String secretSantaBudgetValue(String amount) {
    return '$amount per gift';
  }

  @override
  String get secretSantaNoBudget => 'No budget';

  @override
  String secretSantaExchangeOn(String date) {
    return 'Exchange on $date';
  }

  @override
  String get secretSantaGroupName => 'Group name';

  @override
  String get secretSantaGroupNameHint => 'e.g. Office 2026';

  @override
  String get secretSantaType => 'Group type';

  @override
  String get secretSantaBudget => 'Budget per gift';

  @override
  String get secretSantaCustomBudget => 'Custom';

  @override
  String get secretSantaCustomBudgetHint => 'Amount in IQD';

  @override
  String get secretSantaBudgetError => 'Enter an amount.';

  @override
  String get secretSantaExchangeDate => 'Exchange date';

  @override
  String get secretSantaDateError => 'Choose a date from tomorrow on.';

  @override
  String get secretSantaInviteTitle => 'Invite your group';

  @override
  String get secretSantaInviteBody =>
      'Share the link or the code — members join in the Golden Gift app.';

  @override
  String get secretSantaCopyCode => 'Copy code';

  @override
  String get secretSantaShareLink => 'Share link';

  @override
  String secretSantaShareText(String name, String link, String code) {
    return 'Join my Secret Santa group “$name” on Golden Gift! Open $link or enter the code $code.';
  }

  @override
  String get secretSantaShareSubject => 'Secret Santa on Golden Gift';

  @override
  String get secretSantaMembers => 'Members';

  @override
  String get secretSantaYou => 'You';

  @override
  String get secretSantaMyWishNote => 'My wish note';

  @override
  String get secretSantaWishNoteHint =>
      'What would you love to get? Your Secret Santa will see this.';

  @override
  String get secretSantaWishNoteEmpty =>
      'Add a note so your Secret Santa knows what you\'d love.';

  @override
  String get secretSantaAddNote => 'Add a note';

  @override
  String get secretSantaWishNoteSaved => 'Wish note saved';

  @override
  String get secretSantaDraw => 'Draw names';

  @override
  String secretSantaDrawHint(int min) {
    return 'At least $min members are needed to draw names.';
  }

  @override
  String get secretSantaDrawConfirmTitle => 'Draw names now?';

  @override
  String get secretSantaDrawConfirmBody =>
      'Everyone will see who they\'re buying for, and no one can join after the draw.';

  @override
  String get secretSantaDrawDone =>
      'Names drawn! Everyone can now see who they\'re buying for.';

  @override
  String secretSantaBuyingFor(String name) {
    return 'You\'re buying for $name';
  }

  @override
  String get secretSantaOnlyYou => 'Shh — only you can see this.';

  @override
  String get secretSantaTheirWish => 'Their wish note';

  @override
  String get secretSantaNoWishNote => 'They haven\'t added a wish note yet.';

  @override
  String get secretSantaShopForThem => 'Shop for them';

  @override
  String get secretSantaDrawPending =>
      'Names have been drawn — your match will appear in a moment.';

  @override
  String get secretSantaWaitingForDraw =>
      'Waiting for the organiser to draw names.';

  @override
  String get secretSantaNotMember => 'This group isn\'t available to you.';

  @override
  String get secretSantaJoinTitle => 'Join Secret Santa';

  @override
  String secretSantaJoinBody(String code) {
    return 'You\'ve been invited with the code $code. Add your name so the group knows who you are.';
  }

  @override
  String get secretSantaJoinGroup => 'Join group';

  @override
  String get secretSantaJoined => 'You\'re in! Welcome to the group.';

  @override
  String get secretSantaErrorNotFound =>
      'We couldn\'t find a group with that code.';

  @override
  String get secretSantaErrorAlreadyDrawn =>
      'Names have already been drawn in this group.';

  @override
  String get secretSantaErrorFull => 'This group is full.';

  @override
  String get secretSantaErrorImpossible =>
      'No valid draw is possible with the current exclusions.';

  @override
  String get secretSantaErrorNotOrganiser =>
      'Only the organiser can draw names.';

  @override
  String get secretSantaErrorUnavailable =>
      'Secret Santa isn\'t available right now. Please try again later.';

  @override
  String get reviewsTitle => 'Reviews';

  @override
  String reviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews',
      one: '1 review',
      zero: 'No reviews yet',
    );
    return '$_temp0';
  }

  @override
  String get reviewsSeeAll => 'See all';

  @override
  String reviewStarsLabel(String rating) {
    return 'Rated $rating out of 5';
  }

  @override
  String reviewStarButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get reviewRate => 'Rate';

  @override
  String get reviewFormTitle => 'Rate this gift';

  @override
  String get reviewYourRating => 'Your rating';

  @override
  String get reviewRatingRequired => 'Choose a star rating.';

  @override
  String get reviewTextLabel => 'Your review';

  @override
  String get reviewTextHint => 'What did you love about it?';

  @override
  String reviewAddPhotos(int max) {
    return 'Photos (up to $max)';
  }

  @override
  String get reviewAddPhoto => 'Add photo';

  @override
  String get reviewSubmit => 'Submit review';

  @override
  String get reviewThanks => 'Thanks! Your review will appear after approval.';

  @override
  String get reviewPending => 'Your review is pending approval';

  @override
  String get reviewReviewed => 'Reviewed';

  @override
  String get reviewEdit => 'Edit review';

  @override
  String get reviewEditWarning =>
      'Editing your review sends it back for approval before it\'s shown again.';

  @override
  String get reviewAnonymous => 'Customer';

  @override
  String get addressPinOnMap => 'Pin on map';

  @override
  String get addressPinOnMapHint => 'Optional — helps the driver find the door';

  @override
  String get addressLocationPinned => 'Location pinned';

  @override
  String get addressChangePin => 'Change';

  @override
  String get addressUseThisLocation => 'Use this location';

  @override
  String get addressMapTitle => 'Pin your location';

  @override
  String get addressMapHelp => 'Move the map until the pin sits on your door.';

  @override
  String get wishlistDefaultList => 'Favourites';

  @override
  String get wishlistNewList => 'New list';

  @override
  String get wishlistListName => 'List name';

  @override
  String get wishlistListNameHint => 'e.g. Mum\'s birthday';

  @override
  String get wishlistCreateList => 'Create list';

  @override
  String get wishlistRenameList => 'Rename list';

  @override
  String get wishlistDeleteList => 'Delete list';

  @override
  String wishlistDeleteListConfirm(String name, String defaultName) {
    return 'Delete “$name”? Its gifts move to $defaultName.';
  }

  @override
  String get wishlistListOptions => 'List options';

  @override
  String get wishlistMoveTo => 'Move to…';

  @override
  String get wishlistSaveTo => 'Save to…';

  @override
  String wishlistSavedTo(String name) {
    return 'Saved to $name';
  }

  @override
  String wishlistMovedTo(String name) {
    return 'Moved to $name';
  }

  @override
  String get wishlistListEmptyTitle => 'This list is empty';

  @override
  String get wishlistListEmptyBody =>
      'Long-press the heart on any gift to save it to a list.';

  @override
  String get wishlistChooseList => 'Choose a list';

  @override
  String orderRefundedToWallet(String amount) {
    return 'Refunded to your wallet: $amount';
  }

  @override
  String get orderChangedByStore => 'By the store';

  @override
  String get orderChangedByYou => 'By you';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String bannerSemanticLabel(int index, int count) {
    return 'Offer $index of $count';
  }

  @override
  String get categorySoonBadge => 'Soon';

  @override
  String categoryComingSoonLabel(String category) {
    return '$category, coming soon';
  }

  @override
  String get comingSoonTagline => 'Curated with care. Arriving soon.';

  @override
  String comingSoonMessage(String category) {
    return 'We\'re crafting something special for $category. Our team is working on it — in the meantime, discover beautiful gifts in our other categories.';
  }

  @override
  String get comingSoonExploreOthers => 'Explore other categories';

  @override
  String get comingSoonGiftsYouMightLove => 'Gifts you might love';

  @override
  String get comingSoonExploreAll => 'Explore all categories';

  @override
  String get comingSoonBackHome => 'Back to home';

  @override
  String get comingSoonShowAllGifts => 'Show all gifts';

  @override
  String get giftForTitle => 'Gift for';

  @override
  String get giftForEveryone => 'Everyone';

  @override
  String get giftForMen => 'For him';

  @override
  String get giftForWomen => 'For her';

  @override
  String get giftForCompanies => 'For companies';

  @override
  String get giftForMenTagline => 'Gifts he\'ll love';

  @override
  String get giftForWomenTagline => 'Gifts she\'ll love';

  @override
  String get giftForCompaniesTagline => 'Corporate & team gifts';

  @override
  String get shopForTitle => 'Shop for';

  @override
  String get reels => 'Reels';

  @override
  String get reelsFilterTitle => 'Filter reels';

  @override
  String get reelsCategory => 'Category';

  @override
  String get reelsShowResults => 'Show reels';

  @override
  String get reelsShopNow => 'Shop now';

  @override
  String get reelsEmptyTitle => 'No reels yet';

  @override
  String get reelsEmptyBody => 'Fresh gift videos are on their way.';

  @override
  String get reelsNoMatchTitle => 'No reels match these filters';

  @override
  String get reelsNoMatchBody => 'Try another category, price or gift type.';

  @override
  String get reelsClearFilters => 'Clear filters';

  @override
  String get reelsSoundOn => 'Turn sound on';

  @override
  String get reelsSoundOff => 'Turn sound off';

  @override
  String get reelsPlay => 'Play';

  @override
  String get reelsPause => 'Pause';

  @override
  String get reelsVideoError => 'This video can\'t be played';

  @override
  String get reelsRemoveFilter => 'Remove filter';

  @override
  String get reelsMore => 'more';

  @override
  String reelsViewProduct(String product) {
    return 'View $product';
  }
}
