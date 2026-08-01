import '../constants/app_constants.dart';

class ProductLabels {
  ProductLabels._();

  static const categories = {
    'dairy': 'Молочное',
    'meat': 'Мясо',
    'fish': 'Рыба и морепродукты',
    'vegetables': 'Овощи',
    'fruits': 'Фрукты',
    'eggs': 'Яйца',
    'grains': 'Крупы и хлеб',
    'canned': 'Консервы',
    'frozen': 'Заморозка',
    'condiments': 'Соусы и приправы',
    'beverages': 'Напитки',
    'other': 'Другое',
  };

  static String category(String value) => categories[value] ?? value;

  static String unit(String value) => switch (value) {
        'l' => 'л',
        'ml' => 'мл',
        'kg' => 'кг',
        'g' => 'г',
        _ => 'шт',
      };

  static String addMethod(String value) => switch (value) {
        AppConstants.addOcr => 'сканом чека',
        AppConstants.addBarcode => 'по штрихкоду',
        AppConstants.addVoice => 'голосом',
        _ => 'вручную',
      };
}
