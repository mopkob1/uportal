# UPORTAL Link Inserter

Thunderbird WebExtension для вставки ссылок из словаря UPORTAL и автоматической публикации redirect/pixel при отправке письма.

## Настройки

- `API base URL` — сервер UPORTAL для API-запросов.
- `Pixel base URL` — публичный base URL для pixel short-link. Если поле пустое, используется `API base URL`.
- `X-User-Token` — пользовательский токен UPORTAL.
- `URL словаря` — endpoint словаря, например `http://localhost:8080/api/admin/dictionary`.

## Переключатель на письмо

В окне вставки ссылок есть чекбокс `Отправить это письмо без UPORTAL`.

Если он включён для текущего окна письма:

- UPORTAL API не вызывается при отправке;
- redirect placeholders заменяются на обычные URL из словаря;
- email pixel не публикуется и не вставляется.

## Упаковка

```bash
zip -r uportal-link-inserter.xpi . -x '*.git*'
```
