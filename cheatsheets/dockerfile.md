# ---- глобальные аргументы билда ----
# Эти ARG объявлены "снаружи" и видны во всех стадиях, если их там тоже объявить.
ARG BUILD_VERSION=dev
ARG BUILD_DATE=unknown

# ---- builder stage: здесь ставим зависимости ----
FROM python:3.12-slim AS builder  # Базовый образ Python, лёгкий (slim), стадия называется "builder"

# Подтягиваем те же ARG уже ВНУТРИ стадии builder
ARG BUILD_VERSION
ARG BUILD_DATE

# Просто метка, чтобы при docker inspect было понятнее, что это за стадия
LABEL stage="builder"

# Устанавливаем минимум нужных пакетов.
# ca-certificates нужно, чтобы curl/pip могли ходить по HTTPS.
# В конце чистим /var/lib/apt/lists, чтобы слой был меньше.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Тут будем собирать приложение
WORKDIR /build

# Копируем список зависимостей
COPY requirements.txt .

# Ключевой момент:
# ставим Python-зависимости в /install, а не в стандартные пути.
# Потом этот /install просто скопируем в рантайм-образ.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Копируем код (он сейчас тут не нужен, но может пригодиться для тестов на стадии билда)
COPY app.py .

# ---- runtime stage: чистый образ для запуска ----
FROM python:3.12-slim AS runtime  # Новый базовый образ, без истории builder-слоёв

# Ещё раз объявляем ARG, чтобы можно было прокинуть их в ENV
ARG BUILD_VERSION
ARG BUILD_DATE

# Полезные лейблы для идентификации образа
LABEL maintainer="you@yourdomain.net" \
      service="lab25-web" \
      env="lab"

# Вот тут забираем из builder только установленный /install
# и кидаем его в /usr/local рантайма. Там живут python либы.
COPY --from=builder /install /usr/local

# Создаём не-root пользователя для приложения
# shell /usr/sbin/nologin значит, что это "сервисный" пользователь, логиниться им нельзя.
RUN useradd --create-home --shell /usr/sbin/nologin appuser

# Рабочая директория приложения
WORKDIR /app

# Кладём наш код внутрь контейнера
COPY app.py .

# Переменные окружения внутри контейнера по умолчанию.
# PORT и LAB_ENV — для приложения.
# BUILD_VERSION, BUILD_DATE — чтобы знать, что за билд, когда он собран.
ENV PORT=8080 \
    LAB_ENV=lab \
    BUILD_VERSION=${BUILD_VERSION} \
    BUILD_DATE=${BUILD_DATE}

# Документация: контейнер слушает порт 8080.
# Для человека и некоторых tools. Само по себе ничего не публикует.
EXPOSE 8080

# Ставим curl ТОЛЬКО для healthcheck.
# Снова чистим /var/lib/apt/lists, чтобы слой не раздувался.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Healthcheck на уровне Docker-образа:
# каждые 30 сек ходим на /health, ждём до 3 сек,
# даём 10 сек на старт, после трёх фейлов подряд контейнер unhealthy.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

# Меняем пользователя с root на appuser — приложение будет крутиться не от root.
USER appuser

# Команда по умолчанию: запустить Flask-приложение
CMD ["python", "app.py"]
