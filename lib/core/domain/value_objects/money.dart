/// مبلغ بالليرة السورية كعدد صحيح (لا كسور إطلاقًا، لتفادي أخطاء الفاصلة
/// العائمة). كل العمليات الحسابية في التطبيق تمر عبر هذا النوع.
class Money {
  final int amount;

  const Money(this.amount);

  static const Money zero = Money(0);

  Money operator +(Money other) => Money(amount + other.amount);
  Money operator -(Money other) => Money(amount - other.amount);
  Money operator *(int factor) => Money(amount * factor);

  bool operator >(Money other) => amount > other.amount;
  bool operator <(Money other) => amount < other.amount;
  bool operator >=(Money other) => amount >= other.amount;
  bool operator <=(Money other) => amount <= other.amount;

  bool get isZero => amount == 0;

  @override
  bool operator ==(Object other) => other is Money && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'Money($amount)';
}

/// مجموع قائمة مبالغ.
Money sumMoney(Iterable<Money> values) {
  var total = 0;
  for (final v in values) {
    total += v.amount;
  }
  return Money(total);
}
