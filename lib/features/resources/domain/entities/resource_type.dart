import 'resource_kind.dart';

/// نوع طاولة (بلياردو، هوكي...). تبدأ القائمة فارغة، والمدير يضيف أنواعه
/// بنفسه مرة واحدة فتظهر دائمًا عند إضافة طاولة، ويعدّلها أو يحذفها متى شاء.
class ResourceType {
  final int id;
  final String name;
  final ResourceKind kind;

  const ResourceType({
    required this.id,
    required this.name,
    required this.kind,
  });
}
