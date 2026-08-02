<div align="center">
  <img src="assets/images/app_icon_master.png" alt="Eat on Time" width="180" />

  # Eat on Time

  **Умный хранитель продуктов, который помогает съесть их вовремя.**

  Сканирует упаковку, распознаёт срок годности, напоминает о важных датах
  и показывает, сколько продуктов и денег удалось спасти.

  [![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
  [![Android](https://img.shields.io/badge/Android-API_23+-3DDC84?logo=android&logoColor=white)](https://developer.android.com/)
  [![CI](https://github.com/whym1ss/eatontime/actions/workflows/flutter.yml/badge.svg)](https://github.com/whym1ss/eatontime/actions/workflows/flutter.yml)
  [![Release](https://img.shields.io/github/v/release/whym1ss/eatontime?display_name=tag&sort=semver)](https://github.com/whym1ss/eatontime/releases/latest)
  [![Поддержать автора](https://img.shields.io/badge/поддержать_автора-DonationAlerts-FF424D)](https://www.donationalerts.com/r/whym1ss)
  ![Offline first](https://img.shields.io/badge/offline--first-ready-2E7D32)

  [Возможности](#-возможности) · [Быстрый старт](#-быстрый-старт) ·
  [Архитектура](#-архитектура) · [Умное сканирование](#-умное-сканирование)
</div>

---

## 📥 Скачать

Готовый APK для Android доступен на странице
**[последнего релиза](https://github.com/whym1ss/eatontime/releases/latest)**.
Для установки APK не из Google Play может потребоваться разрешить установку из
выбранного браузера или файлового менеджера.

## Зачем это приложение

Продукты часто портятся не потому, что их не хотят использовать, а потому что
о них вспоминают слишком поздно. Eat on Time хранит домашний список продуктов,
выделяет срочные позиции, предлагает подходящее место хранения и помогает
быстро добавить покупки камерой, голосом или по чеку.

Приложение построено по принципу **offline-first**: основные функции и локальная
база работают без аккаунта и интернета. Облачная синхронизация подключается
опционально.

## ✨ Возможности

| Функция | Что умеет |
| --- | --- |
| 📦 Учёт продуктов | Название, бренд, категория, количество, цена, заметка и зона хранения |
| ⏳ Контроль свежести | Статусы «свежий», «скоро испортится», «съесть срочно» и «просрочен» |
| 🔎 Умный сканер | EAN-8/13, UPC, Code 128, QR и Data Matrix |
| 🧠 Автозаполнение | Локальная история → каталог Eat on Time → серверный шлюз → Open Food Facts → эвристики |
| 📅 OCR упаковки | Читает название, объём, условия хранения, срок и фразу «после вскрытия» по трём кадрам |
| 🛍 Разобрать пакет | Непрерывно сканирует несколько покупок без переходов между экранами |
| 🧾 Работа с чеками | OCR фотографии чека и интерфейс официального импорта по фискальному QR |
| 🎙 Голосовой ввод | Понимает команды вроде «добавь молоко в холодильник на пять дней» |
| 🔔 Напоминания | Ежедневно предупреждает о продуктах с близким сроком |
| 💡 Умные советы | Предлагает место хранения, заморозку и идеи использования продукта |
| 📊 Статистика | Съеденное, выброшенное, спасённые деньги и динамика по категориям |
| ☁️ Синхронизация | Опциональный Supabase, а без него — полностью локальная работа |

## 📱 Умное сканирование

```text
Камера
  ├─ EAN / UPC / Code 128 / QR / Data Matrix
  └─ OCR названия, объёма, условий хранения и даты
          ↓
ProductResolutionService
  1. локальная история пользователя
  2. проверенный каталог Eat on Time
  3. официальный серверный шлюз
  4. Open Food Facts
  5. локальные эвристики
          ↓
Предпросмотр с источником и уверенностью → подтверждение → Isar
```

Обычный штрихкод определяет вид товара, но не дату конкретной упаковки. Поэтому
после нахождения карточки приложение предлагает навести камеру на напечатанный
срок. OCR анализирует три кадра, нормализует разные форматы дат и не выдаёт
сомнительную догадку за точный результат.

Для Data Matrix локально разбираются известные GS1-поля: GTIN, дата, партия и
серийная часть — если они действительно присутствуют в коде.

### Источники данных и безопасность

- Open Food Facts используется с атрибуцией; база распространяется по ODbL,
  содержимое — Database Contents License, изображения — CC BY-SA.
- Ключи Национального каталога, провайдера фискальных чеков и источника отзывов
  никогда не помещаются в APK. Клиент обращается только к серверным функциям.
- Без настроенного сервера недоступные источники мягко пропускаются, а сканер
  продолжает работать через локальный кэш, Open Food Facts и OCR.
- Приложение не объявляет товар подлинным или безопасным без официального
  ответа и корректной трактовки источника.

Подробный технический план: [`docs/SMART_SCANNING_ROADMAP.md`](docs/SMART_SCANNING_ROADMAP.md).

## 🧱 Технологии

- Flutter 3.44 / Dart 3.12, Material 3;
- Riverpod и `go_router`;
- Isar как локальный источник истины;
- Supabase как опциональный backend;
- ML Kit Text Recognition, Camera и Mobile Scanner;
- Workmanager и Flutter Local Notifications;
- Freezed и JSON Serializable;
- FL Chart, Flutter Animate и Shimmer.

## 🚀 Быстрый старт

### Требования

- Flutter stable;
- Android Studio и Android SDK;
- устройство или эмулятор с Android API 23+.

### Запуск без backend

```bash
git clone https://github.com/whym1ss/eatontime.git
cd eatontime

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Сгенерированные файлы `*.g.dart` и `*.freezed.dart` не хранятся в Git, поэтому
после первого клонирования нужен шаг `build_runner`.

### Подключение Supabase

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

В Supabase необходимо включить Anonymous Sign-Ins и создать таблицы из раздела
[`Схема Supabase`](#-схема-supabase). Если параметры отсутствуют, приложение
автоматически остаётся в локальном режиме.

### Сборка APK

```bash
flutter build apk --release
```

Для публикации в Google Play добавьте собственный upload keystore и локальный
`android/key.properties`. Эти файлы исключены из Git. Без них проект создаёт
установочную release-сборку с debug-подписью только для локального тестирования.

## 🗃 Схема Supabase

<details>
<summary>Показать SQL для базовых таблиц и RLS</summary>

```sql
create table if not exists products (
  id            uuid primary key,
  user_id       uuid not null references auth.users on delete cascade,
  name          text not null,
  brand         text,
  barcode       text,
  category      text,
  zone_id       text not null default 'fridge',
  expiry_date   timestamptz not null,
  purchase_date timestamptz,
  opened_date   timestamptz,
  quantity      int not null default 1,
  unit          text not null default 'pcs',
  price         numeric,
  note          text,
  image_path    text,
  add_method    text not null default 'manual',
  status        text not null default 'fresh',
  notified      boolean not null default false,
  consumed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  is_deleted    boolean not null default false
);

create table if not exists waste_entries (
  id              bigserial primary key,
  user_id         uuid not null references auth.users on delete cascade,
  product_id      uuid,
  product_name    text not null,
  category        text,
  expiry_date     timestamptz,
  wasted_date     timestamptz not null,
  reason          text,
  estimated_value numeric,
  created_at      timestamptz not null default now()
);

create table if not exists product_catalog (
  barcode      text primary key,
  name         text not null,
  brand        text,
  category     text,
  default_days int,
  opening_days int,
  image_url    text
);

create index if not exists products_user_updated_idx
  on products (user_id, updated_at);
create index if not exists products_user_barcode_idx
  on products (user_id, barcode);
create index if not exists waste_user_date_idx
  on waste_entries (user_id, wasted_date);

alter table products enable row level security;
alter table waste_entries enable row level security;
alter table product_catalog enable row level security;

create policy "own products" on products
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own waste" on waste_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "catalog read" on product_catalog
  for select using (true);
```

</details>

## 🏗 Архитектура

```text
lib/
├── core/             темы, константы, сеть и локальные алгоритмы
├── data/
│   ├── local/        Isar entities и offline-хранилище
│   ├── models/       модели приложения и результатов сканирования
│   ├── remote/       Supabase data source
│   └── repositories/ offline-first репозитории
├── providers/        Riverpod providers
├── presentation/
│   ├── screens/      продукты, сканеры, чеки, статистика, настройки
│   └── widgets/      переиспользуемые UI-компоненты
├── services/         OCR, разрешение товара, уведомления и фоновые задачи
├── router/           маршрутизация
└── main.dart         запуск и подключение зависимостей
```

### Offline-first поток

1. Изменение мгновенно сохраняется в Isar с `isDirty = true`.
2. Интерфейс получает обновление через локальный stream.
3. При доступном Supabase изменения отправляются фоном.
4. Серверные обновления подтягиваются с момента последней синхронизации.
5. При конфликте более новая несинхронизированная локальная версия сохраняется.

## ✅ Проверка качества

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

GitHub Actions выполняет генерацию моделей, статический анализ и тесты для
каждого push и pull request.

## 🗺 Дальнейшее развитие

Продуктовый roadmap находится в [`docs/ROADMAP.md`](docs/ROADMAP.md). Главные
внешние зависимости — официальный партнёрский доступ к Национальному каталогу,
провайдеру фискальных данных и достоверному источнику отзывов партий.

## 🤝 Участие в разработке

Предложения и сообщения об ошибках можно создавать через
[GitHub Issues](https://github.com/whym1ss/eatontime/issues). Перед pull request
запустите форматирование, анализатор и тесты.

История пользовательских изменений: [`CHANGELOG.md`](CHANGELOG.md).

## 😺 Поддержать автора

Если Eat on Time оказался полезен, можно
[поддержать разработку через DonationAlerts](https://www.donationalerts.com/r/whym1ss).
Поддержи пж, для тебя стараюсь 💚

---

<div align="center">
  Сделано с заботой о продуктах, бюджете и планете 🌿
</div>
