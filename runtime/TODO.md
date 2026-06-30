# UPORTAL TODO

## 1. MP4/mobile fallback при необходимости

- Page assets уже должны отдаваться nginx static path с поддержкой Range.
- Если после проверки `Range: bytes=...` конкретный mp4 все еще плохо играет на
  мобильном, repack через `ffmpeg -movflags +faststart`.
- Это operational fallback, а не обязательная разработка, пока Range-support
  работает.
