// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'غولدن غيفت';

  @override
  String get appTagline => 'هدايا مخصّصة، مصنوعة خصيصًا لهم';

  @override
  String get loading => 'جارٍ التحميل...';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get ok => 'حسنًا';

  @override
  String get done => 'تم';

  @override
  String get next => 'التالي';

  @override
  String get back => 'رجوع';

  @override
  String get skip => 'تخطي';

  @override
  String get search => 'بحث';

  @override
  String get viewAll => 'عرض الكل';

  @override
  String get noResults => 'لا توجد نتائج';

  @override
  String get somethingWentWrong => 'حدث خطأ ما';

  @override
  String get confirm => 'تأكيد';

  @override
  String get edit => 'تعديل';

  @override
  String get close => 'إغلاق';

  @override
  String get apply => 'تطبيق';

  @override
  String get home => 'الرئيسية';

  @override
  String get cart => 'السلة';

  @override
  String get profile => 'حسابي';

  @override
  String get createYourAccount => 'أنشئ حسابك';

  @override
  String get registerSubtitle =>
      'سجّل الآن وابدأ بتصميم هدايا مخصّصة خلال دقائق!';

  @override
  String get signUp => 'إنشاء حساب';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get yourName => 'اسمك';

  @override
  String get enterYourName => 'أدخل اسمك';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get enterYourEmail => 'أدخل بريدك الإلكتروني';

  @override
  String get mobileNumber => 'رقم الهاتف';

  @override
  String get enterYourNumber => 'أدخل رقمك';

  @override
  String get haveReferralCode => 'لديك رمز إحالة؟';

  @override
  String get alreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get or => 'أو';

  @override
  String get continueAsGuest => 'المتابعة كضيف';

  @override
  String get goodMorning => 'صباح الخير';

  @override
  String get goodAfternoon => 'نهارك سعيد';

  @override
  String get goodEvening => 'مساء الخير';

  @override
  String get aiGiftSearch => 'البحث الذكي عن الهدايا';

  @override
  String get aiGiftSearchHint => 'صِف لمن الهدية أو ما هي المناسبة';

  @override
  String get popular => 'الأكثر طلبًا';

  @override
  String get featured => 'مميّز';

  @override
  String get forYou => 'لك';

  @override
  String get giftCards => 'بطاقات الهدايا';

  @override
  String get discover => 'اكتشف';

  @override
  String get all => 'الكل';

  @override
  String get more => 'المزيد';

  @override
  String get myCart => 'سلتي';

  @override
  String get emptyCartTitle => 'سلة غولدن غيفت تشعر بالوحدة!';

  @override
  String get emptyCartSubtitle =>
      'لنملأها بلمسات مخصّصة ساحرة. ابدأ بتصميم هداياك المثالية الآن!';

  @override
  String get startShopping => 'ابدأ التسوق';

  @override
  String get products => 'المنتجات';

  @override
  String get searchForProduct => 'ابحث عن منتج';

  @override
  String get allCategories => 'جميع الفئات';

  @override
  String get searchForCategory => 'ابحث عن فئة';

  @override
  String get productDetails => 'تفاصيل المنتج';

  @override
  String get aboutTheProduct => 'عن المنتج';

  @override
  String get addToCart => 'أضف إلى السلة';

  @override
  String get share => 'مشاركة';

  @override
  String preparationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'يحتاج هذا المنتج إلى $days يومًا للتحضير',
      few: 'يحتاج هذا المنتج إلى $days أيام للتحضير',
      two: 'يحتاج هذا المنتج إلى يومين للتحضير',
      one: 'يحتاج هذا المنتج إلى يوم واحد للتحضير',
    );
    return '$_temp0';
  }

  @override
  String get sameDayShipping => 'يمكن شحن هذا المنتج في اليوم نفسه';

  @override
  String availableOnlyIn(String cities) {
    return 'متوفر فقط في: $cities';
  }

  @override
  String get uploadYourPhotos => 'ارفع صورك';

  @override
  String get customizeTextHint => 'أدخل النص الذي تريد إضافته على منتجك';

  @override
  String get selectADate => 'اختر تاريخًا';

  @override
  String get notes => 'ملاحظات';

  @override
  String get account => 'الحساب';

  @override
  String get orders => 'الطلبات';

  @override
  String get myWishlists => 'المفضلة';

  @override
  String get wishlistSubtitle => 'الهدايا التي حفظتها';

  @override
  String get secretSanta => 'سانتا السري';

  @override
  String get secretSantaSubtitle =>
      'تبادل الهدايا مع العائلة والأصدقاء وزملاء العمل';

  @override
  String get savedCards => 'البطاقات المحفوظة';

  @override
  String get myWallet => 'محفظتي';

  @override
  String get inviteAndEarn => 'ادعُ واربح';

  @override
  String get specialRequests => 'الطلبات الخاصة';

  @override
  String get savedAddresses => 'العناوين المحفوظة';

  @override
  String get myGiftCards => 'بطاقات هداياي';

  @override
  String get promoCodes => 'رموز الخصم';

  @override
  String get contactUs => 'تواصل معنا';

  @override
  String get availableBalance => 'الرصيد المتاح';

  @override
  String get noTransactionsYet => 'لا توجد معاملات بعد';

  @override
  String get transactionHistoryHint => 'سيظهر سجل معاملاتك هنا';

  @override
  String get creditsBalance => 'رصيد مكافآت غولدن غيفت';

  @override
  String get successfulReferrals => 'الإحالات الناجحة';

  @override
  String get pendingReferrals => 'الإحالات المعلّقة';

  @override
  String get yourReferralCode => 'رمز الإحالة الخاص بك';

  @override
  String get inviteFriends => 'ادعُ أصدقاءك';

  @override
  String get walletTransactions => 'المعاملات';

  @override
  String get walletBalance => 'الرصيد';

  @override
  String get walletCredits => 'المكافآت';

  @override
  String get walletSignInBody => 'سجّل الدخول لرؤية رصيدك ومكافآتك ومعاملاتك.';

  @override
  String get txnTopUp => 'شحن الرصيد';

  @override
  String get txnOrderPayment => 'دفع طلب';

  @override
  String get txnRefund => 'استرداد';

  @override
  String get txnReferralCredit => 'مكافأة إحالة';

  @override
  String get txnGiftCardRedeem => 'استبدال بطاقة هدية';

  @override
  String get txnAdminAdjustment => 'تعديل الرصيد';

  @override
  String get txnCreditExpiry => 'انتهت صلاحية رصيد المكافآت';

  @override
  String creditsExpiryNote(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'تنتهي صلاحية المكافآت بعد $days يومًا من استلامها.',
      few: 'تنتهي صلاحية المكافآت بعد $days أيام من استلامها.',
      two: 'تنتهي صلاحية المكافآت بعد يومين من استلامها.',
      one: 'تنتهي صلاحية المكافآت بعد يوم واحد من استلامها.',
    );
    return '$_temp0';
  }

  @override
  String get promoHeaderTitle => 'تحب العروض الرائعة؟ ونحن أيضًا! 🎉';

  @override
  String promoPercentOff(int percent) {
    return 'خصم $percent%';
  }

  @override
  String promoAmountOff(String amount) {
    return 'خصم $amount';
  }

  @override
  String get promoCopyCode => 'نسخ الرمز';

  @override
  String get codeCopied => 'تم النسخ';

  @override
  String promoMinOrder(String amount) {
    return 'الحد الأدنى للطلب $amount';
  }

  @override
  String promoMaxDiscount(String amount) {
    return 'أقصى خصم $amount';
  }

  @override
  String get promoFirstOrderOnly => 'للطلب الأول فقط';

  @override
  String get promoUse => 'استخدم';

  @override
  String get promoAppliedLabel => 'مُطبّق';

  @override
  String promoAppliedSnack(String code) {
    return 'تم تطبيق $code على سلتك';
  }

  @override
  String get noPromoCodesTitle => 'لا توجد رموز خصم حاليًا';

  @override
  String get noPromoCodesBody => 'ستظهر العروض الجديدة هنا — عُد قريبًا.';

  @override
  String get promoCodeHint => 'رمز الخصم';

  @override
  String get promoNotFound => 'هذا الرمز غير موجود';

  @override
  String get promoInactive => 'هذا الرمز لم يعد فعّالًا';

  @override
  String get promoExpired => 'انتهت صلاحية هذا الرمز';

  @override
  String promoMinOrderNotMet(String amount) {
    return 'الحد الأدنى للطلب لهذا الرمز هو $amount';
  }

  @override
  String get promoUsageLimit => 'وصل هذا الرمز إلى الحد الأقصى للاستخدام';

  @override
  String get promoPerUserLimit => 'لقد استخدمت هذا الرمز من قبل';

  @override
  String get promoFirstOrderOnlyError => 'هذا الرمز لطلبك الأول فقط';

  @override
  String get promoNotApplicable => 'غير صالح للمنتجات الموجودة في سلتك';

  @override
  String promoDiscountRow(String code) {
    return 'خصم ($code)';
  }

  @override
  String promoSaved(String amount) {
    return 'وفّرت $amount';
  }

  @override
  String useMyCredits(String amount) {
    return 'استخدم مكافآتي ($amount متاحة)';
  }

  @override
  String get inviteFriendsBody =>
      'ادعُ أصدقاءك ودعهم يصنعون هدايا ومنتجات فريدة على طريقتهم. 🎁✨';

  @override
  String get successfulReferralsHint => 'أصدقاء سجّلوا وأتمّوا طلبًا مدفوعًا';

  @override
  String get pendingReferralsHint =>
      'أصدقاء سجّلوا — تحصل على المكافأة عندما يطلبون';

  @override
  String referralBothGet(String amount) {
    return 'شاركه مع أصدقائك — ستحصلان كلاكما على $amount';
  }

  @override
  String referralEachGets(String friend, String you) {
    return 'شاركه مع أصدقائك — يحصلون على $friend وتحصل على $you';
  }

  @override
  String referralYouGet(String you) {
    return 'شاركه مع أصدقائك — تحصل على $you بعد أول طلب مدفوع لهم';
  }

  @override
  String referralFriendGets(String friend) {
    return 'شاركه مع أصدقائك — يحصلون على $friend عند التسجيل';
  }

  @override
  String get learnMoreReferrals => 'اعرف المزيد عن الإحالات';

  @override
  String get copyReferralCode => 'نسخ رمز الإحالة';

  @override
  String referralShareText(String amount, String code, String link) {
    return 'انضم إليّ في غولدن غيفت للهدايا المخصصة! سجّل برمزي $code واحصل على $amount مكافآت: $link';
  }

  @override
  String referralShareTextNoBonus(String code, String link) {
    return 'انضم إليّ في غولدن غيفت للهدايا المخصصة! سجّل برمزي $code: $link';
  }

  @override
  String get referralShareSubject => 'انضم إليّ في غولدن غيفت';

  @override
  String get referralRulesTitle => 'كيف تعمل الإحالات';

  @override
  String referralRuleJoin(String amount) {
    return 'يسجّل صديقك برمزك ويحصل على $amount مكافآت.';
  }

  @override
  String referralRuleOrder(String amount) {
    return 'تحصل على $amount مكافآت عندما يتم توصيل أول طلب له ودفع ثمنه.';
  }

  @override
  String referralRuleMonthlyCap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يمكنك الحصول على مكافأة عن $count صديقًا كحد أقصى شهريًا.',
      few: 'يمكنك الحصول على مكافأة عن $count أصدقاء كحد أقصى شهريًا.',
      two: 'يمكنك الحصول على مكافأة عن صديقين كحد أقصى شهريًا.',
      one: 'يمكنك الحصول على مكافأة عن صديق واحد شهريًا.',
    );
    return '$_temp0';
  }

  @override
  String get referralRuleSpend =>
      'يمكن استخدام المكافآت في أي طلب داخل التطبيق، ولا يمكن سحبها نقدًا.';

  @override
  String get referralRuleFairUse =>
      'لا تُمنح مكافآت عند إحالة نفسك أو حساب آخر على الجهاز نفسه.';

  @override
  String get referralInvitesTitle => 'دعواتك';

  @override
  String get referralStatusPending => 'قيد الانتظار';

  @override
  String get referralStatusCompleted => 'تمت المكافأة';

  @override
  String get referralStatusCancelled => 'ملغاة';

  @override
  String get referralAFriend => 'صديق';

  @override
  String get inviteSignInBody =>
      'سجّل الدخول للحصول على رمز الإحالة ودعوة أصدقائك.';

  @override
  String get referralRewardsChip => 'مكافآت الإحالة';

  @override
  String get referralSheetTitle => 'ادعُ أصدقاءك واربح مكافآت';

  @override
  String get referralSheetBody =>
      'شارك رابطك الشخصي مرة واحدة واحصل على مكافأة عندما يكتشف أصدقاؤك غولدن غيفت.';

  @override
  String get referralFriendJoins => 'انضمام صديق';

  @override
  String get referralFirstPaidOrder => 'أول طلب مدفوع';

  @override
  String get referralShareLinkTitle => 'شارك رابط الدعوة';

  @override
  String get referralShareLinkBody =>
      'افتح مكافآتي في أي وقت لنسخه أو مشاركته.';

  @override
  String get referralWatchCreditsTitle => 'شاهد مكافآتك تتراكم';

  @override
  String referralWatchBoth(String friend, String you) {
    return 'يحصلون على $friend عند التسجيل، وتربح $you بعد أول طلب مدفوع لهم.';
  }

  @override
  String referralWatchYou(String you) {
    return 'تربح $you بعد أول طلب مدفوع لهم.';
  }

  @override
  String referralWatchFriend(String friend) {
    return 'يحصلون على $friend عند التسجيل.';
  }

  @override
  String get referralMyRewards => 'مكافآتي';

  @override
  String get referralInvite => 'دعوة';

  @override
  String get referralMaybeLater => 'ربما لاحقًا';

  @override
  String get referralLinkSignedIn =>
      'رموز الإحالة مخصصة للحسابات الجديدة. ادعُ أصدقاءك من صفحة ادعُ واربح.';

  @override
  String get submitYourRequest => 'أرسل طلبك';

  @override
  String get writeYourIdeaHere => 'اكتب فكرتك هنا';

  @override
  String expiresOn(String date) {
    return 'ينتهي في: $date';
  }

  @override
  String get outOfStock => 'نفدت الكمية';

  @override
  String get filter => 'تصفية';

  @override
  String get clear => 'مسح';

  @override
  String get addToWishlist => 'أضف إلى المفضلة';

  @override
  String get removeFromWishlist => 'إزالة من المفضلة';

  @override
  String originalPrice(String price) {
    return 'السعر الأصلي $price';
  }

  @override
  String percentOff(int percent) {
    return 'خصم $percent%';
  }

  @override
  String get onboardingTitle1 => 'خصّص كل هدية';

  @override
  String get onboardingBody1 =>
      'أضف الأسماء والصور والألوان والرسائل لتصبح الهدية لهم حقًا.';

  @override
  String get onboardingTitle2 => 'توصيل بعناية';

  @override
  String get onboardingBody2 =>
      'توصيل في جميع أنحاء العراق وإقليم كوردستان — مغلّفة وجاهزة للإهداء.';

  @override
  String get onboardingTitle3 => 'اربح رصيدًا';

  @override
  String get onboardingBody3 =>
      'ادعُ أصدقاءك واجمع رصيد غولدن غيفت عندما يطلبون.';

  @override
  String get getStarted => 'ابدأ الآن';

  @override
  String get signInTitle => 'مرحبًا بعودتك';

  @override
  String get signInSubtitle => 'سجّل الدخول برقم هاتفك للمتابعة.';

  @override
  String get dontHaveAccount => 'ليس لديك حساب؟';

  @override
  String get referralCodeLabel => 'رمز الإحالة';

  @override
  String get referralCodeHint => 'رمز من 6 أحرف';

  @override
  String get continueWithGoogle => 'المتابعة باستخدام Google';

  @override
  String get continueWithApple => 'المتابعة باستخدام Apple';

  @override
  String get selectCountry => 'اختر الدولة';

  @override
  String get termsAgreement =>
      'بالمتابعة فإنك توافق على شروط الخدمة وسياسة الخصوصية.';

  @override
  String get completeProfileTitle => 'أكمل حسابك';

  @override
  String get completeProfileSubtitle => 'أخبرنا قليلًا عنك لإكمال التسجيل.';

  @override
  String get phoneLaterNote =>
      'يمكنك إضافة رقم هاتفك لاحقًا — وهو مطلوب قبل الدفع.';

  @override
  String get otpTitle => 'تحقّق من رقمك';

  @override
  String otpSubtitle(String phone) {
    return 'أدخل الرمز المكوّن من 6 أرقام الذي أرسلناه إلى $phone';
  }

  @override
  String otpResendIn(int seconds) {
    return 'إعادة إرسال الرمز خلال $seconds ث';
  }

  @override
  String get otpResend => 'إعادة إرسال الرمز';

  @override
  String get otpVerify => 'تحقّق';

  @override
  String get otpCodeSent => 'تم إرسال الرمز';

  @override
  String get changeNumber => 'تغيير الرقم';

  @override
  String get errorRequired => 'هذا الحقل مطلوب';

  @override
  String get errorNameLength => 'يجب أن يتكوّن الاسم من 2 إلى 50 حرفًا';

  @override
  String get errorInvalidEmail => 'أدخل بريدًا إلكترونيًا صحيحًا';

  @override
  String get errorInvalidPhone => 'أدخل رقم هاتف صحيحًا';

  @override
  String get errorInvalidReferralCode =>
      'يتكوّن رمز الإحالة من 6 أحرف أو أرقام';

  @override
  String get authErrorInvalidCode =>
      'الرمز غير صحيح. تحقّق منه وحاول مرة أخرى.';

  @override
  String get authErrorCodeExpired => 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.';

  @override
  String get authErrorTooManyRequests =>
      'محاولات كثيرة جدًا. يرجى المحاولة لاحقًا.';

  @override
  String get authErrorNetwork =>
      'لا يوجد اتصال بالإنترنت. تحقّق من اتصالك وحاول مرة أخرى.';

  @override
  String get authErrorPhoneInUse => 'هذا الرقم مرتبط بحساب آخر.';

  @override
  String get authErrorUnavailable => 'خيار تسجيل الدخول هذا غير متاح بعد.';

  @override
  String get authErrorAccountDisabled =>
      'تم تعطيل هذا الحساب. تواصل معنا للمساعدة.';

  @override
  String get signInToContinue => 'سجّل الدخول للمتابعة';

  @override
  String get signInToContinueBody =>
      'أنشئ حسابًا أو سجّل الدخول لحفظ الهدايا وإتمام الطلب وتتبّع طلباتك.';

  @override
  String get maintenanceTitle => 'سنعود قريبًا';

  @override
  String get maintenanceBody =>
      'يخضع غولدن غيفت لتحديث بسيط. يرجى العودة قريبًا.';

  @override
  String get updateRequiredTitle => 'التحديث مطلوب';

  @override
  String get updateRequiredBody =>
      'يتوفّر إصدار جديد من غولدن غيفت. يرجى التحديث للمتابعة.';

  @override
  String get updateNow => 'حدّث الآن';

  @override
  String get guest => 'ضيف';

  @override
  String get guestProfileTitle => 'أنت تتصفّح كضيف';

  @override
  String get guestProfileBody =>
      'سجّل الدخول لرؤية طلباتك ومحفظتك والهدايا المحفوظة.';

  @override
  String inviteAndEarnSubtitle(String amount) {
    return 'اربح $amount عن كل صديق';
  }

  @override
  String get language => 'اللغة';

  @override
  String get chooseLanguage => 'اختر اللغة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get logoutConfirm => 'هل تريد تسجيل الخروج من غولدن غيفت؟';

  @override
  String get addPhoneNumber => 'أضف رقم الهاتف';

  @override
  String get editProfile => 'تعديل الملف الشخصي';

  @override
  String get changePhoto => 'تغيير الصورة';

  @override
  String get birthday => 'تاريخ الميلاد';

  @override
  String get selectBirthday => 'اختر تاريخ ميلادك';

  @override
  String get gender => 'الجنس';

  @override
  String get genderMale => 'ذكر';

  @override
  String get genderFemale => 'أنثى';

  @override
  String get genderPreferNot => 'أفضّل عدم الذكر';

  @override
  String get city => 'المدينة';

  @override
  String get selectCity => 'اختر مدينتك';

  @override
  String get changePhone => 'تغيير';

  @override
  String get profileSaved => 'تم حفظ الملف الشخصي';

  @override
  String get phoneUpdated => 'تم تحديث رقم الهاتف';

  @override
  String get changePhoneTitle => 'تغيير رقم الهاتف';

  @override
  String get changePhoneSubtitle => 'سنرسل رمز تحقّق إلى رقمك الجديد.';

  @override
  String get sendCode => 'إرسال الرمز';

  @override
  String get phoneChangeMobileOnly => 'تغيير الرقم متاح في تطبيق الهاتف.';

  @override
  String get photoUploadFailed => 'تعذّر رفع الصورة. يرجى المحاولة مرة أخرى.';

  @override
  String get unsavedChanges => 'هل تريد تجاهل التغييرات؟';

  @override
  String get discard => 'تجاهل';

  @override
  String get notificationsSetting => 'الإشعارات';

  @override
  String get notificationsSettingSubtitle => 'تحديثات الطلبات والعروض';

  @override
  String get appearance => 'المظهر';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get termsOfService => 'شروط الخدمة';

  @override
  String appVersion(String version) {
    return 'الإصدار $version';
  }

  @override
  String get deleteAccount => 'حذف الحساب';

  @override
  String get deleteAccountTitle => 'هل تريد حذف حسابك؟';

  @override
  String get deleteAccountBody =>
      'سيتم حذف ملفك الشخصي وعناوينك وسلتك والمفضلة. نحتفظ بالطلبات السابقة في سجلاتنا. لا يمكن التراجع عن ذلك.';

  @override
  String get deleteAccountConfirm => 'احذف حسابي';

  @override
  String get accountDeleted => 'تم حذف حسابك.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageKurdish => 'کوردی';

  @override
  String get takePhoto => 'التقاط صورة';

  @override
  String get chooseFromGallery => 'اختيار من المعرض';

  @override
  String get authErrorDeliveryFailed =>
      'تعذّر إرسال الرمز. تحقّق من الرقم ومن اتصالك ثم حاول مرة أخرى.';

  @override
  String get profileCompletionTitle =>
      'أكمل ملفك الشخصي للحصول على اقتراحات أفضل';

  @override
  String get goToProfile => 'الذهاب إلى الملف الشخصي';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get filters => 'عوامل التصفية';

  @override
  String get sortBy => 'الترتيب حسب';

  @override
  String get sortRelevance => 'الأكثر تطابقًا';

  @override
  String get sortNewest => 'الأحدث';

  @override
  String get sortPopular => 'الأكثر شيوعًا';

  @override
  String get sortPriceLowHigh => 'السعر: من الأقل إلى الأعلى';

  @override
  String get sortPriceHighLow => 'السعر: من الأعلى إلى الأقل';

  @override
  String get price => 'السعر';

  @override
  String priceUnder(String amount) {
    return 'أقل من $amount';
  }

  @override
  String priceBetween(String min, String max) {
    return '$min – $max';
  }

  @override
  String priceAndAbove(String amount) {
    return '$amount فأكثر';
  }

  @override
  String get availability => 'التوفّر';

  @override
  String get sameDayOnly => 'يُشحن في نفس اليوم';

  @override
  String get onSaleOnly => 'عليه خصم';

  @override
  String get deliverTo => 'التوصيل إلى';

  @override
  String get anyCity => 'أي مدينة';

  @override
  String get resetFilters => 'إعادة تعيين';

  @override
  String get showResults => 'عرض النتائج';

  @override
  String get offlineChip => 'غير متصل — نعرض العناصر المحفوظة';

  @override
  String get noProductsTitle => 'لم نجد هدايا';

  @override
  String get noProductsBody => 'جرّب بحثًا آخر أو أزل بعض عوامل التصفية.';

  @override
  String get searchFallbackNote =>
      'البحث محدود حاليًا — نعرض النتائج من جميع الفئات والمدن.';

  @override
  String get noCategoriesMatch => 'لا توجد فئات مطابقة لبحثك';

  @override
  String get loadMoreFailed => 'تعذّر تحميل المزيد من الهدايا.';

  @override
  String get readMore => 'اقرأ المزيد';

  @override
  String get readLess => 'عرض أقل';

  @override
  String get optionalLabel => '(اختياري)';

  @override
  String get optionRequiredError => 'يرجى اختيار خيار';

  @override
  String get textRequiredError => 'يرجى إدخال النص';

  @override
  String get dateRequiredError => 'يرجى اختيار تاريخ';

  @override
  String textTooLongError(int max) {
    return 'لا تتجاوز $max حرفًا';
  }

  @override
  String photosRequiredError(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: 'أضف $min صورة على الأقل',
      few: 'أضف $min صور على الأقل',
      two: 'أضف صورتين على الأقل',
      one: 'أضف صورة',
    );
    return '$_temp0';
  }

  @override
  String get optionUnavailableError => 'هذا الخيار نفد — اختر خيارًا آخر';

  @override
  String get addedToCart => 'تمت الإضافة إلى السلة';

  @override
  String get viewCart => 'عرض السلة';

  @override
  String uploadingPhotos(int percent) {
    return 'جارٍ رفع الصور… $percent%';
  }

  @override
  String get photoTooLarge => 'هذه الصورة أكبر من 10 ميغابايت';

  @override
  String get removePhoto => 'إزالة الصورة';

  @override
  String photoSlot(int n) {
    return 'الصورة $n';
  }

  @override
  String get quantity => 'الكمية';

  @override
  String get productNotFound => 'هذه الهدية لم تعد متوفرة';

  @override
  String get subtotal => 'المجموع الفرعي';

  @override
  String get deliveryFee => 'التوصيل';

  @override
  String get deliveryCalculatedAtCheckout => 'يُحسب عند الدفع';

  @override
  String get total => 'الإجمالي';

  @override
  String get checkout => 'إتمام الطلب';

  @override
  String get remove => 'إزالة';

  @override
  String get itemUnavailable => 'لم يعد متوفرًا — غير محتسب في الإجمالي';

  @override
  String priceChangedNote(String price) {
    return 'تم تحديث السعر إلى $price';
  }

  @override
  String soldBy(String store) {
    return 'يبيعه $store';
  }

  @override
  String photosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة',
      few: '$count صور',
      two: 'صورتان',
      one: 'صورة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get wishlistEmptyTitle => 'لا توجد هدايا محفوظة بعد';

  @override
  String get wishlistEmptyBody => 'اضغط على القلب في أي هدية لحفظها هنا.';

  @override
  String get increaseQuantity => 'زيادة الكمية';

  @override
  String get decreaseQuantity => 'تقليل الكمية';

  @override
  String get addAddress => 'إضافة عنوان';

  @override
  String get editAddress => 'تعديل العنوان';

  @override
  String get addressLabel => 'اسم العنوان (مثل المنزل، العمل)';

  @override
  String get recipientName => 'اسم المستلم';

  @override
  String get area => 'المنطقة / الحي';

  @override
  String get street => 'الشارع';

  @override
  String get building => 'المبنى';

  @override
  String get floor => 'الطابق / الشقة';

  @override
  String get addressNotes => 'إرشادات لمندوب التوصيل';

  @override
  String get defaultAddress => 'افتراضي';

  @override
  String get setAsDefault => 'تعيين كافتراضي';

  @override
  String get deleteAddressConfirm => 'هل تريد حذف هذا العنوان؟';

  @override
  String get noAddressesTitle => 'لا توجد عناوين محفوظة';

  @override
  String get noAddressesBody => 'أضف عنوانًا لتصلك هداياك.';

  @override
  String get deliveryAddress => 'عنوان التوصيل';

  @override
  String get changeAddress => 'تغيير';

  @override
  String get deliveryDateAndTime => 'تاريخ ووقت التوصيل';

  @override
  String get today => 'اليوم';

  @override
  String get tomorrow => 'غدًا';

  @override
  String get yesterday => 'أمس';

  @override
  String get noSlotsToday =>
      'لا توجد أوقات توصيل متبقية اليوم — اختر يومًا آخر';

  @override
  String get giftOptions => 'خيارات الهدية';

  @override
  String get thisIsAGift => 'هذه هدية';

  @override
  String get hidePricesOnInvoice => 'إخفاء الأسعار في الفاتورة';

  @override
  String get giftMessage => 'رسالة الهدية';

  @override
  String get giftMessageHint => 'اكتب رسالة للبطاقة';

  @override
  String get paymentMethod => 'طريقة الدفع';

  @override
  String get cashOnDelivery => 'الدفع عند الاستلام';

  @override
  String get walletPayment => 'المحفظة والرصيد';

  @override
  String get cardPayment => 'بطاقة / محفظة إلكترونية';

  @override
  String get orderSummary => 'ملخص الطلب';

  @override
  String get placeOrder => 'تأكيد الطلب';

  @override
  String get placingOrder => 'جارٍ إرسال طلبك…';

  @override
  String itemNotDeliverableToCity(String item) {
    return 'لا يمكن توصيل $item إلى هذه المدينة';
  }

  @override
  String minimumOrderNotMet(String amount) {
    return 'الحد الأدنى للطلب هو $amount';
  }

  @override
  String get orderFailedCartChanged => 'تغيّرت بعض المنتجات. يرجى مراجعة سلتك.';

  @override
  String get orderFailedOutOfStock =>
      'نفدت بعض المنتجات للتو. يرجى مراجعة سلتك.';

  @override
  String get orderFailedCity =>
      'لا يمكن توصيل بعض المنتجات إلى المدينة المختارة.';

  @override
  String get orderFailedUnavailable =>
      'الطلب غير متاح حاليًا. يرجى المحاولة لاحقًا.';

  @override
  String get orderPlacedTitle => 'تم إرسال الطلب!';

  @override
  String orderPlacedBody(String number) {
    return 'شكرًا لك! استلمنا الطلب $number.';
  }

  @override
  String get estimatedDelivery => 'موعد التوصيل المتوقع';

  @override
  String get trackOrder => 'تتبّع الطلب';

  @override
  String get continueShopping => 'متابعة التسوق';

  @override
  String get activeOrders => 'النشطة';

  @override
  String get completedOrders => 'المكتملة';

  @override
  String get cancelledOrders => 'الملغاة';

  @override
  String get noOrdersTitle => 'لا توجد طلبات بعد';

  @override
  String get noOrdersBody => 'ستظهر طلباتك هنا.';

  @override
  String orderNumber(String number) {
    return 'الطلب $number';
  }

  @override
  String get orderDetails => 'تفاصيل الطلب';

  @override
  String get orderStatus => 'حالة الطلب';

  @override
  String get items => 'المنتجات';

  @override
  String get paymentInfo => 'الدفع';

  @override
  String get cancelOrder => 'إلغاء الطلب';

  @override
  String get cancelOrderConfirm => 'هل تريد إلغاء هذا الطلب؟';

  @override
  String get cancelReasonHint => 'السبب (اختياري)';

  @override
  String get orderCancelled => 'تم إلغاء الطلب';

  @override
  String get orderNotCancellable => 'لم يعد بالإمكان إلغاء هذا الطلب.';

  @override
  String get reorder => 'إعادة الطلب';

  @override
  String get reorderAdded => 'تمت إضافة المنتجات إلى سلتك';

  @override
  String get contactSupport => 'تواصل مع الدعم';

  @override
  String get statusPending => 'قيد الانتظار';

  @override
  String get statusConfirmed => 'مؤكد';

  @override
  String get statusPreparing => 'قيد التحضير';

  @override
  String get statusReadyForDelivery => 'جاهز للتوصيل';

  @override
  String get statusOutForDelivery => 'في الطريق إليك';

  @override
  String get statusDelivered => 'تم التوصيل';

  @override
  String get statusCancelledByBuyer => 'ملغى';

  @override
  String get statusCancelledBySeller => 'ألغاه المتجر';

  @override
  String get statusReturned => 'مُرتجع';

  @override
  String get statusRefunded => 'تم الاسترداد';

  @override
  String get markAllRead => 'تحديد الكل كمقروء';

  @override
  String get noNotificationsTitle => 'لا توجد إشعارات بعد';

  @override
  String get noNotificationsBody => 'ستظهر هنا تحديثات الطلبات والعروض.';

  @override
  String get contactUsBody =>
      'نحن هنا للمساعدة — تواصل معنا بالطريقة التي تفضلها.';

  @override
  String get contactWhatsapp => 'واتساب';

  @override
  String get contactCall => 'اتصل بنا';

  @override
  String get contactEmail => 'البريد الإلكتروني';

  @override
  String get contactInstagram => 'إنستغرام';

  @override
  String get discount => 'الخصم';

  @override
  String get paymentStatusPending => 'لم يُدفع بعد';

  @override
  String get paymentStatusPaid => 'مدفوع';

  @override
  String get paymentStatusFailed => 'فشل الدفع';

  @override
  String get paymentStatusRefunded => 'تم الاسترداد';

  @override
  String get paymentZainCash => 'زين كاش';

  @override
  String get paymentZainCashHint => 'ادفع عبر صفحة زين كاش الآمنة';

  @override
  String zainCashMinimum(String amount) {
    return 'يتطلب الدفع عبر زين كاش مبلغًا لا يقل عن $amount. اختر طريقة دفع أخرى.';
  }

  @override
  String get paymentConnecting => 'جارٍ فتح زين كاش…';

  @override
  String get paymentOrderSaved => 'تم حفظ طلبك — يمكنك دفعه من تفاصيل الطلب.';

  @override
  String get paymentErrorDisabled =>
      'الدفع الإلكتروني متوقف حاليًا. يرجى اختيار طريقة دفع أخرى.';

  @override
  String get paymentErrorNotPayable => 'لا يمكن دفع هذا الطلب إلكترونيًا.';

  @override
  String get paymentErrorAlreadyPaid => 'تم دفع هذا الطلب مسبقًا.';

  @override
  String get paymentErrorExpired => 'انتهت مهلة دفع هذا الطلب.';

  @override
  String get paymentErrorUnavailable =>
      'زين كاش غير متاح حاليًا. لم يُخصم أي مبلغ — يرجى المحاولة بعد قليل.';

  @override
  String get paymentOpenFailed =>
      'تعذّر فتح زين كاش. اضغط على «افتح زين كاش مجددًا».';

  @override
  String get paymentWaitingTitle => 'أكمل الدفع عبر زين كاش';

  @override
  String get paymentWaitingBody =>
      'فتحنا صفحة زين كاش الآمنة. بعد الدفع عُد إلى هنا — ستتحدّث هذه الصفحة تلقائيًا.';

  @override
  String get paymentAmountToPay => 'المبلغ المطلوب دفعه';

  @override
  String get paymentForTopUp => 'شحن رصيد المحفظة';

  @override
  String paymentTimeLeft(String time) {
    return 'الوقت المتبقي للدفع: $time';
  }

  @override
  String get paymentOpenAgain => 'افتح زين كاش مجددًا';

  @override
  String get paymentCheckStatus => 'دفعت — تحقّق من الحالة';

  @override
  String get paymentStillPending =>
      'لم يؤكد زين كاش الدفع بعد. ستتحدّث هذه الصفحة فور تأكيده.';

  @override
  String get paymentTimeUp =>
      'انتهى الوقت. نتحقق من النتيجة مع زين كاش — قد يستغرق ذلك بضع دقائق.';

  @override
  String get paymentChecking => 'جارٍ التحقق من الدفع…';

  @override
  String get paymentNotFound => 'لم نعثر على عملية الدفع هذه.';

  @override
  String get paymentFailedTitle => 'لم تكتمل عملية الدفع';

  @override
  String get paymentExpiredTitle => 'انتهت مهلة الدفع';

  @override
  String paymentOrderCancelledBody(String number) {
    return 'أُلغي الطلب $number. لم يُخصم أي مبلغ، وأُعيدت أي مكافآت استخدمتها إلى محفظتك.';
  }

  @override
  String get paymentNothingCharged =>
      'لم يُخصم أي مبلغ. يمكنك المحاولة مجددًا.';

  @override
  String get paymentTryAgain => 'حاول مجددًا';

  @override
  String get paymentLateCreditedTitle => 'تم استلام الدفعة';

  @override
  String paymentLateCreditedBody(String amount) {
    return 'كان الطلب قد أُلغي مسبقًا، لذلك أضفنا $amount إلى رصيد محفظتك.';
  }

  @override
  String get topUpSuccessTitle => 'تم شحن الرصيد';

  @override
  String topUpSuccessBody(String amount) {
    return 'أُضيف $amount إلى رصيدك.';
  }

  @override
  String get backToWallet => 'العودة إلى المحفظة';

  @override
  String get payNow => 'ادفع الآن';

  @override
  String payWithinNote(String time) {
    return 'ادفع خلال $time، وإلا سيُلغى الطلب تلقائيًا.';
  }

  @override
  String get orderCancelReasonPaymentFailed => 'لم تكتمل عملية الدفع';

  @override
  String get orderCancelReasonPaymentExpired => 'لم يُدفع في الوقت المحدد';

  @override
  String get walletTopUp => 'شحن الرصيد';

  @override
  String get topUpTitle => 'اشحن رصيدك';

  @override
  String get topUpBody => 'ادفع عبر زين كاش — يُضاف المبلغ إلى رصيد محفظتك.';

  @override
  String get topUpOtherAmount => 'مبلغ آخر';

  @override
  String topUpAmountHint(String min, String max) {
    return 'بين $min و$max';
  }

  @override
  String topUpAmountRange(String min, String max) {
    return 'أدخل مبلغًا بين $min و$max.';
  }

  @override
  String get topUpContinue => 'المتابعة إلى زين كاش';

  @override
  String get orderFailedPromo =>
      'لم يعد بالإمكان استخدام رمز الخصم، لذا أزلناه. يرجى مراجعة المجموع الجديد.';

  @override
  String get walletInsufficient =>
      'رصيد محفظتك لا يغطي هذا الطلب. اختر الدفع عند الاستلام أو فعّل رصيد المكافآت.';

  @override
  String get orderFailedInvalidChoice =>
      'وقت التوصيل أو طريقة الدفع هذه لم تعد متاحة. يرجى الاختيار مرة أخرى.';

  @override
  String get checkoutRemoveUnavailable =>
      'بعض المنتجات في سلتك لم تعد متوفرة. احذفها من السلة للمتابعة.';

  @override
  String get giftCardLabel => 'بطاقة هدية';

  @override
  String giftCardFrom(String amount) {
    return 'ابتداءً من $amount';
  }

  @override
  String giftCardTo(String name) {
    return 'إلى: $name';
  }

  @override
  String get giftCardShopTitle => 'متجر بطاقات الهدايا';

  @override
  String get giftCardShopEmptyTitle => 'لا توجد بطاقات هدايا متاحة حاليًا';

  @override
  String get giftCardShopEmptyBody => 'تصاميم جديدة قريبًا.';

  @override
  String get giftCardDesignTagline => 'صمّم بطاقة هديتك واجعلها شخصية.';

  @override
  String get giftCardDesignerTitle => 'صمّم بطاقة هديتك';

  @override
  String get giftCardDesignTitle => 'تصميم البطاقة';

  @override
  String get giftCardAmountTitle => 'المبلغ';

  @override
  String get giftCardCustomAmount => 'مبلغ مخصص';

  @override
  String giftCardAmountHint(String min, String max) {
    return 'بين $min و$max';
  }

  @override
  String get giftCardAmountRequired => 'أدخل المبلغ';

  @override
  String giftCardAmountRange(String min, String max) {
    return 'اختر مبلغًا بين $min و$max';
  }

  @override
  String get giftCardPhotoTitle => 'صورة';

  @override
  String get giftCardMessageTitle => 'الرسالة';

  @override
  String get giftCardRecipientTitle => 'المستلم';

  @override
  String get giftCardRecipientPhone => 'رقم هاتف المستلم';

  @override
  String get giftCardContactHint =>
      'سنرسل البطاقة إلى رقم الهاتف أو البريد الإلكتروني هذا.';

  @override
  String get giftCardContactRequired =>
      'أضف رقم هاتف المستلم أو بريده الإلكتروني';

  @override
  String get giftCardWhenTitle => 'موعد الإرسال';

  @override
  String get giftCardSendNow => 'أرسل الآن';

  @override
  String get giftCardSchedule => 'جدولة';

  @override
  String get giftCardSendNowNote => 'سنرسلها فور الدفع.';

  @override
  String get giftCardSendOn => 'تاريخ الإرسال';

  @override
  String get giftCardScheduleRequired => 'اختر يوم إرسال البطاقة';

  @override
  String get giftCardScheduleRange => 'اختر يومًا من الغد وحتى سنة من الآن';

  @override
  String get giftCardWalletBalance => 'رصيد المحفظة';

  @override
  String giftCardWalletNote(String balance) {
    return 'يُدفع من رصيد محفظتك ($balance). لا يمكن استخدام المكافآت لشراء بطاقات الهدايا.';
  }

  @override
  String giftCardWalletShort(String balance) {
    return 'رصيد محفظتك ($balance) لا يغطي هذه البطاقة. لا يمكن استخدام المكافآت لشراء بطاقات الهدايا.';
  }

  @override
  String get giftCardCodNote =>
      'يستلم مندوبنا المبلغ من عنوانك، ونرسل البطاقة بعد الدفع.';

  @override
  String get giftCardAddressRequired => 'أضف العنوان الذي سنستلم منه المبلغ';

  @override
  String get giftCardBuy => 'اشترِ بطاقة الهدية';

  @override
  String get giftCardFixErrors => 'يرجى مراجعة الحقول المحددة';

  @override
  String get giftCardUnavailable => 'بطاقة الهدية هذه لم تعد متاحة';

  @override
  String get giftCardHaveCode => 'هل لديك رمز بطاقة هدية؟';

  @override
  String get giftCardRedeem => 'استبدال';

  @override
  String get giftCardRedeemToCredits => 'استبدلها بمكافآت';

  @override
  String get giftCardCodeInvalid => 'أدخل الرمز المكوّن من 12 خانة';

  @override
  String get giftCardsReceived => 'المستلَمة';

  @override
  String get giftCardsSent => 'المرسَلة';

  @override
  String get giftCardsReceivedEmptyTitle => 'لا توجد بطاقات هدايا بعد';

  @override
  String get giftCardsReceivedEmptyBody =>
      'ستظهر هنا بطاقات الهدايا المرسلة إليك. لديك رمز؟ أدخله في الأعلى.';

  @override
  String get giftCardsSentEmptyTitle => 'لم ترسل أي بطاقة هدية بعد';

  @override
  String get giftCardsSentEmptyBody => 'فاجئ شخصًا عزيزًا ببطاقة هدية شخصية.';

  @override
  String get giftCardDesignCta => 'صمّم بطاقة هدية';

  @override
  String get giftCardStatusPending => 'بانتظار الدفع';

  @override
  String get giftCardStatusScheduled => 'مجدولة';

  @override
  String get giftCardStatusActive => 'فعّالة';

  @override
  String get giftCardStatusSent => 'أُرسلت';

  @override
  String get giftCardStatusRedeemed => 'تم الاستبدال';

  @override
  String get giftCardStatusExpired => 'منتهية الصلاحية';

  @override
  String get giftCardStatusDisabled => 'معطّلة';

  @override
  String giftCardBalance(String amount) {
    return 'الرصيد: $amount';
  }

  @override
  String giftCardSentOn(String date) {
    return 'أُرسلت في $date';
  }

  @override
  String giftCardScheduledFor(String date) {
    return 'سيتم إرسالها في $date';
  }

  @override
  String get giftCardRedeemedTitle => 'تم استبدال بطاقة الهدية!';

  @override
  String giftCardRedeemedBody(String amount) {
    return 'تمت إضافة $amount إلى مكافآتك';
  }

  @override
  String get giftCardViewWallet => 'عرض محفظتي';

  @override
  String get redeemNotFound =>
      'لم نعثر على بطاقة هدية بهذا الرمز. تحقق منه وحاول مجددًا.';

  @override
  String get redeemExpired => 'انتهت صلاحية بطاقة الهدية هذه.';

  @override
  String get redeemAlreadyRedeemed => 'تم استبدال بطاقة الهدية هذه مسبقًا.';

  @override
  String get redeemDisabled =>
      'لا يمكن استخدام بطاقة الهدية هذه. يرجى التواصل مع الدعم.';

  @override
  String get redeemNotYetSent =>
      'بطاقة الهدية هذه غير مفعّلة بعد — تُفعّل بعد دفعها وإرسالها.';

  @override
  String get redeemTooManyAttempts =>
      'محاولات كثيرة جدًا. يرجى المحاولة لاحقًا.';

  @override
  String get redeemUnavailable =>
      'الاستبدال غير متاح حاليًا. يرجى المحاولة لاحقًا.';

  @override
  String get srAddPhoto => 'أضف صورة';

  @override
  String get srSubtitle =>
      'لديك فكرة مميزة؟ أخبرنا عنها وسنتواصل معك قريبًا لتحقيقها!';

  @override
  String srPhotosHint(int max) {
    return 'أضف حتى $max صور (اختياري)';
  }

  @override
  String get srTextRequired => 'أخبرنا عن فكرتك';

  @override
  String get srSubmitted => 'شكرًا! استلمنا طلبك وسنتواصل معك قريبًا.';

  @override
  String get srMyRequests => 'طلباتي';

  @override
  String get srStatusSubmitted => 'تم الإرسال';

  @override
  String get srStatusInReview => 'قيد المراجعة';

  @override
  String get srStatusQuoted => 'تم التسعير';

  @override
  String get srStatusAccepted => 'مقبول';

  @override
  String get srStatusRejected => 'مرفوض';

  @override
  String get srStatusCompleted => 'مكتمل';

  @override
  String get srTypeSupport => 'الدعم';

  @override
  String get srNewReply => 'رد جديد';

  @override
  String get srDetailsTitle => 'طلبك';

  @override
  String get srNotFound => 'لم نعثر على هذا الطلب';

  @override
  String get srMessages => 'الرسائل';

  @override
  String get srNoMessages => 'لا توجد رسائل بعد — سنرد عليك هنا.';

  @override
  String get srYou => 'أنت';

  @override
  String get srReplyHint => 'اكتب رسالة';

  @override
  String get srSend => 'إرسال';

  @override
  String get srClosedNote =>
      'تم إغلاق هذا الطلب. لأي شيء آخر، أرسل لنا طلبًا جديدًا.';

  @override
  String get srRejectedNote =>
      'عذرًا، لا يمكننا تنفيذ هذا الطلب. لا تتردد في إرسال فكرة أخرى.';

  @override
  String get srQuoteTitle => 'عرض السعر';

  @override
  String get srQuoteDeliveryNote => 'تُضاف رسوم التوصيل في الخطوة التالية.';

  @override
  String get srAcceptQuote => 'قبول العرض';

  @override
  String get srViewOrder => 'عرض الطلب';

  @override
  String get srQuoteUnavailable => 'لم يعد بالإمكان قبول هذا العرض';

  @override
  String get srBackToRequest => 'العودة إلى الطلب';

  @override
  String get srCityNotServed =>
      'لا نوصل إلى هذه المدينة بعد. اختر عنوانًا آخر.';

  @override
  String srWalletShort(String balance) {
    return 'رصيد محفظتك ($balance) لا يغطي هذا الطلب.';
  }

  @override
  String get srQuoteRow => 'السعر المعروض';

  @override
  String get srConfirmOrder => 'تأكيد الطلب';

  @override
  String get supportSendUsMessage => 'أرسل لنا رسالة';

  @override
  String get supportMessageHint => 'كيف يمكننا مساعدتك؟';

  @override
  String get supportSend => 'إرسال';

  @override
  String get supportMessageSent =>
      'تم إرسال الرسالة! سنرد عليك في رسائلك قريبًا.';

  @override
  String get supportViewMessages => 'عرض رسائلك';

  @override
  String get supportSendAnother => 'إرسال رسالة أخرى';

  @override
  String get partnerScreenTitle => 'كن شريكًا';

  @override
  String get partnerHeroTitle => 'بِع على غولدن غيفت';

  @override
  String get partnerHeroBody =>
      'أوصل هداياك إلى المزيد من الناس في العراق وكردستان.';

  @override
  String get partnerWhyTitle => 'لماذا تصبح شريكًا لنا';

  @override
  String get partnerBenefitReachTitle => 'عملاء أكثر';

  @override
  String get partnerBenefitReachBody =>
      'اعرض منتجاتك لمتسوقي الهدايا في كل مدينة نخدمها.';

  @override
  String get partnerBenefitDashboardTitle => 'لوحة تحكم خاصة بمتجرك';

  @override
  String get partnerBenefitDashboardBody => 'أدر منتجاتك وطلباتك من مكان واحد.';

  @override
  String get partnerBenefitPersonalTitle => 'هدايا حسب الطلب';

  @override
  String get partnerBenefitPersonalBody =>
      'استلم أسماء العملاء وصورهم ورسائلهم مع كل طلب.';

  @override
  String get partnerFormTitle => 'قدّم طلب البيع';

  @override
  String get partnerStoreName => 'اسم المتجر';

  @override
  String get partnerStoreNameLength =>
      'يجب أن يتكون اسم المتجر من 2 إلى 60 حرفًا';

  @override
  String get partnerOwnerName => 'اسم المالك';

  @override
  String get partnerCategory => 'ماذا تبيع؟';

  @override
  String get partnerCategoryHint => 'مثال: خشب محفور، ورود، كيك';

  @override
  String get partnerInstagramInvalid => 'أدخل اسم مستخدم إنستغرام صالحًا';

  @override
  String get partnerSamplePhotos => 'صور نماذج من منتجاتك';

  @override
  String get partnerSubmit => 'إرسال الطلب';

  @override
  String get partnerThanksTitle => 'شكرًا لتقديمك!';

  @override
  String get partnerThanksBody => 'استلمنا طلبك وسنتواصل معك قريبًا.';

  @override
  String get partnerPendingTitle => 'نحن نراجع طلبك';

  @override
  String partnerPendingBody(String store) {
    return 'شكرًا لتقديمك لبيع منتجات $store على غولدن غيفت. سنتواصل معك قريبًا.';
  }

  @override
  String get partnerYourStore => 'متجرك';

  @override
  String get partnerActiveTitle => 'متجرك يعمل الآن';

  @override
  String get partnerActiveBody => 'أدِره من لوحة تحكم غولدن غيفت:';

  @override
  String get partnerOpenDashboard => 'فتح لوحة التحكم';

  @override
  String get partnerCopyLink => 'نسخ الرابط';

  @override
  String get partnerSuspendedTitle => 'تم إيقاف متجرك مؤقتًا';

  @override
  String get partnerSuspendedBody => 'يرجى التواصل مع فريق الدعم لحل المشكلة.';

  @override
  String get partnerAlreadyApplied => 'لقد قدّمت طلبًا بهذا الحساب مسبقًا.';

  @override
  String get partnerInvalid => 'يرجى التحقق من بياناتك والمحاولة مجددًا.';

  @override
  String get partnerUnavailable =>
      'التقديم غير متاح حاليًا. يرجى المحاولة لاحقًا.';

  @override
  String get aiSearchFieldHint => 'مثال: تخرج أختي، تحب النباتات';

  @override
  String get aiSearchExamplesTitle => 'جرّب مثالًا';

  @override
  String get aiSearchOccasion => 'المناسبة';

  @override
  String get aiSearchRecipient => 'لمن الهدية';

  @override
  String get aiSearchBudget => 'الميزانية';

  @override
  String get aiSearchAnyBudget => 'أي ميزانية';

  @override
  String aiSearchUpTo(String amount) {
    return 'حتى $amount';
  }

  @override
  String get aiOccasionBirthday => 'عيد ميلاد';

  @override
  String get aiOccasionAnniversary => 'ذكرى زواج';

  @override
  String get aiOccasionGraduation => 'تخرج';

  @override
  String get aiOccasionWedding => 'زفاف';

  @override
  String get aiOccasionNewBaby => 'مولود جديد';

  @override
  String get aiOccasionEid => 'العيد';

  @override
  String get aiOccasionThankYou => 'شكر وامتنان';

  @override
  String get aiRecipientMum => 'أمي';

  @override
  String get aiRecipientDad => 'أبي';

  @override
  String get aiRecipientWife => 'زوجتي';

  @override
  String get aiRecipientHusband => 'زوجي';

  @override
  String get aiRecipientSister => 'أختي';

  @override
  String get aiRecipientBrother => 'أخي';

  @override
  String get aiRecipientFriend => 'صديق';

  @override
  String get aiRecipientColleague => 'زميل عمل';

  @override
  String get aiRecipientChild => 'طفل';

  @override
  String get aiSearchFindGifts => 'ابحث عن هدايا';

  @override
  String get aiSearchQueryRequired => 'أخبرنا لمن الهدية أو ما المناسبة.';

  @override
  String get aiSearchQueryTooShort =>
      'أضف بضع كلمات أخرى لنجد الهدايا المناسبة.';

  @override
  String get aiSearchResultsTitle => 'أفكار هدايا لك';

  @override
  String get aiSearchFallbackNote =>
      'نعرض نتائج مطابقة للكلمات — اقتراحات الذكاء الاصطناعي غير متاحة الآن.';

  @override
  String get aiSearchRateLimited =>
      'لقد استنفدت عمليات البحث الذكي لهذا اليوم. نعرض نتائج مطابقة للكلمات بدلًا منها.';

  @override
  String get aiSearchNoResultsTitle => 'لم نجد أفكار هدايا';

  @override
  String get aiSearchNoResultsBody =>
      'جرّب وصفهم بكلمات أخرى، أو اختر ميزانية أكبر.';

  @override
  String get secretSantaIntro =>
      'اسحبوا الأسماء مع العائلة أو الأصدقاء أو الزملاء — يرى كل شخص فقط من سيشتري له.';

  @override
  String get secretSantaCreateGroup => 'إنشاء مجموعة';

  @override
  String get secretSantaJoinWithCode => 'الانضمام برمز';

  @override
  String get secretSantaCodeHint => 'رمز الدعوة (8 أحرف)';

  @override
  String get secretSantaJoin => 'انضمام';

  @override
  String get secretSantaInvalidCode =>
      'أدخل الرمز المكوّن من 8 أحرف الموجود في دعوتك.';

  @override
  String get secretSantaNoGroupsTitle => 'لا توجد مجموعات بعد';

  @override
  String get secretSantaNoGroupsBody =>
      'أنشئ مجموعة، أو انضم إلى مجموعة برمز الدعوة الذي وصلك.';

  @override
  String get secretSantaTypeFamily => 'العائلة';

  @override
  String get secretSantaTypeFriends => 'الأصدقاء';

  @override
  String get secretSantaTypeWork => 'العمل';

  @override
  String get secretSantaStatusOpen => 'مفتوحة';

  @override
  String get secretSantaStatusDrawn => 'تم السحب';

  @override
  String get secretSantaStatusClosed => 'مغلقة';

  @override
  String get secretSantaOrganiserBadge => 'أنت المنظّم';

  @override
  String get secretSantaOrganiser => 'المنظّم';

  @override
  String secretSantaMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو',
      many: '$count عضوًا',
      few: '$count أعضاء',
      two: 'عضوان',
      one: 'عضو واحد',
    );
    return '$_temp0';
  }

  @override
  String secretSantaMembersOf(int count, int max) {
    return 'الأعضاء ($count/$max)';
  }

  @override
  String secretSantaBudgetValue(String amount) {
    return '$amount لكل هدية';
  }

  @override
  String get secretSantaNoBudget => 'بلا ميزانية';

  @override
  String secretSantaExchangeOn(String date) {
    return 'التبادل في $date';
  }

  @override
  String get secretSantaGroupName => 'اسم المجموعة';

  @override
  String get secretSantaGroupNameHint => 'مثال: المكتب 2026';

  @override
  String get secretSantaType => 'نوع المجموعة';

  @override
  String get secretSantaBudget => 'الميزانية لكل هدية';

  @override
  String get secretSantaCustomBudget => 'مبلغ آخر';

  @override
  String get secretSantaCustomBudgetHint => 'المبلغ بالدينار العراقي';

  @override
  String get secretSantaBudgetError => 'أدخل مبلغًا.';

  @override
  String get secretSantaExchangeDate => 'تاريخ التبادل';

  @override
  String get secretSantaDateError => 'اختر تاريخًا ابتداءً من الغد.';

  @override
  String get secretSantaInviteTitle => 'ادعُ مجموعتك';

  @override
  String get secretSantaInviteBody =>
      'شارك الرابط أو الرمز — ينضم الأعضاء من تطبيق Golden Gift.';

  @override
  String get secretSantaCopyCode => 'نسخ الرمز';

  @override
  String get secretSantaShareLink => 'مشاركة الرابط';

  @override
  String secretSantaShareText(String name, String link, String code) {
    return 'انضم إلى مجموعة سانتا السري «$name» على Golden Gift! افتح $link أو أدخل الرمز $code.';
  }

  @override
  String get secretSantaShareSubject => 'سانتا السري على Golden Gift';

  @override
  String get secretSantaMembers => 'الأعضاء';

  @override
  String get secretSantaYou => 'أنت';

  @override
  String get secretSantaMyWishNote => 'أمنيتي';

  @override
  String get secretSantaWishNoteHint =>
      'ما الذي تتمنى أن تحصل عليه؟ سيرى سانتا السري الخاص بك هذه الملاحظة.';

  @override
  String get secretSantaWishNoteEmpty =>
      'أضف ملاحظة ليعرف سانتا السري ما الذي تحبه.';

  @override
  String get secretSantaAddNote => 'إضافة ملاحظة';

  @override
  String get secretSantaWishNoteSaved => 'تم حفظ أمنيتك';

  @override
  String get secretSantaDraw => 'سحب الأسماء';

  @override
  String secretSantaDrawHint(int min) {
    return 'يلزم $min أعضاء على الأقل لسحب الأسماء.';
  }

  @override
  String get secretSantaDrawConfirmTitle => 'سحب الأسماء الآن؟';

  @override
  String get secretSantaDrawConfirmBody =>
      'سيرى كل شخص من سيشتري له، ولن يتمكن أحد من الانضمام بعد السحب.';

  @override
  String get secretSantaDrawDone =>
      'تم سحب الأسماء! يمكن للجميع الآن رؤية من سيشترون له.';

  @override
  String secretSantaBuyingFor(String name) {
    return 'ستشتري هدية لـ $name';
  }

  @override
  String get secretSantaOnlyYou => 'لا يرى هذا أحد غيرك.';

  @override
  String get secretSantaTheirWish => 'أمنيته';

  @override
  String get secretSantaNoWishNote => 'لم يُضِف أمنية بعد.';

  @override
  String get secretSantaShopForThem => 'تسوّق له';

  @override
  String get secretSantaDrawPending =>
      'تم سحب الأسماء — سيظهر اسم الشخص المختار لك بعد لحظات.';

  @override
  String get secretSantaWaitingForDraw => 'بانتظار أن يسحب المنظّم الأسماء.';

  @override
  String get secretSantaNotMember => 'هذه المجموعة غير متاحة لك.';

  @override
  String get secretSantaJoinTitle => 'الانضمام إلى سانتا السري';

  @override
  String secretSantaJoinBody(String code) {
    return 'تمت دعوتك بالرمز $code. أضف اسمك ليعرف أعضاء المجموعة من أنت.';
  }

  @override
  String get secretSantaJoinGroup => 'انضم إلى المجموعة';

  @override
  String get secretSantaJoined => 'أهلًا بك في المجموعة!';

  @override
  String get secretSantaErrorNotFound => 'لم نجد مجموعة بهذا الرمز.';

  @override
  String get secretSantaErrorAlreadyDrawn =>
      'تم سحب الأسماء في هذه المجموعة بالفعل.';

  @override
  String get secretSantaErrorFull => 'هذه المجموعة ممتلئة.';

  @override
  String get secretSantaErrorImpossible =>
      'لا يمكن إجراء سحب صحيح مع الاستثناءات الحالية.';

  @override
  String get secretSantaErrorNotOrganiser => 'المنظّم فقط يمكنه سحب الأسماء.';

  @override
  String get secretSantaErrorUnavailable =>
      'سانتا السري غير متاح الآن. يرجى المحاولة لاحقًا.';

  @override
  String get reviewsTitle => 'التقييمات';

  @override
  String reviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تقييم',
      many: '$count تقييمًا',
      few: '$count تقييمات',
      two: 'تقييمان',
      one: 'تقييم واحد',
      zero: 'لا توجد تقييمات بعد',
    );
    return '$_temp0';
  }

  @override
  String get reviewsSeeAll => 'عرض الكل';

  @override
  String reviewStarsLabel(String rating) {
    return 'التقييم $rating من 5';
  }

  @override
  String reviewStarButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نجمة',
      few: '$count نجوم',
      two: 'نجمتان',
      one: 'نجمة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get reviewRate => 'قيّم';

  @override
  String get reviewFormTitle => 'قيّم هذه الهدية';

  @override
  String get reviewYourRating => 'تقييمك';

  @override
  String get reviewRatingRequired => 'اختر عدد النجوم.';

  @override
  String get reviewTextLabel => 'رأيك';

  @override
  String get reviewTextHint => 'ما الذي أعجبك فيها؟';

  @override
  String reviewAddPhotos(int max) {
    return 'الصور (حتى $max)';
  }

  @override
  String get reviewAddPhoto => 'إضافة صورة';

  @override
  String get reviewSubmit => 'إرسال التقييم';

  @override
  String get reviewThanks => 'شكرًا! سيظهر تقييمك بعد الموافقة عليه.';

  @override
  String get reviewPending => 'تقييمك بانتظار الموافقة';

  @override
  String get reviewReviewed => 'تم التقييم';

  @override
  String get reviewEdit => 'تعديل التقييم';

  @override
  String get reviewEditWarning =>
      'تعديل تقييمك يعيده إلى المراجعة قبل أن يظهر مجددًا.';

  @override
  String get reviewAnonymous => 'عميل';

  @override
  String get addressPinOnMap => 'تحديد الموقع على الخريطة';

  @override
  String get addressPinOnMapHint =>
      'اختياري — يساعد السائق في الوصول إلى الباب';

  @override
  String get addressLocationPinned => 'تم تحديد الموقع';

  @override
  String get addressChangePin => 'تغيير';

  @override
  String get addressUseThisLocation => 'استخدم هذا الموقع';

  @override
  String get addressMapTitle => 'حدّد موقعك';

  @override
  String get addressMapHelp => 'حرّك الخريطة حتى يصبح الدبوس على بابك.';

  @override
  String get wishlistDefaultList => 'هداياي المفضلة';

  @override
  String get wishlistNewList => 'قائمة جديدة';

  @override
  String get wishlistListName => 'اسم القائمة';

  @override
  String get wishlistListNameHint => 'مثال: عيد ميلاد أمي';

  @override
  String get wishlistCreateList => 'إنشاء قائمة';

  @override
  String get wishlistRenameList => 'إعادة تسمية القائمة';

  @override
  String get wishlistDeleteList => 'حذف القائمة';

  @override
  String wishlistDeleteListConfirm(String name, String defaultName) {
    return 'حذف «$name»؟ ستنتقل هداياها إلى $defaultName.';
  }

  @override
  String get wishlistListOptions => 'خيارات القائمة';

  @override
  String get wishlistMoveTo => 'نقل إلى…';

  @override
  String get wishlistSaveTo => 'حفظ في…';

  @override
  String wishlistSavedTo(String name) {
    return 'تم الحفظ في $name';
  }

  @override
  String wishlistMovedTo(String name) {
    return 'تم النقل إلى $name';
  }

  @override
  String get wishlistListEmptyTitle => 'هذه القائمة فارغة';

  @override
  String get wishlistListEmptyBody =>
      'اضغط مطولًا على القلب في أي هدية لحفظها في قائمة.';

  @override
  String get wishlistChooseList => 'اختر قائمة';

  @override
  String orderRefundedToWallet(String amount) {
    return 'أُعيد إلى محفظتك: $amount';
  }

  @override
  String get orderChangedByStore => 'بواسطة المتجر';

  @override
  String get orderChangedByYou => 'بواسطتك';

  @override
  String get comingSoon => 'قريبًا';

  @override
  String bannerSemanticLabel(int index, int count) {
    return 'العرض $index من $count';
  }

  @override
  String get categorySoonBadge => 'قريبًا';

  @override
  String categoryComingSoonLabel(String category) {
    return '$category، قريبًا';
  }

  @override
  String get comingSoonTagline => 'نُعدّها بعناية… وتصل قريبًا.';

  @override
  String comingSoonMessage(String category) {
    return 'نُحضّر لكم شيئًا مميزًا في فئة $category. فريقنا يعمل عليه الآن — وحتى ذلك الحين، اكتشفوا هدايا رائعة في فئاتنا الأخرى.';
  }

  @override
  String get comingSoonExploreOthers => 'اكتشف فئات أخرى';

  @override
  String get comingSoonGiftsYouMightLove => 'هدايا قد تُعجبك';

  @override
  String get comingSoonExploreAll => 'تصفّح جميع الفئات';

  @override
  String get comingSoonBackHome => 'العودة إلى الرئيسية';

  @override
  String get comingSoonShowAllGifts => 'عرض جميع الهدايا';

  @override
  String get giftForTitle => 'هدية لـ';

  @override
  String get giftForEveryone => 'الجميع';

  @override
  String get giftForMen => 'للرجال';

  @override
  String get giftForWomen => 'للنساء';

  @override
  String get giftForCompanies => 'للشركات';

  @override
  String get giftForMenTagline => 'هدايا سيحبّها';

  @override
  String get giftForWomenTagline => 'هدايا ستحبّها';

  @override
  String get giftForCompaniesTagline => 'هدايا الشركات وفِرق العمل';

  @override
  String get shopForTitle => 'تسوّق لـ';

  @override
  String get reels => 'ريلز';

  @override
  String get reelsFilterTitle => 'تصفية الريلز';

  @override
  String get reelsCategory => 'الفئة';

  @override
  String get reelsShowResults => 'عرض الريلز';

  @override
  String get reelsShopNow => 'تسوّق الآن';

  @override
  String get reelsEmptyTitle => 'لا توجد ريلز بعد';

  @override
  String get reelsEmptyBody => 'فيديوهات هدايا جديدة في طريقها إليك.';

  @override
  String get reelsNoMatchTitle => 'لا توجد ريلز تطابق هذه الفلاتر';

  @override
  String get reelsNoMatchBody => 'جرّب فئة أو سعرًا أو نوع هدية آخر.';

  @override
  String get reelsClearFilters => 'مسح الفلاتر';

  @override
  String get reelsSoundOn => 'تشغيل الصوت';

  @override
  String get reelsSoundOff => 'كتم الصوت';

  @override
  String get reelsPlay => 'تشغيل';

  @override
  String get reelsPause => 'إيقاف مؤقت';

  @override
  String get reelsVideoError => 'تعذّر تشغيل هذا الفيديو';

  @override
  String get reelsRemoveFilter => 'إزالة الفلتر';

  @override
  String get reelsMore => 'المزيد';

  @override
  String reelsViewProduct(String product) {
    return 'عرض $product';
  }
}
