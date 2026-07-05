/// Mirror of `error_messages_fr.dart` — see that file for the rationale.
/// Every key here must exist in `error_messages_fr.dart` and
/// `error_messages_en.dart` too (CLAUDE.md rule #26).
const Map<String, String> errorMessagesAr = {
  'AUTH_INVALID_CREDENTIALS': 'بيانات الاعتماد غير صحيحة.',
  'AUTH_TOKEN_MISSING': 'يجب تسجيل الدخول للقيام بهذا الإجراء.',
  'AUTH_TOKEN_INVALID': 'انتهت صلاحية جلستك. الرجاء إعادة تسجيل الدخول.',
  'AUTH_TOKEN_REVOKED': 'تم إلغاء جلستك. الرجاء إعادة تسجيل الدخول.',
  'AUTH_FORBIDDEN_ROLE': 'ليست لديك الصلاحية للقيام بهذا الإجراء.',

  'ADMIN_NOT_FOUND': 'المسؤول غير موجود.',

  'ZONE_NOT_FOUND': 'المنطقة غير موجودة.',

  'AGENT_EMAIL_TAKEN': 'هذا البريد الإلكتروني مستخدم بالفعل من طرف عون آخر.',
  'AGENT_NOT_FOUND': 'العون غير موجود.',
  'AGENT_NO_ZONE_ASSIGNED': 'هذا العون غير مرتبط بأي منطقة.',
  'AGENT_ZONE_NOT_ASSIGNED_TO_AGENT': 'هذه المنطقة غير مسندة حاليًا لهذا العون.',

  'COMMUNE_NOT_FOUND': 'البلدية غير موجودة.',

  'REPORT_ALREADY_SUBMITTED': 'لقد قمت بالإبلاغ عن هذا العرض من قبل.',

  'DEVICE_ID_MISSING': 'معرّف الجهاز مفقود. أعد تشغيل التطبيق.',

  'STORAGE_INVALID_IMAGE': 'الملف المرسل ليس صورة صالحة. أعد المحاولة بصورة.',

  'PROMO_NOT_FOUND': 'العرض غير موجود.',
  'PROMO_NOT_OWNED_BY_COMMERCANT': 'هذا العرض لا ينتمي إلى هذا التاجر.',
  'PROMO_DATE_FIN_NOT_FUTURE': 'يجب أن يكون تاريخ الانتهاء في المستقبل.',
  'PROMO_ALREADY_PUBLISHED': 'هذا العرض منشور بالفعل.',
  'PROMO_NOT_PUBLISHED': 'لا يمكن إيقاف سوى عرض منشور.',
  'PROMO_PRIX_APRES_NOT_LOWER': 'يجب أن يكون السعر بعد التخفيض أقل من السعر قبله.',

  'COMMERCANT_PHONE_TAKEN': 'رقم الهاتف هذا مسجل بالفعل.',
  'COMMERCANT_NOT_FOUND': 'التاجر غير موجود.',
  'COMMERCANT_PIN_ALREADY_SET': 'تم بالفعل تحديد رمز PIN لهذا الرقم — اتصل بالمسؤول لإعادة تعيينه.',
  'COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION': 'لا يوجد طلب تحقق في الانتظار.',
  'COMMERCANT_NOT_IN_AGENT_ZONE': 'هذا التاجر ليس ضمن منطقة هذا العون.',

  'RATE_LIMITED': 'عدد كبير جدًا من المحاولات. أعد المحاولة بعد قليل.',
  'HTTP_ERROR': 'حدث خطأ ما.',
  'INTERNAL_ERROR': 'حدث خطأ غير متوقع. أعد المحاولة لاحقًا.',

  'NETWORK_ERROR': 'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
};
