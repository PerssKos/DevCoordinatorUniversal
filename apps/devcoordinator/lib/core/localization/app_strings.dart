import 'package:flutter/widgets.dart';

final class AppStrings {
  const AppStrings._(this.locale);

  final Locale locale;

  static AppStrings of(BuildContext context) {
    return AppStrings._(Localizations.localeOf(context));
  }

  bool get _ru => locale.languageCode.toLowerCase() == 'ru';

  String text({required String en, required String ru}) => _ru ? ru : en;

  String get appName => 'DevCoordinator';
  String get projects => text(en: 'Projects', ru: 'Проекты');
  String get servers => text(en: 'Servers', ru: 'Серверы');
  String get containers => text(en: 'Containers', ru: 'Контейнеры');
  String get ports => text(en: 'Ports', ru: 'Порты');
  String get events => text(en: 'Events', ru: 'События');
  String get settings => text(en: 'Settings', ru: 'Настройки');
  String get dashboard => text(en: 'Overview', ru: 'Обзор');
  String get refresh => text(en: 'Refresh', ru: 'Обновить');
  String get retry => text(en: 'Try again', ru: 'Повторить');
  String get cancel => text(en: 'Cancel', ru: 'Отмена');
  String get close => text(en: 'Close', ru: 'Закрыть');
  String get save => text(en: 'Save', ru: 'Сохранить');
  String get connect => text(en: 'Connect', ru: 'Подключиться');
  String get disconnect => text(en: 'Disconnect', ru: 'Отключиться');
  String get later => text(en: 'Later', ru: 'Позже');
  String get update => text(en: 'Update', ru: 'Обновить');
  String get ignoreVersion =>
      text(en: 'Skip this version', ru: 'Пропустить эту версию');
  String get noData => text(
    en: 'No data from this host yet.',
    ru: 'От этого хоста пока нет данных.',
  );
  String get offline =>
      text(en: 'The host is unavailable.', ru: 'Хост недоступен.');
  String get light => text(en: 'Light', ru: 'Светлая');
  String get dark => text(en: 'Dark', ru: 'Тёмная');
  String get system => text(en: 'System', ru: 'Как в системе');
  String get appearance => text(en: 'Appearance', ru: 'Оформление');
  String get style => text(en: 'Visual style', ru: 'Стиль интерфейса');
  String get connection => text(en: 'Connection', ru: 'Подключение');
  String get updates => text(en: 'Updates', ru: 'Обновления');
  String get checkUpdates =>
      text(en: 'Check for updates', ru: 'Проверить обновления');
  String get upToDate => text(
    en: 'You have the latest version.',
    ru: 'Установлена последняя версия.',
  );
  String get loading => text(en: 'Loading…', ru: 'Загрузка…');
  String get start => text(en: 'Start', ru: 'Запустить');
  String get stop => text(en: 'Stop', ru: 'Остановить');
  String get restart => text(en: 'Restart', ru: 'Перезапустить');
  String get logs => text(en: 'Logs', ru: 'Логи');
  String get running => text(en: 'Running', ru: 'Работает');
  String get stopped => text(en: 'Stopped', ru: 'Остановлен');
  String get unhealthy => text(en: 'Needs attention', ru: 'Требует внимания');
  String get unknown => text(en: 'Unknown', ru: 'Неизвестно');
}
