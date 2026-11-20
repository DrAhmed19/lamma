/// رقم النسخة. الويب والتطبيق ينبنون من نفس التعديل، فلازم يطلع نفس الرقم بالاثنين.
/// BUILD ينحط بالبناء (أول 7 حروف من رقم التعديل بـ GitHub). محلياً يطلع "dev".
const appVersion = '0.2.0';
const buildId = String.fromEnvironment('BUILD', defaultValue: 'dev');
const versionLabel = 'نسخة $appVersion · $buildId';
