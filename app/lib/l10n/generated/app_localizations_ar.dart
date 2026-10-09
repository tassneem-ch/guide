// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'دليل';

  @override
  String get homeTitle => 'خطّط لرحلة';

  @override
  String get fromLabel => 'من';

  @override
  String get toLabel => 'إلى';

  @override
  String get searchHint => 'مدينة أو عنوان أو مكان';

  @override
  String get useMyLocation => 'استعمل موقعي';

  @override
  String get locationDenied => 'تم رفض إذن الموقع — أدخل المكان يدويًا.';

  @override
  String get swapButton => 'تبديل';

  @override
  String get addWaypoint => 'إضافة محطة';

  @override
  String waypoint(int n) {
    return 'محطة $n';
  }

  @override
  String get departureTime => 'وقت الانطلاق';

  @override
  String get departNow => 'انطلق الآن';

  @override
  String get chooseTime => 'اختر وقتاً';

  @override
  String get travelMode => 'وسيلة التنقل';

  @override
  String get modeDriving => 'بالسيارة';

  @override
  String get modeWalking => 'سيراً';

  @override
  String get modeCycling => 'بالدراجة';

  @override
  String get preference => 'الأولوية';

  @override
  String get prefFastest => 'الأسرع';

  @override
  String get prefBalanced => 'متوازن';

  @override
  String get prefPrayerFriendly => 'محسّن للصلاة';

  @override
  String get prayerStopsLabel => 'مواقيت الصلاة';

  @override
  String get stopsOptional => 'اختياري';

  @override
  String get stopsMandatory => 'إلزامي';

  @override
  String get stopsNone => 'بدون';

  @override
  String get advancedOptions => 'حدود التخطيط';

  @override
  String get maxDetour => 'أقصى انحراف لزيارة مسجد';

  @override
  String get stopDuration => 'مدة التوقف';

  @override
  String get planningWindow => 'نافذة التخطيط (الوصول مبكراً)';

  @override
  String get prayerBuffer => 'مهلة بعد رفع الأذان';

  @override
  String minutesShort(int n) {
    return '$n د';
  }

  @override
  String get planRoute => 'خطّط المسار';

  @override
  String get nextPrayer => 'الصلاة القادمة';

  @override
  String get todayPrayers => 'مواقيت اليوم';

  @override
  String get noPrayerData => 'مواقيت الصلاة غير متاحة';

  @override
  String get prayerFajr => 'الفجر';

  @override
  String get prayerDhuhr => 'الظهر';

  @override
  String get prayerAsr => 'العصر';

  @override
  String get prayerMaghrib => 'المغرب';

  @override
  String get prayerIsha => 'العشاء';

  @override
  String get searchFirst => 'اختر نقطة البداية لعرض مواقيت الصلاة.';

  @override
  String get routesTitle => 'مقارنة المسارات';

  @override
  String get journeyTitle => 'تفاصيل الرحلة';

  @override
  String get tripTitle => 'مخطط الرحلات';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get labelFastest => 'المسار الأسرع';

  @override
  String get labelBalanced => 'المسار المتوازن';

  @override
  String get labelPrayerFriendly => 'المسار المحسّن للصلاة';

  @override
  String get totalDistance => 'المسافة';

  @override
  String get totalDuration => 'المدة';

  @override
  String get arrivalTime => 'وقت الوصول';

  @override
  String get detourVsFastest => 'الانحراف مقارنة بالأسرع';

  @override
  String get mosqueStops => 'توقفات المساجد';

  @override
  String get whyChosen => 'لماذا هذا المسار';

  @override
  String get uncertainties => 'غير مؤكد / غير متحقق';

  @override
  String get servedPrayers => 'الصلوات المخدومة';

  @override
  String get missedPrayers => 'صلوات بدون توقف';

  @override
  String get selectRoute => 'عرض الرحلة';

  @override
  String get stopsTimeline => 'المحطات والمسافات';

  @override
  String get origin => 'الانطلاق';

  @override
  String get destination => 'الوصول';

  @override
  String arriveAt(String time) {
    return 'الوصول $time';
  }

  @override
  String departAt(String time) {
    return 'المغادرة $time';
  }

  @override
  String prayerAt(String prayer, String time) {
    return '$prayer في $time';
  }

  @override
  String get rationale => 'سبب اختيار هذا التوقف';

  @override
  String alternativeMosques(int n) {
    return '$n مساجد بديلة قريبة';
  }

  @override
  String get mosqueDetails => 'تفاصيل المسجد';

  @override
  String get openingHours => 'ساعات العمل';

  @override
  String get hoursUnknown => 'مصدر البيانات لم ينشر ساعات العمل.';

  @override
  String get hoursUnverified =>
      'الساعات مقدّمة من المزود وغير متحقق منها بشكل مستقل.';

  @override
  String get hoursVerified => 'الساعات مؤكدة من مصدر البيانات.';

  @override
  String get congregationUnknown =>
      'وقت الإقامة غير معروف — تُعرض مواقيت الأذان المحسوبة فقط.';

  @override
  String get phone => 'الهاتف';

  @override
  String get website => 'الموقع';

  @override
  String get wheelchair => 'متاح لمستخدمي كرسي المتحرك';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get notSpecified => 'غير محدد';

  @override
  String get dataFrom => 'مصدر البيانات';

  @override
  String get liveData => 'بيانات مباشرة';

  @override
  String get fixtureData => 'بيانات تجريبية';

  @override
  String get openInMaps => 'فتح الاتجاهات في الخرائط';

  @override
  String detourValue(Object n) {
    return 'انحراف $n دقيقة';
  }

  @override
  String get tripName => 'اسم الرحلة';

  @override
  String get days => 'الأيام';

  @override
  String get activities => 'الجولات والأنشطة';

  @override
  String get addActivity => 'إضافة نشاط';

  @override
  String get activityName => 'اسم النشاط';

  @override
  String get durationMin => 'المدة (دقيقة)';

  @override
  String get dayIndex => 'اليوم (يبدأ العدّ من 1)';

  @override
  String get planTrip => 'خطّط الرحلة';

  @override
  String get saveTrip => 'حفظ الخطة';

  @override
  String get savedTrips => 'الخطط المحفوظة';

  @override
  String get resume => 'استئناف';

  @override
  String get delete => 'حذف';

  @override
  String get conflict => 'تعارض';

  @override
  String get overnight => 'مبيت';

  @override
  String get paceLabel => 'دقائق الأنشطة المخططة يومياً';

  @override
  String get nothingPlanned => 'لا توجد خطط بعد.';

  @override
  String get language => 'اللغة';

  @override
  String get prayerMethod => 'طريقة حساب الصلاة';

  @override
  String get asrSchool => 'حساب العصر';

  @override
  String get asrStandard => 'الجمهور (الشافعي والمالكي والحنبلي)';

  @override
  String get asrHanafi => 'الحنفي';

  @override
  String get highLatitude => 'قاعدة خطوط العرض العليا';

  @override
  String get unsupportedByProvider => 'غير مدعوم من المزود الحالي';

  @override
  String get manualAdjustments => 'تعديلات يدوية (دقائق)';

  @override
  String get timeFormat => 'نظام الوقت';

  @override
  String get time24 => '24 ساعة';

  @override
  String get time12 => '12 ساعة';

  @override
  String get units => 'الوحدات';

  @override
  String get unitsMetric => 'متري (كم)';

  @override
  String get unitsImperial => 'إمبراطوري (ميل)';

  @override
  String get notifications => 'تذكيرات توقف الصلاة';

  @override
  String get notificationsNote =>
      'يُحفظ التفضيل؛ تنبيهات الجهاز المحلي غير متاحة في هذه النسخة بعد.';

  @override
  String get appearance => 'المظهر';

  @override
  String get darkMode => 'الوضع الداكن';

  @override
  String get backendStatus => 'حالة مزوّدي الخادم';

  @override
  String get prayerProviderLabel => 'مزوّد مواقيت الصلاة';

  @override
  String get demoMode => 'بيانات تجريبية (معاينة دون اتصال)';

  @override
  String get demoModeNote => 'تعرض رحلات نموذجية بوضوح دون خادم خلفي.';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get errorGeneric => 'حدث خطأ ما';

  @override
  String get errorNetwork =>
      'تعذّر الوصول إلى الخادم — تحقق من عنوان الخادم في الإعدادات.';

  @override
  String errorProvider(String message) {
    return 'فشل أحد مزوّدي البيانات: $message';
  }

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String offlineBanner(Object time) {
    return 'دون اتصال — تُعرض البيانات المحفوظة من $time.';
  }

  @override
  String get fixtureBanner => 'وضع التجارب نشط — البيانات محاكاة وليست مباشرة.';

  @override
  String get noResults => 'لا توجد نتائج';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get close => 'إغلاق';

  @override
  String get done => 'تم';

  @override
  String get requiredField => 'مطلوب';

  @override
  String get unknown => 'غير معروف';

  @override
  String unitsKmValue(String n) {
    return '$n كم';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h س $m د';
  }

  @override
  String inTime(String time) {
    return 'بعد $time';
  }

  @override
  String countdownDays(int d, int h) {
    return '$dي $hس';
  }

  @override
  String countdownHours(int h, int m) {
    return '$hس $mد';
  }

  @override
  String countdownMinutes(int m) {
    return '$mد';
  }

  @override
  String get backendUrl => 'عنوان الخادم الخلفي';

  @override
  String get backendUrlHint => 'مثال: http://10.0.2.2:8000 (محاكي أندرويد)';

  @override
  String get resetToDefault => 'إعادة الافتراضي';

  @override
  String get settingsSaved => 'تم حفظ الإعدادات';

  @override
  String providerReport(String prayer, String routing, String mosques) {
    return 'الصلاة: $prayer · المسار: $routing · المساجد: $mosques';
  }
}
